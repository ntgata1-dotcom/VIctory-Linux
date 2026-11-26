#!/usr/bin/env bash
# Translates every shader of the title's pack and makes its host pipelines
# once, into VICTORY_CACHE_DIR (VIctory's `translate --cache --pipelines`), so
# runs neither translate shaders nor build pipelines while they play. Again
# after a VIctory update that changes the translator. Takes minutes.
# Usage: linux/warm-cache.sh [release|diag]
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/env.sh" || { echo "copy linux/env.example.sh to linux/env.sh and edit it first" >&2; exit 1; }
exe="$here/../target/x86_64-pc-windows-msvc/${1:-release}/victory.exe"
[ -f "$exe" ] || { echo "build first: linux/build.sh ${1:-release}" >&2; exit 1; }
trap 'wineserver -k 2>/dev/null' EXIT
if [ -n "${VICTORY_WINESERVER:-}" ]; then
    wineserver -k 2>/dev/null || true
    "$VICTORY_WINESERVER" -p 60 || exit 1
fi
g="$VICTORY_GAME_DIR"
wine "$exe" translate --cache --pipelines "$g\\shaders.rpf" "$g\\$VICTORY_GAME_EXE" \
    "$g\\XboxBvhBuilder.dll" "$g\\amd_fidelityfx_upscaler_xbox.dll"
