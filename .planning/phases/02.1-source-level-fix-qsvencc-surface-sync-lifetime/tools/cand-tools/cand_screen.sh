#!/usr/bin/env bash
# cand_screen.sh -- sequential candidate screening through the UNMODIFIED harness's own `run-iter`.
# D-08: >=1 corrupt frame at 923/299 or 1129/299 == "not a fix" -> stop at the FIRST one (a non-fix with the
# 8.31 baseline [P(any hot corrupt)=0.545/iteration] is rejected within ~2 iterations on average, 98% within 5)
# instead of burning a full N=20 batch (~9 min). If MAX valid iterations pass with 0 corrupt -> "ESCALATE" (D-08),
# i.e. run the official `./harness.sh run-batch 60` in a FRESH candidate dir (cand_setup.sh refuses to reuse one).
# usage: cand_screen.sh <candidate-dir> [MAX=20]       (GPU: exclusive, sequential; ~26 s/iteration)
# UNTESTED against the real GPU harness -- logic tested with stubs only.
set -u
W="$(cd "${1:?candidate dir (from cand_setup.sh)}" && pwd)"; MAX="${2:-20}"
cd "$W" || exit 2
source ./lib.sh                                  # gpu_clients, cleanup_gpu_procs, require_gpu_exclusive (unchanged harness lib)
export PATH="$W/bin:$PATH"
echo "iteration,scene,offset,status,psnr_db,corrupt,control_clean" > report.csv
valid=0; total=0; verdict="PASS-SO-FAR"
for i in $(seq 1 "$MAX"); do
  it="$(printf '%02d' "$i")"
  idle=0
  for r in 1 2 3; do sleep 1; [[ -z "$(gpu_clients)" ]] && { idle=1; break; }; cleanup_gpu_procs; done
  (( idle )) || { echo "ABORT: GPU not idle before iteration $it: $(gpu_clients)" >&2; exit 3; }
  ./harness.sh run-iter "$it" >> batch.log 2>&1 || true
  f="runs/it$it/result.csv"
  [[ -s "$f" ]] || { echo "iteration $it: no result.csv (EXEC_FAILURE?)" >&2; total=$((total+1)); continue; }
  cat "$f" >> report.csv; total=$((total+1))
  if awk -F, '$4!="OK"{bad=1} END{exit !bad}' "$f"; then echo "iteration $it: INVALID (non-OK status) -- not counted"; continue; fi
  valid=$((valid+1))
  if awk -F, '($2==923 || $2==1129) && $6==1 {hit=1} END{exit !hit}' "$f"; then
    echo "iteration $it: CORRUPT hot frame -> candidate REJECTED (D-08) after $valid valid iterations"; verdict="REJECTED"; break
  fi
  echo "iteration $it: clean ($valid/$MAX valid)"
done
if [[ "$verdict" == "PASS-SO-FAR" ]]; then
  need=$(( (MAX*85 + 99) / 100 ))
  if (( valid >= need )); then verdict="ESCALATE-TO-60 ($valid valid iterations, 0 corrupt)"; else verdict="DEGRADED ($valid valid < $need)"; fi
fi
echo "VERDICT: $verdict" | tee verdict.txt
