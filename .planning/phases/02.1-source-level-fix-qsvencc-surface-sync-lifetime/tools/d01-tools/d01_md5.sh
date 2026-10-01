#!/usr/bin/env bash
# d01_md5.sh -- whole-file corruption detector (no GPU, no PSNR).
# A clean concurrent run is BIT-IDENTICAL to the isolated single-session reference of its scene
# (verified Phase-1/8.22 and 8.31: S<->clean, D<->harness-corrupt, 60/60 + 60/60 outputs agree).
# usage: d01_md5.sh <workdir-with-runs/-and-reference/>   (e.g. scratch/repro-831)
# prints one line per iteration: S = same md5 as reference, D = different.  Exit 0 always.
set -u
W="${1:?workdir (contains runs/ and reference/)}"
declare -A refmd5
for s in 923 928 1129; do refmd5[$s]="$(md5sum < "$W/reference/chunk${s}_ref.obu" | awk '{print $1}')"; done
printf "%-6s %-5s %-5s %-5s\n" iter 923 928 1129
for d in "$W"/runs/it*; do
  it="${d##*/it}"; row=""
  for s in 923 928 1129; do
    f="$d/c$s.obu"
    if [[ ! -s "$f" ]]; then row="$row  ?  "; continue; fi
    m="$(md5sum < "$f" | awk '{print $1}')"
    [[ "$m" == "${refmd5[$s]}" ]] && row="$row  S  " || row="$row  D  "
  done
  printf "it%-4s %s\n" "$it" "$row"
done
