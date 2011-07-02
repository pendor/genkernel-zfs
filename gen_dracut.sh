#!/bin/bash
# $Id$

BASIC_MODULES=dash\ i18n\ kernel-modules\ resume\ rootfs-block\ terminfo
BASIC_MODULES+=\ udev-rules\ base
MODULES=lvm\ dmraid\ iscsi\ mdraid\ crypt\ crypt-gpg\ multipath\ plymouth\ gensplash\ zfs

strstr() {
    [[ $1 =~ $2 ]]
}

dracut_modules() {
	local a=() o=()

	isTrue "${PLYMOUTH}" && isTrue "${GENSPLASH}" && gen_die 'Framebuffer Splash and Plymouth selected!  You cannot choose both splash engines.'
	isTrue "${UNIONFS}" && gen_die 'UnionFS not yet supported.'

	for var in ${MODULES}
	do
		opt="${var^^}"
        opt="${opt//-/_}"
		isTrue "${!opt}" && a+=(${var})
	done

	a+=(${ADD_MODULES})

	! isTrue "${AUTO}" && echo -n "-m '${BASIC_MODULES}'"
	[[ ${a[*]} ]] && echo -n " -a '${a[*]}'"
	[[ ${o[*]} ]] && echo -n " -o '${o[*]}'"
}

create_initramfs() {
	local tmprd="${TMPDIR}/initramfs-${KV}" opts='-f -L=3 -M' add_files=()

	print_info 1 'initramfs: >> Initializing Dracut...'

	if isTrue "${GENERIC}"
	then
		print_info 1 '           >> Will build generic (read: huge) initramfs'
	else
		opts+=\ -H
	fi

	[[ ${INSTALL_MOD_PATH} ]] && opts+=\ -k\ "${INSTALL_MOD_PATH}"

	if isTrue "${NORAMDISKMODULES}" || isTrue "${BUILD_STATIC}"
	then
		print_info 1 '           >> Not copying kernel modules and firmware...'
		opts+=\ --no-kernel
	else
		isTrue "${FIRMWARE}" && opts+=" --fwdir ${FIRMWARE_DIR}"
		[[ ${FIRMWARE_FILES} ]] && add_files+=(${FIRMWARE_FILES})
	fi

	[[ ${DRACUT_DIR} ]] && opts="-l ${opts}"
	[[ ${INITRAMFS_OVERLAY} ]] && opts+=" ${INITRAMFS_OVERLAY} /"
	[[ ${add_files[*]} ]] && opts+=" -I '${add_files[*]}'"
	opts+=" ${EXTRA_OPTIONS}"
	opts+=" $(dracut_modules)"

    if strstr "${opts}" " mdraid "
    then
        isTrue "${MDRAID_CONFIG}" && opts+=\ --mdadmconf || \
            opts+=\ --nomdadmconf
    fi

	if isTrue "${GENSPLASH}"
	then
		export DRACUT_GENSPLASH_THEME=${GENSPLASH_THEME}
		export DRACUT_GENSPLASH_RES=${GENSPLASH_RES}
		print_info 1 "           >> DRACUT_GENSPLASH_THEME=${GENSPLASH_THEME}"
		print_info 1 "           >> DRACUT_GENSPLASH_RES=${GENSPLASH_RES}"
	fi
	print_info 1 "           >> dracut ${opts} '${tmprd}' '${KV}'"
	rm -f ${TMPDIR}/drac.failed
	if [[ ${DRACUT_DIR} ]]; then
		cd "${DRACUT_DIR}"
		eval ./dracut ${opts} \'${tmprd}\' \'${KV}\' || touch ${TMPDIR}/drac.failed
		cd - >/dev/null
	else
		eval dracut ${opts} \'${tmprd}\' \'${KV}\' || touch ${TMPDIR}/drac.failed \
		  | while read module; do
			[[ \ $MODULES\  =~ \ $module\  ]] && module="${BOLD}${module}${NORMAL}"
			print_info 1 "              >> Including module: $module"
		done
	fi
	if [ -f ${TMPDIR}/drac.failed ] ; then
	  gen_die "Running Dracut failed."
	fi

	if isTrue "${INTEGRATED_INITRAMFS}"
	then
		mv ${tmprd} ${tmprd}.cpio.gz
		sed -i '/^.*CONFIG_INITRAMFS_SOURCE=.*$/d' ${KERNEL_DIR}/.config
		echo -e "CONFIG_INITRAMFS_SOURCE=\"${tmprd}.cpio.gz\"\nCONFIG_INITRAMFS_ROOT_UID=0\nCONFIG_INITRAMFS_ROOT_GID=0" \
				>> ${KERNEL_DIR}/.config
	fi

	if ! isTrue "${CMD_NOINSTALL}"
	then
		if ! isTrue "${INTEGRATED_INITRAMFS}"
		then
			copy_image_with_preserve initramfs "${tmprd}" \
				"initramfs-${KNAME}-${ARCH}-${KV}"
		fi
	fi
}
