require recipes-graphics/clutter/clutter-gst.inc

PR = "r0"

LIC_FILES_CHKSUM = "file://COPYING;md5=4fbd65380cdd255951079008b364516c \
                    file://clutter-gst/clutter-gst.h;beginline=1;endline=24;md5=95baacba194e814c110ea3bdf25ddbf4"

DEPENDS += "clutter-1.8 gstreamer"
RDEPENDS_${PN} += "gst-meta-base"

SRC_URI = "http://source.clutter-project.org/sources/clutter-gst/1.4/clutter-gst-${PV}.tar.bz2 \
           file://enable_tests-1.8.patch"

S = "${WORKDIR}/clutter-gst-${PV}"

SRC_URI[md5sum] = "c660649907785ee96f6e84d97f19d574"
SRC_URI[sha256sum] = "23cb10e7629696a696ca8619614c517ff0a341e89a701075f2a123a2e26999e9"

do_configure_prepend () {
       # Disable DOLT
       sed -i -e 's/^DOLT//' ${S}/configure.ac
}
