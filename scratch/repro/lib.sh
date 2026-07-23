#!/usr/bin/env bash
# lib.sh -- shared config + helpers for scratch/repro/harness.sh
#
# Sourced by harness.sh. Not meant to be executed directly.
# See harness.sh header for the full protocol this supports.

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# Read-only source media (never written to; see D-09 / T-01-01).
SRC="/data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv"

# Workdir -- hardcoded under scratch/repro/. Never construct a path under
# /data from any variable in this file (D-09, T-01-01).
W="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Exact qsvencc flag string from PROJECT.md §4 / 01-RESEARCH.md Code Examples,
# reused verbatim (color flags are the "auto" set for this SDR source).
COMMON="-c av1 --icq 24 --qp-max 100 --output-depth 10 --profile main \
  --gop-len 300 --gop-ref-dist 6 --b-pyramid --tile-col 1 --tile-row 1 \
  --tune perceptual --scenario-info archive \
  --colorrange auto --colormatrix auto --colorprim auto --transfer auto --chromaloc auto"

# Per-encode timeout (review concern 2). Overridable via env for testing.
ENCODE_TIMEOUT="${ENCODE_TIMEOUT:-120}"

# Scene table (PROJECT.md §4): scene -> seek, trim, hotspot offset.
SCENE_923_SEEK="01:16:14.167"; SCENE_923_TRIM="0:339"; SCENE_923_OFF=299
SCENE_928_SEEK="01:17:00.667"; SCENE_928_TRIM="0:110"; SCENE_928_OFF=96
SCENE_1129_SEEK="01:34:24.583"; SCENE_1129_TRIM="0:361"; SCENE_1129_OFF=299

# ---------------------------------------------------------------------------
# gpu_clients -- list PIDs currently holding an fd on renderD128.
# fuser/lsof are absent in this container; this is the verified fallback
# (01-RESEARCH.md "GPU-exclusivity check").
# ---------------------------------------------------------------------------
gpu_clients() {
  for pidfd in /proc/[0-9]*/fd/*; do
    t=$(readlink "$pidfd" 2>/dev/null) || continue
    [[ "$t" == *renderD128* ]] || continue
    pid=$(echo "$pidfd" | cut -d/ -f3)
    echo "PID $pid: $(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
  done
}

# ---------------------------------------------------------------------------
# require_gpu_exclusive -- abort before any "isolated"/"reference"/
# "control-reference" run if the GPU is not exclusively ours.
# ---------------------------------------------------------------------------
require_gpu_exclusive() {
  local clients
  clients="$(gpu_clients)"
  if [[ -n "$clients" ]]; then
    echo "ABORT: GPU not exclusive, found: $clients" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# run_encode -- run a single encode command under a timeout, returning its
# exit code. Exit 124 means the timeout fired (caller treats this distinctly
# from a normal non-zero exit -- review concern 2).
#
# Usage: run_encode <logfile> <cmd...>
# ---------------------------------------------------------------------------
run_encode() {
  local logfile="$1"; shift
  timeout "${ENCODE_TIMEOUT}" "$@" > "$logfile" 2>&1
  return $?
}

# ---------------------------------------------------------------------------
# cleanup_gpu_procs -- kill -9 any leftover qsvencc/ffmpeg PIDs still bound
# to renderD128 after an iteration, so a zombie can't trip the next
# iteration's exclusivity gate (review concerns 2 + 4-adjacent). Only ever
# targets PIDs derived from gpu_clients() with a qsvencc/ffmpeg cmdline --
# never a blanket pkill (T-01-04).
# ---------------------------------------------------------------------------
cleanup_gpu_procs() {
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local pid cmd
    pid="${line#PID }"; pid="${pid%%:*}"
    cmd="${line#*: }"
    if [[ "$cmd" == *qsvencc* || "$cmd" == *ffmpeg* ]]; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  done < <(gpu_clients)
}
