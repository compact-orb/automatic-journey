#!/usr/bin/env bash
# Update Google Chrome ebuilds with ChromeOS Widevine CDM in Gentoo overlay.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_WV_URL="https://lively-flower-f91a.compact-orb.workers.dev/local/libwidevinecdm.so"

UPSTREAM_DIR="${1:-/tmp/gentoo-mirror/www-client/google-chrome}"
OVERLAY_DIR="${2:-${REPO_ROOT}/www-client/google-chrome}"
WIDEVINE_URL="${3:-${DEFAULT_WV_URL}}"

mkdir --parents "${OVERLAY_DIR}"

# 1. Sync metadata.xml
if [[ -f "${UPSTREAM_DIR}/metadata.xml" ]]; then
	cp "${UPSTREAM_DIR}/metadata.xml" "${OVERLAY_DIR}/metadata.xml"
fi

# 2. Process upstream ebuilds
upstream_ebuilds=("${UPSTREAM_DIR}"/google-chrome-*.ebuild)
if [[ ! -e "${upstream_ebuilds[0]}" ]]; then
	echo "Error: No upstream google-chrome ebuilds in ${UPSTREAM_DIR}" >&2
	exit 1
fi

for ebuild_path in "${upstream_ebuilds[@]}"; do
	ebuild_name="$(basename "${ebuild_path}")"
	target_ebuild="${OVERLAY_DIR}/${ebuild_name}"

	echo "Processing ${ebuild_name}..."

	# Multiline SRC_URI replacement
	src_uri_expr='/^SRC_URI="/,/^"/c\'
	src_uri_expr+='SRC_URI="\n'
	src_uri_expr+='\thttps://dl.google.com/linux/chrome/deb/pool/main/g/'
	src_uri_expr+='${MY_PN}/${MY_P}_amd64.deb\n'
	src_uri_expr+="\t${WIDEVINE_URL}\n\""

	# Transform upstream ebuild directly into overlay variant
	sed \
		--expression='s/^KEYWORDS=".*"/KEYWORDS="-* amd64"/' \
		--expression='s/^src_install()/upstream_src_install()/' \
		--expression="${src_uri_expr}" \
		"${ebuild_path}" > "${target_ebuild}"

	# Append custom src_install hook
	cat << 'EOF' >> "${target_ebuild}"

src_install() {
	upstream_src_install

	einfo "Installing ChromeOS Atlas libwidevinecdm.so..."
	local cdm_base="${ED}/${CHROME_HOME}/WidevineCdm/_platform_specific"
	local target_dir="${cdm_base}/linux_x64"
	cp "${DISTDIR}/libwidevinecdm.so" "${target_dir}/libwidevinecdm.so" || \
		die "Failed to copy Widevine CDM"

	# Configure ChromeOS User-Agent wrapper (Tier 1)
	dodir /etc/default
	cat <<- CONF > "${ED}/etc/default/google-chrome"
	# ChromeOS User Agent for Widevine DRM streaming
	CHROME_USER_AGENT="Mozilla/5.0 (X11; CrOS x86_64 10066.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${PV%%.*}.0.0.0 Safari/537.36"
	# Hardware video acceleration flags
	CHROME_FLAGS="--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder,VaapiOnNvidiaGPUs"
	CONF

	local hook
	hook='if [[ -f /etc/default/google-chrome ]]; then\n'
	hook+='\tsource /etc/default/google-chrome\n'
	hook+='fi\n'
	hook+='if [[ -n "${CHROME_FLAGS}" ]]; then\n'
	hook+='\tset -- ${CHROME_FLAGS} "$@"\n'
	hook+='fi\n'
	hook+='if [[ -n "${CHROME_USER_AGENT:-\${CHROME_OS_UA}}" ]]; then\n'
	hook+='\tset -- --user-agent="${CHROME_USER_AGENT:-\${CHROME_OS_UA}}" "$@"\n'
	hook+='fi\n&'

	sed --in-place \
		"s|^exec -a .*|${hook}|" \
		"${ED}/${CHROME_HOME}/google-chrome" || \
		die "Failed to patch google-chrome launcher"
}
EOF
done

# 3. Prune obsolete ebuilds from overlay
for local_ebuild_path in "${OVERLAY_DIR}"/google-chrome-*.ebuild; do
	[[ -e "${local_ebuild_path}" ]] || continue
	local_name="$(basename "${local_ebuild_path}")"
	if [[ ! -f "${UPSTREAM_DIR}/${local_name}" ]]; then
		echo "Removing obsolete ebuild: ${local_name}"
		rm --force "${local_ebuild_path}"
	fi
done

# 4. Generate Manifest
echo "Updating Manifest..."
manifest_file="${OVERLAY_DIR}/Manifest"
> "${manifest_file}"

if [[ -f "${UPSTREAM_DIR}/Manifest" ]]; then
	grep --extended-regexp '^DIST google-chrome-stable_.*_amd64\.deb' \
		"${UPSTREAM_DIR}/Manifest" >> "${manifest_file}" || true
fi

tmp_widevine="$(mktemp)"
trap 'rm --force "${tmp_widevine}"' EXIT
echo "Fetching ${WIDEVINE_URL} for checksumming..."
curl \
	--fail \
	--location \
	--output "${tmp_widevine}" \
	--show-error \
	--silent \
	"${WIDEVINE_URL}"

wv_size=$(stat --format=%s "${tmp_widevine}")
wv_b2=$(b2sum "${tmp_widevine}" | awk '{print $1}')
wv_sha512=$(sha512sum "${tmp_widevine}" | awk '{print $1}')

echo "DIST libwidevinecdm.so ${wv_size} BLAKE2B ${wv_b2} SHA512 ${wv_sha512}" \
	>> "${manifest_file}"
sort --output="${manifest_file}" --unique "${manifest_file}"

echo "Done! Ebuilds and Manifest updated successfully."
