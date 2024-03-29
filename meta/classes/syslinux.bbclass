# syslinux.bbclass
# Copyright (C) 2004-2006, Advanced Micro Devices, Inc.  All Rights Reserved
# Released under the MIT license (see packages/COPYING)

# Provide syslinux specific functions for building bootable images.

# External variables
# ${INITRD} - indicates a filesystem image to use as an initrd (optional)
# ${ROOTFS} - indicates a filesystem image to include as the root filesystem (optional)
# ${AUTO_SYSLINUXMENU} - set this to 1 to enable creating an automatic menu
# ${LABELS} - a list of targets for the automatic config
# ${APPEND} - an override list of append strings for each label
# ${SYSLINUX_OPTS} - additional options to add to the syslinux file ';' delimited

do_bootimg[depends] += "syslinux:do_populate_sysroot \
                        syslinux-native:do_populate_sysroot"

SYSLINUXCFG  = "${S}/syslinux.cfg"
SYSLINUXMENU = "${S}/menu"

SYSLINUX_ISODIR = "${ISODIR}/isolinux"
SYSLINUX_HDDDIR = "${HDDDIR}"
ISO_BOOTIMG = "isolinux/isolinux.bin"
ISO_BOOTCAT = "isolinux/boot.cat"
MKISOFS_OPTIONS = "-no-emul-boot -boot-load-size 4 -boot-info-table"

syslinux_populate() {
	DEST=$1
	CFGNAME=$2

	install -d ${DEST}

	# Install the kernel, initrd, and rootfs
	install -m 0644 ${STAGING_DIR_HOST}/kernel/bzImage ${DEST}/vmlinuz
	if [ -n "${INITRD}" ] && [ -s "${INITRD}" ]; then
		install -m 0644 ${INITRD} ${DEST}/initrd
	fi
	if [ -n "${ROOTFS}" ] && [ -s "${ROOTFS}" ]; then
		install -m 0644 ${ROOTFS} ${DEST}/rootfs.img
	fi

	# Install the config files
	install -m 0644 ${SYSLINUXCFG} ${DEST}/${CFGNAME}
	if [ -f ${SYSLINUXMENU} ]; then
		install -m 0644 ${SYSLINUXMENU} ${DEST}
	fi
}

syslinux_iso_populate() {
	syslinux_populate ${SYSLINUX_ISODIR} isolinux.cfg
	install -m 0644 ${STAGING_LIBDIR}/syslinux/isolinux.bin ${SYSLINUX_ISODIR}
}

syslinux_hddimg_populate() {
	syslinux_populate ${SYSLINUX_HDDDIR} syslinux.cfg
	install -m 0444 ${STAGING_LIBDIR}/syslinux/ldlinux.sys ${SYSLINUX_HDDDIR}/ldlinux.sys
}

syslinux_hddimg_install() {
	syslinux ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.hddimg
}

python build_syslinux_menu () {
	import copy
	import sys

	workdir = d.getVar('WORKDIR', 1)
	if not workdir:
		bb.error("WORKDIR is not defined")
		return
		
	labels = d.getVar('LABELS', 1)
	if not labels:
		bb.debug(1, "LABELS not defined, nothing to do")
		return
	
	if labels == []:
		bb.debug(1, "No labels, nothing to do")
		return

	cfile = d.getVar('SYSLINUXMENU', 1)
	if not cfile:
		raise bb.build.FuncFailed('Unable to read SYSLINUXMENU')

	try:
		cfgfile = file(cfile, 'w')
	except OSError:
		raise bb.build.funcFailed('Unable to open %s' % (cfile))

	# Beep the speaker and Clear the screen
	cfgfile.write('\x07\x0C')

	# The title should be configurable
	cfgfile.write('Linux Boot Menu\n')
	cfgfile.write('The following targets are available on this image:\n')
	cfgfile.write('\n')

	for label in labels.split():
		from copy import deepcopy
		localdata = deepcopy(d)

		overrides = localdata.getVar('OVERRIDES')
		if not overrides:
			raise bb.build.FuncFailed('OVERRIDES not defined')
		overrides = bb.data.expand(overrides, localdata)
	
		localdata.setVar('OVERRIDES', label + ':' + overrides)
		bb.data.update_data(localdata)

		usage = localdata.getVar('USAGE', 1)
		cfgfile.write('  \x0F\x30\x3E%16s\x0F\x30\x37: ' % (label))
		cfgfile.write('%s\n' % (usage))

		del localdata

	cfgfile.write('\n')
	cfgfile.close()
}

python build_syslinux_cfg () {
	import copy
	import sys

	workdir = d.getVar('WORKDIR', 1)
	if not workdir:
		bb.error("WORKDIR not defined, unable to package")
		return
		
	labels = d.getVar('LABELS', 1)
	if not labels:
		bb.debug(1, "LABELS not defined, nothing to do")
		return
	
	if labels == []:
		bb.debug(1, "No labels, nothing to do")
		return

	cfile = d.getVar('SYSLINUXCFG', 1)
	if not cfile:
		raise bb.build.FuncFailed('Unable to read SYSLINUXCFG')

	try:
		cfgfile = file(cfile, 'w')
	except OSError:
		raise bb.build.funcFailed('Unable to open %s' % (cfile))

	# FIXME - the timeout should be settable
	# And maybe the default too
	# Definately the prompt

	cfgfile.write('# Automatically created by OE\n')

	opts = d.getVar('SYSLINUX_OPTS', 1)

	if opts:
		for opt in opts.split(';'):
			cfgfile.write('%s\n' % opt)

	cfgfile.write('ALLOWOPTIONS 1\n');
	cfgfile.write('DEFAULT %s\n' % (labels.split()[0]))

	timeout = d.getVar('SYSLINUX_TIMEOUT', 1)

	if timeout:
		cfgfile.write('TIMEOUT %s\n' % timeout)
	else:
		cfgfile.write('TIMEOUT 50\n')

	cfgfile.write('PROMPT 1\n')

	menu = d.getVar('AUTO_SYSLINUXMENU', 1)

	# This is ugly.  My bad.

	if menu:
		bb.build.exec_func('build_syslinux_menu', d)
		mfile = d.getVar('SYSLINUXMENU', 1)
		cfgfile.write('DISPLAY %s\n' % (mfile.split('/')[-1]) )
	
	for label in labels.split():
		localdata = bb.data.createCopy(d)

		overrides = localdata.getVar('OVERRIDES', True)
		if not overrides:
			raise bb.build.FuncFailed('OVERRIDES not defined')
	
		localdata.setVar('OVERRIDES', label + ':' + overrides)
		bb.data.update_data(localdata)
	
		cfgfile.write('LABEL %s\nKERNEL vmlinuz\n' % (label))

		append = localdata.getVar('APPEND', 1)
		initrd = localdata.getVar('INITRD', 1)

		if append:
			cfgfile.write('APPEND ')

			if initrd:
				cfgfile.write('initrd=initrd ')

			cfgfile.write('LABEL=%s '% (label))

			cfgfile.write('%s\n' % (append))

	cfgfile.close()
}
