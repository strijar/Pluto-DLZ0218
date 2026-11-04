#!/bin/sh
set -eu

BOARD_DIR="${BR2_EXTERNAL_SYSTEM_PATH}/board/dlz0218"

support/scripts/genimage.sh -c "${BOARD_DIR}/genimage.cfg"
