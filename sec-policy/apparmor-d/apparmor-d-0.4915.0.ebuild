# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module shell-completion systemd

EGO_SUM=(
	"github.com/davecgh/go-spew v1.1.0/go.mod"
	"github.com/davecgh/go-spew v1.1.1"
	"github.com/davecgh/go-spew v1.1.1/go.mod"
	"github.com/fsnotify/fsnotify v1.10.1"
	"github.com/fsnotify/fsnotify v1.10.1/go.mod"
	"github.com/pmezard/go-difflib v1.0.0"
	"github.com/pmezard/go-difflib v1.0.0/go.mod"
	"github.com/stretchr/objx v0.1.0/go.mod"
	"github.com/stretchr/objx v0.4.0/go.mod"
	"github.com/stretchr/objx v0.5.0/go.mod"
	"github.com/stretchr/objx v0.5.2/go.mod"
	"github.com/stretchr/testify v1.11.1"
	"github.com/stretchr/testify v1.11.1/go.mod"
	"github.com/stretchr/testify v1.7.1/go.mod"
	"github.com/stretchr/testify v1.8.0/go.mod"
	"github.com/stretchr/testify v1.8.4/go.mod"
	"golang.org/x/sys v0.47.0"
	"golang.org/x/sys v0.47.0/go.mod"
	"gopkg.in/check.v1 v0.0.0-20161208181325-20d25e280405/go.mod"
	"gopkg.in/ini.v1 v1.67.3"
	"gopkg.in/ini.v1 v1.67.3/go.mod"
	"gopkg.in/yaml.v3 v3.0.0-20200313102051-9f266ea9e77c/go.mod"
	"gopkg.in/yaml.v3 v3.0.1"
	"gopkg.in/yaml.v3 v3.0.1/go.mod"
)
go-module_set_globals

MY_PN="apparmor.d"
MY_P="${MY_PN}-${PV}"

DESCRIPTION="Full set of AppArmor profiles and abstractions from apparmor.d"
HOMEPAGE="https://github.com/roddhjav/apparmor.d"
SRC_URI="
	https://github.com/roddhjav/${MY_PN}/releases/download/v${PV}/${MY_P}.tar.gz
	${EGO_SUM_SRC_URI}
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
BDEPEND="
	dev-lang/go
"

S="${WORKDIR}/${MY_P}"

src_prepare() {
	default

	# Adjust unix_chkpwd execution path for Gentoo (/usr/bin/unix_chkpwd)
	sed -i 's:@{exec_path} = @{sbin}/unix_chkpwd:@{exec_path} = /{,usr/}{bin,sbin}/unix_chkpwd:' \
		apparmor.d/profiles-s-z/unix-chkpwd || die
}

src_compile() {
	# Compile the profile generator
	ego build -o bin/prebuild ./cmd/prebuild

	# Render profiles, convert ABI 5.0 to 4.0, and generate systemd drop-ins
	# DISTRIBUTION=opensuse targets AppArmor 5.0 with ABI 4.0 matching Gentoo
	DISTRIBUTION=opensuse ./bin/prebuild --buildir .build || die "prebuild failed"

	# Build management tools if USE=tools is enabled
	if use tools; then
		ego build -o bin/aa-install ./cmd/aa-install
		ego build -o bin/aa-log ./cmd/aa-log
		ego build -o bin/aa-mode ./cmd/aa-mode
	fi
}

src_install() {
	# Base abstractions and tunables (merged cleanly with apparmor-profiles[minimal])
	insinto /etc/apparmor.d/abstractions
	doins -r .build/apparmor.d/abstractions/*

	insinto /etc/apparmor.d/tunables
	doins -r .build/apparmor.d/tunables/*

	# Gentoo-specific PAM drop-in
	insinto /etc/apparmor.d/abstractions/authentication.d
	newins - gentoo.conf <<< "/usr/share/pam/** r,"

	# Systemd drop-in units for profile confinement
	local system_unit_dir="$(systemd_get_systemunitdir)"
	local user_unit_dir="$(systemd_get_userunitdir)"
	local file service

	for file in .build/systemd/system/*; do
		[[ -f "${file}" ]] || continue
		service="$(basename "${file}")"
		insinto "${system_unit_dir}/${service}.d"
		newins "${file}" apparmor.conf
	done

	for file in .build/systemd/user/*; do
		[[ -f "${file}" ]] || continue
		service="$(basename "${file}")"
		insinto "${user_unit_dir}/${service}.d"
		newins "${file}" apparmor.conf
	done

	# Prebuilt profile collection in /usr/share/apparmor.d/
	insinto /usr/share/apparmor.d
	doins -r .build/apparmor.d/{groups,mappings,namespaces,profiles-*}

	# Tooling
	if use tools; then
		dobin bin/aa-install bin/aa-log bin/aa-mode
		doman share/man/man1/aa-install.1 share/man/man1/aa-mode.1 share/man/man8/aa-log.8
		dobashcomp share/bash-completion/completions/aa-install \
			share/bash-completion/completions/aa-log \
			share/bash-completion/completions/aa-mode
		dozshcomp share/zsh/site-functions/_aa-install.zsh \
			share/zsh/site-functions/_aa-log.zsh \
			share/zsh/site-functions/_aa-mode.zsh
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
