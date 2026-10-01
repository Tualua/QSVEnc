#!/usr/bin/env bash
# d01_scan_batch.sh -- D-01 over a whole batch: for every corrupt row of <workdir>/report.csv run the
# own-scene reference scan. Output TSV: iter scene harness_psnr best_idx best_psnr second_idx second_psnr verdict
# verdict = STALE_OWN_FRAME(<idx>) if best>=35 dB and idx != hotspot (intra-session stale surface),
#           OTHER otherwise.  Needs only ffmpeg (software decode); ~6 s per corrupt frame on 16 cores.
# usage: d01_scan_batch.sh <workdir> <outdir>
set -u
W="${1:?workdir}"; O="${2:?outdir}"; mkdir -p "$O"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -A NF=([923]=340 [928]=111 [1129]=362)
declare -A PNG=([923]=frame299.png [928]=frame96_928.png [1129]=frame299_1129.png)
declare -A HOT=([923]=299 [928]=96 [1129]=299)
printf "iter\tscene\tharness_psnr\tbest_idx\tbest_psnr\tsecond_idx\tsecond_psnr\tverdict\n"
awk -F, 'NR>1 && $6==1 {print $1","$2","$5}' "$W/report.csv" | while IFS=, read -r it sc ps; do
  read -r p1 i1 p2 i2 < <("$HERE/d01_scan_ref.sh" "$W/reference/chunk${sc}_ref.obu" "$W/runs/it$it/${PNG[$sc]}" "${NF[$sc]}" "$O/scan_${sc}_it$it.log" | head -2 | tr '\n' ' ')
  v=OTHER
  if awk -v p="$p1" 'BEGIN{exit !(p+0>=35)}' && [[ "$i1" != "${HOT[$sc]}" ]]; then v="STALE_OWN_FRAME($i1)"; fi
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$it" "$sc" "$ps" "$i1" "$p1" "$i2" "$p2" "$v"
done
