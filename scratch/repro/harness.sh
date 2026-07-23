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
# ensure_vaapi_reference -- generate a scene's av1_vaapi self-reference
# (D-04), cache-check-then-generate like ensure_scene_reference/
# ensure_control_reference. For scene 923 (the required primary hotspot),
# performs a D-05 determinism re-confirmation FIRST: two isolated
# vaapi_encode() runs, md5-compared with the WR-10 fail-closed guard (both
# hashes non-empty AND equal). Because av1_vaapi bit-determinism is
# unverified by research, a md5 mismatch falls back to a >=50 dB PSNR
# comparison of the two runs' extracted hotspot frames before accepting
# determinism; failing both is a hard abort (D-05 precondition). Scenes
# 928/1129 get a single isolated encode each (no determinism re-check
# required by D-04 -- only 923 is the required primary hotspot), since the
# next plan's classification compares all three scenes against their own
# vaapi self-reference.
#
# Worker-function contract: returns 1 on error, never exit/die -- only
# cmd_reference_vaapi (top-level) exits.
# ---------------------------------------------------------------------------
ensure_vaapi_reference() {
  local scene="$1" obu png seek off frames
  obu="$(vaapi_ref_obu "$scene")" || return 1
  png="$(vaapi_ref_png "$scene")" || return 1
  if [[ -f "$obu" && -f "$png" ]]; then
    echo "av1_vaapi reference for scene $scene already exists, skipping re-encode: $obu"
    return 0
  fi
  seek="$(scene_seek "$scene")"; off="$(scene_offset "$scene")"
  frames="$(ctrl_frames "$scene")" || return 1

  # WR-06: renderD128/VA-surface release is async to process exit -- wait for
  # the GPU to actually go idle (with cleanup + retries) before requiring
  # exclusivity, mirroring ensure_scene_reference/cmd_run_batch's gate.
  local _r
  for _r in 1 2 3; do
    [[ -z "$(gpu_clients)" ]] && break
    cleanup_gpu_procs
    sleep 1
  done
  require_gpu_exclusive || { echo "ABORT: av1_vaapi reference generation for scene $scene requires exclusive GPU access" >&2; return 1; }

  if [[ "$scene" == "923" ]]; then
    echo "== reference-vaapi: av1_vaapi isolated determinism check (scene 923, D-05) =="
    vaapi_encode "$seek" "$frames" "$obu" \
      || { echo "ABORT: av1_vaapi reference encode (run 1) for scene 923 failed" >&2; return 1; }
    local obu_repeat="${obu%.obu}_repeat.obu"
    vaapi_encode "$seek" "$frames" "$obu_repeat" \
      || { echo "ABORT: av1_vaapi reference encode (run 2) for scene 923 failed" >&2; return 1; }

    local md5_a md5_b
    md5_a="$(md5sum "$obu" | awk '{print $1}')"
    md5_b="$(md5sum "$obu_repeat" | awk '{print $1}')"
    # WR-10: require both hashes non-empty AND equal (same fail-closed
    # direction as CR-01/cmd_reference's own md5 gate).
    if [[ -n "$md5_a" && -n "$md5_b" && "$md5_a" == "$md5_b" ]]; then
      echo "av1_vaapi reference determinism OK (bit-identical): md5 $md5_a matches across two isolated encodes"
    else
      echo "av1_vaapi reference not bit-identical (md5 '$md5_a' vs '$md5_b') -- falling back to D-05 PSNR determinism check"
      local png_a png_b psnr_val
      png_a="$W/reference/frame299_vaapi_ref_run1.png"
      png_b="$W/reference/frame299_vaapi_ref_run2.png"
      ff_bounded -y -nostdin -i "$obu" -vf "select='eq(n\,$off)'" -vsync 0 -frames:v 1 "$png_a" -hide_banner -loglevel error \
        || { echo "ABORT: av1_vaapi determinism-fallback frame extraction (run 1) failed" >&2; return 1; }
      ff_bounded -y -nostdin -i "$obu_repeat" -vf "select='eq(n\,$off)'" -vsync 0 -frames:v 1 "$png_b" -hide_banner -loglevel error \
        || { echo "ABORT: av1_vaapi determinism-fallback frame extraction (run 2) failed" >&2; return 1; }
      psnr_val="$(psnr_of "$png_a" "$png_b" "$W/reference/vaapi_determinism_psnr.log")"
      # D-05 fallback threshold: >=50 dB. 50 dB corresponds to <1-bit average
      # per-pixel difference -- ~4x the <30 dB corrupt threshold, and well
      # above plausible ICQ-mode rate-control encode variance -- high enough
      # to trust the self-reference while tolerating non-bit-exact rate
      # control, and far above the ~12-22 dB a concurrency-induced content
      # swap scores against its own reference (so a swapped frame can never
      # masquerade as determinism-confirmed).
      if [[ "$psnr_val" == "inf" ]]; then
        echo "av1_vaapi reference determinism OK (byte-identical extracted frame, PSNR=inf)"
      elif [[ -n "$psnr_val" ]] && awk -v p="$psnr_val" 'BEGIN{exit !(p+0>=50)}'; then
        echo "av1_vaapi reference determinism OK (PSNR fallback): $psnr_val dB >= 50 dB"
      else
        echo "ABORT: av1_vaapi self-reference determinism check failed (D-05 precondition) -- md5 '$md5_a' vs '$md5_b', PSNR fallback '$psnr_val' dB < 50 dB" >&2
        return 1
      fi
    fi
    # The first run's OBU (already at $obu) is kept as the trusted reference.
  else
    echo "== reference-vaapi: av1_vaapi isolated reference (scene $scene) =="
    vaapi_encode "$seek" "$frames" "$obu" \
      || { echo "ABORT: av1_vaapi reference encode for scene $scene failed" >&2; return 1; }
  fi

  ff_bounded -y -nostdin -i "$obu" -vf "select='eq(n\,$off)'" -vsync 0 -frames:v 1 "$png" -hide_banner -loglevel error \
    || { echo "ABORT: av1_vaapi reference frame extraction for scene $scene failed" >&2; return 1; }
  echo "av1_vaapi reference generated for scene $scene: $obu -> $png"
  return 0
}

# ---------------------------------------------------------------------------
# cmd_reference_vaapi -- top-level entry point (D-04/D-05): generate the
# determinism-confirmed av1_vaapi self-reference for all three scenes
# (923/928/1129). Top-level cmd_* entry point: the only vaapi reference
# function allowed to exit; ensure_vaapi_reference itself only returns.
# ---------------------------------------------------------------------------
cmd_reference_vaapi() {
  mkdir -p "$W/reference"
  local scene
  for scene in 923 928 1129; do
    ensure_vaapi_reference "$scene" \
      || { echo "ABORT: av1_vaapi reference generation for scene $scene failed" >&2; exit 1; }
  done
  echo "reference-vaapi complete: av1_vaapi self-references generated for 923/928/1129"
}

# ---------------------------------------------------------------------------
# cmd_run_iter_vaapi <N> -- one full end-to-end av1_vaapi concurrency
# iteration (Phase 2 DIAG-02). Structural copy of cmd_run_iter's four-step
# shape, swapping the measurement encoder to vaapi_encode() and the
# classification reference to the av1_vaapi self-reference (vaapi_ref_png,
# NOT scene_ref_png -- Pitfall 6). The paired ffmpeg av1_qsv immune control
# (ctrl_encode) is UNCHANGED (D-11).
#
#   1. 3-way concurrent av1_vaapi measurement (923/928/1129) into
#      $W/vaapi_runs/it$n, per-encode timeout, per-PID exit capture. PIDs are
#      named vp1/vp2/vp3 (NOT p1/p2/p3) so they never collide with the
#      control block's PID variables in the shared INT/TERM trap. Because the
#      extra_hw_frames=64 fix lives inside vaapi_encode() (02-01), a valid
#      encode exits 0 -- this gate is never loosened. Non-zero/timeout ->
#      EXEC_FAILURE/TIMEOUT, skip PSNR, emit NA rows, do not run the control,
#      return non-zero.
#   2. Multi-scene PSNR classification against vaapi_ref_png (the av1_vaapi
#      self-reference), reusing psnr_of()/classify_corrupt() verbatim
#      (D-06). A failed extraction / empty PSNR is MEASURE_FAILURE (CR-01
#      fail-closed).
#   3. Paired ffmpeg av1_qsv immune control, SEQUENTIAL-AFTER the av1_vaapi
#      measurement, as its own separate 3-way run into
#      $W/control_runs/it$n -- identical to cmd_run_iter's control block,
#      calling ctrl_encode() unchanged (D-11). A non-clean/timed-out control
#      sets status=CONTROL_INVALID for every row of this iteration.
#   4. cleanup_gpu_procs() to avoid tripping the next iteration's gate.
# Emits one row per scene per iteration with the SAME schema as Phase 1:
# iteration,scene,offset,status,psnr_db,corrupt,control_clean.
# ---------------------------------------------------------------------------
cmd_run_iter_vaapi() {
  local n="$1"
  local it_dir="$W/vaapi_runs/it$n"
  local ctrl_dir="$W/control_runs/it$n"
  mkdir -p "$it_dir" "$ctrl_dir"
  local result_file="$it_dir/result.csv"
  : > "$result_file"

  # WR-01 (carried): kill any launched background PIDs and reap GPU clients
  # on INT/TERM. vp1/vp2/vp3 are the av1_vaapi measurement PIDs, distinct
  # from cp1/cp2/cp3 (the control PIDs) so neither block shadows the other.
  trap 'for _pid in "${vp1:-}" "${vp2:-}" "${vp3:-}" "${cp1:-}" "${cp2:-}" "${cp3:-}"; do [[ -n "$_pid" ]] && kill "$_pid" 2>/dev/null || true; done; cleanup_gpu_procs' INT TERM

  # --- Step 1: 3-way concurrent av1_vaapi measurement ---
  vaapi_encode "$SCENE_923_SEEK" "$(ctrl_frames 923)" "$it_dir/c923.obu" &
  local vp1=$!
  vaapi_encode "$SCENE_928_SEEK" "$(ctrl_frames 928)" "$it_dir/c928.obu" &
  local vp2=$!
  vaapi_encode "$SCENE_1129_SEEK" "$(ctrl_frames 1129)" "$it_dir/c1129.obu" &
  local vp3=$!
  wait "$vp1"; local r1=$?
  wait "$vp2"; local r2=$?
  wait "$vp3"; local r3=$?

  local meas_status="OK"
  if [[ $r1 -eq 124 || $r2 -eq 124 || $r3 -eq 124 ]]; then
    meas_status="TIMEOUT"
  elif [[ $r1 -ne 0 || $r2 -ne 0 || $r3 -ne 0 ]]; then
    meas_status="EXEC_FAILURE"
  fi
  echo "vaapi iteration $n measurement exit codes: 923=$r1 928=$r2 1129=$r3 status=$meas_status"

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

  # --- Step 2: multi-scene PSNR classification vs the av1_vaapi self-reference ---
  declare -A psnr_db corrupt meas_fail
  local scene ref_fail=0
  for scene in 923 928 1129; do
    ensure_vaapi_reference "$scene" || { ref_fail=1; break; }
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
    ref_png="$(vaapi_ref_png "$scene")"
    # CR-01: a *failed* frame extraction is the strongest corruption signal.
    # Must NEVER fall through to a clean score -- explicit MEASURE_FAILURE.
    if ! ff_bounded -y -nostdin -i "$obu" -vf "select='eq(n\,$off)'" -vsync 0 -frames:v 1 \
         "$test_png" -hide_banner -loglevel error || [[ ! -s "$test_png" ]]; then
      psnr_db[$scene]="NA"; corrupt[$scene]="NA"; meas_fail[$scene]=1
      echo "vaapi scene $scene offset $off: MEASURE_FAILURE (frame extraction failed / test frame missing)"
      continue
    fi
    local raw
    raw="$(psnr_of "$test_png" "$ref_png" "$statsfile")"
    if [[ -z "$raw" ]]; then
      psnr_db[$scene]="NA"; corrupt[$scene]="NA"; meas_fail[$scene]=1
      echo "vaapi scene $scene offset $off: MEASURE_FAILURE (empty PSNR measurement)"
      continue
    fi
    psnr_db[$scene]="$raw"; corrupt[$scene]="$(classify_corrupt "$raw")"
    meas_fail[$scene]=0
    echo "vaapi scene $scene offset $off: psnr_db=${psnr_db[$scene]} corrupt=${corrupt[$scene]}"
  done

  # --- Step 3: paired ffmpeg av1_qsv immune control, sequential-after,
  #     UNCHANGED (D-11) -- identical to cmd_run_iter's own control block ---
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
    # WR-04 (carried): PSNR-validate EVERY control scene against its own
    # control reference; clean (1) only if all three are >= 30 dB. A
    # missing/empty control PSNR is treated conservatively as NOT clean.
    local cscene coff cpng cref cpsnr
    control_clean="1"
    for cscene in 923 928 1129; do
      coff="$(scene_offset "$cscene")"
      cref="$(ctrl_ref_png "$cscene")"
      cpng="$ctrl_dir/ctrl_frame_${cscene}.png"
      if ! ff_bounded -y -nostdin -i "$ctrl_dir/c${cscene}.obu" -vf "select='eq(n\,$coff)'" -vsync 0 -frames:v 1 \
           "$cpng" -hide_banner -loglevel error || [[ ! -s "$cpng" ]]; then
        echo "vaapi-batch control scene $cscene: frame extraction failed -> control NOT clean"
        control_clean="0"; continue
      fi
      cpsnr="$(psnr_of "$cpng" "$cref" "$ctrl_dir/ctrl_psnr_${cscene}.log")"
      if [[ "$cpsnr" == "inf" ]]; then
        : # byte-identical to the control reference -> clean
      elif [[ -z "$cpsnr" ]]; then
        echo "vaapi-batch control scene $cscene: empty PSNR measurement -> control NOT clean"
        control_clean="0"
      elif [[ "$(awk -v p="$cpsnr" 'BEGIN { print (p+0 >= 30) ? 1 : 0 }')" != "1" ]]; then
        echo "vaapi-batch control scene $cscene: psnr=$cpsnr < 30 dB -> control NOT clean"
        control_clean="0"
      fi
    done
  fi

  if [[ "$control_clean" == "1" ]]; then
    status_final="OK"
  else
    status_final="CONTROL_INVALID"
  fi
  echo "vaapi iteration $n control exit codes: 923=$cr1 928=$cr2 1129=$cr3 control_clean=$control_clean status=$status_final"

  for scene in 923 928 1129; do
    off="$(scene_offset "$scene")"
    if [[ "${meas_fail[$scene]}" == "1" ]]; then
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
# Content-origin cross-match (D-09/D-10): for a frame classified corrupt
# (<30 dB self-reference), confirm its content actually originates from one
# of the OTHER concurrently-running scenes' same-iteration output -- not
# generic garbage -- using ONLY the Phase-1-proven psnr_of() primitive
# (02-RESEARCH.md Pattern 2). This is an add-on to the PSNR classifier,
# never a replacement.
#
# THRESHOLD BAND (distinct from, and higher than, the 30 dB self-reference
# corrupt threshold -- grounded in the qsvencc corrupt frames scoring
# ~12-22 dB against their OWN reference, so a genuine cross-scene content
# match must sit well above that):
#   best_psnr >= 35 dB          -> CONFIRMED CROSS-SESSION CONTENT SWAP
#   20 dB <= best_psnr < 35 dB  -> AMBIGUOUS ORIGIN
#   best_psnr < 20 dB           -> GENERIC GARBAGE (no cross-scene origin)
# TIE-BREAK: if the best match against EACH of the two other scenes is
# within ~2 dB of each other, report "ambiguous origin (matches both
# concurrent scenes within 2 dB)" rather than silently picking one.
#
# Performance note: a naive per-candidate single-frame `select=eq(n,f)`
# extraction re-decodes an .obu from its start for EVERY candidate index (no
# keyframe seeking in a raw AV1 elementary stream), making an N-frame
# scene's full candidate scan cost O(N^2) decode time -- empirically ~1-1.4s
# PER candidate on this hardware, which would put the full historical scan
# at several hours. Instead each OTHER-scene .obu is decoded ONCE per
# (iteration, scene) pair into a cache directory under crossmatch_cache/
# (5-15s for a 111-362 frame scene, verified empirically), and every corrupt
# frame that needs that same iteration+scene's candidates reuses the cache
# -- an O(N) extraction amortized across every corrupt-frame comparison
# against it (e.g. iterations where BOTH 923 and 1129 are corrupt reuse the
# same 928 candidate cache), turning a several-hour naive scan into roughly
# an hour.
#
# Fail-closed (CR-01/T-02-10 lineage): an empty/failed candidate PSNR is
# logged distinctly via failed_candidates in the report line, NEVER silently
# treated as "no match" or scored as 0 -- it is excluded from the best-match
# search, not folded into it.
#
# Worker-function contract: echoes ABORT to stderr and returns 1 on a hard
# failure (missing corrupt PNG, both other-scene legs unusable); never
# exit/die. cmd_cross_match_qsvencc (top-level) is the only entry allowed to
# exit.
# ---------------------------------------------------------------------------
_ccm_cache_key() {
  local obu="$1"
  echo "$(basename "$(dirname "$obu")")_$(basename "$obu" .obu)"
}

# _ccm_extract_candidates <obu> <cache_key> <max_candidates> -- decode <obu>
# ONCE into $W/crossmatch_cache/<cache_key>/frame_%04d.png (0-based, matching
# the "n" convention used everywhere else in this harness), reusing an
# already-populated cache dir if present. max_candidates=0 means extract
# every frame (full scan); >0 caps to the first N frames via -frames:v,
# which lets ffmpeg stop decoding early (used by --smoke).
_ccm_extract_candidates() {
  local obu="$1" cache_key="$2" max_candidates="$3"
  local cache_dir="$W/crossmatch_cache/$cache_key"
  if [[ -d "$cache_dir" && -n "$(ls -A "$cache_dir" 2>/dev/null)" ]]; then
    echo "$cache_dir"
    return 0
  fi
  mkdir -p "$cache_dir" || { echo "ABORT: mkdir cache dir failed: $cache_dir" >&2; return 1; }
  if [[ "$max_candidates" -gt 0 ]]; then
    ff_bounded -y -nostdin -i "$obu" -start_number 0 -frames:v "$max_candidates" -vsync 0 \
      "$cache_dir/frame_%04d.png" -hide_banner -loglevel error
  else
    ff_bounded -y -nostdin -i "$obu" -start_number 0 -vsync 0 \
      "$cache_dir/frame_%04d.png" -hide_banner -loglevel error
  fi
  local rc=$?
  if [[ $rc -ne 0 || -z "$(ls -A "$cache_dir" 2>/dev/null)" ]]; then
    echo "ABORT: candidate frame extraction failed for $obu (exit $rc)" >&2
    return 1
  fi
  echo "$cache_dir"
  return 0
}

# _ccm_psnr_num <raw psnr_of output> -- numeric form for awk comparisons
# ("inf" -> 999, a well-above-band sentinel; empty stays empty).
_ccm_psnr_num() {
  local p="$1"
  if [[ "$p" == "inf" ]]; then
    echo "999"
  elif [[ -z "$p" ]]; then
    echo ""
  else
    echo "$p"
  fi
}

# _ccm_band <numeric psnr> -- the explicit, auditable threshold-band verdict.
_ccm_band() {
  local psnr_num="$1"
  if [[ -z "$psnr_num" ]]; then
    echo "NO VALID CANDIDATES (fail-closed -- cannot classify)"
    return
  fi
  awk -v p="$psnr_num" 'BEGIN {
    if (p+0 >= 35) print "CONFIRMED CROSS-SESSION CONTENT SWAP";
    else if (p+0 >= 20) print "AMBIGUOUS ORIGIN";
    else print "GENERIC GARBAGE (no cross-scene origin)";
  }'
}

# content_cross_match <corrupt_label> <corrupt_png> <otherA_scene> <otherA_obu>
#                      <otherB_scene> <otherB_obu> <out_report> [max_candidates]
# Appends one auditable line to out_report and returns 0, or returns 1 (with
# an ABORT to stderr) only if BOTH other-scene legs are entirely unusable.
content_cross_match() {
  local corrupt_label="$1" corrupt_png="$2"
  local otherA_scene="$3" otherA_obu="$4"
  local otherB_scene="$5" otherB_obu="$6"
  local out_report="$7"
  local max_candidates="${8:-0}"

  if [[ ! -f "$corrupt_png" ]]; then
    echo "ABORT: content_cross_match corrupt_png missing: $corrupt_png" >&2
    return 1
  fi

  local -A scene_best scene_best_raw scene_best_desc
  local failed_count=0 usable_legs=0
  local -a pairs=("$otherA_scene:$otherA_obu" "$otherB_scene:$otherB_obu")
  local pair sc ob
  for pair in "${pairs[@]}"; do
    sc="${pair%%:*}"; ob="${pair#*:}"
    if [[ ! -f "$ob" ]]; then
      echo "content_cross_match: WARN other-scene obu missing for scene $sc ($corrupt_label): $ob" >&2
      scene_best[$sc]=""; scene_best_raw[$sc]=""; scene_best_desc[$sc]="obu missing"
      continue
    fi
    local cache_key cache_dir
    cache_key="$(_ccm_cache_key "$ob")"
    cache_dir="$(_ccm_extract_candidates "$ob" "$cache_key" "$max_candidates")"
    if [[ -z "$cache_dir" ]]; then
      echo "content_cross_match: WARN candidate extraction failed for scene $sc ($corrupt_label)" >&2
      scene_best[$sc]=""; scene_best_raw[$sc]=""; scene_best_desc[$sc]="extraction failed"
      failed_count=$((failed_count + 1))
      continue
    fi
    usable_legs=$((usable_legs + 1))
    local best_local="" best_local_raw="" best_local_desc="" scanned=0
    local cand idx statsfile p pnum
    for cand in "$cache_dir"/frame_*.png; do
      [[ -f "$cand" ]] || continue
      scanned=$((scanned + 1))
      if (( scanned % 100 == 0 )); then
        echo "  content_cross_match progress ($corrupt_label vs scene $sc): $scanned candidates scanned"
      fi
      idx="$(basename "$cand" .png)"; idx="${idx#frame_}"
      statsfile="$W/crossmatch_cache/.psnr_tmp_$$.log"
      p="$(psnr_of "$corrupt_png" "$cand" "$statsfile")"
      rm -f "$statsfile"
      if [[ -z "$p" ]]; then
        # CR-01/T-02-10 fail-closed: logged distinctly, never silently
        # treated as "no match" or scored as 0.
        echo "content_cross_match: WARN empty PSNR for $corrupt_label vs scene $sc frame $idx -- logged, not scored" >&2
        failed_count=$((failed_count + 1))
        continue
      fi
      pnum="$(_ccm_psnr_num "$p")"
      if [[ -z "$best_local" ]] || awk -v a="$pnum" -v b="$best_local" 'BEGIN{exit !(a+0>b+0)}'; then
        best_local="$pnum"; best_local_raw="$p"; best_local_desc="scene $sc frame $idx"
      fi
    done
    scene_best[$sc]="$best_local"
    scene_best_raw[$sc]="$best_local_raw"
    scene_best_desc[$sc]="${best_local_desc:-no candidates found} ($scanned candidates scanned)"
  done

  if [[ $usable_legs -eq 0 ]]; then
    echo "ABORT: content_cross_match both other-scene legs unusable for $corrupt_label" >&2
    echo "$corrupt_label: BOTH other-scene legs unusable -- verdict=NO VALID CANDIDATES (fail-closed)" >> "$out_report"
    return 1
  fi

  local a_num="${scene_best[$otherA_scene]}" a_raw="${scene_best_raw[$otherA_scene]}"
  local b_num="${scene_best[$otherB_scene]}" b_raw="${scene_best_raw[$otherB_scene]}"
  local verdict best_display_raw winner_num diff

  if [[ -n "$a_num" && -n "$b_num" ]]; then
    diff="$(awk -v a="$a_num" -v b="$b_num" 'BEGIN{d=a-b; if(d<0)d=-d; print d}')"
    if awk -v d="$diff" 'BEGIN{exit !(d<=2)}'; then
      verdict="AMBIGUOUS ORIGIN (matches both concurrent scenes within 2 dB)"
      if awk -v a="$a_num" -v b="$b_num" 'BEGIN{exit !(a>=b)}'; then best_display_raw="$a_raw"; else best_display_raw="$b_raw"; fi
    else
      if awk -v a="$a_num" -v b="$b_num" 'BEGIN{exit !(a>b)}'; then
        best_display_raw="$a_raw"; winner_num="$a_num"
      else
        best_display_raw="$b_raw"; winner_num="$b_num"
      fi
      verdict="$(_ccm_band "$winner_num")"
    fi
  elif [[ -n "$a_num" ]]; then
    best_display_raw="$a_raw"; verdict="$(_ccm_band "$a_num")"
  elif [[ -n "$b_num" ]]; then
    best_display_raw="$b_raw"; verdict="$(_ccm_band "$b_num")"
  else
    best_display_raw=""
    verdict="NO VALID CANDIDATES (fail-closed -- no scored candidates from either scene)"
  fi

  local disp_a="${a_raw:-NA}" disp_b="${b_raw:-NA}"
  echo "$corrupt_label: vs_${otherA_scene}=${disp_a} (${scene_best_desc[$otherA_scene]:-n/a}) vs_${otherB_scene}=${disp_b} (${scene_best_desc[$otherB_scene]:-n/a}) failed_candidates=$failed_count best_psnr=${best_display_raw:-NA} verdict=$verdict" >> "$out_report"
  echo "content_cross_match result for $corrupt_label: best_psnr=${best_display_raw:-NA} verdict=$verdict"
  return 0
}

# _ccm_corrupt_png_path <scene> <it> -- the Phase-1 on-disk corrupt-frame PNG
# path for a qsvencc historical iteration (mirrors cmd_run_iter's own
# test_png naming: 923 -> frame299.png, 1129 -> frame299_1129.png).
_ccm_corrupt_png_path() {
  local scene="$1" it="$2"
  case "$scene" in
    923) echo "$W/runs/it$it/frame299.png" ;;
    1129) echo "$W/runs/it$it/frame299_1129.png" ;;
    *) echo "unsupported scene for qsvencc cross-match: $scene" >&2; return 1 ;;
  esac
}

# _ccm_ensure_corrupt_png <scene> <it> -- PNG preflight (T-02-16): extract the
# corrupt-frame PNG from that iteration's .obu at scene_offset if it is not
# already on disk, so the long scan cannot fail mid-way on a missing input.
_ccm_ensure_corrupt_png() {
  local scene="$1" it="$2" png off obu
  png="$(_ccm_corrupt_png_path "$scene" "$it")" || return 1
  [[ -f "$png" ]] && return 0
  off="$(scene_offset "$scene")"
  obu="$W/runs/it$it/c${scene}.obu"
  if [[ ! -f "$obu" ]]; then
    echo "ABORT: cannot preflight corrupt-frame PNG for it$it scene $scene -- source obu missing: $obu" >&2
    return 1
  fi
  echo "preflight: extracting missing corrupt-frame PNG for it$it scene $scene from $obu (offset $off)"
  ff_bounded -y -nostdin -i "$obu" -vf "select='eq(n\,$off)'" -vsync 0 -frames:v 1 "$png" -hide_banner -loglevel error \
    || { echo "ABORT: preflight extraction failed for it$it scene $scene" >&2; return 1; }
  [[ -s "$png" ]] || { echo "ABORT: preflight extraction produced empty file for it$it scene $scene" >&2; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# cmd_cross_match_qsvencc [--smoke] -- top-level entry point (D-09/D-10):
# apply content_cross_match to the historical Phase-1 qsvencc corrupt frames
# (scratch/repro/runs/itNN/, read strictly READ-ONLY -- T-02-11). Closes
# Phase 1's summary.txt "Mechanism-vs-symptom NOTE", explicitly deferred to
# Phase 2.
#
#   --smoke  scans exactly ONE corrupt frame against a capped ~15-candidate
#            subset of each other scene, writing crossmatch_qsvencc_smoke.txt
#            in well under a minute -- proves the code path + verdict format
#            WITHOUT the multi-hour full scan. NEVER overwrites the real
#            full-scan output file.
#   (none)   full historical scan over every report.csv corrupt row (or the
#            01-EVIDENCE.md fallback list if report.csv is missing/empty),
#            writing crossmatch_qsvencc.txt with an aggregate verdict. This
#            is the long operator batch (T-02-16) -- run via a backgrounded
#            / non-blocking mechanism, never inside a short verify timeout.
#
# report.csv GUARD: the corrupt set is read at runtime from report.csv
# (corrupt==1, status==OK rows), never hardcoded. A missing/empty report.csv
# degrades to a loud WARN + the documented 01-EVIDENCE.md corrupt-iteration
# list; if BOTH report.csv and the runs/ .obu inputs are absent, this
# ABORTs (nothing to cross-match against).
#
# Top-level cmd_* entry point: the only cross-match function allowed to
# exit; content_cross_match itself only returns.
# ---------------------------------------------------------------------------
cmd_cross_match_qsvencc() {
  local smoke=0
  [[ "${1:-}" == "--smoke" ]] && smoke=1

  echo "=============================================================================="
  echo "content-origin cross-match: qsvencc historical corrupt-frame scan (D-09/D-10)"
  echo "=============================================================================="
  if [[ $smoke -eq 1 ]]; then
    echo "MODE: --smoke -- ONE corrupt frame, ~15-candidate cap per other scene, writes"
    echo "  crossmatch_qsvencc_smoke.txt (does NOT touch the real crossmatch_qsvencc.txt)"
  else
    echo "COST WARNING: full historical scan, GPU-free (decode+PSNR only, no Arc"
    echo "  contention) but NOT a trivial-cost step -- expect roughly ~1 hour"
    echo "  wall-clock on this hardware (each other-scene .obu is decoded once into a"
    echo "  cache, then ~1500-3500 PSNR compares against the cached candidates). Run"
    echo "  this as a background / non-blocking operator batch, never inside a short"
    echo "  verify timeout."
    local avail_kb threshold_kb=$((30 * 1024 * 1024))
    avail_kb="$(df -Pk "$W" | awk 'NR==2{print $4}')"
    if [[ -z "$avail_kb" || "$avail_kb" -lt "$threshold_kb" ]]; then
      echo "ABORT: insufficient free disk space under $W for the candidate-frame cache (available: ${avail_kb:-unknown} KB, need >= ${threshold_kb} KB)" >&2
      exit 1
    fi
    echo "disk preflight OK: ${avail_kb} KB available under $W"
  fi
  echo

  local report="$W/report.csv"
  local -a corrupt_923_its=() corrupt_1129_its=()
  local have_report=0
  if [[ -s "$report" ]]; then
    have_report=1
    local iteration scene offset status psnr_db corrupt control_clean
    while IFS=, read -r iteration scene offset status psnr_db corrupt control_clean; do
      [[ "$iteration" == "iteration" ]] && continue
      [[ "$status" == "OK" && "$corrupt" == "1" ]] || continue
      case "$scene" in
        923) corrupt_923_its+=("$iteration") ;;
        1129) corrupt_1129_its+=("$iteration") ;;
      esac
    done < "$report"
  fi

  if [[ $have_report -eq 0 || ( ${#corrupt_923_its[@]} -eq 0 && ${#corrupt_1129_its[@]} -eq 0 ) ]]; then
    echo "WARN: report.csv not found or has zero corrupt rows; falling back to the 01-EVIDENCE.md known corrupt list" >&2
    if [[ ! -d "$W/runs" || -z "$(find "$W/runs" -maxdepth 2 -name '*.obu' -print -quit 2>/dev/null)" ]]; then
      echo "ABORT: report.csv not found and runs/ .obu inputs missing; re-run Phase 1 run-batch first" >&2
      exit 1
    fi
    corrupt_923_its=(04 07 08 10 11 12 14 17)
    corrupt_1129_its=(05 06 09 10 12 13 14 18)
  fi

  echo "corrupt set: scene 923 -> ${corrupt_923_its[*]:-(none)}  scene 1129 -> ${corrupt_1129_its[*]:-(none)}"
  echo

  # PNG preflight (T-02-16): ensure every corrupt-frame PNG exists BEFORE the
  # long loop starts, so the multi-hour scan cannot fail mid-way on a
  # missing input (1129's frame299_1129.png in particular may not have been
  # extracted per-iteration in Phase 1).
  local it
  for it in "${corrupt_923_its[@]}"; do
    _ccm_ensure_corrupt_png 923 "$it" || exit 1
  done
  for it in "${corrupt_1129_its[@]}"; do
    _ccm_ensure_corrupt_png 1129 "$it" || exit 1
  done
  echo "corrupt-frame PNG preflight OK"
  echo

  local out_report max_candidates
  if [[ $smoke -eq 1 ]]; then
    out_report="$W/crossmatch_qsvencc_smoke.txt"
    max_candidates=15
  else
    out_report="$W/crossmatch_qsvencc.txt"
    max_candidates=0
  fi
  : > "$out_report"

  local -a worklist=()
  for it in "${corrupt_923_its[@]}"; do worklist+=("923:$it"); done
  for it in "${corrupt_1129_its[@]}"; do worklist+=("1129:$it"); done

  if [[ $smoke -eq 1 && ${#worklist[@]} -gt 0 ]]; then
    worklist=("${worklist[0]}")
  fi

  local total="${#worklist[@]}"
  local done_count=0 confirmed=0 ambiguous=0 generic=0 novalid=0
  local entry sc it_lbl corrupt_png otherA_sc otherB_sc otherA_obu otherB_obu

  for entry in "${worklist[@]}"; do
    sc="${entry%%:*}"; it_lbl="${entry#*:}"
    done_count=$((done_count + 1))
    echo "-- [$done_count/$total] cross-matching it$it_lbl scene $sc --"
    corrupt_png="$(_ccm_corrupt_png_path "$sc" "$it_lbl")" || exit 1
    case "$sc" in
      923) otherA_sc=928; otherB_sc=1129 ;;
      1129) otherA_sc=923; otherB_sc=928 ;;
    esac
    otherA_obu="$W/runs/it$it_lbl/c${otherA_sc}.obu"
    otherB_obu="$W/runs/it$it_lbl/c${otherB_sc}.obu"

    if content_cross_match "it$it_lbl-$sc" "$corrupt_png" "$otherA_sc" "$otherA_obu" "$otherB_sc" "$otherB_obu" "$out_report" "$max_candidates"; then
      local last_line
      last_line="$(tail -n1 "$out_report")"
      case "$last_line" in
        *"verdict=CONFIRMED"*) confirmed=$((confirmed + 1)) ;;
        *"verdict=AMBIGUOUS"*) ambiguous=$((ambiguous + 1)) ;;
        *"verdict=GENERIC"*) generic=$((generic + 1)) ;;
        *) novalid=$((novalid + 1)) ;;
      esac
    else
      echo "WARN: content_cross_match failed for it$it_lbl scene $sc -- see stderr above" >&2
      novalid=$((novalid + 1))
    fi
  done

  {
    echo
    echo "=============================================================================="
    if [[ $smoke -eq 1 ]]; then
      echo "AGGREGATE VERDICT (SMOKE): $total corrupt frame(s) cross-matched"
    else
      echo "AGGREGATE VERDICT (FULL): $total corrupt frame(s) cross-matched"
    fi
    echo "  confirmed cross-session content swap (>=35 dB): $confirmed"
    echo "  ambiguous origin (20-35 dB or within-2dB tie):  $ambiguous"
    echo "  generic garbage / no cross-scene origin (<20 dB): $generic"
    echo "  no valid candidates (fail-closed):               $novalid"
    if [[ $smoke -eq 0 ]]; then
      if [[ $total -gt 0 && $confirmed -eq $total ]]; then
        echo "  -> Phase 1's deferred Mechanism-vs-symptom NOTE is CLOSED: every historical"
        echo "     qsvencc corrupt frame is a confirmed cross-session content swap."
      elif [[ $confirmed -gt 0 ]]; then
        echo "  -> Phase 1's deferred Mechanism-vs-symptom NOTE is PARTIALLY closed:"
        echo "     $confirmed/$total corrupt frames confirmed as cross-session content swaps;"
        echo "     the remainder scored ambiguous/generic (see per-frame lines above)."
      else
        echo "  -> Phase 1's deferred Mechanism-vs-symptom NOTE is NOT closed by this scan:"
        echo "     no corrupt frame scored >=35 dB against a concurrent scene."
      fi
    fi
    echo "=============================================================================="
  } | tee -a "$out_report"
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
# print_batch_summary_vaapi -- read report_vaapi.csv and print the
# av1_vaapi-specific triangulation report (Phase 2 DIAG-02): raw X/N_actual +
# 95% Wilson CI for the primary hotspot (reusing wilson_ci()/scene_stats()
# verbatim from print_batch_summary, same 30 dB threshold, same OK-only
# denominator), confirmatory fractions for the other two hotspots, the paired
# av1_qsv immune control result (D-11), the D-02 triad caveat read from
# vaapi_probe.txt (degrades to an explicit UNAVAILABLE line, never a silent
# blank, if the probe file is missing/empty -- T-02-15), a minimum-valid-
# iteration floor emitting a DEGRADED BATCH warning below ceil(0.85 x
# n_requested) valid iterations, the D-07/D-08 gated-escalation verdict
# (positive -> stop; 0/N + full triad -> escalate to N~60; 0/N + partial/
# unknown triad -> do NOT escalate), and the explicit roadmap SC#2
# interpretation (partial-triad clean branch states "immunity NOT proven",
# D-03). Also saved to summary_vaapi.txt.
# ---------------------------------------------------------------------------
print_batch_summary_vaapi() {
  local report="$1" n_requested="$2" n_actual="$3"
  REPORT_CSV="$report" N_REQUESTED="$n_requested" N_ACTUAL="$n_actual" \
    VAAPI_PROBE_FILE="$W/vaapi_probe.txt" python3 <<'PYEOF' | tee "$W/summary_vaapi.txt"
import csv, os, math, statistics

report_csv = os.environ["REPORT_CSV"]
n_requested = int(os.environ["N_REQUESTED"])
n_actual = int(os.environ["N_ACTUAL"])
probe_file = os.environ["VAAPI_PROBE_FILE"]

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

# D-02 triad caveat: read vaapi_probe.txt. A missing/empty file (workdir
# cleaned or probe never run) degrades to an explicit UNAVAILABLE line --
# never a silent blank and never an error (T-02-15).
reorder_verdict = "UNAVAILABLE"
p010_verdict = "UNAVAILABLE"
hwdecode_verdict = "UNAVAILABLE"
triad_line = "UNAVAILABLE"
probe_available = False
try:
    with open(probe_file) as f:
        content = f.read()
    if content.strip():
        probe_available = True
        for line in content.splitlines():
            if line.startswith("reorder:"):
                reorder_verdict = line.split(":", 1)[1].strip()
            elif line.startswith("p010:"):
                p010_verdict = line.split(":", 1)[1].strip()
            elif line.startswith("hw_decode:"):
                hwdecode_verdict = line.split(":", 1)[1].strip()
            elif line.startswith("triad:"):
                triad_line = line.split(":", 1)[1].strip()
except OSError:
    probe_available = False

full_triad = probe_available and reorder_verdict == "ACTIVE" and p010_verdict == "ACTIVE" and hwdecode_verdict == "ACTIVE"

# Minimum-valid-iteration floor (T-02-15): ceil(0.85 * n_requested), e.g. 17
# of 20. Below this floor, emit a loud DEGRADED BATCH warning in addition to
# (never instead of) the existing OK-only denominator accounting.
valid_floor = math.ceil(0.85 * n_requested)
degraded = n_actual < valid_floor

total_corrupt = s923["x"] + s928["x"] + s1129["x"]

print("=" * 78)
print("av1_vaapi concurrent-encode triangulation -- detection batch report (DIAG-02)")
print("=" * 78)
print()
print(f"N_requested: {n_requested}")
print(f"N_actual:    {n_actual}")
print(f"  OK: {ok_n}  EXEC_FAILURE: {exec_failure}  TIMEOUT: {timeout_n}  MEASURE_FAILURE: {measure_failure}  CONTROL_INVALID: {control_invalid}")
print(f"  (excluded from corruption-fraction denominator: {exec_failure + timeout_n + measure_failure + control_invalid})")
print()
print("-- Primary hotspot: scene 923 / offset 299 (vs av1_vaapi self-reference) --")
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
print("-- Paired immune control (D-11) --")
print(f"  ffmpeg av1_qsv control non-clean/invalidated iterations: {control_invalid}/{n_actual}")
print(f"  (expected 0/{n_actual} -- a non-zero count here means the control itself was")
print("   compromised for that iteration and it was excluded from the av1_vaapi finding)")
print()
print("-- av1_vaapi triad caveat (D-02/D-03) --")
if not probe_available:
    print("  triad caveat: UNAVAILABLE - probe not run or file missing")
else:
    print(f"  reorder (B-frame leg):        {reorder_verdict}")
    print(f"  p010 (10-bit surfaces):       {p010_verdict}")
    print(f"  hw_decode (VA video-memory):  {hwdecode_verdict}")
    print(f"  triad verdict: {triad_line}")
    print("  (reorder caveat is narrow: no display/decode reordering observed via PTS/DTS;")
    print("   this is NOT a claim of zero reference-surface-lifetime effect -- 02-RESEARCH.md Open Question #1)")
print(f"  full_triad = {full_triad}")
print()
print("-- Minimum-valid-iteration floor --")
print(f"  valid iterations: {n_actual}/{n_requested} (floor: {valid_floor} = ceil(0.85 x {n_requested}))")
if degraded:
    print(f"  DEGRADED BATCH - detection power reduced (only {n_actual} of {n_requested} iterations valid); re-run recommended")
else:
    print("  floor met -- detection power at nominal N")
print()
print("-- Gated escalation (D-07/D-08) --")
if total_corrupt >= 1:
    print(f"  av1_vaapi REPRODUCES corruption; detection-grade, STOP (no N~60 once positive)")
elif full_triad:
    print(f"  0/{n_actual} with FULL triad -> escalate to validation-N~60 (rule-of-three) to earn a clean/immune claim")
    print("  operator should run: run-batch-vaapi 60")
else:
    print(f"  0/{n_actual} with PARTIAL/UNKNOWN triad -> do NOT escalate; 60 runs on a broken triad prove nothing")
    print("  report detection-grade PARTIAL-TRIAD only")
print()
print("-- Interpretation (roadmap SC#2) --")
if total_corrupt >= 1:
    print("  av1_vaapi CORRUPT: broadens the suspected fault beyond qsvencc's own oneVPL")
    print("  pool code toward the shared kernel/driver VA layer.")
elif full_triad:
    print("  av1_vaapi CLEAN with FULL triad: strengthens the ffmpeg-migration case (Option C).")
else:
    print("  av1_vaapi CLEAN but PARTIAL triad: immunity NOT proven (D-03) -- a clean result")
    print("  here does not confirm av1_vaapi is immune to the trigger triad, only that the")
    print("  legs that WERE reproducible did not corrupt under this concurrency.")
print()
print("-- Detection-N vs validation-N (D-07) --")
print(f"  This batch is the DETECTION sample (N_requested={n_requested}), sized to observe")
print("  whether av1_vaapi reproduces the documented corruption under 3-way concurrency.")
print("  A larger ~60 zero-failure VALIDATION-N (rule-of-three) is defined but only run")
print("  if the gated-escalation verdict above calls for it (D-08).")
print("=" * 78)
PYEOF
}

# ---------------------------------------------------------------------------
# run-batch-vaapi [N=20] -- loop cmd_run_iter_vaapi N times, write
# report_vaapi.csv (distinct from the qsvencc report.csv). Structural copy of
# cmd_run_batch: WR-08 numeric-N guard, disk preflight, an EXTENDED
# reference-artifact preflight (requires both the av1_vaapi self-references
# AND the av1_qsv control references), inter-iteration GPU-idle recheck with
# cleanup_gpu_procs retries, and the "one bad iteration never aborts the
# batch" pattern.
# ---------------------------------------------------------------------------
cmd_run_batch_vaapi() {
  local n_requested="${1:-20}"
  # WR-08: a non-numeric N silently no-ops `seq` (zero iterations) and then
  # would crash a Python summary at int(N_REQUESTED). Validate up front.
  if [[ ! "$n_requested" =~ ^[1-9][0-9]*$ ]]; then
    echo "ABORT: N must be a positive integer (got: '$n_requested')" >&2
    exit 2
  fi
  mkdir -p "$W/vaapi_runs" "$W/control_runs"

  # Disk preflight (carried from cmd_run_batch).
  local avail_kb threshold_kb=$((5 * 1024 * 1024))
  avail_kb="$(df -Pk "$W" | awk 'NR==2{print $4}')"
  if [[ -z "$avail_kb" || "$avail_kb" -lt "$threshold_kb" ]]; then
    echo "ABORT: insufficient free disk space under $W (available: ${avail_kb:-unknown} KB, need >= ${threshold_kb} KB) -- aborting before the batch to avoid a full-disk mid-batch corruption" >&2
    exit 1
  fi
  echo "disk preflight OK: ${avail_kb} KB available under $W"

  # Reference-artifact preflight (WR-05), EXTENDED for av1_vaapi: without
  # both the av1_vaapi self-references and the av1_qsv control references,
  # every iteration's classification/control validation fails silently.
  local rscene missing=0 vpng cpng
  for rscene in 923 928 1129; do
    vpng="$(vaapi_ref_png "$rscene")"; cpng="$(ctrl_ref_png "$rscene")"
    [[ -f "$vpng" ]] || { echo "ABORT: missing av1_vaapi self-reference frame for scene $rscene: $vpng" >&2; missing=1; }
    [[ -f "$cpng" ]] || { echo "ABORT: missing control reference frame for scene $rscene: $cpng" >&2; missing=1; }
  done
  if [[ $missing -ne 0 ]]; then
    echo "ABORT: run '$0 reference-vaapi' and '$0 reference' first (missing reference artifacts)" >&2
    exit 1
  fi
  echo "reference-artifact preflight OK: av1_vaapi self-references + control references present for 923/928/1129"

  local report="$W/report_vaapi.csv"
  echo "iteration,scene,offset,status,psnr_db,corrupt,control_clean" > "$report"

  local i iter_label n_actual=0 n_contaminated=0
  for i in $(seq 1 "$n_requested"); do
    iter_label="$(printf "%02d" "$i")"

    # Inter-iteration GPU isolation re-check (carried from cmd_run_batch).
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
      echo "WARNING: vaapi iteration $iter_label GPU still not idle after cleanup + retries -- marking contaminated, not starting a new encode on a dirty GPU: $(gpu_clients)" >&2
      local scene off
      for scene in 923 928 1129; do
        off="$(scene_offset "$scene")"
        echo "$iter_label,$scene,$off,EXEC_FAILURE,NA,NA,NA" >> "$report"
      done
      n_contaminated=$((n_contaminated + 1))
      continue
    fi

    cmd_run_iter_vaapi "$iter_label" || true
    if [[ -f "$W/vaapi_runs/it$iter_label/result.csv" ]]; then
      cat "$W/vaapi_runs/it$iter_label/result.csv" >> "$report"
      n_actual=$((n_actual + 1))
    fi
  done

  echo "vaapi batch complete: n_requested=$n_requested n_actual=$n_actual contaminated_skipped=$n_contaminated"
  print_batch_summary_vaapi "$report" "$n_requested" "$n_actual"
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
    reference-vaapi)
      cmd_reference_vaapi
      ;;
    run-iter)
      shift
      cmd_run_iter "${1:?run-iter requires an iteration number}"
      ;;
    run-batch)
      shift
      cmd_run_batch "${1:-20}"
      ;;
    run-iter-vaapi)
      shift
      cmd_run_iter_vaapi "${1:?run-iter-vaapi requires an iteration number}"
      ;;
    run-batch-vaapi)
      shift
      cmd_run_batch_vaapi "${1:-20}"
      ;;
    cross-match-qsvencc)
      shift
      cmd_cross_match_qsvencc "${1:-}"
      ;;
    *)
      echo "Usage: $0 {probe|probe-vaapi|reference|reference-vaapi|run-iter <N>|run-batch [N=20]|run-iter-vaapi <N>|run-batch-vaapi [N=20]|cross-match-qsvencc [--smoke]}" >&2
      exit 2
      ;;
  esac
}

main "$@"
