#!/bin/bash
# $Id$

BASIC_MODULES=dash\ i18n\ kernel-modules\ resume\ rootfs-block\ terminfo
BASIC_MODULES+=\ udev-rules\ uswsusp\ base
MODULES=lvm\ dmraid\ iscsi\ mdraid\ crypt\ multipath\ plymouth\ gensplash

dracut_modules() {
	local a=() o=()

	isTrue "${PLYMOUTH}" && isTrue "${GENSPLASH}" && gen_die 'Framebuffer Splash and Plymouth selected!  You cannot choose both splash engines.'
	isTrue "${EVMS}" && gen_die 'EVMS is no longer supported.  If you *really* need it, file a bug report and we bring it back to life.'
	isTrue "${UNIONFS}" && gen_die 'UnionFS not yet supported.'

	for var in ${MODULES}
	do
		var="${var^^}"
		isTrue "${!var}" && a+=(${var,,})
	done

	a+=(${ADD_MODULES})

	! isTrue "${AUTO}" && echo -n "-m '${BASIC_MODULES}'"
	[[ ${a[*]} ]] && echo -n " -a '${a[*]}'"
	[[ ${o[*]} ]] && echo -n " -o '${o[*]}'"
}

create_initramfs() {
	local tmprd="${TMPDIR}/initramfs-${KV}" opts='-f -v' add_files=()

	print_info 1 'initramfs: >> Initializing Dracut...'

	if isTrue "${GENERIC}"
	then
		print_info 1 '           >> Will build generic (read: huge) initramfs'
	else
		opts+=\ -H
	fi

	if isTrue "${NORAMDISKMODULES}"
	then
		print_info 1 '           >> Not copying kernel modules and firmware...'
		opts+=\ --ignore-kernel-modules
	else
		isTrue "${FIRMWARE}" && opts+=" --fwdir ${FIRMWARE_DIR}"
		[[ ${FIRMWARE_FILES} ]] && add_files+=(${FIRMWARE_FILES})
	fi

	[[ ${DRACUT_DIR} ]] && opts="-l ${opts}"
	[[ ${INITRAMFS_OVERLAY} ]] && opts+=" ${INITRAMFS_OVERLAY} /"
	[[ ${add_files[*]} ]] && opts+=" -I '${add_files[*]}'"
	opts+=" ${EXTRA_OPTIONS}"
	opts+=" $(dracut_modules)"

	export DRACUT_GENSPLASH_THEME=${GENSPLASH_THEME}
	export DRACUT_GENSPLASH_RES=${GENSPLASH_RES}
	print_info 1 "           >> DRACUT_GENSPLASH_THEME=${GENSPLASH_THEME}"
	print_info 1 "           >> DRACUT_GENSPLASH_RES=${GENSPLASH_RES}"
	print_info 1 "           >> dracut ${opts} '${tmprd}' '${KV}'"
	if [[ ${DRACUT_DIR} ]]; then
		cd "${DRACUT_DIR}"
		eval ./dracut ${opts} \'${tmprd}\' \'${KV}\'
		cd - >/dev/null
	else
		eval dracut ${opts} \'${tmprd}\' \'${KV}\'
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
