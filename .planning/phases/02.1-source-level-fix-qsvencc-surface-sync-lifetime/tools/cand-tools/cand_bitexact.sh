#!/usr/bin/env bash
# cand_bitexact.sh -- single-session bit-exactness + fps gate for a candidate binary (needs the GPU, EXCLUSIVELY).
# Encodes scenes 923/928/1129 one at a time with the exact harness COMMON/seek/trim, compares md5 with the
# stock-8.31 isolated references (8.22 and 8.31 references are bit-identical: ca77cc72.. / 0c37720d.. / e0061679..)
# and prints the fps of each encode.   usage: cand_bitexact.sh <qsvencc-binary> <outdir>   (outdir NOT under /data)
set -u
BIN="${1:?binary}"; OUT="${2:?outdir}"; mkdir -p "$OUT"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../repro" && pwd)"
source "$HERE/lib.sh"                      # SRC, COMMON, SCENE_*  (read-only reuse of the harness config)
declare -A REF=([923]=ca77cc72b0cfa2cfd291f278ab62f278 [928]=0c37720dd1886fceef86b45abe24d389 [1129]=e0061679b2904499162081e5b0ef96ef)
declare -A SEEK=([923]=$SCENE_923_SEEK [928]=$SCENE_928_SEEK [1129]=$SCENE_1129_SEEK)
declare -A TRIM=([923]=$SCENE_923_TRIM [928]=$SCENE_928_TRIM [1129]=$SCENE_1129_TRIM)
require_gpu_exclusive || exit 2
rc=0
for s in 923 928 1129; do
  for rep in 1 2; do
    o="$OUT/single_${s}_r$rep.obu"
    timeout -k 10 120 "$BIN" --avhw --va -i "$SRC" $COMMON --seek "${SEEK[$s]}" --trim "${TRIM[$s]}" -o "$o" > "$OUT/single_${s}_r$rep.log" 2>&1 || { echo "scene $s rep $rep: ENCODE FAILED"; rc=1; continue; }
    m="$(md5sum < "$o" | awk '{print $1}')"
    fps="$(sed 's/\x1b\[[0-9;]*m//g' "$OUT/single_${s}_r$rep.log" | awk '/^encoded/ {for(i=1;i<=NF;i++) if($i=="fps,") print $(i-1)}')"
    [[ "$m" == "${REF[$s]}" ]] && v=BITEXACT || { v=MISMATCH; rc=1; }
    echo "scene $s rep $rep: $v md5=$m fps=$fps"
  done
done
exit $rc
