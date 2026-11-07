# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker xdg

DESCRIPTION="Windscribe VPN desktop client (prebuilt binary)"
HOMEPAGE="https://windscribe.com"
SRC_URI="
	amd64? ( https://github.com/Windscribe/Desktop-App/releases/download/v${PV}/windscribe_${PV}_amd64.deb )
	arm64? ( https://github.com/Windscribe/Desktop-App/releases/download/v${PV}/windscribe_${PV}_arm64.deb )
"
S="${WORKDIR}"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror strip"

RDEPEND="
	acct-group/windscribe
	acct-user/windscribe
	media-libs/libglvnd
	sys-apps/dbus
	sys-libs/glibc
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libxkbcommon[X]
"

QA_PREBUILT="opt/windscribe/*"

src_unpack() {
	:
}

src_install() {
	dodir /
	cd "${ED}" || die
	unpacker

	# Symlink CLI to PATH
	dosym /opt/windscribe/windscribe-cli /usr/bin/windscribe-cli

	# Create platform file required by windscribe-helper
	dodir /etc/windscribe
	if use amd64; then
		echo "linux_deb_x64" > "${ED}"/etc/windscribe/platform || die
	elif use arm64; then
		echo "linux_deb_arm64" > "${ED}"/etc/windscribe/platform || die
	fi

	# Set setgid permission on Windscribe GUI binary to communicate with helper
	fowners :windscribe /opt/windscribe/Windscribe
	fperms 2755 /opt/windscribe/Windscribe

	# Remove Debian package preset and non-standard autostart dir
	rm --recursive "${ED}"/usr/lib/systemd/system-preset || die
	rm --recursive "${ED}"/etc/windscribe/autostart || die
}

pkg_postinst() {
	xdg_pkg_postinst
	elog "To enable and start the Windscribe helper service:"
	elog "  systemctl enable --now windscribe-helper"
}
