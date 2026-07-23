# Phase 2: In-Container Triangulation — av1_vaapi - Pattern Map

**Mapped:** 2026-07-23
**Files analyzed:** 2 (both modified/extended, no wholly new source files — per phase scope note)
**Analogs found:** 9 / 11 (function-group granularity; see below — 2 genuinely-new logic blocks have no in-harness analog and are called out explicitly)

This phase does not add new files to the repo tree; it extends `scratch/repro/harness.sh` and `scratch/repro/lib.sh` in place. Because "closest analog" at file granularity is trivial (there are only two files), this map operates at **function-group granularity**: each new function/logic block the plan will add is mapped to the closest existing function it should structurally mirror, with concrete excerpts.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog (same file, function-level) | Match Quality |
|---|---|---|---|---|
| `scratch/repro/harness.sh` (extended) | controller / CLI dispatcher script | request-response (subcommand dispatch) + batch | itself — `main()` dispatcher, existing subcommand functions | exact (same file, additive) |
| `scratch/repro/lib.sh` (extended) | utility / shared helper library | transform + batch | itself — existing helper functions | exact (same file, additive) |

### Function-level classification (what the plan will actually add)

| New Function (proposed) | Role | Data Flow | Closest Analog Function | Match Quality |
|---|---|---|---|---|
| `cmd_probe_vaapi` (D-02 triad-leg probe) | controller / gate | request-response, writes `vaapi_probe.txt` | `cmd_reference` (harness.sh:114-181) — "fails fast, gates the next stage" shape; secondarily `cmd_probe` (harness.sh:80-107) — "individually-guarded checks written to a report file" shape | role-match (blend of two existing analogs) |
| `vaapi_encode()` (av1_vaapi command builder) | utility / encode invocation wrapper | request-response (single encode call) | `ctrl_encode()` (harness.sh:189-198) | exact |
| `ensure_vaapi_reference` (D-04/D-05 self-reference + determinism check) | utility / reference-generation helper | CRUD (generate-once, cache-check) | `ensure_control_reference` (harness.sh:274-291) and `ensure_scene_reference` (harness.sh:300-325); determinism-md5 block from `cmd_reference` (harness.sh:128-138) | exact |
| `vaapi_ref_obu` / `vaapi_ref_png` (scene table lookups for the vaapi self-reference) | utility / lookup table | CRUD | `ctrl_ref_obu` / `ctrl_ref_png` / `ctrl_frames` (harness.sh:251-266) | exact |
| `cmd_run_iter_vaapi` (3-way concurrent av1_vaapi measure + classify + paired control) | controller / orchestration | event-driven (parallel job fan-out/fan-in) + CRUD | `cmd_run_iter` (harness.sh:378-544) | exact |
| `psnr_of` / `classify_corrupt` (D-06 classifier) | utility / transform | transform | **reused verbatim, no new function needed** — `psnr_of` (lib.sh via harness.sh:332-337), `classify_corrupt` (harness.sh:344-357) | exact (verbatim reuse) |
| PTS/DTS reorder probe (D-02 leg-a test) | utility / measurement | transform (ffprobe output → boolean) | **no analog in harness** — genuinely new technique | none — see "No Analog Found" |
| Content-origin cross-match (D-09/D-10) | utility / search-loop | batch (nested loop over candidate frames) + transform | closest structural parallel: the per-scene loop in `cmd_run_iter` (harness.sh:444-472) that calls `psnr_of` per scene; but the nested "loop over every candidate frame of two other scenes, track max" shape is new | none exact — see "No Analog Found" |
| `print_batch_summary_vaapi` | utility / reporting (Python heredoc via env-passed CSV) | transform + batch | `print_batch_summary` (harness.sh:555-682) | exact |
| `cmd_run_batch_vaapi` | controller / batch loop | batch | `cmd_run_batch` (harness.sh:689-769) | exact |
| `main()` dispatcher cases (`probe-vaapi`, `run-iter-vaapi`, `run-batch-vaapi`) | controller / CLI routing | request-response | `main()` (harness.sh:774-798) | exact |

## Pattern Assignments

### `vaapi_encode()` (utility, request-response) — command builder

**Analog:** `ctrl_encode()`, `scratch/repro/harness.sh:189-198`

**Core pattern to copy** (verbatim structure — logfile derivation, `run_encode` wrapping, `-ss` before `-i`, flags-then-output-then-loglevel arg order):
```bash
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
```
**How `vaapi_encode()` should differ (per RESEARCH.md Code Examples, verified 2026-07-23):**
- `-hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128` (not `qsv`)
- `-vf 'scale_vaapi=format=p010:extra_hw_frames=64'` — **NOT** `vpp_qsv=format=p010le` and **NOT** `format=p010,hwupload=...` (both wrong for a VAAPI-hwaccel-decoded input; the `extra_hw_frames=64` is mandatory — Pitfall 2, see Shared Patterns below)
- `-c:v av1_vaapi -profile:v main -low_power 1 -g 300 -bf N -b_depth N -refs 4 -rc_mode ICQ -global_quality 24 -tiles 1x1`
- Same `run_encode "$logfile" ... "$out" -hide_banner -loglevel error` wrapper shape, unchanged
- Keep `-ss` **before** `-i` (Pitfall 3 — accurate-seek mode on `-ss` after `-i` will blow the 120s `ENCODE_TIMEOUT` on deep-timeline scenes)

---

### `ensure_vaapi_reference` (utility, CRUD) — self-reference + determinism check

**Analog 1 — cache-check-then-generate shape:** `ensure_control_reference()`, `scratch/repro/harness.sh:274-291`
```bash
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
```
Note the worker-function contract: **`return 1`, never `exit`/`die()`**, inside a helper called from a loop — this is the pattern the RESEARCH.md "Project Constraints" section says must carry forward unchanged.

**Analog 2 — determinism (D-05) re-confirmation, WR-10 empty-string guard:** `cmd_reference()` md5 block, `scratch/repro/harness.sh:120-138`
```bash
qsvencc --avhw --va -i "$SRC" $COMMON \
  --seek "$SCENE_923_SEEK" --trim "$SCENE_923_TRIM" \
  -o "$W/reference/chunk923_ref.obu" || { echo "ABORT: reference encode (run 1) failed" >&2; exit 1; }

qsvencc --avhw --va -i "$SRC" $COMMON \
  --seek "$SCENE_923_SEEK" --trim "$SCENE_923_TRIM" \
  -o "$W/reference/chunk923_ref_repeat.obu" || { echo "ABORT: reference encode (run 2) failed" >&2; exit 1; }

local md5_a md5_b
md5_a="$(md5sum "$W/reference/chunk923_ref.obu" | awk '{print $1}')"
md5_b="$(md5sum "$W/reference/chunk923_ref_repeat.obu" | awk '{print $1}')"
# WR-10: require both hashes non-empty AND equal (fail-closed, same direction as CR-01)
if [[ -z "$md5_a" || -z "$md5_b" || "$md5_a" != "$md5_b" ]]; then
  echo "ABORT: reference determinism check invalid or failed -- md5 '$md5_a' vs '$md5_b' (D-05 precondition violated)" >&2
  exit 1
fi
```
**Apply to av1_vaapi:** two isolated `vaapi_encode()` calls on scene 923 (offset 299, per D-04), md5-compare, same WR-10 empty-string guard, same fail-loud-at-top-level semantics (D-05 explicitly requires this pre-trust gate). Store outputs under a separate path so they are never confused with the qsvencc reference (D-04's own warning / Pitfall 6: reusing the qsvencc reference for av1_vaapi classification silently makes every frame look corrupt).

---

### `cmd_run_iter_vaapi` (controller, event-driven + CRUD)

**Analog:** `cmd_run_iter()`, `scratch/repro/harness.sh:378-544` — copy its four-step shape wholesale:

1. **3-way concurrent background jobs + exit-code capture** (harness.sh:393-413):
```bash
run_encode "$it_dir/log923.txt" qsvencc --avhw --va -i "$SRC" $COMMON \
  --seek "$SCENE_923_SEEK" --trim "$SCENE_923_TRIM" -o "$it_dir/c923.obu" &
local p1=$!
...
wait "$p1"; local r1=$?
wait "$p2"; local r2=$?
wait "$p3"; local r3=$?

local meas_status="OK"
if [[ $r1 -eq 124 || $r2 -eq 124 || $r3 -eq 124 ]]; then
  meas_status="TIMEOUT"
elif [[ $r1 -ne 0 || $r2 -ne 0 || $r3 -ne 0 ]]; then
  meas_status="EXEC_FAILURE"
fi
```
**Critical deviation required for av1_vaapi (Pitfall 2, harness-breaking gotcha found live in this environment):** with the `extra_hw_frames=64` fix applied inside `vaapi_encode()`'s `scale_vaapi` filter string, ffmpeg exits 0 for a valid `-frames:v`-bounded pipeline. **Without the fix, exit code 244 fires on a fully valid output** and this exact `meas_status="EXEC_FAILURE"` branch would silently discard every av1_vaapi iteration from the corruption-fraction denominator — apply the fix inside `vaapi_encode()`, do not loosen this gate.

2. **Multi-scene PSNR classification loop** (harness.sh:426-472) — reuse `psnr_of()`/`classify_corrupt()` verbatim, only swap the reference PNGs to the new `vaapi_ref_png` lookups and the trap/PID list to the vaapi job PIDs.

3. **Paired immune control, sequential-after, separate 3-way run** (harness.sh:474-519) — `ctrl_encode()` calls **unchanged, verbatim** (D-11: this is still the ffmpeg `av1_qsv` control, identical to Phase 1/qsvencc's own control — do not build a new control encoder).

4. **INT/TERM cleanup trap** (harness.sh:391) — copy verbatim, extend the PID list for the vaapi job variables:
```bash
trap 'for _pid in "${p1:-}" "${p2:-}" "${p3:-}" "${cp1:-}" "${cp2:-}" "${cp3:-}"; do [[ -n "$_pid" ]] && kill "$_pid" 2>/dev/null || true; done; cleanup_gpu_procs' INT TERM
```

---

### `print_batch_summary_vaapi` (utility, transform + batch)

**Analog:** `print_batch_summary()`, `scratch/repro/harness.sh:555-682` — same env-var-passed-CSV-into-python3-heredoc shape:
```bash
print_batch_summary() {
  local report="$1" n_requested="$2" n_actual="$3"
  REPORT_CSV="$report" N_REQUESTED="$n_requested" N_ACTUAL="$n_actual" \
    FINGERPRINT_FILE="$W/fingerprint.txt" python3 <<'PYEOF' | tee "$W/summary.txt"
...
PYEOF
}
```
**Extend, do not replace**, per RESEARCH.md's structure diagram: add to the same Python body (or a sibling function following the identical env-var-passthrough pattern) the D-02 triad-caveat line, the D-07/D-08 gated-escalation statement (0/20 + triad-confirmed → run N~60; 0/20 + partial-triad → do NOT escalate, report detection-grade only), and the D-09/D-10 content-cross-match result. Keep the `wilson_ci()` helper and `scene_stats()` shape verbatim — same 30 dB threshold, same Wilson-CI math, same excluded-from-denominator accounting.

---

### `cmd_run_batch_vaapi` (controller, batch)

**Analog:** `cmd_run_batch()`, `scratch/repro/harness.sh:689-769` — copy verbatim shape:
- N-validation guard (`WR-08`): `[[ ! "$n_requested" =~ ^[1-9][0-9]*$ ]]` (harness.sh:693) — RESEARCH.md's own Security Domain table calls this out explicitly as the pattern any new `run-batch-vaapi [N]` subcommand must follow.
- Disk preflight (harness.sh:701-707)
- Reference-artifact preflight (harness.sh:713-723) — extend to also check the vaapi self-reference PNGs exist before the batch starts (same "fail loud and early" rationale: WR-05).
- Inter-iteration GPU idle re-check with `cleanup_gpu_procs` retries (harness.sh:734-756)
- `cmd_run_iter_vaapi "$iter_label" || true` then conditionally append to report.csv (harness.sh:758-764) — never let one bad iteration abort the batch.

---

## Shared Patterns

### GPU exclusivity gate
**Source:** `require_gpu_exclusive()` + `gpu_clients()`, `scratch/repro/lib.sh:38-59`
**Apply to:** `cmd_probe_vaapi`, `ensure_vaapi_reference`, and any isolated (non-concurrent) av1_vaapi determinism encode — exactly as `cmd_reference`/`ensure_control_reference`/`ensure_scene_reference` already do. No new exclusivity mechanism needed.
```bash
require_gpu_exclusive() {
  local clients
  clients="$(gpu_clients)"
  if [[ -n "$clients" ]]; then
    echo "ABORT: GPU not exclusive, found: $clients" >&2
    return 1
  fi
  return 0
}
```

### Timeout-bounded execution (run_encode / ff_bounded)
**Source:** `scratch/repro/lib.sh:68-85`
**Apply to:** every new av1_vaapi encode invocation (`vaapi_encode()` must call `run_encode`, never call `ffmpeg`/`timeout` directly) and every new frame-extraction/PSNR/probe ffmpeg call (`ff_bounded`, not a bare `ffmpeg`).
```bash
run_encode() {
  local logfile="$1"; shift
  timeout -k 10 "${ENCODE_TIMEOUT}" "$@" > "$logfile" 2>&1
  return $?
}
ff_bounded() {
  timeout -k 10 "${ENCODE_TIMEOUT}" ffmpeg "$@"
}
```
This is also where exit-code 124 (timeout) vs other nonzero (EXEC_FAILURE) is distinguished — reuse that distinction verbatim for the vaapi path rather than inventing a third status.

### Worker-function-returns, never `die()` (carried from PROJECT.md, restated in RESEARCH.md "Project Constraints")
**Apply to:** every new helper function (`vaapi_encode`, `ensure_vaapi_reference`, the PTS/DTS probe helper, the content-cross-match search function). Only the top-level `cmd_*` entry points invoked directly from `main()` may `exit`; anything called from inside a loop or from another function must `echo "ABORT: ..." >&2; return 1` and let the caller decide whether to abort the batch or record a failure row. This is the same discipline `ensure_control_reference`/`ensure_scene_reference` already demonstrate.

### Fail-closed classification (CR-01 / WR-09 lineage)
**Source:** `classify_corrupt()`, `scratch/repro/harness.sh:344-357`; the `meas_fail[$scene]=1` guards in `cmd_run_iter`, `scratch/repro/harness.sh:452-468`
**Apply to:** the new content-origin cross-match (a failed/empty PSNR from any candidate-frame comparison must never be silently treated as "no match" without being logged distinctly from a genuine low-PSNR non-match) and the D-02 triad probe (an unreadable/failed probe leg must be reported as "UNKNOWN", never silently folded into "unsupported").
```bash
classify_corrupt() {
  local p="$1"
  if [[ "$p" == "inf" ]]; then
    echo 0
  elif [[ -z "$p" ]]; then
    echo NA   # measurement failure, never scored "clean"
  else
    awk -v p="$p" 'BEGIN { print (p+0 < 30) ? 1 : 0 }'
  fi
}
```

### `-ss` before `-i` (Pitfall 3)
**Source:** every existing encode call in the harness places `-ss` before `-i` (e.g. `ctrl_encode`, harness.sh:193-194: `-ss "$seek" -i "$SRC"`).
**Apply to:** `vaapi_encode()` and the PTS/DTS probe command — misplacement was directly reproduced this research session to blow the 120s timeout on deep-timeline scenes (e.g. scene 923 at 01:16:14).

### Scene table as the single source of truth
**Source:** `scratch/repro/lib.sh:29-31` (`SCENE_923_SEEK`/`_TRIM`/`_OFF` etc.) plus the `scene_seek`/`scene_trim`/`scene_offset` lookup functions (harness.sh:203-223).
**Apply to:** do not duplicate seek/trim/offset literals inside any new vaapi function — call the existing `scene_seek "$scene"` / `scene_offset "$scene"` lookups (the vaapi path uses the identical scenes 923/928/1129, identical seeks/trims/offsets — only the reference PNGs and encoder differ).

## No Analog Found

Files/logic with no close structural match in the existing harness (planner should build from RESEARCH.md's verified Code Examples, not invent from scratch, but should not expect to copy an existing function shape):

| Logic Block | Role | Data Flow | Reason | What to use instead |
|---|---|---|---|---|
| PTS/DTS reorder probe (D-02 leg-a B-frame test) | utility / measurement | transform | No existing harness function inspects `pts`/`dts` fields or does reorder detection — this is genuinely new diagnostic logic, not a variant of anything already present | RESEARCH.md "Pattern 1: Probe → Run → Caveat" — verified working `ffprobe -show_entries frame=pts,dts -of csv=p=0` + `awk` comparison, already tested live this session |
| Content-origin cross-match search loop (D-09/D-10) | utility / batch search | batch + transform | No existing function loops over an unbounded set of candidate frames from other sessions and tracks a running maximum — `psnr_of()` itself is reused verbatim, but the surrounding double-loop-and-track-max control flow is new | RESEARCH.md "Pattern 2: Content-Origin Cross-Match" — verified-runnable loop built entirely from `psnr_of()`; reuse the frame-extraction idiom (`ffmpeg ... -vf "select='eq(n\,$f)'" -vsync 0 -frames:v 1`) already used throughout `cmd_run_iter`/`ensure_*_reference` for single-frame PNG extraction |

## Conventions

Convention derivation could not run for this scope: the shared deterministic module (`gsd-tools verify conventions --derive`) inspects source files by extension-based heuristics tuned for JS/TS/Python-style codebases. Run both scoped (`--scope scratch/repro`) and repo-wide against this repo (QSVEnc — C++/bash/AviUtl-plugin codebase):

```
$ node gsd-tools.cjs verify conventions --derive --scope scratch/repro
{"mode":"derive","skipped":true,"reason":"no-readable-files","axes":[]}
$ node gsd-tools.cjs verify conventions --derive
{"mode":"derive","skipped":true,"reason":"no-readable-files","axes":[]}
```

**Convention derivation skipped (no-readable-files — the derivation module's file-extension heuristics do not recognize this repo's bash/C++ file set).** No 4-axis table is available from the tool. In its place, the conventions actually observed by direct reading of `harness.sh`/`lib.sh` (both files, in full) are:

| Axis | Observed Convention | Evidence |
|---|---|---|
| Function naming | `snake_case`, `cmd_` prefix for subcommand entry points, verb-first for helpers (`ensure_*`, `require_*`, `classify_*`) | `cmd_probe`, `cmd_reference`, `cmd_run_iter`, `ensure_scene_reference`, `require_gpu_exclusive`, `classify_corrupt` |
| Variable naming | `snake_case`, `local` declared at top of function, `UPPER_SNAKE` reserved for module-level config (`SRC`, `W`, `COMMON`, `ENCODE_TIMEOUT`, `SCENE_*`) | `lib.sh:11-31`; every function in `harness.sh` |
| Error/abort style | `echo "ABORT: <message>" >&2; return 1` inside helpers; `exit 1`/`exit 2` only at top-level `cmd_*`/dispatcher boundaries; never a bare `die()` | consistent across all functions in `harness.sh` (see Shared Patterns above) |
| File/output layout | All new artifacts hardcoded under `$W` (`scratch/repro/`), never under `/data`; per-scene subdirectory-and-suffix naming (`chunk923_ref.obu`, `frame299_ref.png`) | `lib.sh:14-16` (`W` derivation), `harness.sh` throughout |

**Contested hotspots (author's choice):** None applicable to this scope — this is a single-author bash harness with one consistent style throughout, not a repo with a dual-resolver split. (For general orientation: elsewhere in the GSD tooling itself, the CJS↔SDK dual resolver — `bin/lib/**` as CJS `module.exports`/`require` vs `sdk/src/**` as ESM `export`/`import` — is the canonical example of an intentional, contested-but-locally-consistent split; no equivalent split exists in this harness, so new av1_vaapi code should simply match the single existing style shown above.)

## Metadata

**Analog search scope:** `scratch/repro/harness.sh` (full file, 799 lines), `scratch/repro/lib.sh` (full file, 113 lines) — both read in full, no other files searched (per phase note: this is a two-file extension, not a new-module addition; RESEARCH.md's own "Don't Hand-Roll" and "Sources" sections already confirm no other repo location is relevant).
**Files scanned:** 2 (both fully read)
**Pattern extraction date:** 2026-07-23
