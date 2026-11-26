#!/usr/bin/env bash
# Cross-builds victory.exe for Windows on Linux with cargo-xwin (which downloads the
# MSVC CRT and Windows SDK on first use; that means accepting Microsoft's license).
# Usage: linux/build.sh [release|diag]   (diag: the diagnostics build, for VICTORY_LOG etc.)
set -euo pipefail
cd "$(dirname "$0")/.."
command -v cargo-xwin >/dev/null || { echo "install it first: cargo install --locked cargo-xwin" >&2; exit 1; }
case "${1:-release}" in
    release) cargo xwin build --release -p victory --locked --target x86_64-pc-windows-msvc ;;
    diag) cargo xwin build --profile diag -p victory --features diagnostics --locked --target x86_64-pc-windows-msvc ;;
    *) echo "usage: $0 [release|diag]" >&2; exit 1 ;;
esac
echo "built: target/x86_64-pc-windows-msvc/${1:-release}/victory.exe"
