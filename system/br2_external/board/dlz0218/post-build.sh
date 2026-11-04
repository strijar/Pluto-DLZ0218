#!/bin/sh
set -eu

BOARD_DIR="${BR2_EXTERNAL_SYSTEM_PATH}/board/dlz0218"

install -m 0644 -D "${BOARD_DIR}/extlinux.conf" "${BINARIES_DIR}/extlinux/extlinux.conf"
mkdir -p "${BINARIES_DIR}/settings"

# Always package the bitstream exported by this board's FPGA build.

BITSTREAM="${DLZ0218_BITSTREAM:-${BR2_EXTERNAL_SYSTEM_PATH}/../../fpga/build/export/system.bit}"

if [ ! -s "${BITSTREAM}" ]; then
    echo "Build fpga first: missing ${BITSTREAM}" >&2
    exit 1
fi

install -m 0644 "${BITSTREAM}" "${BINARIES_DIR}/system.bit"
