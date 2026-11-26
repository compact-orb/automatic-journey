#!/usr/bin/env bash
# Update AmneziaWG kernel module ebuild in Gentoo overlay.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERLAY_DIR="${REPO_ROOT}/net-vpn/amneziawg-modules"
UPSTREAM_REPO="https://github.com/amnezia-vpn/amneziawg-linux-kernel-module"

# 1. Determine target tag and Gentoo version
TARGET_TAG="${1:-}"

if [[ -z "${TARGET_TAG}" ]]; then
	echo "Checking upstream for latest AmneziaWG tag..."
	TARGET_TAG="$(git ls-remote --refs --tags "${UPSTREAM_REPO}.git" |
		awk -F'refs/tags/' '
			$2 ~ /^v[0-9]+(\.[0-9]+)+(-[0-9]+)?$/ { print $2 }
		' |
		sort --version-sort |
		tail --lines=1)"
fi

TARGET_TAG="${TARGET_TAG#v}"
TARGET_TAG="${TARGET_TAG//_p/-}"
TARGET_VER="${TARGET_TAG//-/_p}"

if [[ -z "${TARGET_VER}" ]]; then
	echo "Error: Could not determine version." >&2
	exit 1
fi

echo "Target tag: v${TARGET_TAG} (version ${TARGET_VER})"

# 2. Check existing ebuilds and find template
existing_ebuilds=("${OVERLAY_DIR}"/amneziawg-modules-*.ebuild)
if [[ ! -e "${existing_ebuilds[0]}" ]]; then
	echo "Error: No template ebuild found in ${OVERLAY_DIR}" >&2
	exit 1
fi

target_prefix="${OVERLAY_DIR}/amneziawg-modules-${TARGET_VER}"
TARGET_EBUILD="${target_prefix}.ebuild"
for ebuild in "${existing_ebuilds[@]}"; do
	if [[ "${ebuild}" == "${TARGET_EBUILD}" ||
		"${ebuild}" == "${target_prefix}"-r*.ebuild ]]; then
		echo "AmneziaWG modules is up to date (${TARGET_VER})."
		exit 0
	fi
done

template_ebuild="${existing_ebuilds[0]}"
echo "Creating ${TARGET_EBUILD} from ${template_ebuild}..."
cp "${template_ebuild}" "${TARGET_EBUILD}"

# 3. Remove older ebuilds
for old_ebuild in "${existing_ebuilds[@]}"; do
	echo "Removing old ebuild: $(basename "${old_ebuild}")"
	rm --force "${old_ebuild}"
done

# 4. Download source tarball and write Manifest
MANIFEST_FILE="${OVERLAY_DIR}/Manifest"
tmp_dir="$(mktemp --directory)"
trap 'rm --force --recursive "${tmp_dir}"' EXIT

tar_name="amneziawg-modules-${TARGET_VER}.tar.gz"
tar_url="${UPSTREAM_REPO}/archive/refs/tags/v${TARGET_TAG}.tar.gz"
tar_path="${tmp_dir}/${tar_name}"

echo "Downloading ${tar_name} to compute checksums..."
curl \
	--fail \
	--location \
	--output "${tar_path}" \
	--show-error \
	--silent \
	"${tar_url}"

size=$(stat --format=%s "${tar_path}")
b2=$(b2sum "${tar_path}" | awk '{print $1}')
sha512=$(sha512sum "${tar_path}" | awk '{print $1}')

echo "DIST ${tar_name} ${size} BLAKE2B ${b2} SHA512 ${sha512}" \
	> "${MANIFEST_FILE}"

echo "Updated AmneziaWG modules ebuild and Manifest to ${TARGET_VER}."
