#!/usr/bin/env bash
# d01_fullscan.sh -- for every md5-different output (D) of a workdir, list ALL frame indices that differ from
# the isolated reference (psnr != inf). Verified on all 30 corrupt outputs (8.31: 13, 8.22: 17): exactly 295..299.
# usage: d01_fullscan.sh <workdir> <outdir>      (no GPU; ~6-10 s per corrupt output)
set -u
W="${1:?workdir}"; OUT="${2:?outdir}"; mkdir -p "$OUT"
for d in "$W"/runs/it*; do it="${d##*/it}"
  for s in 923 928 1129; do
    f="$d/c$s.obu"; r="$W/reference/chunk${s}_ref.obu"
    [[ -s "$f" ]] || continue
    [[ "$(md5sum < "$f")" == "$(md5sum < "$r")" ]] && continue
    LC_ALL=C ffmpeg -hide_banner -loglevel error -nostdin -y -i "$f" -i "$r" -lavfi "psnr=stats_file=$OUT/full_${s}_it$it.log" -f null - 2>/dev/null
    echo "it$it scene $s: differing idx = $(awk '{n=$1; sub("n:","",n); split($6,a,":"); if (a[2]!="inf") printf "%d ", n-1}' "$OUT/full_${s}_it$it.log")"
  done
done
