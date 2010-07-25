#!/bin/bash
# $Id$

MODULES=LVM\ DMRAID\ ISCSI\ MDRAID\ CRYPT\ MULTIPATH\ PLYMOUTH\ GEN2SPLASH

dracut_modules() {
	local m=()

	isTrue "${PLYMOUTH}" && isTrue "${GEN2SPLASH}" && gen_die 'Gentoo Splash and Plymouth selected!  You cannot choose both splash engines.'
	isTrue "${EVMS}" && gen_die 'EVMS is no longer supported.  If you *really* need it, file a bug report and we bring it back to life.'
	isTrue "${UNIONFS}" && gen_die 'UnionFS not yet supported.'

	for var in ${MODULES}; do
		var="${var^^}"
		isTrue "${!var}" && m+=(${var,,})
	done

	[[ ${m[*]} ]] && echo -n "-m '${m[*]} ${EXTRA_MODULES}'"
}

create_initramfs() {
	local tmprd="${TMPDIR}/initramfs-${KV}" opts='-f' add_files=()

	print_info 1 'initramfs: >> Initializing Dracut...'

	if isTrue "${GENERIC}"
	then
		print_info 1 '           >> Will build generic (read: huge) initramfs'
	else
		opts+=\ -H
	fi

	if ! isTrue "${AUTO}"
	then
		opts+=" $(dracut_modules)"

		if isTrue "${NORAMDISKMODULES}"
		then
			print_info 1 '           >> Not copying kernel modules and firmware...'
			opts+=\ --no-kernel
		else
			isTrue "${FIRMWARE}" && opts+=" --fwdir ${FIRMWARE_DIR}"
			[[ ${FIRMWARE_FILES} ]] && add_files+=(${FIRMWARE_FILES})
		fi

		isTrue "${DISKLABEL}" && print_info 1 '           >> Skipping explicit install of blkid.  Should be installed' \
				&& print_info 1 '              automatically if needed.'
		[[ ${INITRAMFS_OVERLAY} ]] && opts+=" ${INITRAMFS_OVERLAY} /"
	else
		print_info 1 '           >> Auto configuration - ignoring other options'
	fi

	[[ ${add_files[*]} ]] && opts+=" -I '${add_files[*]}'"
	opts+="${EXTRA_OPTIONS}"

	print_info 1 "           >> dracut ${opts} \\"
	print_info 1 "              ${tmprd} \\"
	print_info 1 "              ${KV}"
	eval dracut ${opts} \'${tmprd}\' \'${KV}\'

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
