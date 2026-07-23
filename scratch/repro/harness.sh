#!/usr/bin/env bash
#
# harness.sh -- calibrated, control-validated reproduction instrument for the
# QSV concurrent-encode frame-corruption bug (see repo-root PROJECT.md).
#
# Purpose: fingerprint this environment, run 3-way concurrent qsvencc on the
# documented hotspot scenes, classify corruption via external-ffmpeg PSNR
# against a bit-clean single-session reference, pair every measurement batch
# with an ffmpeg av1_qsv immune control, and report a baseline corruption
# fraction + PSNR signature over a detection-sized sample.
#
# Authoritative recipe: repo-root PROJECT.md §4 (exact qsvencc command,
# scene/seek/trim/offset table). Reuses the pre-verified commands from
# .planning/phases/01-harness-control-environment-fingerprinting/01-RESEARCH.md
# "Code Examples" verbatim.
#
# Locked decisions this implements (see 01-CONTEXT.md for full rationale):
#   D-01 standalone bash harness under scratch/repro/ (this file + lib.sh)
#   D-02 reproduction target is the stock installed qsvencc (r4385), not a
#        from-source build
#   D-03 exact seek/trim scene table, 923/299 the required primary hotspot
#   D-04 corruption classified via external ffmpeg PSNR, threshold <30dB,
#        never qsvencc --psnr/--ssim (OpenCL-gated)
#   D-05 bit-clean reference = single isolated (non-concurrent) encode,
#        determinism-verified via md5 across two independent runs
#   D-06 every qsvencc measurement batch is paired with an ffmpeg av1_qsv
#        immune control, run sequentially-after as its own separate 3-way
#        run (never merged into one 6-way run -- see run-iter step 3)
#   D-07 N=20 is the phase-1 DETECTION sample size; the larger ~60
#        zero-failure VALIDATION-N (rule-of-three) is defined but reserved
#        for later fix/clean claims, not run in this phase
#   D-08 environment fingerprint fields: kernel, gpu driver, pci id, vainfo,
#        guc/huc firmware -- each individually degrades to UNAVAILABLE
#   D-09 every output path is hardcoded under scratch/repro/; the source
#        media under /data is read-only and never written to
#
# Subcommands:
#   probe            -> writes fingerprint.txt (REPRO-01)
#   reference         -> generates the bit-clean qsvencc reference frame and
#                        the once-only ffmpeg av1_qsv control reference
#                        (REPRO-03 reference half, REPRO-04 control half)
#   run-iter <N>      -> one full end-to-end iteration: 3-way qsvencc measure
#                        -> multi-scene PSNR classify -> sequential 3-way
#                        immune control (REPRO-02, REPRO-03, REPRO-04)
#   run-batch [N=20]  -> loops run-iter N times, writes report.csv + a
#                        summary with the recorded baseline (REPRO-05)
#
# Outputs (all under scratch/repro/, never under /data -- D-09):
#   fingerprint.txt, reference/, control_reference/, runs/it<N>/,
#   control_runs/it<N>/, report.csv
#
# set -e policy (per subcommand, review hygiene item 11):
#   probe      -- the subcommand overall does NOT use `set -e`; every
#                 individual probe line is `|| echo UNAVAILABLE`-guarded so
#                 one blocked command (e.g. dmesg, no CAP_SYS_ADMIN in this
#                 container) can never abort the rest of the fingerprint.
#   reference  -- fails fast overall (`set -e`-equivalent via explicit exit
#                 checks): a determinism mismatch or a frame-count mismatch
#                 must stop the harness loudly before any measurement.
#   run-iter   -- fails fast internally for its own setup, but its own exit
#                 codes for the 3 concurrent measurement encodes and the
#                 control encodes are captured explicitly (never a bare
#                 `set -e` swallowing a background job's failure).
#   run-batch  -- deliberately catches per-iteration failures and continues;
#                 a failed/timed-out iteration is recorded (status column)
#                 and excluded from the corruption-fraction denominator, but
#                 never aborts the batch.

set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SELF_DIR/lib.sh"

AFFECTED_HOST_KERNEL="6.19.14-200.fc43.x86_64"

# ---------------------------------------------------------------------------
# probe -- environment fingerprint (REPRO-01, D-08)
# Every line is individually degraded to UNAVAILABLE; no set -e here.
# ---------------------------------------------------------------------------
cmd_probe() {
  local kernel gpu_driver pci_vendor pci_device vainfo_line guc_huc
  local kernel_match

  kernel="$(uname -r)"
  if [[ "$kernel" == "$AFFECTED_HOST_KERNEL" ]]; then
    kernel_match="YES"
  else
    kernel_match="NO"
  fi

  gpu_driver="$(readlink -f /sys/class/drm/card2/device/driver 2>/dev/null || echo UNAVAILABLE)"
  pci_vendor="$(cat /sys/bus/pci/drivers/i915/*/vendor 2>/dev/null || echo UNAVAILABLE)"
  pci_device="$(cat /sys/bus/pci/drivers/i915/*/device 2>/dev/null || echo UNAVAILABLE)"
  vainfo_line="$(LIBVA_DRIVER_NAME=iHD vainfo 2>&1 | grep -i 'Driver version' || echo UNAVAILABLE)"
  guc_huc="$(dmesg 2>&1 | grep -iE 'guc|huc' || echo 'UNAVAILABLE: dmesg blocked (no CAP_SYS_ADMIN in this container)')"

  {
    echo "kernel: $kernel"
    echo "kernel_matches_affected_host: $kernel_match (affected host: $AFFECTED_HOST_KERNEL)"
    echo "gpu_driver: $gpu_driver"
    echo "pci_id: ${pci_vendor}:${pci_device}"
    echo "vainfo: $vainfo_line"
    echo "guc_huc: $guc_huc"
  } > "$W/fingerprint.txt"

  cat "$W/fingerprint.txt"
}

# ---------------------------------------------------------------------------
# reference -- bit-clean qsvencc reference (D-05) + frame-offset gate +
# once-only ffmpeg av1_qsv control reference (D-06, review concern 5).
# Fails fast: any determinism/gate failure stops the harness loudly.
# ---------------------------------------------------------------------------
cmd_reference() {
  mkdir -p "$W/reference" "$W/control_reference"

  echo "== reference: qsvencc isolated determinism check (scene 923) =="
  require_gpu_exclusive || { echo "ABORT: reference step requires exclusive GPU access" >&2; exit 1; }

  qsvencc --avhw --va -i "$SRC" $COMMON \
    --seek "$SCENE_923_SEEK" --trim "$SCENE_923_TRIM" \
    -o "$W/reference/chunk923_ref.obu" || { echo "ABORT: reference encode (run 1) failed" >&2; exit 1; }

  qsvencc --avhw --va -i "$SRC" $COMMON \
    --seek "$SCENE_923_SEEK" --trim "$SCENE_923_TRIM" \
    -o "$W/reference/chunk923_ref_repeat.obu" || { echo "ABORT: reference encode (run 2) failed" >&2; exit 1; }

  local md5_a md5_b
  md5_a="$(md5sum "$W/reference/chunk923_ref.obu" | awk '{print $1}')"
  md5_b="$(md5sum "$W/reference/chunk923_ref_repeat.obu" | awk '{print $1}')"
  if [[ "$md5_a" != "$md5_b" ]]; then
    echo "ABORT: reference determinism check failed -- md5 $md5_a != $md5_b (D-05 precondition violated)" >&2
    exit 1
  fi
  echo "reference determinism OK: md5 $md5_a matches across two isolated encodes"

  # Frame-offset assertion gate (review concern 6): confirm the encoder's
  # own frame count aligns with the documented offset before trusting it.
  local nb_frames
  nb_frames="$(ffprobe -v error -count_frames -select_streams v:0 \
    -show_entries stream=nb_read_frames -of csv=p=0 \
    "$W/reference/chunk923_ref.obu" 2>/dev/null || echo "")"
  if [[ "$nb_frames" != "340" ]]; then
    echo "ABORT: reference frame count $nb_frames != expected 340 -- offset $SCENE_923_OFF may not map to the documented hotspot; aborting before any measurement" >&2
    exit 1
  fi
  if (( SCENE_923_OFF < 0 || SCENE_923_OFF >= nb_frames )); then
    echo "ABORT: hotspot offset $SCENE_923_OFF out of range [0,$nb_frames)" >&2
    exit 1
  fi
  echo "reference frame-count gate OK: nb_read_frames=$nb_frames, offset $SCENE_923_OFF in range"

  ffmpeg -y -i "$W/reference/chunk923_ref.obu" -vf "select='eq(n\,$SCENE_923_OFF)'" -vsync 0 -frames:v 1 \
    "$W/reference/frame299_ref.png" -hide_banner -loglevel error \
    || { echo "ABORT: reference frame extraction failed" >&2; exit 1; }
  echo "reference frame extracted: $W/reference/frame299_ref.png"

  # Once-only ffmpeg av1_qsv control reference (D-06, review concern 5 --
  # must NOT be re-encoded inside run-iter). Guard with an existence check.
  if [[ -f "$W/control_reference/c923_ffref.obu" ]]; then
    echo "control reference already exists, skipping re-encode: $W/control_reference/c923_ffref.obu"
  else
    echo "== reference: ffmpeg av1_qsv control reference (scene 923) =="
    require_gpu_exclusive || { echo "ABORT: control-reference step requires exclusive GPU access" >&2; exit 1; }
    ctrl_encode "$SCENE_923_SEEK" 339 "$W/control_reference/c923_ffref.obu" \
      || { echo "ABORT: control reference encode failed" >&2; exit 1; }
    ffmpeg -y -i "$W/control_reference/c923_ffref.obu" -vf "select='eq(n\,$SCENE_923_OFF)'" -vsync 0 -frames:v 1 \
      "$W/control_reference/ffref_299.png" -hide_banner -loglevel error \
      || { echo "ABORT: control reference frame extraction failed" >&2; exit 1; }
    echo "control reference generated: $W/control_reference/c923_ffref.obu"
  fi
}

# ---------------------------------------------------------------------------
# ctrl_encode -- ffmpeg av1_qsv immune-control encode helper (D-06).
# Exact working command from 01-RESEARCH.md Code Examples ("-profile:v main"
# is mandatory -- Pitfall 4, plain "-profile main" is ambiguous).
# Usage: ctrl_encode <seek> <frames> <out>
# ---------------------------------------------------------------------------
ctrl_encode() {
  local seek="$1" frames="$2" out="$3"
  local logfile="${out%.obu}.log"
  run_encode "$logfile" ffmpeg -y -hwaccel qsv -hwaccel_output_format qsv -c:v h264_qsv \
    -ss "$seek" -i "$SRC" -frames:v "$frames" \
    -vf "vpp_qsv=format=p010le" \
    -c:v av1_qsv -profile:v main -g 300 -bf 5 -refs 4 -global_quality 24 -look_ahead_depth 0 \
    -tile_cols 1 -tile_rows 1 \
    "$out" -hide_banner -loglevel error
}

# ---------------------------------------------------------------------------
# Scene table lookups (923/928/1129 -> seek, trim, offset, reference paths).
# ---------------------------------------------------------------------------
scene_seek() {
  case "$1" in
    923) echo "$SCENE_923_SEEK" ;;
    928) echo "$SCENE_928_SEEK" ;;
    1129) echo "$SCENE_1129_SEEK" ;;
  esac
}
scene_trim() {
  case "$1" in
    923) echo "$SCENE_923_TRIM" ;;
    928) echo "$SCENE_928_TRIM" ;;
    1129) echo "$SCENE_1129_TRIM" ;;
  esac
}
scene_offset() {
  case "$1" in
    923) echo "$SCENE_923_OFF" ;;
    928) echo "$SCENE_928_OFF" ;;
    1129) echo "$SCENE_1129_OFF" ;;
  esac
}
scene_ref_obu() {
  case "$1" in
    923) echo "$W/reference/chunk923_ref.obu" ;;
    928) echo "$W/reference/chunk928_ref.obu" ;;
    1129) echo "$W/reference/chunk1129_ref.obu" ;;
  esac
}
scene_ref_png() {
  case "$1" in
    923) echo "$W/reference/frame299_ref.png" ;;
    928) echo "$W/reference/frame96_928_ref.png" ;;
    1129) echo "$W/reference/frame299_1129_ref.png" ;;
  esac
}

# ---------------------------------------------------------------------------
# ensure_scene_reference -- generate a scene's isolated reference (chunk +
# extracted hotspot frame) if it does not already exist, mirroring Task 1's
# 923 reference generation. Gated by require_gpu_exclusive, same as the
# `reference` subcommand (923's own reference is normally already present
# from `reference`; 928/1129 are generated lazily here, once, and cached).
# ---------------------------------------------------------------------------
ensure_scene_reference() {
  local scene="$1" obu png seek trim off
  obu="$(scene_ref_obu "$scene")"
  png="$(scene_ref_png "$scene")"
  if [[ -f "$obu" && -f "$png" ]]; then
    return 0
  fi
  seek="$(scene_seek "$scene")"; trim="$(scene_trim "$scene")"; off="$(scene_offset "$scene")"
  echo "generating missing reference for scene $scene (offset $off)..."
  require_gpu_exclusive || { echo "ABORT: reference generation for scene $scene requires exclusive GPU access" >&2; return 1; }
  qsvencc --avhw --va -i "$SRC" $COMMON --seek "$seek" --trim "$trim" -o "$obu" \
    || { echo "ABORT: reference encode for scene $scene failed" >&2; return 1; }
  ffmpeg -y -i "$obu" -vf "select='eq(n\,$off)'" -vsync 0 -frames:v 1 "$png" -hide_banner -loglevel error \
    || { echo "ABORT: reference frame extraction for scene $scene failed" >&2; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# psnr_of -- extract PSNR (psnr_avg field) between a test PNG and a
# reference PNG via external ffmpeg (D-04, OpenCL-free). Prints the raw
# value ("inf" for byte-identical, or a float) to stdout.
# ---------------------------------------------------------------------------
psnr_of() {
  local test_png="$1" ref_png="$2" statsfile="$3"
  LC_ALL=C ffmpeg -y -i "$test_png" -i "$ref_png" -lavfi "psnr=stats_file=$statsfile" \
    -f null - -hide_banner -loglevel error
  awk -F'psnr_avg:' '{split($2,a," "); print a[1]}' "$statsfile"
}

# ---------------------------------------------------------------------------
# classify_corrupt -- < 30 dB = corrupt (1), else clean (0). Threshold-only
# classifier -- never a hardcoded equality against any specific dB value
# (Pitfall 2, Anti-Pattern).
# ---------------------------------------------------------------------------
classify_corrupt() {
  local p="$1"
  if [[ "$p" == "inf" || -z "$p" ]]; then
    echo 0
  else
    awk -v p="$p" 'BEGIN { print (p+0 < 30) ? 1 : 0 }'
  fi
}

# ---------------------------------------------------------------------------
# run-iter <N> -- one full end-to-end iteration (REPRO-02, REPRO-03, REPRO-04).
#   1. 3-way concurrent qsvencc measurement (923/928/1129), per-encode timeout,
#      per-PID exit capture. Non-zero/timeout -> EXEC_FAILURE/TIMEOUT, skip
#      PSNR, emit NA rows, do not run the control, return non-zero.
#   2. Multi-scene PSNR classification (923/299 primary + 928/96 + 1129/299).
#   3. Paired ffmpeg av1_qsv immune control, SEQUENTIAL-AFTER the qsvencc
#      measurement, as its OWN separate 3-way run (never merged into one
#      6-way run): the documented trigger triad is same-tool 3-way
#      concurrency, and the control tests ffmpeg's immunity to ITS OWN 3-way
#      concurrency; merging the two would change qsvencc's contention
#      profile away from the documented trigger and could itself corrupt
#      the control under heavier combined load (D-06, review concern 1).
#      A non-clean/timed-out control sets status=CONTROL_INVALID for every
#      row of this iteration.
#   4. cleanup_gpu_procs() to avoid tripping the next iteration's gate.
# Emits one result.csv line per scene per iteration with the report.csv
# schema: iteration,scene,offset,status,psnr_db,corrupt,control_clean.
# ---------------------------------------------------------------------------
cmd_run_iter() {
  local n="$1"
  local it_dir="$W/runs/it$n"
  local ctrl_dir="$W/control_runs/it$n"
  mkdir -p "$it_dir" "$ctrl_dir"
  local result_file="$it_dir/result.csv"
  : > "$result_file"

  # --- Step 1: 3-way concurrent qsvencc measurement ---
  run_encode "$it_dir/log923.txt" qsvencc --avhw --va -i "$SRC" $COMMON \
    --seek "$SCENE_923_SEEK" --trim "$SCENE_923_TRIM" -o "$it_dir/c923.obu" &
  local p1=$!
  run_encode "$it_dir/log928.txt" qsvencc --avhw --va -i "$SRC" $COMMON \
    --seek "$SCENE_928_SEEK" --trim "$SCENE_928_TRIM" -o "$it_dir/c928.obu" &
  local p2=$!
  run_encode "$it_dir/log1129.txt" qsvencc --avhw --va -i "$SRC" $COMMON \
    --seek "$SCENE_1129_SEEK" --trim "$SCENE_1129_TRIM" -o "$it_dir/c1129.obu" &
  local p3=$!
  wait "$p1"; local r1=$?
  wait "$p2"; local r2=$?
  wait "$p3"; local r3=$?

  local meas_status="OK"
  if [[ $r1 -eq 124 || $r2 -eq 124 || $r3 -eq 124 ]]; then
    meas_status="TIMEOUT"
  elif [[ $r1 -ne 0 || $r2 -ne 0 || $r3 -ne 0 ]]; then
    meas_status="EXEC_FAILURE"
  fi
  echo "iteration $n measurement exit codes: 923=$r1 928=$r2 1129=$r3 status=$meas_status"

  if [[ "$meas_status" != "OK" ]]; then
    local scene off
    for scene in 923 928 1129; do
      off="$(scene_offset "$scene")"
      echo "$n,$scene,$off,$meas_status,NA,NA,NA" >> "$result_file"
    done
    cleanup_gpu_procs
    cat "$result_file"
    return 1
  fi

  # --- Step 2: multi-scene PSNR classification ---
  declare -A psnr_db corrupt
  local scene ref_fail=0
  for scene in 923 928 1129; do
    ensure_scene_reference "$scene" || { ref_fail=1; break; }
  done
  if [[ $ref_fail -ne 0 ]]; then
    local off
    for scene in 923 928 1129; do
      off="$(scene_offset "$scene")"
      echo "$n,$scene,$off,EXEC_FAILURE,NA,NA,NA" >> "$result_file"
    done
    cleanup_gpu_procs
    cat "$result_file"
    return 1
  fi

  local off obu ref_png test_png statsfile
  for scene in 923 928 1129; do
    off="$(scene_offset "$scene")"
    case "$scene" in
      923) obu="$it_dir/c923.obu"; test_png="$it_dir/frame299.png"; statsfile="$it_dir/psnr.log" ;;
      928) obu="$it_dir/c928.obu"; test_png="$it_dir/frame96_928.png"; statsfile="$it_dir/psnr_928.log" ;;
      1129) obu="$it_dir/c1129.obu"; test_png="$it_dir/frame299_1129.png"; statsfile="$it_dir/psnr_1129.log" ;;
    esac
    ref_png="$(scene_ref_png "$scene")"
    ffmpeg -y -i "$obu" -vf "select='eq(n\,$off)'" -vsync 0 -frames:v 1 "$test_png" -hide_banner -loglevel error
    psnr_db[$scene]="$(psnr_of "$test_png" "$ref_png" "$statsfile")"
    corrupt[$scene]="$(classify_corrupt "${psnr_db[$scene]}")"
    echo "scene $scene offset $off: psnr_db=${psnr_db[$scene]} corrupt=${corrupt[$scene]}"
  done

  # --- Step 3: paired ffmpeg av1_qsv immune control, sequential-after,
  #     separate 3-way run (D-06, review concern 1 -- see comment block above) ---
  ctrl_encode "$SCENE_923_SEEK" 339 "$ctrl_dir/c923.obu" &
  local cp1=$!
  ctrl_encode "$SCENE_928_SEEK" 110 "$ctrl_dir/c928.obu" &
  local cp2=$!
  ctrl_encode "$SCENE_1129_SEEK" 361 "$ctrl_dir/c1129.obu" &
  local cp3=$!
  wait "$cp1"; local cr1=$?
  wait "$cp2"; local cr2=$?
  wait "$cp3"; local cr3=$?

  local control_clean status_final
  if [[ $cr1 -eq 124 || $cr2 -eq 124 || $cr3 -eq 124 ]]; then
    control_clean="TIMEOUT"
  elif [[ $cr1 -ne 0 || $cr2 -ne 0 || $cr3 -ne 0 ]]; then
    control_clean="0"
  else
    local ctrl_psnr
    ffmpeg -y -i "$ctrl_dir/c923.obu" -vf "select='eq(n\,$SCENE_923_OFF)'" -vsync 0 -frames:v 1 \
      "$ctrl_dir/frame299.png" -hide_banner -loglevel error
    ctrl_psnr="$(psnr_of "$ctrl_dir/frame299.png" "$W/control_reference/ffref_299.png" "$ctrl_dir/psnr.log")"
    if [[ "$ctrl_psnr" == "inf" ]]; then
      control_clean="1"
    else
      control_clean="$(awk -v p="$ctrl_psnr" 'BEGIN { print (p+0 >= 30) ? 1 : 0 }')"
    fi
  fi

  if [[ "$control_clean" == "1" ]]; then
    status_final="OK"
  else
    status_final="CONTROL_INVALID"
  fi
  echo "iteration $n control exit codes: 923=$cr1 928=$cr2 1129=$cr3 control_clean=$control_clean status=$status_final"

  for scene in 923 928 1129; do
    off="$(scene_offset "$scene")"
    if [[ "$status_final" == "OK" ]]; then
      echo "$n,$scene,$off,OK,${psnr_db[$scene]},${corrupt[$scene]},$control_clean" >> "$result_file"
    else
      echo "$n,$scene,$off,CONTROL_INVALID,NA,NA,$control_clean" >> "$result_file"
    fi
  done

  cleanup_gpu_procs
  cat "$result_file"

  [[ "$status_final" == "OK" ]]
}

# ---------------------------------------------------------------------------
# dispatcher
# ---------------------------------------------------------------------------
main() {
  local subcmd="${1:-}"
  case "$subcmd" in
    probe)
      cmd_probe
      ;;
    reference)
      cmd_reference
      ;;
    run-iter)
      shift
      cmd_run_iter "${1:?run-iter requires an iteration number}"
      ;;
    run-batch)
      shift
      cmd_run_batch "${1:-20}"
      ;;
    *)
      echo "Usage: $0 {probe|reference|run-iter <N>|run-batch [N=20]}" >&2
      exit 2
      ;;
  esac
}

main "$@"
