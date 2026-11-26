#!/usr/bin/env bash
# Makes the Wine prefix VIctory runs in, with vkd3d-proton and DXVK's dxgi from a
# GE-Proton release. Usage: linux/setup-prefix.sh <GE-Proton directory> [d3dcompiler_47.dll]
# The optional second argument is Microsoft's d3dcompiler_47.dll, which you supply
# yourself; without it Wine's own compiler is used (enough with this repo's clamp).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ -f "$here/env.sh" ] || { echo "copy linux/env.example.sh to linux/env.sh and edit it first" >&2; exit 1; }
. "$here/env.sh"
ge=${1:?usage: $0 <GE-Proton directory> [d3dcompiler_47.dll]}
vkd3d="$ge/files/lib/wine/vkd3d-proton/x86_64-windows"
dxvk="$ge/files/lib/wine/dxvk/x86_64-windows"
for f in "$vkd3d/d3d12.dll" "$vkd3d/d3d12core.dll" "$dxvk/dxgi.dll"; do
    [ -f "$f" ] || { echo "not found: $f (is this a GE-Proton directory?)" >&2; exit 1; }
done
mkdir -p "$WINEPREFIX"
WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u >/dev/null 2>&1
sys32="$WINEPREFIX/drive_c/windows/system32"
cp "$vkd3d/d3d12.dll" "$vkd3d/d3d12core.dll" "$dxvk/dxgi.dll" "$sys32/"
if [ -n "${2:-}" ]; then
    cp "$2" "$sys32/d3dcompiler_47.dll"
    echo "Microsoft's d3dcompiler_47 installed: add ';d3dcompiler_47=n' to WINEDLLOVERRIDES in linux/env.sh"
fi
wineserver -k 2>/dev/null || true
echo "prefix ready: $WINEPREFIX"
