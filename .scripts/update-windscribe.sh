#!/usr/bin/env bash
# Update Windscribe ebuild in Gentoo overlay.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERLAY_DIR="${REPO_ROOT}/net-vpn/windscribe-bin"

# 1. Determine target version
TARGET_VER="${1:-}"

if [[ -z "${TARGET_VER}" ]]; then
	echo "Checking upstream for latest Windscribe release..."
	release_url="$(curl \
		--fail \
		--location \
		--output /dev/null \
		--silent \
		--write-out '%{url_effective}\n' \
		"https://github.com/Windscribe/Desktop-App/releases/latest")"
	TARGET_VER="$(basename "${release_url}")"
fi

# Strip leading 'v'
TARGET_VER="${TARGET_VER#v}"

if [[ -z "${TARGET_VER}" ]]; then
	echo "Error: Could not determine version." >&2
	exit 1
fi

echo "Target version: ${TARGET_VER}"

TARGET_EBUILD="${OVERLAY_DIR}/windscribe-bin-${TARGET_VER}.ebuild"
if [[ -f "${TARGET_EBUILD}" ]]; then
	echo "Windscribe is already up to date (${TARGET_VER})."
	exit 0
fi

# 2. Find template ebuild
existing_ebuilds=("${OVERLAY_DIR}"/windscribe-bin-*.ebuild)
if [[ ! -e "${existing_ebuilds[0]}" ]]; then
	echo "Error: No template ebuild found in ${OVERLAY_DIR}" >&2
	exit 1
fi
template_ebuild="${existing_ebuilds[0]}"

echo "Creating ${TARGET_EBUILD} from ${template_ebuild}..."
cp "${template_ebuild}" "${TARGET_EBUILD}"

# 3. Remove older ebuilds
for old_ebuild in "${existing_ebuilds[@]}"; do
	[[ "${old_ebuild}" == "${TARGET_EBUILD}" ]] && continue
	echo "Removing old ebuild: $(basename "${old_ebuild}")"
	rm --force "${old_ebuild}"
done

# 4. Download release packages and write Manifest
MANIFEST_FILE="${OVERLAY_DIR}/Manifest"
> "${MANIFEST_FILE}"

tmp_dir="$(mktemp --directory)"
trap 'rm --force --recursive "${tmp_dir}"' EXIT

base_url="https://github.com/Windscribe/Desktop-App/releases/download"
ARCHES=("amd64" "arm64")
for arch in "${ARCHES[@]}"; do
	deb_name="windscribe_${TARGET_VER}_${arch}.deb"
	deb_url="${base_url}/v${TARGET_VER}/${deb_name}"
	deb_path="${tmp_dir}/${deb_name}"

	echo "Downloading ${deb_name} to compute checksums..."
	curl \
		--fail \
		--location \
		--output "${deb_path}" \
		--show-error \
		--silent \
		"${deb_url}"

	size=$(stat --format=%s "${deb_path}")
	b2=$(b2sum "${deb_path}" | awk '{print $1}')
	sha512=$(sha512sum "${deb_path}" | awk '{print $1}')

	echo "DIST ${deb_name} ${size} BLAKE2B ${b2} SHA512 ${sha512}" \
		>> "${MANIFEST_FILE}"
done

sort --output="${MANIFEST_FILE}" --unique "${MANIFEST_FILE}"

echo "Updated Windscribe ebuild and Manifest to ${TARGET_VER}."
