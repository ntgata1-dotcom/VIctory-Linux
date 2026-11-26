#!/usr/bin/env bash
# Names the places in VIctory's own code that a run's log gives as offsets
# (`victory.exe+0x2b9533`, in crash lines and in backtraces), from the build's
# PDB next to the exe. Offsets into the title are left alone: the title has no
# symbols, and nothing of it goes into reports beyond the offset.
# Usage: linux/symbolize.sh <log> [release|diag]    (needs llvm-symbolizer)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
log=${1:?usage: $0 <log> [release|diag]}
exe="$here/../target/x86_64-pc-windows-msvc/${2:-release}/victory.exe"
[ -f "$exe" ] || { echo "no $exe: build it first (linux/build.sh ${2:-release})" >&2; exit 1; }
[ -f "${exe%.exe}.pdb" ] || { echo "no ${exe%.exe}.pdb next to the exe" >&2; exit 1; }
command -v llvm-symbolizer >/dev/null || { echo "install llvm (llvm-symbolizer)" >&2; exit 1; }
base=$(llvm-readobj --file-headers "$exe" | awk '/ImageBase/ {print $2}')
# The log names the exe by whatever file it was run as; any name ending in .exe
# that is not the title's is taken as ours, so pass the log of this build only.
grep -oE '[A-Za-z0-9_.-]+\.exe\+0x[0-9a-fA-F]+' "$log" | grep -v '^game_' | sort | uniq -c | sort -rn |
    while read -r count site; do
        off=${site##*+}
        printf '%s (%s times):\n' "$site" "$count"
        llvm-symbolizer --obj="$exe" --pretty-print "$(printf '0x%x' $((base + off)))" | sed 's/^/    /'
    done
