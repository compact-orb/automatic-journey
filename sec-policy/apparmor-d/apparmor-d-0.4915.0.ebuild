# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker

MY_PN="apparmor.d"
MY_P="${MY_PN}-${PV}"

DESCRIPTION="Full set of AppArmor profiles and abstractions from apparmor.d"
HOMEPAGE="https://github.com/roddhjav/apparmor.d"
SRC_URI="
	https://github.com/roddhjav/${MY_PN}/releases/download/v${PV}/${MY_P}.tar.gz
	tools? (
		amd64? (
			https://pkg.pujol.io/debian/repo/pool/main/a/${MY_PN}/${MY_PN}-tools_${PV}-1+deb13_amd64.deb -> ${MY_P}-tools-amd64.deb
		)
	)
"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="+tools"
RESTRICT="test"

RDEPEND="
	>=sys-apps/apparmor-5.0
	sec-policy/apparmor-profiles[minimal]
"

S="${WORKDIR}/${MY_P}"

QA_PRESTRIPPED="usr/bin/aa-.*"

src_prepare() {
	default

	# In AppArmor 5.0, @{pci_bus} is defined in tunables/system.
	# Append to it to prevent duplicate variable declaration error.
	sed -i 's/@{pci_bus}=/@{pci_bus}+=/' apparmor.d/tunables/multiarch.d/system || die

	# Fix unix_chkpwd execution mode and attachment
	sed -i 's:@{exec_path} = @{sbin}/unix_chkpwd:@{exec_path} = /{,usr/}{bin,sbin}/unix_chkpwd:' \
		apparmor.d/profiles-s-z/unix-chkpwd || die

	# Allow systemd-userwork to read /etc/login.defs
	echo "  @{etc_ro}/login.defs r," >> apparmor.d/groups/systemd/systemd-userwork || die
}

src_install() {
	# Base abstractions and tunables (merged cleanly with apparmor-profiles[minimal])
	insinto /etc/apparmor.d/abstractions
	doins -r apparmor.d/abstractions/*

	insinto /etc/apparmor.d/tunables
	doins -r apparmor.d/tunables/*

	# Gentoo-specific PAM drop-in
	insinto /etc/apparmor.d/abstractions/authentication.d
	newins - gentoo.conf <<< "/usr/share/pam/** r,"

	# Systemd drop-in units for profile confinement
	local file service
	for file in systemd/system/*; do
		[[ -f "${file}" ]] || continue
		service="$(basename "${file}")"
		insinto "/usr/lib/systemd/system/${service}.d"
		newins "${file}" apparmor.conf
	done

	for file in systemd/user/*; do
		[[ -f "${file}" ]] || continue
		service="$(basename "${file}")"
		insinto "/usr/lib/systemd/user/${service}.d"
		newins "${file}" apparmor.conf
	done

	# Prebuilt profile collection in /usr/share/apparmor.d/
	insinto /usr/share/apparmor.d
	doins -r apparmor.d/{groups,mappings,namespaces,profiles-*}

	# Tooling
	if use tools && use amd64 && [[ -d "${WORKDIR}/usr/bin" ]]; then
		dobin "${WORKDIR}"/usr/bin/aa-*
		if [[ -d "${WORKDIR}/usr/share/man" ]]; then
			gzip -d "${WORKDIR}"/usr/share/man/man1/*.gz 2>/dev/null
			doman "${WORKDIR}"/usr/share/man/man1/aa-*.1
		fi
	fi

	# Runtime state directories
	keepdir /etc/apparmor.d/local
	keepdir /etc/apparmor.d/disable
}

pkg_postinst() {
	if [[ -z ${REPLACING_VERSIONS} ]]; then
		elog "apparmor.d profiles have been installed."
		elog "To deploy profiles to /etc/apparmor.d in complain mode:"
		elog "  aa-install -i -c"
		elog "Ensure apparmor.service is enabled:"
		elog "  systemctl enable --now apparmor.service"
	fi
}
