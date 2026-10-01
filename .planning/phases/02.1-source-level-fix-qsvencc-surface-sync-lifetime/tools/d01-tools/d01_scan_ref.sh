#!/usr/bin/env bash
# d01_scan_ref.sh -- D-01 (no GPU): PSNR of ONE saved corrupt frame (PNG) against ALL frames of its own
# scene's isolated reference OBU. Same rgb48be conversion as the harness's PNG extraction, so a
# frame that is the same SOURCE frame re-encoded scores >=40 dB; unrelated frames score 10-20 dB.
# usage: d01_scan_ref.sh <ref.obu> <corrupt.png> <nframes> <stats_out.log>
# stats n: is 1-based (n:300 == frame index 299). Prints "idx psnr" top-3 (idx 0-based).
set -u
ref="$1"; png="$2"; n="$3"; out="$4"
LC_ALL=C ffmpeg -hide_banner -loglevel error -nostdin -y -i "$ref" -loop 1 -framerate 25 -i "$png" \
  -lavfi "[0:v]format=rgb48be[a];[1:v]format=rgb48be[b];[a][b]psnr=stats_file=$out" -frames:v "$n" -f null - || exit 1
awk '{n=$1; sub("n:","",n); split($6,a,":"); p=a[2]; if (p=="inf") p=999; print p, n-1}' "$out" | sort -rn | head -3
