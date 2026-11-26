#!/usr/bin/env bash
# Runs the title under Wine with a memory cap and a time limit, logging to linux/logs/.
# A run that hangs the GPU can take the desktop with it: save your work first.
# Usage: linux/run.sh [seconds] [release|diag]    (default 1800 s, release)
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/env.sh" || { echo "copy linux/env.example.sh to linux/env.sh and edit it first" >&2; exit 1; }
secs=${1:-1800}; profile=${2:-release}
exe="$here/../target/x86_64-pc-windows-msvc/$profile/victory.exe"
[ -f "$exe" ] || { echo "build first: linux/build.sh $profile" >&2; exit 1; }
logs="$here/logs"; mkdir -p "$logs"; tag=$(date +%Y%m%d-%H%M%S)
journalctl -k -f -n 0 --no-pager 2>/dev/null | grep --line-buffered -iE 'amdgpu|nouveau|nvidia|i915|xe |gpu reset|ring .* timeout' > "$logs/$tag-kernel.log" &
klog=$!
trap 'kill $klog 2>/dev/null; wineserver -k 2>/dev/null' EXIT
echo "logging to $logs/$tag.log (kernel GPU messages: $logs/$tag-kernel.log)"
systemd-run --user --scope -q -p MemoryMax="${VICTORY_MEMORY_MAX:-24G}" -- \
    timeout -k 15 "$secs" wine "$exe" run "$VICTORY_GAME_DIR\\$VICTORY_GAME_EXE" --execute \
    > "$logs/$tag.log" 2>&1
echo "exit=$?"
