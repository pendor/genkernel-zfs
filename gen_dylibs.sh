# Functions imported from Dracut to help locate, unsymlink, strip, and install
# executables and the libraries they require to run.
# Dracut is licensed under the terms of GPL-2.
#
### Original Dracut copyright message:
###
### Copyright 2005-2009 Red Hat, Inc.  All rights reserved.
###
### This program is free software; you can redistribute it and/or modify
### it under the terms of the GNU General Public License as published by
### the Free Software Foundation; either version 2 of the License, or
### (at your option) any later version.
###
### This program is distributed in the hope that it will be useful,
### but WITHOUT ANY WARRANTY; without even the implied warranty of
### MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
### GNU General Public License for more details.
###
### You should have received a copy of the GNU General Public License
### along with this program.  If not, see <http://www.gnu.org/licenses/>.

ddebug() {
  print_info 4 "$1"
}

# Install a directory, keeping symlinks as on the original system.
# Example: if /lib64 points to /lib on the host, "inst_dir /lib/file"
# will create ${initdir}/lib64, ${initdir}/lib64/file,
# and a symlink ${initdir}/lib -> lib64.
inst_dir() {
    local dir="$1"
    [[ -e ${initdir}$dir ]] && return 0

    # iterate over parent directories
    local file=""
    local IFS="/"
    for part in $dir; do
        [[ $part ]] || continue
        file="$file/$part"
        [[ -e ${initdir}$file ]] && continue

        if [[ -L $file ]]; then
            # create link as the original
            local target=$(readlink "$file")
            ln -sfn "$target" "${initdir}$file" || return 1
            # resolve relative path and recursively install destination
            [[ $target == ${target#/} ]] && target="$(dirname "$file")/$target"
            inst_dir "$target"
        else
            # create directory
            mkdir -m 0755 -p "${initdir}$file" || return 1
        fi
    done
}

# $1 = file to copy to ramdisk
# $2 (optional) Name for the file on the ramdisk
# Location of the image dir is assumed to be $initdir
# We never overwrite the target if it exists.
inst_simple() {
    local src target
    [[ -f $1 ]] || return 1
    src=$1 target="${2:-$1}"
    if ! [[ -d ${initdir}$target ]]; then
        [[ -e ${initdir}$target ]] && return 0
        inst_dir "${target%/*}"
    fi
    # install checksum files also
    if [[ -e "${src%/*}/.${src##*/}.hmac" ]]; then
        instd "${src%/*}/.${src##*/}.hmac" "${target%/*}/.${target##*/}.hmac"
    fi
    ddebug "Installing $src to ${initdir}$target" 
    cp -pfL "$src" "${initdir}$target"
}

# find symlinks linked to given library file
# $1 = library file
# Function searches for symlinks by stripping version numbers appended to
# library filename, checks if it points to the same target and finally
# prints the list of symlinks to stdout.
#
# Example:
# rev_lib_symlinks libfoo.so.8.1
# output: libfoo.so.8 libfoo.so
# (Only if libfoo.so.8 and libfoo.so exists on host system.)
rev_lib_symlinks() {
    [[ ! $1 ]] && return 0

    local fn="$1" orig="$(readlink -f "$1")" links=''

    [[ ${fn} =~ .*\.so\..* ]] || return 1

    until [[ ${fn##*.} == so ]]; do
        fn="${fn%.*}"
        [[ -L ${fn} && $(readlink -f "${fn}") == ${orig} ]] && links+=" ${fn}"
    done

    echo "${links}"
}

# Same as above, but specialized to handle dynamic libraries.
# It handles making symlinks according to how the original library
# is referenced.
inst_library() {
    local src=$1 dest=${2:-$1} lib reallib symlink
    [[ -e $initdir$dest ]] && return 0
    if [[ -L $src ]]; then
        # install checksum files also
        if [[ -e "${src%/*}/.${src##*/}.hmac" ]]; then
            instd "${src%/*}/.${src##*/}.hmac" "${dest%/*}/.${dest##*/}.hmac"
        fi
        reallib=$(readlink -f "$src")
        lib=${src##*/}
        inst_simple "$reallib" "$reallib"
        inst_dir "${dest%/*}"
        (cd "${initdir}${dest%/*}" && ln -s "$reallib" "$lib")
    else
        inst_simple "$src" "$dest"
    fi

    # Create additional symlinks.  See rev_symlinks description.
    for symlink in $(rev_lib_symlinks $src) $(rev_lib_symlinks $reallib); do
        [[ ! -e $initdir$symlink ]] && {
            ddebug "Creating extra symlink: $symlink"
            inst_symlink $symlink
        }
    done
}

# find a binary.  If we were not passed the full path directly,
# search in the usual places to find the binary.
find_binary() {
    local binpath="/bin /sbin /usr/bin /usr/sbin" p
    if [[ -z ${1##/*} ]]; then
        if [[ -x $1 ]] || ldd $1 &>/dev/null; then
            echo $1
            return 0
        fi
    fi
    for p in $binpath; do
        [[ -x $p/$1 ]] && { echo "$p/$1"; return 0; }
    done
    return 1
}

# Same as above, but specialized to install binary executables.
# Install binary executable, and all shared library dependencies, if any.
inst_binary() {
    local bin target
    bin=$(find_binary "$1") || return 1
    target=${2:-$bin}
    inst_symlink $bin $target && return 0
    local LDSO NAME IO FILE ADDR I1 n f TLIBDIR
    [[ -e $initdir$target ]] && return 0
    # I love bash!
    LC_ALL=C ldd $bin 2>/dev/null | while read line; do
        [[ $line = 'not a dynamic executable' ]] && return 1
        if [[ $line =~ not\ found ]]; then
            dfatal "Missing a shared library required by $bin."
            dfatal "Run \"ldd $bin\" to find out what it is."
            dfatal "genkernel cannot create an initramfs."
            exit 1
        fi
        so_regex='([^ ]*/lib[^/]*/[^ ]*\.so[^ ]*)'
        [[ $line =~ $so_regex ]] || continue
        FILE=${BASH_REMATCH[1]}
        [[ -e ${initdir}$FILE ]] && continue
        # see if we are loading an optimized version of a shared lib.
        lib_regex='^(/lib[^/]*).*'
        if [[ $FILE =~ $lib_regex ]]; then
            TLIBDIR=${BASH_REMATCH[1]}
            BASE=${FILE##*/}
            # prefer nosegneg libs, then unoptimized ones.
            for f in "$TLIBDIR/i686/nosegneg" "$TLIBDIR"; do
                [[ -e $f/$BASE ]] || continue
                FILE=$f/$BASE
                break
            done
            inst_library "$FILE" "$TLIBDIR/$BASE"
            IF_dynamic=yes
            continue
            fi
            inst_library "$FILE"
    done
    inst_simple "$bin" "$target"
}

# same as above, but specialized for symlinks
inst_symlink() {
    local src=$1 target=$initdir${2:-$1} realsrc
    [[ -L $1 ]] || return 1
    [[ -L $target ]] && return 0
    realsrc=$(readlink -f "$src")
    [[ $realsrc = ${realsrc##*/} ]] && realsrc=${src%/*}/$realsrc
    instd "$realsrc" && mkdir -m 0755 -p "${target%/*}" && \
        ln -s "$realsrc" "$target"
}

# general purpose installation function
# Same args as above.
instd() {
    case $# in
        1) ;;
        2) [[ ! $initdir && -d $2 ]] && export initdir=$2
            [[ $initdir = $2 ]] && set $1;;
        3) [[ -z $initdir ]] && export initdir=$2
            set $1 $3;;
        *) dfatal "inst only takes 1 or 2 or 3 arguments"
            exit 1;;
    esac
    #inst_script
    for x in inst_symlink inst_binary inst_simple; do
        $x "$@" && return 0
    done
    return 1
}
