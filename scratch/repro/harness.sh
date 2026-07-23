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
  # WR-10: without pipefail an md5sum failure yields two empty strings, and
  # "" == "" would pass this D-05 precondition gate on no data. Require both
  # hashes to be non-empty AND equal (same fail-closed direction as CR-01).
  if [[ -z "$md5_a" || -z "$md5_b" || "$md5_a" != "$md5_b" ]]; then
    echo "ABORT: reference determinism check invalid or failed -- md5 '$md5_a' vs '$md5_b' (D-05 precondition violated)" >&2
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

  ff_bounded -y -nostdin -i "$W/reference/chunk923_ref.obu" -vf "select='eq(n\,$SCENE_923_OFF)'" -vsync 0 -frames:v 1 \
    "$W/reference/frame299_ref.png" -hide_banner -loglevel error \
    || { echo "ABORT: reference frame extraction failed" >&2; exit 1; }
  echo "reference frame extracted: $W/reference/frame299_ref.png"

  # WR-06: generate the 928/1129 qsvencc references up front too (mirroring
  # 923) while the GPU is known-exclusive here. Generating them lazily inside
  # run-iter races the async renderD128/VA-surface release right after the
  # measurement encodes exit, which could permanently starve them and convert
  # the entire batch into EXEC_FAILURE.
  local qscene
  for qscene in 928 1129; do
    ensure_scene_reference "$qscene" \
      || { echo "ABORT: reference generation for scene $qscene failed" >&2; exit 1; }
  done

  # Once-only ffmpeg av1_qsv control references for ALL THREE control scenes
  # (D-06, review concern 5; WR-04 -- control immunity must be PSNR-validated
  # per-scene, not 923-only). Each is guarded with an existence check inside
  # the helper and must NOT be re-encoded inside run-iter.
  local cscene
  for cscene in 923 928 1129; do
    ensure_control_reference "$cscene" \
      || { echo "ABORT: control reference generation for scene $cscene failed" >&2; exit 1; }
  done
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
  run_encode "$logfile" ffmpeg -y -nostdin -hwaccel qsv -hwaccel_output_format qsv -c:v h264_qsv \
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

# Control (ffmpeg av1_qsv) per-scene lookups (WR-04): the frame count passed
# to ctrl_encode, the once-only control-reference OBU, and its extracted
# control-reference PNG. All three control scenes are PSNR-validated, so each
# needs its own control reference -- not just 923.
ctrl_frames() {
  case "$1" in
    923) echo 339 ;;
    928) echo 110 ;;
    1129) echo 361 ;;
    *) echo "unknown scene: $1" >&2; return 1 ;;
  esac
}
ctrl_ref_obu() {
  case "$1" in
    923) echo "$W/control_reference/c923_ffref.obu" ;;
    928) echo "$W/control_reference/c928_ffref.obu" ;;
    1129) echo "$W/control_reference/c1129_ffref.obu" ;;
    *) echo "unknown scene: $1" >&2; return 1 ;;
  esac
}
ctrl_ref_png() {
  case "$1" in
    923) echo "$W/control_reference/ffref_299.png" ;;
    928) echo "$W/control_reference/ffref_96_928.png" ;;
    1129) echo "$W/control_reference/ffref_299_1129.png" ;;
    *) echo "unknown scene: $1" >&2; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# vaapi_encode -- full-HW ffmpeg VAAPI av1_vaapi encode helper (Phase 2 D-01).
# Mirrors ctrl_encode()'s structure exactly: logfile derived from the output
# path, wrapped in run_encode, -ss placed BEFORE -i (Pitfall 3 -- accurate-
# seek mode on a deep-timeline scene would otherwise blow ENCODE_TIMEOUT),
# flags-then-output-then-loglevel arg order.
#
# scale_vaapi=format=p010:extra_hw_frames=64 (NOT vpp_qsv, NOT
# format=p010,hwupload) is the only correct HW-frame-to-HW-frame P010
# conversion for a -hwaccel_output_format vaapi decoded input (Pitfall 3 in
# 02-RESEARCH.md numbering / State of the Art). extra_hw_frames=64 is
# MANDATORY: without it, any -frames:v-bounded scale_vaapi pipeline throws a
# spurious nonzero exit (244, "Cannot allocate memory") on otherwise-valid
# output (Pitfall 2), which run_encode's fail-closed exit gate would
# misclassify as EXEC_FAILURE for every single av1_vaapi iteration.
#
# Usage: vaapi_encode <seek> <frames> <out>
# ---------------------------------------------------------------------------
vaapi_encode() {
  local seek="$1" frames="$2" out="$3"
  local logfile="${out%.obu}.log"
  run_encode "$logfile" ffmpeg -y -nostdin -hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128 \
    -ss "$seek" -i "$SRC" -frames:v "$frames" \
    -vf "scale_vaapi=format=p010:extra_hw_frames=64" \
    -c:v av1_vaapi -profile:v main -low_power 1 -g 300 -bf 5 -b_depth 3 -refs 4 -rc_mode ICQ -global_quality 24 -tiles 1x1 \
    "$out" -hide_banner -loglevel error
}

# av1_vaapi self-reference per-scene lookups (D-04). Filenames are
# DELIBERATELY distinct from scene_ref_obu/scene_ref_png (the qsvencc
# reference) -- Pitfall 6: a different encoder produces different clean
# pixels, so reusing the qsvencc reference would make every av1_vaapi frame
# look corrupt regardless of the real concurrency bug.
vaapi_ref_obu() {
  case "$1" in
    923) echo "$W/reference/chunk923_vaapi_ref.obu" ;;
    928) echo "$W/reference/chunk928_vaapi_ref.obu" ;;
    1129) echo "$W/reference/chunk1129_vaapi_ref.obu" ;;
    *) echo "unknown scene: $1" >&2; return 1 ;;
  esac
}
vaapi_ref_png() {
  case "$1" in
    923) echo "$W/reference/frame299_vaapi_ref.png" ;;
    928) echo "$W/reference/frame96_928_vaapi_ref.png" ;;
    1129) echo "$W/reference/frame299_1129_vaapi_ref.png" ;;
    *) echo "unknown scene: $1" >&2; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# cmd_probe_vaapi -- D-02 "probe -> run -> caveat" trigger-triad leg probe.
# Empirically determines, on THIS hardware, which of the three trigger-triad
# legs av1_vaapi can actually reproduce:
#   (a) B-frame reorder    -- PTS/DTS equality test on a remuxed-with-real-
#                              timestamps copy (Pattern 1). NEVER pict_type
#                              (Pitfall 1: AV1 has no native B-slice concept,
#                              pict_type cannot distinguish true reordering
#                              from ordinary P). NEVER the encoder's own
#                              capability log line either (Pitfall 4).
#   (b) P010 10-bit        -- ffprobe pix_fmt == yuv420p10le.
#   (c) HW-VA video-memory decode -- confirmed by the absence of hwdownload
#                              in the filtergraph AND a successful full-HW
#                              encode actually completing (not just a static
#                              string check).
# A failed/unreadable leg is recorded UNKNOWN, never silently folded into
# UNSUPPORTED (CR-01 fail-closed lineage, T-02-03). Writes
# reorder/p010/hw_decode verdicts to vaapi_probe.txt.
#
# Top-level cmd_* entry point (main() dispatches here): the only vaapi
# function in this probe path allowed to exit; everything else is a plain
# encode/ffprobe/awk pipeline.
# ---------------------------------------------------------------------------
cmd_probe_vaapi() {
  require_gpu_exclusive || { echo "ABORT: probe-vaapi requires exclusive GPU access" >&2; exit 1; }

  echo "== probe-vaapi: av1_vaapi trigger-triad leg probe (scene 923, 100 frames) =="
  local probe_mkv="$W/probe_reorder.mkv"
  local vf_string="scale_vaapi=format=p010:extra_hw_frames=64"
  run_encode "$W/probe_reorder.log" ffmpeg -y -nostdin -hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128 \
    -ss "$SCENE_923_SEEK" -i "$SRC" -frames:v 100 \
    -vf "$vf_string" \
    -c:v av1_vaapi -profile:v main -low_power 1 -g 300 -bf 5 -b_depth 3 -refs 4 -rc_mode ICQ -global_quality 24 -r 24 \
    "$probe_mkv" -hide_banner -loglevel error
  local probe_rc=$?

  local reorder_verdict p010_verdict hwdecode_verdict

  if [[ $probe_rc -ne 0 || ! -s "$probe_mkv" ]]; then
    echo "probe-vaapi: probe encode failed (exit $probe_rc) or produced empty output -- see $W/probe_reorder.log"
    reorder_verdict="UNKNOWN"
    p010_verdict="UNKNOWN"
    hwdecode_verdict="UNKNOWN"
  else
    # Leg (a): B-frame reorder -- ANY pts!=dts row is proof of real
    # reordering; all-equal is proof none occurred. Never pict_type.
    #
    # ffprobe field-name gotcha (found live, empirically, in this session):
    # "frame=pts,dts" silently drops the "dts" token -- ffprobe's real
    # per-frame decode-timestamp field is "pkt_dts", not "dts". Requesting
    # the bare "dts" field name does not error; it just produces a single
    # (pts-only) CSV column, which made every frame look mismatched
    # (pts!="" is always true) -- a false ACTIVE verdict on every run,
    # confirmed by directly comparing "frame=pts,dts" against
    # "frame=pts,dts,pkt_dts" output on this exact probe file. Requesting
    # "pts,dts,pkt_dts" keeps the literal "pts,dts" token pairing (for
    # continuity with the documented probe recipe) while ffprobe silently
    # ignores the invalid "dts" and emits a real two-column pts,pkt_dts CSV.
    local reorder_csv
    reorder_csv="$(ffprobe -v error -select_streams v:0 -show_entries frame=pts,dts,pkt_dts -of csv=p=0 "$probe_mkv" 2>/dev/null)"
    if [[ -z "$reorder_csv" ]]; then
      echo "probe-vaapi: ffprobe pts/dts read failed -- leg (a) UNKNOWN"
      reorder_verdict="UNKNOWN"
    else
      local mismatch_count
      mismatch_count="$(echo "$reorder_csv" | awk -F, '$1!=$2{c++} END{print c+0}')"
      if [[ "$mismatch_count" -gt 0 ]]; then
        reorder_verdict="ACTIVE"
      else
        reorder_verdict="UNSUPPORTED"
      fi
    fi

    # Leg (b): P010 10-bit confirmation.
    local pix_fmt
    pix_fmt="$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 "$probe_mkv" 2>/dev/null)"
    if [[ -z "$pix_fmt" ]]; then
      echo "probe-vaapi: ffprobe pix_fmt read failed -- leg (b) UNKNOWN"
      p010_verdict="UNKNOWN"
    elif [[ "$pix_fmt" == "yuv420p10le" ]]; then
      p010_verdict="ACTIVE"
    else
      p010_verdict="UNSUPPORTED"
    fi

    # Leg (c): HW-VA video-memory decode -- the probe pipeline's own filter
    # string must not contain hwdownload (which would mean frames left VA
    # surfaces for system RAM), and the encode above must have actually
    # completed successfully on that pipeline.
    if [[ "$vf_string" == *hwdownload* ]]; then
      hwdecode_verdict="UNSUPPORTED"
    else
      hwdecode_verdict="ACTIVE"
    fi
  fi

  {
    echo "# av1_vaapi trigger-triad leg probe (D-02), scene 923, 100 frames"
    echo "reorder: $reorder_verdict"
    echo "p010: $p010_verdict"
    echo "hw_decode: $hwdecode_verdict"
    if [[ "$reorder_verdict" == "ACTIVE" && "$p010_verdict" == "ACTIVE" && "$hwdecode_verdict" == "ACTIVE" ]]; then
      echo "triad: FULL-TRIAD"
    else
      echo "triad: PARTIAL-TRIAD (immunity NOT proven for any UNSUPPORTED/UNKNOWN leg -- D-03)"
    fi
  } > "$W/vaapi_probe.txt"

  echo "probe-vaapi result:"
  cat "$W/vaapi_probe.txt"
}

# ---------------------------------------------------------------------------
# ensure_control_reference -- generate a scene's once-only ffmpeg av1_qsv
# control reference (immune-control OBU + extracted hotspot frame) if it does
# not already exist (WR-04). Mirrors the 923 control reference for 928/1129 so
# every control scene can be PSNR-validated. Gated by require_gpu_exclusive.
# ---------------------------------------------------------------------------
ensure_control_reference() {
  local scene="$1" obu png frames seek off
  obu="$(ctrl_ref_obu "$scene")"; png="$(ctrl_ref_png "$scene")"
  frames="$(ctrl_frames "$scene")"; seek="$(scene_seek "$scene")"; off="$(scene_offset "$scene")"
  if [[ -f "$obu" && -f "$png" ]]; then
    echo "control reference for scene $scene already exists, skipping re-encode: $obu"
    return 0
  fi
  echo "== reference: ffmpeg av1_qsv control reference (scene $scene) =="
  require_gpu_exclusive || { echo "ABORT: control-reference step requires exclusive GPU access" >&2; return 1; }
  ctrl_encode "$seek" "$frames" "$obu" \
    || { echo "ABORT: control reference encode for scene $scene failed" >&2; return 1; }
  ff_bounded -y -nostdin -i "$obu" -vf "select='eq(n\,$off)'" -vsync 0 -frames:v 1 \
    "$png" -hide_banner -loglevel error \
    || { echo "ABORT: control reference frame extraction for scene $scene failed" >&2; return 1; }
  echo "control reference generated for scene $scene: $obu"
  return 0
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
  # WR-06: renderD128/VA-surface release is async to process exit, so a bare
  # require_gpu_exclusive called right after the measurement encodes can
  # spuriously fail. Wait for the GPU to actually go idle (with cleanup +
  # retries) before requiring exclusivity, mirroring cmd_run_batch's gate.
  local _r
  for _r in 1 2 3; do
    [[ -z "$(gpu_clients)" ]] && break
    cleanup_gpu_procs
    sleep 1
  done
  require_gpu_exclusive || { echo "ABORT: reference generation for scene $scene requires exclusive GPU access" >&2; return 1; }
  qsvencc --avhw --va -i "$SRC" $COMMON --seek "$seek" --trim "$trim" -o "$obu" \
    || { echo "ABORT: reference encode for scene $scene failed" >&2; return 1; }
  ff_bounded -y -nostdin -i "$obu" -vf "select='eq(n\,$off)'" -vsync 0 -frames:v 1 "$png" -hide_banner -loglevel error \
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
  LC_ALL=C ff_bounded -y -nostdin -i "$test_png" -i "$ref_png" -lavfi "psnr=stats_file=$statsfile" \
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
  if [[ "$p" == "inf" ]]; then
    # byte-identical to the reference -> genuinely clean
    echo 0
  elif [[ -z "$p" ]]; then
    # a MISSING/empty PSNR is a measurement failure, NEVER "clean" (CR-01):
    # emit NA so the caller records MEASURE_FAILURE and excludes it from the
    # corruption-fraction denominator instead of scoring it corrupt=0.
    echo NA
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

  # WR-01: without a trap, a Ctrl-C or mid-iteration failure leaves the
  # backgrounded qsvencc/ffmpeg jobs bound to renderD128, contaminating the
  # next iteration's exclusivity gate. Kill any launched background PIDs and
  # reap GPU clients on INT/TERM. ${p1:-} guards set -u once the locals go out
  # of scope (they resolve to the in-function locals while the iteration runs).
  trap 'for _pid in "${p1:-}" "${p2:-}" "${p3:-}" "${cp1:-}" "${cp2:-}" "${cp3:-}"; do [[ -n "$_pid" ]] && kill "$_pid" 2>/dev/null || true; done; cleanup_gpu_procs' INT TERM

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
  declare -A psnr_db corrupt meas_fail
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
    # CR-01: a *failed* frame extraction is the strongest corruption signal
    # (a truncated/broken .obu). It must NEVER fall through to a clean score.
    # Guard the extraction and treat a missing/empty test frame or an empty
    # PSNR as an explicit MEASURE_FAILURE, excluded from the denominator.
    if ! ff_bounded -y -nostdin -i "$obu" -vf "select='eq(n\,$off)'" -vsync 0 -frames:v 1 \
         "$test_png" -hide_banner -loglevel error || [[ ! -s "$test_png" ]]; then
      psnr_db[$scene]="NA"; corrupt[$scene]="NA"; meas_fail[$scene]=1
      echo "scene $scene offset $off: MEASURE_FAILURE (frame extraction failed / test frame missing)"
      continue
    fi
    local raw
    raw="$(psnr_of "$test_png" "$ref_png" "$statsfile")"
    if [[ -z "$raw" ]]; then
      psnr_db[$scene]="NA"; corrupt[$scene]="NA"; meas_fail[$scene]=1
      echo "scene $scene offset $off: MEASURE_FAILURE (empty PSNR measurement)"
      continue
    fi
    psnr_db[$scene]="$raw"; corrupt[$scene]="$(classify_corrupt "$raw")"
    meas_fail[$scene]=0
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
    # WR-04: PSNR-validate EVERY control scene against its own control
    # reference; the control is "clean" (1) only if all three are >= 30 dB.
    # A missing/empty control PSNR is a measurement failure and is treated
    # conservatively as NOT clean (matching CR-01's fail-safe direction),
    # so a scene-dependent control corruption can never pass silently.
    local cscene coff cpng cref cpsnr
    control_clean="1"
    for cscene in 923 928 1129; do
      coff="$(scene_offset "$cscene")"
      cref="$(ctrl_ref_png "$cscene")"
      cpng="$ctrl_dir/ctrl_frame_${cscene}.png"
      if ! ff_bounded -y -nostdin -i "$ctrl_dir/c${cscene}.obu" -vf "select='eq(n\,$coff)'" -vsync 0 -frames:v 1 \
           "$cpng" -hide_banner -loglevel error || [[ ! -s "$cpng" ]]; then
        echo "control scene $cscene: frame extraction failed -> control NOT clean"
        control_clean="0"; continue
      fi
      cpsnr="$(psnr_of "$cpng" "$cref" "$ctrl_dir/ctrl_psnr_${cscene}.log")"
      if [[ "$cpsnr" == "inf" ]]; then
        : # byte-identical to the control reference -> clean
      elif [[ -z "$cpsnr" ]]; then
        echo "control scene $cscene: empty PSNR measurement -> control NOT clean"
        control_clean="0"
      elif [[ "$(awk -v p="$cpsnr" 'BEGIN { print (p+0 >= 30) ? 1 : 0 }')" != "1" ]]; then
        echo "control scene $cscene: psnr=$cpsnr < 30 dB -> control NOT clean"
        control_clean="0"
      fi
    done
  fi

  if [[ "$control_clean" == "1" ]]; then
    status_final="OK"
  else
    status_final="CONTROL_INVALID"
  fi
  echo "iteration $n control exit codes: 923=$cr1 928=$cr2 1129=$cr3 control_clean=$control_clean status=$status_final"

  for scene in 923 928 1129; do
    off="$(scene_offset "$scene")"
    if [[ "${meas_fail[$scene]}" == "1" ]]; then
      # CR-01: a failed measurement is its own outcome -- never OK/clean.
      echo "$n,$scene,$off,MEASURE_FAILURE,NA,NA,$control_clean" >> "$result_file"
    elif [[ "$status_final" == "OK" ]]; then
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
# print_batch_summary -- read report.csv and print the corruption-rate
# summary (REPRO-05): raw X/N_actual + 95% Wilson CI for the primary
# hotspot, confirmatory fractions for the other two hotspots, N_actual vs
# N_requested with exclusion breakdown, the observed PSNR signature +
# stability check, the paired-control result, the detection-N vs
# validation-N statement (D-07), and the mechanism-vs-symptom NOTE. Also
# saved to summary.txt. No `matches_known_signature` field is ever emitted.
# ---------------------------------------------------------------------------
print_batch_summary() {
  local report="$1" n_requested="$2" n_actual="$3"
  REPORT_CSV="$report" N_REQUESTED="$n_requested" N_ACTUAL="$n_actual" \
    FINGERPRINT_FILE="$W/fingerprint.txt" python3 <<'PYEOF' | tee "$W/summary.txt"
import csv, os, math, statistics

report_csv = os.environ["REPORT_CSV"]
n_requested = int(os.environ["N_REQUESTED"])
n_actual = int(os.environ["N_ACTUAL"])
fingerprint_file = os.environ["FINGERPRINT_FILE"]

rows = []
with open(report_csv, newline="") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

def wilson_ci(x, n, z=1.96):
    if n == 0:
        return (None, None)
    phat = x / n
    denom = 1 + z * z / n
    center = (phat + z * z / (2 * n)) / denom
    half = z * math.sqrt(phat * (1 - phat) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, center - half), min(1.0, center + half))

def scene_stats(scene):
    scene_rows = [r for r in rows if r["scene"] == str(scene)]
    ok_rows = [r for r in scene_rows if r["status"] == "OK"]
    corrupt_rows = [r for r in ok_rows if r["corrupt"] == "1"]
    n_ok = len(ok_rows)
    x = len(corrupt_rows)
    lo, hi = wilson_ci(x, n_ok) if n_ok else (None, None)
    psnr_values = []
    for r in corrupt_rows:
        try:
            psnr_values.append(float(r["psnr_db"]))
        except ValueError:
            pass
    return dict(n_ok=n_ok, x=x, lo=lo, hi=hi, psnr_values=psnr_values)

s923 = scene_stats(923)
s928 = scene_stats(928)
s1129 = scene_stats(1129)

status_counts = {}
for r in rows:
    if r["scene"] == "923":
        status_counts[r["status"]] = status_counts.get(r["status"], 0) + 1

control_invalid = status_counts.get("CONTROL_INVALID", 0)
exec_failure = status_counts.get("EXEC_FAILURE", 0)
timeout_n = status_counts.get("TIMEOUT", 0)
measure_failure = status_counts.get("MEASURE_FAILURE", 0)
ok_n = status_counts.get("OK", 0)

fingerprint_summary = "UNAVAILABLE"
try:
    with open(fingerprint_file) as f:
        for line in f:
            if line.startswith("kernel_matches_affected_host"):
                fingerprint_summary = line.strip()
                break
except OSError:
    pass

print("=" * 78)
print("QSV concurrent-encode corruption -- baseline report")
print("=" * 78)
print(f"fingerprint: {fingerprint_file} ({fingerprint_summary})")
print()
print(f"N_requested: {n_requested}")
print(f"N_actual:    {n_actual}")
print(f"  OK: {ok_n}  EXEC_FAILURE: {exec_failure}  TIMEOUT: {timeout_n}  MEASURE_FAILURE: {measure_failure}  CONTROL_INVALID: {control_invalid}")
print(f"  (excluded from corruption-fraction denominator: {exec_failure + timeout_n + measure_failure + control_invalid})")
print()
print("-- Primary hotspot: scene 923 / offset 299 --")
if s923["n_ok"] > 0:
    frac = s923["x"] / s923["n_ok"]
    print(f"  corruption fraction: {s923['x']}/{s923['n_ok']} ({frac:.1%})")
    print(f"  95% Wilson CI: [{s923['lo']:.3f}, {s923['hi']:.3f}]")
else:
    print("  no OK (control-clean) iterations to report")
if s923["psnr_values"]:
    mean = statistics.mean(s923["psnr_values"])
    stdev = statistics.pstdev(s923["psnr_values"]) if len(s923["psnr_values"]) > 1 else 0.0
    stable = stdev < 2.0
    print(f"  observed corrupt-frame PSNR values (dB): {[round(v, 2) for v in s923['psnr_values']]}")
    print(f"  mean={mean:.2f} dB, stddev={stdev:.2f} dB, signature_stable_across_iterations={stable}")
    print("  (informational only: the previously-documented handoff signature was ~15.74 dB;")
    print("   this environment's own deterministic value may differ -- see 01-RESEARCH.md)")
else:
    print("  no corrupt frames observed at this hotspot this batch")
print()
print("-- Confirmatory hotspot: scene 928 / offset 96 --")
if s928["n_ok"] > 0:
    frac = s928["x"] / s928["n_ok"]
    print(f"  corruption fraction: {s928['x']}/{s928['n_ok']} ({frac:.1%})")
else:
    print("  no OK iterations to report")
print()
print("-- Confirmatory hotspot: scene 1129 / offset 299 --")
if s1129["n_ok"] > 0:
    frac = s1129["x"] / s1129["n_ok"]
    print(f"  corruption fraction: {s1129['x']}/{s1129['n_ok']} ({frac:.1%})")
else:
    print("  no OK iterations to report")
print()
print("-- Paired immune control --")
print(f"  ffmpeg av1_qsv control non-clean/invalidated iterations: {control_invalid}/{n_actual}")
print(f"  (expected 0/{n_actual} -- a non-zero count here means the control itself was")
print("   compromised for that iteration and it was excluded from the qsvencc finding)")
print()
print("-- Detection-N vs validation-N (D-07) --")
print(f"  This batch is the DETECTION sample (N_requested={n_requested}), sized to observe")
print("  whether the documented ~33-65% baseline recurs in this environment.")
print("  A larger ~60 zero-failure VALIDATION-N (rule-of-three) is defined but RESERVED")
print("  for later fix/clean claims -- it is NOT run in this phase.")
print()
print("-- Mechanism-vs-symptom NOTE --")
print("  This baseline confirms reproduction by the PSNR-drop SYMPTOM (a hotspot frame")
print("  scoring well below the 30 dB threshold, deterministically, under 3-way")
print("  concurrency). Confirming that the corrupt frame's CONTENT actually originates")
print("  from a concurrently-running session's scene (the documented cross-session")
print("  aliasing mechanism) is DEFERRED to Phase 2 -- not established by this batch.")
print("=" * 78)
PYEOF
}

# ---------------------------------------------------------------------------
# run-batch [N=20] -- loop run-iter N times (default 20 per D-07), write
# report.csv, print the recorded baseline (REPRO-05). Deliberately catches
# per-iteration failures and continues (run-batch's own set -e policy).
# ---------------------------------------------------------------------------
cmd_run_batch() {
  local n_requested="${1:-20}"
  # WR-08: a non-numeric N silently no-ops `seq` (zero iterations) and then
  # crashes the Python summary at int(N_REQUESTED). Validate up front.
  if [[ ! "$n_requested" =~ ^[1-9][0-9]*$ ]]; then
    echo "ABORT: N must be a positive integer (got: '$n_requested')" >&2
    exit 2
  fi
  mkdir -p "$W/runs" "$W/control_runs"

  # Disk preflight (review hygiene item 11) -- a full disk mid-batch would
  # otherwise silently corrupt outputs.
  local avail_kb threshold_kb=$((5 * 1024 * 1024))
  avail_kb="$(df -Pk "$W" | awk 'NR==2{print $4}')"
  if [[ -z "$avail_kb" || "$avail_kb" -lt "$threshold_kb" ]]; then
    echo "ABORT: insufficient free disk space under $W (available: ${avail_kb:-unknown} KB, need >= ${threshold_kb} KB) -- aborting before the batch to avoid a full-disk mid-batch corruption" >&2
    exit 1
  fi
  echo "disk preflight OK: ${avail_kb} KB available under $W"

  # Reference-artifact preflight (WR-05): without the qsvencc and control
  # references, every iteration's PSNR compare fails (empty PSNR -> control
  # not clean), so an entire batch run before `reference` would silently
  # yield all-CONTROL_INVALID with no useful data. Fail loudly and early.
  local rscene missing=0 rpng cpng
  for rscene in 923 928 1129; do
    rpng="$(scene_ref_png "$rscene")"; cpng="$(ctrl_ref_png "$rscene")"
    [[ -f "$rpng" ]] || { echo "ABORT: missing qsvencc reference frame for scene $rscene: $rpng" >&2; missing=1; }
    [[ -f "$cpng" ]] || { echo "ABORT: missing control reference frame for scene $rscene: $cpng" >&2; missing=1; }
  done
  if [[ $missing -ne 0 ]]; then
    echo "ABORT: run '$0 reference' first (missing reference artifacts)" >&2
    exit 1
  fi
  echo "reference-artifact preflight OK: qsvencc + control references present for 923/928/1129"

  local report="$W/report.csv"
  echo "iteration,scene,offset,status,psnr_db,corrupt,control_clean" > "$report"

  local i iter_label n_actual=0 n_contaminated=0
  for i in $(seq 1 "$n_requested"); do
    iter_label="$(printf "%02d" "$i")"

    # Inter-iteration GPU isolation re-check (review concern 4 -- VA
    # surface / renderD128 release can be async to process exit).
    local idle_ok=0 retry
    for retry in 1 2 3; do
      sleep 1
      if [[ -z "$(gpu_clients)" ]]; then
        idle_ok=1
        break
      fi
      cleanup_gpu_procs
    done

    if [[ $idle_ok -ne 1 ]]; then
      echo "WARNING: iteration $iter_label GPU still not idle after cleanup + retries -- marking contaminated, not starting a new encode on a dirty GPU: $(gpu_clients)" >&2
      local scene off
      for scene in 923 928 1129; do
        off="$(scene_offset "$scene")"
        echo "$iter_label,$scene,$off,EXEC_FAILURE,NA,NA,NA" >> "$report"
      done
      # WR-02: a contaminated skip produced no run_iter row; count it
      # separately rather than inflating n_actual (which must reflect only
      # iterations that produced usable measurement rows).
      n_contaminated=$((n_contaminated + 1))
      continue
    fi

    cmd_run_iter "$iter_label" || true
    if [[ -f "$W/runs/it$iter_label/result.csv" ]]; then
      cat "$W/runs/it$iter_label/result.csv" >> "$report"
      # WR-02: only iterations that actually produced rows count as "actual",
      # so control_invalid/n_actual has a truthful denominator.
      n_actual=$((n_actual + 1))
    fi
  done

  echo "batch complete: n_requested=$n_requested n_actual=$n_actual contaminated_skipped=$n_contaminated"
  print_batch_summary "$report" "$n_requested" "$n_actual"
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
    probe-vaapi)
      cmd_probe_vaapi
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
      echo "Usage: $0 {probe|probe-vaapi|reference|run-iter <N>|run-batch [N=20]}" >&2
      exit 2
      ;;
  esac
}

main "$@"
