#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVICE="${1:?device is required}"

BOOT_HEADER_VERSION="${BOOT_HEADER_VERSION:-2}"
BOOT_PAGESIZE="${BOOT_PAGESIZE:-4096}"
BOOT_BASE="${BOOT_BASE:-0x00000000}"
BOOT_KERNEL_OFFSET="${BOOT_KERNEL_OFFSET:-0x00008000}"
BOOT_RAMDISK_OFFSET="${BOOT_RAMDISK_OFFSET:-0x01000000}"
BOOT_TAGS_OFFSET="${BOOT_TAGS_OFFSET:-0x00000100}"
BOOT_DTB_OFFSET="${BOOT_DTB_OFFSET:-0x01f00000}"
BOOT_CMDLINE="${BOOT_CMDLINE:-}"
BOOT_OS_VERSION="${BOOT_OS_VERSION:-12.0.0}"
BOOT_OS_PATCH_LEVEL="${BOOT_OS_PATCH_LEVEL:-2024-01}"

OUT_BOOT_DIR="${ROOT_DIR}/out/arch/arm64/boot"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/${DEVICE}"
RAW_DIR="${ARTIFACT_DIR}/raw"
ANYKERNEL_DIR="${ROOT_DIR}/AnyKernel3-${DEVICE}"
MKBOOTIMG_DIR="${ROOT_DIR}/.cache/mkbootimg"
RAMDISK_DIR="${ARTIFACT_DIR}/ramdisk"

mkdir -p "${RAW_DIR}" "${MKBOOTIMG_DIR}" "${RAMDISK_DIR}"

if [[ -f "${OUT_BOOT_DIR}/Image.gz" ]]; then
	KERNEL_IMAGE="${OUT_BOOT_DIR}/Image.gz"
elif [[ -f "${OUT_BOOT_DIR}/Image" ]]; then
	KERNEL_IMAGE="${OUT_BOOT_DIR}/Image"
else
	echo "Kernel image not found in ${OUT_BOOT_DIR}" >&2
	exit 1
fi

for required_file in "${OUT_BOOT_DIR}/dtb" "${OUT_BOOT_DIR}/dtbo.img"; do
	if [[ ! -f "${required_file}" ]]; then
		echo "Required build output missing: ${required_file}" >&2
		exit 1
	fi
done

cp "${KERNEL_IMAGE}" "${RAW_DIR}/$(basename "${KERNEL_IMAGE}")"
cp "${OUT_BOOT_DIR}/dtb" "${RAW_DIR}/dtb"
cp "${OUT_BOOT_DIR}/dtbo.img" "${RAW_DIR}/dtbo.img"

rm -rf "${ANYKERNEL_DIR}"
git clone --depth=1 "https://github.com/NotZeetaa/AnyKernel3" -b "${DEVICE}" "${ANYKERNEL_DIR}"

cp "${KERNEL_IMAGE}" "${ANYKERNEL_DIR}/$(basename "${KERNEL_IMAGE}")"
cp "${OUT_BOOT_DIR}/dtb" "${ANYKERNEL_DIR}/dtb"
cp "${OUT_BOOT_DIR}/dtbo.img" "${ANYKERNEL_DIR}/dtbo.img"

ZIP_NAME="Nexus-${DEVICE}-${GITHUB_RUN_NUMBER:-local}-${GITHUB_SHA:-manual}.zip"
(
	cd "${ANYKERNEL_DIR}"
	zip -r9 "${ARTIFACT_DIR}/${ZIP_NAME}" ./* -x .git .gitignore '*.zip'
)

rm -f "${ARTIFACT_DIR}/ramdisk.cpio.gz"
(
	cd "${RAMDISK_DIR}"
	printf '' | cpio -o -H newc --quiet | gzip -9 > "${ARTIFACT_DIR}/ramdisk.cpio.gz"
)

if [[ ! -f "${MKBOOTIMG_DIR}/mkbootimg.py" ]]; then
	curl -fsSL "https://android.googlesource.com/platform/system/tools/mkbootimg/+/refs/heads/main/mkbootimg.py?format=TEXT" \
		| base64 --decode > "${MKBOOTIMG_DIR}/mkbootimg.py"
	chmod +x "${MKBOOTIMG_DIR}/mkbootimg.py"
fi

python3 "${MKBOOTIMG_DIR}/mkbootimg.py" \
	--kernel "${KERNEL_IMAGE}" \
	--ramdisk "${ARTIFACT_DIR}/ramdisk.cpio.gz" \
	--dtb "${OUT_BOOT_DIR}/dtb" \
	--header_version "${BOOT_HEADER_VERSION}" \
	--pagesize "${BOOT_PAGESIZE}" \
	--base "${BOOT_BASE}" \
	--kernel_offset "${BOOT_KERNEL_OFFSET}" \
	--ramdisk_offset "${BOOT_RAMDISK_OFFSET}" \
	--tags_offset "${BOOT_TAGS_OFFSET}" \
	--dtb_offset "${BOOT_DTB_OFFSET}" \
	--cmdline "${BOOT_CMDLINE}" \
	--os_version "${BOOT_OS_VERSION}" \
	--os_patch_level "${BOOT_OS_PATCH_LEVEL}" \
	--output "${ARTIFACT_DIR}/boot.img"

sha256sum "${ARTIFACT_DIR}/boot.img" "${ARTIFACT_DIR}/${ZIP_NAME}" > "${ARTIFACT_DIR}/SHA256SUMS"

rm -rf "${ANYKERNEL_DIR}" "${RAMDISK_DIR}"

echo "Artifacts prepared in ${ARTIFACT_DIR}"