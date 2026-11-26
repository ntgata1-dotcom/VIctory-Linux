#!/usr/bin/env bash
# A run's frame times and where they go, from the log of a diagnostics build
# (linux/build.sh diag): the numbers to compare two runs by, and to post.
# The log has a line every 5 s; only lines of world frames count (1,000
# draws or more), also grouped by draws: frames of one scene differ by
# their draws far more than runs differ.
# Usage: linux/summary.sh <log> [<log> ...]
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: $0 <log> [<log> ...]" >&2; exit 1; }
for log in "$@"; do
    sed 's/\x1b\[[0-9;]*m//g' "$log" | awk -v name="$(basename "$log" .log)" '
        /victory_gpu::host: [0-9.]+ fps, [0-9.]+ ms\/frame \(/ {
            ms = d = p = c = g = b = ""
            for (i = 1; i <= NF; i++) {
                if ($i == "ms/frame") ms = $(i - 1)
                if ($i ~ /^draws\/frame/) d = $(i - 1)
                if ($i == "preparing:") p = substr($(i - 1), 2)
                if ($i == "copies") c = $(i + 1)
                if ($i == "GPU;") g = $(i - 3)
                if ($i == "copying" && $(i + 1) == "back") b = $(i - 1)
            }
            if (d + 0 < 1000) next
            n++; v[n] = ms; P += p; C += c; G += g; B += b
            k = d < 2500 ? 1 : d < 4000 ? 2 : 3
            S[k] += ms; N[k]++
        }
        /victory_gpu::copystat: copies per frame/ {
            for (i = 1; i <= NF; i++) {
                if ($i == "refreshes") { r += $(i - 1); rn++ }
                if ($i == "guard" && $(i + 1) ~ /^faults/) { f += $(i - 1); fn++ }
            }
        }
        END {
            if (!n) { printf "%s: no samples of world frames\n", name; exit }
            asort(v)
            printf "%s: %d samples of world frames (5 s each), median %.0f ms a frame (%.1f fps)\n", name, n, v[int(n / 2) + 1], 1000 / v[int(n / 2) + 1]
            printf "  by draws:  1,000-2,500 %s | 2,500-4,000 %s | 4,000+ %s  (ms, mean)\n",
                N[1] ? sprintf("%.0f", S[1] / N[1]) : "-", N[2] ? sprintf("%.0f", S[2] / N[2]) : "-", N[3] ? sprintf("%.0f", S[3] / N[3]) : "-"
            printf "  per frame: preparing %.0f ms (copies %.0f), GPU %.0f ms, copying back %.0f ms\n", P / n, C / n, G / n, B / n
            if (rn) printf "  per frame: %.0f refreshes, %.0f guard faults\n", r / rn, fn ? f / fn : 0
        }'
done
