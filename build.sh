#!/bin/bash

set -o nounset
set -o errexit

SELF_DIR="$(readlink -f "$(dirname "$0")")"
readonly SELF_DIR

readonly BIN_DIR="$SELF_DIR/target/i686-unknown-none/release"
readonly BIN_PATH="$BIN_DIR/snake686"

#
# Build.
#
cargo build -Zjson-target-spec --release

#
# Extract the bootsector from an ELF into a standalone file.
#
objcopy -I elf32-i386 -O binary "$BIN_PATH" "$BIN_DIR/bootsector"

#
# Optionally, run it via QEMU.
#
if [ "$#" -eq 1 ] && [ "$1" = "--run" ]; then
    qemu-system-x86_64 --drive format=raw,file="$BIN_DIR/bootsector"
fi