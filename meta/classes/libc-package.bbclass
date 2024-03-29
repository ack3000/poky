#
# This class knows how to package up [e]glibc. Its shared since prebuild binary toolchains
# may need packaging and its pointless to duplicate this code.
#
# Caller should set GLIBC_INTERNAL_USE_BINARY_LOCALE to one of:
#  "compile" - Use QEMU to generate the binary locale files
#  "precompiled" - The binary locale files are pregenerated and already present
#  "ondevice" - The device will build the locale files upon first boot through the postinst

GLIBC_INTERNAL_USE_BINARY_LOCALE ?= "ondevice"

python __anonymous () {
    enabled = d.getVar("ENABLE_BINARY_LOCALE_GENERATION", True)

    pn = d.getVar("PN", True)
    if pn.endswith("-initial"):
        enabled = False

    if enabled and int(enabled):
        import re

        target_arch = d.getVar("TARGET_ARCH", True)
        binary_arches = d.getVar("BINARY_LOCALE_ARCHES", True) or ""
        use_cross_localedef = d.getVar("LOCALE_GENERATION_WITH_CROSS-LOCALEDEF", True) or ""

        for regexp in binary_arches.split(" "):
            r = re.compile(regexp)

            if r.match(target_arch):
                depends = d.getVar("DEPENDS", True)
		if use_cross_localedef == "1" :
	                depends = "%s cross-localedef-native" % depends
		else:
	                depends = "%s qemu-native" % depends
                d.setVar("DEPENDS", depends)
                d.setVar("GLIBC_INTERNAL_USE_BINARY_LOCALE", "compile")
                break
}

OVERRIDES_append = ":${TARGET_ARCH}-${TARGET_OS}"

do_configure_prepend() {
        sed -e "s#@BASH@#/bin/sh#" -i ${S}/elf/ldd.bash.in
}



# indentation removed on purpose
locale_base_postinst() {
#!/bin/sh

if [ "x$D" != "x" ]; then
	exit 1
fi

rm -rf ${TMP_LOCALE}
mkdir -p ${TMP_LOCALE}
if [ -f ${libdir}/locale/locale-archive ]; then
        cp ${libdir}/locale/locale-archive ${TMP_LOCALE}/
fi
localedef --inputfile=${datadir}/i18n/locales/%s --charmap=%s --prefix=/tmp/locale %s
mkdir -p ${libdir}/locale/
mv ${TMP_LOCALE}/locale-archive ${libdir}/locale/
rm -rf ${TMP_LOCALE}
}

# indentation removed on purpose
locale_base_postrm() {
#!/bin/sh

rm -rf ${TMP_LOCALE}
mkdir -p ${TMP_LOCALE}
if [ -f ${libdir}/locale/locale-archive ]; then
	cp ${libdir}/locale/locale-archive ${TMP_LOCALE}/
fi
localedef --delete-from-archive --inputfile=${datadir}/locales/%s --charmap=%s --prefix=/tmp/locale %s
mv ${TMP_LOCALE}/locale-archive ${libdir}/locale/
rm -rf ${TMP_LOCALE}
}


TMP_LOCALE="/tmp/locale${libdir}/locale"
LOCALETREESRC ?= "{PKGD}"

do_prep_locale_tree() {
	treedir=${WORKDIR}/locale-tree
	rm -rf $treedir
	mkdir -p $treedir/${base_bindir} $treedir/${base_libdir} $treedir/${datadir} $treedir/${libdir}/locale
	tar -cf - -C ${LOCALETREESRC}${datadir} -ps i18n | tar -xf - -C $treedir/${datadir}
	# unzip to avoid parsing errors
	for i in $treedir/${datadir}/i18n/charmaps/*gz; do 
		gunzip $i
	done
	tar -cf - -C ${LOCALETREESRC}${base_libdir} -ps . | tar -xf - -C $treedir/${base_libdir}
	if [ -f ${STAGING_DIR_NATIVE}${prefix_native}/lib/libgcc_s.* ]; then
		tar -cf - -C ${STAGING_DIR_NATIVE}/${prefix_native}/${base_libdir} -ps libgcc_s.* | tar -xf - -C $treedir/${base_libdir}
	fi
	install -m 0755 ${LOCALETREESRC}${bindir}/localedef $treedir/${base_bindir}
}

do_collect_bins_from_locale_tree() {
	treedir=${WORKDIR}/locale-tree

	mkdir -p ${PKGD}${libdir}
	tar -cf - -C $treedir/${libdir} -ps locale | tar -xf - -C ${PKGD}${libdir}
}

inherit qemu

python package_do_split_gconvs () {
	import os, re
	if (d.getVar('PACKAGE_NO_GCONV', True) == '1'):
		bb.note("package requested not splitting gconvs")
		return

	if not d.getVar('PACKAGES', True):
		return

	bpn = d.getVar('BPN', True)
	libdir = d.getVar('libdir', True)
	if not libdir:
		bb.error("libdir not defined")
		return
	datadir = d.getVar('datadir', True)
	if not datadir:
		bb.error("datadir not defined")
		return

	gconv_libdir = base_path_join(libdir, "gconv")
	charmap_dir = base_path_join(datadir, "i18n", "charmaps")
	locales_dir = base_path_join(datadir, "i18n", "locales")
	binary_locales_dir = base_path_join(libdir, "locale")

	def calc_gconv_deps(fn, pkg, file_regex, output_pattern, group):
		deps = []
		f = open(fn, "r")
		c_re = re.compile('^copy "(.*)"')
		i_re = re.compile('^include "(\w+)".*')
		for l in f.readlines():
			m = c_re.match(l) or i_re.match(l)
			if m:
				dp = legitimize_package_name('%s-gconv-%s' % (bpn, m.group(1)))
				if not dp in deps:
					deps.append(dp)
		f.close()
		if deps != []:
			d.setVar('RDEPENDS_%s' % pkg, " ".join(deps))
		if bpn != 'glibc':
			d.setVar('RPROVIDES_%s' % pkg, pkg.replace(bpn, 'glibc'))

	do_split_packages(d, gconv_libdir, file_regex='^(.*)\.so$', output_pattern=bpn+'-gconv-%s', \
		description='gconv module for character set %s', hook=calc_gconv_deps, \
		extra_depends=bpn+'-gconv')

	def calc_charmap_deps(fn, pkg, file_regex, output_pattern, group):
		deps = []
		f = open(fn, "r")
		c_re = re.compile('^copy "(.*)"')
		i_re = re.compile('^include "(\w+)".*')
		for l in f.readlines():
			m = c_re.match(l) or i_re.match(l)
			if m:
				dp = legitimize_package_name('%s-charmap-%s' % (bpn, m.group(1)))
				if not dp in deps:
					deps.append(dp)
		f.close()
		if deps != []:
			d.setVar('RDEPENDS_%s' % pkg, " ".join(deps))
		if bpn != 'glibc':
			d.setVar('RPROVIDES_%s' % pkg, pkg.replace(bpn, 'glibc'))

	do_split_packages(d, charmap_dir, file_regex='^(.*)\.gz$', output_pattern=bpn+'-charmap-%s', \
		description='character map for %s encoding', hook=calc_charmap_deps, extra_depends='')

	def calc_locale_deps(fn, pkg, file_regex, output_pattern, group):
		deps = []
		f = open(fn, "r")
		c_re = re.compile('^copy "(.*)"')
		i_re = re.compile('^include "(\w+)".*')
		for l in f.readlines():
			m = c_re.match(l) or i_re.match(l)
			if m:
				dp = legitimize_package_name(bpn+'-localedata-%s' % m.group(1))
				if not dp in deps:
					deps.append(dp)
		f.close()
		if deps != []:
			d.setVar('RDEPENDS_%s' % pkg, " ".join(deps))
		if bpn != 'glibc':
			d.setVar('RPROVIDES_%s' % pkg, pkg.replace(bpn, 'glibc'))

	do_split_packages(d, locales_dir, file_regex='(.*)', output_pattern=bpn+'-localedata-%s', \
		description='locale definition for %s', hook=calc_locale_deps, extra_depends='')
	d.setVar('PACKAGES', d.getVar('PACKAGES') + ' ' + d.getVar('MLPREFIX') + bpn + '-gconv')

	use_bin = d.getVar("GLIBC_INTERNAL_USE_BINARY_LOCALE", True)

	dot_re = re.compile("(.*)\.(.*)")

#GLIBC_GENERATE_LOCALES var specifies which locales to be supported, empty or "all" means all locales 
	if use_bin != "precompiled":
		supported = d.getVar('GLIBC_GENERATE_LOCALES', True)
		if not supported or supported == "all":
			f = open(base_path_join(d.getVar('WORKDIR', True), "SUPPORTED"), "r")
			supported = f.readlines()
			f.close()
		else:
			supported = supported.split()
			supported = map(lambda s:s.replace(".", " ") + "\n", supported)
	else:
		supported = []
		full_bin_path = d.getVar('PKGD', True) + binary_locales_dir
		for dir in os.listdir(full_bin_path):
			dbase = dir.split(".")
			d2 = "  "
			if len(dbase) > 1:
				d2 = "." + dbase[1].upper() + "  "
			supported.append(dbase[0] + d2)

	# Collate the locales by base and encoding
	utf8_only = int(d.getVar('LOCALE_UTF8_ONLY', True) or 0)
	encodings = {}
	for l in supported:
		l = l[:-1]
		(locale, charset) = l.split(" ")
		if utf8_only and charset != 'UTF-8':
			continue
		m = dot_re.match(locale)
		if m:
			locale = m.group(1)
		if not encodings.has_key(locale):
			encodings[locale] = []
		encodings[locale].append(charset)

	def output_locale_source(name, pkgname, locale, encoding):
		d.setVar('RDEPENDS_%s' % pkgname, 'localedef %s-localedata-%s %s-charmap-%s' % \
		(bpn, legitimize_package_name(locale), bpn, legitimize_package_name(encoding)))
		d.setVar('pkg_postinst_%s' % pkgname, d.getVar('locale_base_postinst', True) \
		% (locale, encoding, locale))
		d.setVar('pkg_postrm_%s' % pkgname, d.getVar('locale_base_postrm', True) % \
		(locale, encoding, locale))

	def output_locale_binary_rdepends(name, pkgname, locale, encoding):
		m = re.match("(.*)\.(.*)", name)
		if m:
			libc_name = "%s.%s" % (m.group(1), m.group(2).lower().replace("-",""))
		else:
			libc_name = name
		d.setVar('RDEPENDS_%s' % pkgname, legitimize_package_name('%s-binary-localedata-%s' \
			% (bpn, libc_name)))
		rprovides = (d.getVar('RPROVIDES_%s' % pkgname, True) or "").split()
		rprovides.append(legitimize_package_name('%s-binary-localedata-%s' % (bpn, libc_name)))
		d.setVar('RPROVIDES_%s' % pkgname, " ".join(rprovides))

	commands = {}

	def output_locale_binary(name, pkgname, locale, encoding):
		treedir = base_path_join(d.getVar("WORKDIR", True), "locale-tree")
		ldlibdir = base_path_join(treedir, d.getVar("base_libdir", True))
		path = d.getVar("PATH", True)
		i18npath = base_path_join(treedir, datadir, "i18n")
		gconvpath = base_path_join(treedir, "iconvdata")
		outputpath = base_path_join(treedir, libdir, "locale")

		use_cross_localedef = d.getVar("LOCALE_GENERATION_WITH_CROSS-LOCALEDEF", True) or "0"
		if use_cross_localedef == "1":
	    		target_arch = d.getVar('TARGET_ARCH', True)
			locale_arch_options = { \
				"arm":     " --uint32-align=4 --little-endian ", \
				"powerpc": " --uint32-align=4 --big-endian ",    \
				"powerpc64": " --uint32-align=4 --big-endian ",  \
				"mips":    " --uint32-align=4 --big-endian ",    \
				"mipsel":  " --uint32-align=4 --little-endian ", \
				"i586":    " --uint32-align=4 --little-endian ", \
				"x86_64":  " --uint32-align=4 --little-endian "  }

			if target_arch in locale_arch_options:
				localedef_opts = locale_arch_options[target_arch]
			else:
				bb.error("locale_arch_options not found for target_arch=" + target_arch)
				raise bb.build.FuncFailed("unknown arch:" + target_arch + " for locale_arch_options")

			localedef_opts += " --force --old-style --no-archive --prefix=%s \
				--inputfile=%s/%s/i18n/locales/%s --charmap=%s %s/%s" \
				% (treedir, treedir, datadir, locale, encoding, outputpath, name)

			cmd = "PATH=\"%s\" I18NPATH=\"%s\" GCONV_PATH=\"%s\" cross-localedef %s" % \
				(path, i18npath, gconvpath, localedef_opts)
		else: # earlier slower qemu way 
			qemu = qemu_target_binary(d) 
			localedef_opts = "--force --old-style --no-archive --prefix=%s \
				--inputfile=%s/i18n/locales/%s --charmap=%s %s" \
				% (treedir, datadir, locale, encoding, name)

			qemu_options = d.getVar("QEMU_OPTIONS_%s" % d.getVar('PACKAGE_ARCH', True), True)
			if not qemu_options:
				qemu_options = d.getVar('QEMU_OPTIONS', True)

			cmd = "PSEUDO_RELOADED=YES PATH=\"%s\" I18NPATH=\"%s\" %s -L %s \
				-E LD_LIBRARY_PATH=%s %s %s/bin/localedef %s" % \
				(path, i18npath, qemu, treedir, ldlibdir, qemu_options, treedir, localedef_opts)

		commands["%s/%s" % (outputpath, name)] = cmd

		bb.note("generating locale %s (%s)" % (locale, encoding))

	def output_locale(name, locale, encoding):
		pkgname = d.getVar('MLPREFIX') + 'locale-base-' + legitimize_package_name(name)
		d.setVar('ALLOW_EMPTY_%s' % pkgname, '1')
		d.setVar('PACKAGES', '%s %s' % (pkgname, d.getVar('PACKAGES', True)))
		rprovides = ' virtual-locale-%s' % legitimize_package_name(name)
		m = re.match("(.*)_(.*)", name)
		if m:
			rprovides += ' virtual-locale-%s' % m.group(1)
		d.setVar('RPROVIDES_%s' % pkgname, rprovides)

		if use_bin == "compile":
			output_locale_binary_rdepends(name, pkgname, locale, encoding)
			output_locale_binary(name, pkgname, locale, encoding)
		elif use_bin == "precompiled":
			output_locale_binary_rdepends(name, pkgname, locale, encoding)
		else:
			output_locale_source(name, pkgname, locale, encoding)

	if use_bin == "compile":
		bb.note("preparing tree for binary locale generation")
		bb.build.exec_func("do_prep_locale_tree", d)

	# Reshuffle names so that UTF-8 is preferred over other encodings
	non_utf8 = []
	for l in encodings.keys():
		if len(encodings[l]) == 1:
			output_locale(l, l, encodings[l][0])
			if encodings[l][0] != "UTF-8":
				non_utf8.append(l)
		else:
			if "UTF-8" in encodings[l]:
				output_locale(l, l, "UTF-8")
				encodings[l].remove("UTF-8")
			else:
				non_utf8.append(l)
			for e in encodings[l]:
				output_locale('%s.%s' % (l, e), l, e)

	if non_utf8 != [] and use_bin != "precompiled":
		bb.note("the following locales are supported only in legacy encodings:")
		bb.note("  " + " ".join(non_utf8))

	if use_bin == "compile":
		makefile = base_path_join(d.getVar("WORKDIR", True), "locale-tree", "Makefile")
		m = open(makefile, "w")
		m.write("all: %s\n\n" % " ".join(commands.keys()))
		for cmd in commands:
			m.write(cmd + ":\n")
			m.write("	" + commands[cmd] + "\n\n")
		m.close()
		d.setVar("B", os.path.dirname(makefile))
		d.setVar("EXTRA_OEMAKE", "${PARALLEL_MAKE}")
		bb.note("Executing binary locale generation makefile")
		bb.build.exec_func("oe_runmake", d)
		bb.note("collecting binary locales from locale tree")
		bb.build.exec_func("do_collect_bins_from_locale_tree", d)
		do_split_packages(d, binary_locales_dir, file_regex='(.*)', \
			output_pattern=bpn+'-binary-localedata-%s', \
			description='binary locale definition for %s', extra_depends='', allow_dirs=True)
	elif use_bin == "precompiled":
		do_split_packages(d, binary_locales_dir, file_regex='(.*)', \
			output_pattern=bpn+'-binary-localedata-%s', \
			description='binary locale definition for %s', extra_depends='', allow_dirs=True)
	else:
		bb.note("generation of binary locales disabled. this may break i18n!")

}

# We want to do this indirection so that we can safely 'return'
# from the called function even though we're prepending
python populate_packages_prepend () {
	bb.build.exec_func('package_do_split_gconvs', d)
}

