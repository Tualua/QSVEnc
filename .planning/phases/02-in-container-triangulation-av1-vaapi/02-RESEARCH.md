# Phase 2: In-Container Triangulation — av1_vaapi - Research

**Researched:** 2026-07-23
**Domain:** ffmpeg VA-API (`av1_vaapi`) AV1 hardware encode on Intel Arc A380 (Alchemist/DG2), low-power-only entrypoint behavior, and OpenCL-free content-origin cross-matching for a concurrency-triggered frame-corruption harness
**Confidence:** HIGH for the central B-frame-reproducibility hazard and the harness-breaking exit-code gotcha (both directly reproduced live in this environment during this research pass, not inferred from documentation); MEDIUM for exact flag-level recommendations (rate-control mapping, tiling); LOW/ASSUMED only where explicitly marked in the Assumptions Log.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Build the `av1_vaapi` device-under-test as a full-HW ffmpeg VAAPI pipeline: HW VAAPI decode (`-hwaccel vaapi -hwaccel_output_format vaapi`) → VA video-memory surfaces → `-c:v av1_vaapi`, keeping frames on VA surfaces end-to-end (no download to system RAM) so the shared-VA-pool condition that the whole bug hinges on is preserved.
- **D-02:** **Probe → run → caveat.** Before the concurrency test, empirically probe which trigger-triad legs `av1_vaapi` can actually reproduce on this Arc A380 — specifically (a) B-frame reorder (`-bf N` / hierarchical-B, the highest-risk leg), (b) P010 10-bit surfaces, (c) HW-VA video-memory decode. Reproduce **every supported leg at maximum fidelity**, run the 3-way concurrency test regardless, and **record exactly which legs were active**.
- **D-03:** **Never claim immunity off a run that could not reproduce the trigger.** If a leg (especially B-frames) is unsupported, report the result as a **PARTIAL-TRIAD data point** with an explicit "immunity NOT proven" caveat. A "cannot exercise the trigger triad via av1_vaapi LP encode" outcome is itself a valid, reportable finding.
  - *Known constraint (grounding, verified at discussion time):* on this Arc A380, AV1 encode exposes **only `VAEntrypointEncSliceLP`** (low-power) — there is no full-power AV1 entrypoint. Low-power AV1 VAAPI encode on Alchemist commonly does **not** support B-frames, so the B-reorder leg is at real risk of being non-reproducible. This is the central interpretive hazard of the phase and mirrors the Xe-gating logic already planned for Phase 3.
- **D-04:** Classify corruption via a **new bit-clean single-session `av1_vaapi` self-reference** (scene 923, offset 299), mirroring the Phase-1 self-consistency method. The Phase-1 *qsvencc* reference frame is invalid here (different encoder → different clean pixels) and must not be reused.
- **D-05:** Before trusting the self-reference, **re-confirm its determinism** the way Phase 1 D-05 did: encode the isolated single session twice and verify the extracted frame is bit-identical / very-high PSNR. Only a determinism-confirmed self-reference is trusted.
- **D-06:** Keep the **same `<30 dB` = corrupt PSNR threshold** and OpenCL-free external-ffmpeg metric from Phase 1 (D-04/D-06 there). A clean concurrent frame should score ~bit-identical to the self-reference; a corrupt one drops well below 30 dB.
- **D-07:** Run **detection-N=20 first** (mirrors Phase 1). If **≥1 corrupt** → av1_vaapi reproduces corruption; report frequency + PSNR signature at detection-N and **stop** (no 60-run once positive).
- **D-08:** **Gated escalation on a clean result.** If **0/20 AND the D-02 triad gate confirmed all legs active** → escalate to **validation-N ~60 zero-failure** (rule-of-three) *within this phase* to earn a "clean/immune" claim. If **0/20 but the triad was only partial** → do **NOT** escalate (60 runs on a broken triad prove nothing); report detection-grade partial-triad only.
- **D-09:** Add a **lightweight content-origin cross-match** as an *add-on* to the PSNR classifier (not a replacement): when any frame scores `<30 dB`, cross-match its content against the OTHER concurrently-running scenes' frames (928 / 1129) to confirm it is a genuine **cross-session content swap**, not generic garbage.
- **D-10:** Apply the content-origin cross-match to **both** the existing **qsvencc baseline** (closing the loose thread that Phase 1's `summary.txt` explicitly deferred "to Phase 2") **and** any **av1_vaapi** corrupt frame. This upgrades the whole triangulation from "PSNR-drop symptom" to "confirmed cross-session content swap."
- **D-11:** Every av1_vaapi measurement batch keeps its **own paired ffmpeg `av1_qsv` immune control in the same run** (roadmap SC#1). A non-zero control invalidates that batch as a finding (Phase 1 D-06 semantics, unchanged).

### Claude's Discretion

- Exact `av1_vaapi` rate-control mapping (icq/qp target vs qsvencc's `--icq 24`), tile/gop flag translation, and how the capability probe is scripted.
- The concrete content-origin cross-match implementation (e.g. per-frame PSNR of the corrupt frame against each concurrent scene's decoded frames, pick best match) and its reporting format.
- How the new av1_vaapi measurement path is wired into `harness.sh` (new subcommand/flag vs parameterized encoder selector).

### Deferred Ideas (OUT OF SCOPE)

- Host-side levers — GuC/HuC firmware update, i915→Xe migration (Phase 3; the av1_vaapi result here informs their interpretation).
- Workaround throughput measurement (`--avsw`, `--jobs 1`, ffmpeg-migration) + defense-in-depth content-verification gate design (Phase 4).
- Definition-of-Done synthesis report (Phase 5).
- Corrupted Cold Eyes re-encode (DEBT-01) — deferred v2, user decision after a fix is chosen.

None of the above were pulled into scope; this research stayed within the DIAG-02 boundary, with the one deliberate, user-approved add-on: reusing the harness's existing Phase-1 frames to close the deferred content-origin note (D-09/D-10).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DIAG-02 | Test the pure VA-API `av1_vaapi` encode path (bypassing oneVPL) as an in-container triangulation data point under the same 3-way concurrency, with the paired immune control. | Verified working full-HW `av1_vaapi` command shape (Code Examples); empirically confirmed which trigger-triad legs are actually reproducible on this hardware (Summary/Pitfalls); verified content-origin cross-match technique reusing Phase-1 on-disk artifacts (Don't Hand-Roll); verified harness-integration gotcha that would otherwise silently misclassify every measurement (Pitfall 2). |
</phase_requirements>

## Summary

This research directly executed the phase's central open question on the live Arc A380 in this environment, rather than relying on documentation or training-data assumptions. Three findings dominate planning:

**1. The B-frame-reorder leg of the trigger triad is empirically NOT reproducible via `av1_vaapi` on this hardware — confirmed, not just suspected.** `vainfo` confirms `VAProfileAV1Profile0` exposes only `VAEntrypointEncSliceLP` (no full-power entrypoint). Running `av1_vaapi -low_power 1 -bf 5 -b_depth 3` and remuxing the output to get real PTS/DTS timestamps shows **`pts == dts` for every one of 100 test frames** — i.e., decode order equals display order, meaning **no actual frame reordering (no hidden/bidirectional B-pictures) occurs**, despite ffmpeg's own capability log claiming "Using intra, P- and B-frames (supported references: 3 / 1)" and despite `-bf`/`-b_depth` being silently accepted without error. **This means D-03's PARTIAL-TRIAD-with-explicit-caveat outcome should be treated as the expected result, not a low-probability edge case**, when the phase's own D-02 probe step runs. P010 10-bit surfaces (leg b) and full-HW VA-decode-to-video-memory (leg c) both ARE reproducible and were directly confirmed.

**2. A harness-breaking gotcha was found and fixed: a hard `-frames:v`/`-t` cutoff on a `scale_vaapi`-filtered VAAPI pipeline throws a nonzero ffmpeg exit code (244) with a trailing "Cannot allocate memory" filter-teardown message — even though the output file is complete and correct.** Reproduced deterministically across multiple frame counts (20/21/22/24/25/28/30/40). The existing harness's `run_encode()` (`lib.sh`) treats any nonzero exit as `EXEC_FAILURE` and excludes the iteration from the corruption-fraction denominator — left unaddressed, this would silently discard **every** av1_vaapi measurement iteration as a harness failure rather than a real result. The fix, verified 3/3 clean runs: add `extra_hw_frames=64` to the `scale_vaapi` filter string (`scale_vaapi=format=p010:extra_hw_frames=64`).

**3. `av1_vaapi` requires `scale_vaapi`, not `hwupload`, to reach P010 from an already-hardware-decoded VAAPI frame.** The example command in `.planning/research/STACK.md` (`format=p010,hwupload=...`) errors immediately ("Impossible to convert between the formats... Function not implemented") because `hwupload` expects a **software** input frame, but `-hwaccel_output_format vaapi` already produces a **hardware** frame. `scale_vaapi=format=p010` is the correct filter for a hardware-frame-to-hardware-frame P010 conversion, keeping the pipeline entirely on VA surfaces per D-01.

**Primary recommendation:** implement the phase's D-02 probe step using **PTS/DTS-equality** (not `pict_type`, which is provably unreliable for AV1 — see Pitfall 1) as the empirical B-frame-reorder detection test; use the corrected `scale_vaapi=format=p010:extra_hw_frames=64` filter and correct `-ss`-before`-i` placement in every av1_vaapi command; and plan the phase's own probe step to almost certainly conclude "B-frame leg unsupported → PARTIAL-TRIAD," which per D-03 is still a fully valid, reportable, plannable outcome — it does not block DIAG-02's success criteria.

## Project Constraints (from CLAUDE.md)

`./CLAUDE.md` documents QSVEnc's own source-tree conventions (directory layout, shared-vs-encoder-specific parameter files, documentation update rules for `QSVEncC_Options.md`). **None of these apply to this phase**: Phase 2 makes no changes to QSVEnc source code — it only extends the standalone bash measurement harness (`scratch/repro/`), which lives outside `QSVPipeline`/`QSVEncC` entirely. The one directive that DOES carry forward (from the repo-root `PROJECT.md` handoff, referenced in the phase brief and already the pattern used throughout `lib.sh`): **worker functions return `(success, error)`; they must never call `die()`**. The existing harness already follows this (every helper function `echo`s an `ABORT:` message to stderr and `return 1`/`exit 1` only at the top-level subcommand boundary, never a bare `die()`); any new av1_vaapi functions added in this phase must follow the identical pattern.

## Architectural Responsibility Map

This is a standalone diagnostic bash harness, not a multi-tier application — the "tiers" below are the harness's own internal layers plus the hardware/driver boundary it measures.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| av1_vaapi encode command construction & invocation | Harness orchestration (`harness.sh`/`lib.sh`, bash) | — | Mirrors existing `ctrl_encode()` helper pattern exactly; no new tier |
| HW VAAPI decode → P010 surface conversion → AV1 LP encode | Hardware/Driver (VA-API, `iHD`, kernel `i915`) | — | Out of the harness's control — this is the device under test, only measured |
| Capability probe (D-02: which triad legs are active) | Harness orchestration (new bash/ffmpeg probe step) | Hardware/Driver (what it reports back) | Probe queries the driver/encoder but the pass/fail *interpretation* is harness-side logic |
| Corruption classification (PSNR vs self-reference) | Harness orchestration (reused `psnr_of`/`classify_corrupt` from `lib.sh`) | External tool (ffmpeg `-lavfi psnr`) | Identical to Phase 1 — no new tier introduced |
| Content-origin cross-match (D-09/D-10) | Harness orchestration (new bash/python glue) | External tool (ffmpeg `-lavfi psnr`, looped) | New logic this phase, but built entirely from Phase-1-proven primitives |
| Result reporting / summary | Harness orchestration (extends `print_batch_summary`, Python) | — | Same tier as Phase 1, extended not replaced |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `ffmpeg` (system) | `6.1.1-3ubuntu5` `[VERIFIED: ffmpeg -version, this environment, 2026-07-23]` | `av1_vaapi` encode, `av1_qsv` control (unchanged from Phase 1), PSNR extraction, content cross-match | Already the harness's only external tool dependency (Phase 1 D-01); built with `--enable-vaapi --enable-libdrm --enable-libvpl`, confirmed both `av1_vaapi` and `av1_qsv` present in `-encoders` output |
| `ffmpeg-8.1` (alternate build) | 8.1.x line `[CITED: .planning/research/STACK.md]` | Fallback/cross-check ffmpeg build | Already installed at `/usr/local/bin/ffmpeg-8.1` per Phase 1 findings; not needed unless the system ffmpeg 6.1.1 shows unexpected behavior — not used in this research pass since system ffmpeg already reproduced every finding cleanly |
| `iHD` VA-API driver | 26.2.2 `[VERIFIED: vainfo, this environment, 2026-07-23]` | VA-API driver backing both `av1_vaapi` and `av1_qsv` | Unchanged from Phase 1 (already exhausted as a lever per handoff §5) — this phase only measures against it, does not change it |
| Python 3 (stdlib only) | already present | Extends `print_batch_summary`'s existing CSV/Wilson-CI reporting; drives the content cross-match best-match search | Zero new dependency — `harness.sh` already shells out to `python3` inline for reporting (Phase 1 pattern) |

### Supporting

No new supporting libraries. This phase is a pure extension of the Phase-1 harness's existing tool surface — no new packages, no new language runtimes.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `ffmpeg av1_vaapi` (system 6.1.1) | `gstreamer` + `vaapiav1enc` | A genuinely different implementation (higher triangulation value in theory) but much higher setup cost for one data point; `.planning/research/STACK.md` already flagged this as lower-payoff than the ffmpeg path already validated for `av1_qsv`. Not pursued. |
| `scale_vaapi=format=p010` for the HW P010 conversion | `vpp_qsv=format=p010le` (the `av1_qsv` control's filter) | Not usable here — `vpp_qsv` is oneVPL/QSV-specific and would reintroduce the oneVPL runtime layer that `av1_vaapi` is specifically meant to bypass (D-01's whole point). |
| PTS/DTS-equality B-frame check | Raw AV1 OBU bitstream parsing (`show_existing_frame` OBU counting) | Bitstream-level parsing would give a more granular "how many hidden frames" answer, but requires either a raw OBU parser (no readily-available tool found: `dav1d`/`aomdec` not installed in this environment) or `-v trace` decode logging (verified to work but extremely slow/verbose, impractical for a routine probe step). PTS/DTS equality is a coarser but sufficient binary signal ("did any reordering happen at all") and was directly verified to work with tools already in the standard stack. |

**Installation:** None required — every tool used in this phase is already installed and was directly exercised in this research session.

**Version verification:**
```bash
ffmpeg -version | head -1        # 6.1.1-3ubuntu5, confirmed 2026-07-23
ffmpeg -hide_banner -encoders | grep -E 'av1_(qsv|vaapi)'   # both present
LIBVA_DRIVER_NAME=iHD vainfo 2>&1 | grep -A2 'VAProfileAV1Profile0'
```

## Package Legitimacy Audit

**Not applicable to this phase.** No new external packages are installed — the phase exclusively reuses already-installed system binaries (`ffmpeg`, `python3`) that were also the Phase-1 dependency set. The Package Legitimacy Gate protocol (slopcheck, registry verification) applies to package *installs*, and none occur here.

## Architecture Patterns

### System Architecture Diagram

```
                     ┌─────────────────────────────────────────┐
                     │  cmd_probe_vaapi (NEW, D-02)             │
                     │  1. vainfo: confirm AV1 EncSliceLP-only  │
                     │  2. short av1_vaapi encode w/ -bf N      │
                     │  3. remux -> check pts==dts (reorder?)   │
                     │  4. confirm pix_fmt=yuv420p10le (P010)   │
                     │  5. confirm no hwdownload in filtergraph │
                     │  -> writes vaapi_triad_caveat.txt        │
                     └───────────────┬───────────────────────────┘
                                     │ (which legs active)
                                     ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │  cmd_run_iter_vaapi <N> (NEW, extends run-iter pattern)          │
   │                                                                   │
   │  Step 1: 3-way concurrent av1_vaapi measurement (923/928/1129)  │
   │    -hwaccel vaapi -hwaccel_output_format vaapi -ss <seek> -i SRC│
   │    -vf scale_vaapi=format=p010:extra_hw_frames=64               │
   │    -c:v av1_vaapi -low_power 1 -bf N -b_depth N -rc_mode ICQ    │
   │           │                                                      │
   │           ▼                                                      │
   │  Step 2: PSNR vs av1_vaapi self-reference (NEW, D-04/D-05)      │
   │    reuses psnr_of()/classify_corrupt() from lib.sh unchanged    │
   │           │                                                      │
   │           ▼                                                      │
   │  Step 3: paired av1_qsv immune control (UNCHANGED, D-11/D-06)   │
   │    reuses ctrl_encode() from lib.sh verbatim                    │
   │           │                                                      │
   │           ▼ (only if corrupt <30dB found)                       │
   │  Step 4: content-origin cross-match (NEW, D-09/D-10)            │
   │    for each frame of scene 928's & 1129's SAME-iteration output:│
   │      psnr_of(corrupt_frame, candidate_frame) -> track max       │
   │    high-PSNR match against a DIFFERENT concurrent scene         │
   │    = confirmed cross-session content swap (not generic garbage) │
   └─────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
                     ┌─────────────────────────────────────────┐
                     │  print_batch_summary_vaapi (extends      │
                     │  existing print_batch_summary)           │
                     │  - detection-N=20 result + triad caveat  │
                     │  - gated escalation to N=60 (D-08)       │
                     │  - explicit clean-vs-corrupt interpretation│
                     │    contract (roadmap SC#2)                │
                     └─────────────────────────────────────────┘
```

### Recommended Project Structure

```
scratch/repro/
├── harness.sh          # extend: add vaapi_probe/run-iter-vaapi/run-batch-vaapi
│                        #        dispatcher cases, mirroring existing ones
├── lib.sh               # extend: add vaapi_encode() helper (mirrors ctrl_encode()),
│                        #        SCENE_*_OFF table reused unchanged, add
│                        #        vaapi-scene reference/self-ref path lookups
├── reference/            # extend: add av1_vaapi self-reference OBUs/PNGs
│                        #   (chunk923_vaapi_ref.obu, frame299_vaapi_ref.png, etc.)
│                        #   -- separate from qsvencc's existing reference/ (D-04)
├── vaapi_reference/      # NEW (or subfolder of reference/, discretion) --
│                        #   av1_vaapi-specific self-reference + determinism check
├── runs/itNN/            # unchanged Phase-1 qsvencc concurrent outputs --
│                        #   REUSED READ-ONLY for D-10's qsvencc cross-match
├── vaapi_runs/itNN/       # NEW -- av1_vaapi concurrent measurement outputs
└── vaapi_probe.txt        # NEW -- D-02 triad-caveat capability probe result
```

### Pattern 1: Probe → Run → Caveat (D-02)

**What:** Before any concurrency measurement, empirically determine which of the three trigger-triad legs are actually active for `av1_vaapi` on this specific hardware, using direct, reproducible tests — never assume from documentation or a capability log line.
**When to use:** Once, before `run-batch-vaapi`, mirroring how `cmd_reference` gates `cmd_run_batch` in the existing harness.
**Example (verified working in this session):**
```bash
# Source: direct testing, this environment, 2026-07-23 [VERIFIED]

# Leg (a) B-frame reorder probe: does decode order == display order?
ffmpeg -y -nostdin -hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128 \
  -ss "$SCENE_923_SEEK" -i "$SRC" -frames:v 100 \
  -vf 'scale_vaapi=format=p010:extra_hw_frames=64' \
  -c:v av1_vaapi -profile:v main -low_power 1 \
  -g 300 -bf 5 -b_depth 3 -refs 4 -rc_mode ICQ -global_quality 24 -r 24 \
  "$W/probe_reorder.mkv" -hide_banner -loglevel error

# Compare pts vs dts for every frame -- ANY mismatch = real reordering (leg a ACTIVE).
# All-equal (observed result on this hardware) = leg a NOT reproducible.
ffprobe -v error -select_streams v:0 -show_entries frame=pts,dts -of csv=p=0 "$W/probe_reorder.mkv" \
  | awk -F, '{if ($1 != $2) print "REORDER DETECTED: pts="$1" dts="$2; else ok++} END{print ok" frames pts==dts (no reorder)"}'

# Leg (b) P010 confirmation
ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt,profile -of default=nw=1 "$W/probe_reorder.mkv"
# expect: pix_fmt=yuv420p10le, profile=Main
```

### Pattern 2: Content-Origin Cross-Match (D-09/D-10)

**What:** For any frame classified corrupt (`<30 dB` vs self-reference), confirm the pixel content actually originates from one of the OTHER concurrently-running scenes in the SAME iteration — not generic garbage — using only external ffmpeg PSNR, reusing Phase-1's already-proven `psnr_of()` primitive.
**When to use:** As an add-on step, triggered only when `classify_corrupt()` returns `1`, for both the historical qsvencc batch (D-10, using Phase-1's still-present `scratch/repro/runs/itNN/` artifacts) and any new av1_vaapi corrupt frame.
**Example:**
```bash
# Source: this research session, built entirely from lib.sh's existing psnr_of() [VERIFIED via direct testing of the underlying primitive]

# Given: a corrupt frame PNG (e.g. scratch/repro/runs/it04/frame299.png, scene 923,
# already known corrupt at 12.82 dB per 01-EVIDENCE.md), and the OTHER TWO scenes'
# raw .obu outputs from the SAME iteration (it04/c928.obu, it04/c1129.obu -- confirmed
# still present on disk from Phase 1).

corrupt_png="scratch/repro/runs/it04/frame299.png"
best_psnr=-1; best_desc=""
for other_obu in scratch/repro/runs/it04/c928.obu scratch/repro/runs/it04/c1129.obu; do
  nframes=$(ffprobe -v error -count_frames -select_streams v:0 \
    -show_entries stream=nb_read_frames -of csv=p=0 "$other_obu")
  for ((f=0; f<nframes; f++)); do
    cand_png="/tmp/cand_${f}.png"
    ffmpeg -y -nostdin -i "$other_obu" -vf "select='eq(n\,$f)'" -vsync 0 -frames:v 1 \
      "$cand_png" -hide_banner -loglevel error
    p=$(psnr_of "$corrupt_png" "$cand_png" "/tmp/cand_${f}.psnrlog")   # reused verbatim from lib.sh
    # track max (best match) across all candidates from both other scenes
    if [[ "$p" != "NA" ]] && awk -v a="$p" -v b="$best_psnr" 'BEGIN{exit !(a+0>b+0)}'; then
      best_psnr="$p"; best_desc="$other_obu frame $f"
    fi
  done
done
echo "best cross-scene match: $best_desc at $best_psnr dB"
# A high best_psnr (near-identical, e.g. >30dB / near-inf) against a DIFFERENT
# concurrent scene's frame = confirmed content SWAP, not generic garbage.
```

### Anti-Patterns to Avoid

- **Trusting `pict_type` (I/P/B) from `ffprobe` as a B-frame verification signal for AV1:** AV1's bitstream has no native "B slice" concept the way H.264/HEVC do — ffmpeg's AV1 parser maps `KEY_FRAME`→I and `INTER_FRAME`→P regardless of whether that inter frame uses forward-only or bidirectional/hidden-reference prediction. Every frame in this research's tests showed `pict_type=P` for ALL non-keyframes even where the encoder's own log claimed B-frame support — this field cannot distinguish "true B/reordered" from "ordinary P." Use PTS/DTS equality instead (Pattern 1).
- **Using `format=p010,hwupload` after `-hwaccel_output_format vaapi`:** errors immediately (`Impossible to convert between the formats...`) because `hwupload` expects software input frames, but the hwaccel decode path already produces hardware (VAAPI) frames. Use `scale_vaapi=format=p010` instead.
- **Placing `-ss` after `-i`:** on this ~2-hour, very-frequent-keyframe source, this triggers ffmpeg's accurate (full sequential decode-from-start) seek mode rather than fast input-level seeking, and can exceed the harness's `ENCODE_TIMEOUT=120` for any scene deep into the file (e.g. scene 923 at 01:16:14). Always place `-ss` before `-i`, exactly as the existing `ctrl_encode()` already does.
- **Trusting a nonzero ffmpeg exit code alone as proof of a failed encode for this specific pipeline shape:** see Pitfall 2 — verify the output file's frame count/PSNR before excluding an iteration as `EXEC_FAILURE`, or (preferred) apply the `extra_hw_frames` fix so the spurious nonzero exit never occurs in the first place.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|--------------|-----|
| B-frame/reorder detection for AV1 | A custom AV1 OBU parser to count `show_existing_frame` headers | PTS/DTS-equality check via `ffprobe -show_entries frame=pts,dts` on a container-remuxed copy (`-r 24` remux to `.mkv`) | Directly verified to work in this research session with tools already in the standard stack; a raw OBU parser (`dav1d`/`aomdec`) is not installed in this environment and would be new tooling for a one-shot diagnostic |
| Content cross-match best-frame search | A custom pixel-diff/perceptual-hash matcher | Loop `psnr_of()` (already in `lib.sh`, OpenCL-free, Phase-1-proven) across every candidate frame of the other two concurrent scenes' same-iteration `.obu` outputs, keep the max | Reuses the exact metric and threshold semantics already established and trusted from Phase 1 — introduces zero new measurement methodology, only a search loop around it |
| VA-surface-pool-exhaustion workaround for the trailing "Cannot allocate memory" exit-244 gotcha | A custom retry/backoff wrapper around `ffmpeg`, or loosening `run_encode()`'s exit-code check | `scale_vaapi`'s `extra_hw_frames=64` filter option | Fixes the actual root cause (an undersized internal hardware-frame pool relative to the encoder's held references) at the source; verified 3/3 clean vs. 1/1+ failure without it; loosening the exit-code check instead would violate the harness's existing fail-closed philosophy (CR-01/WR-09) |
| av1_vaapi self-reference determinism check | New bespoke logic | Reuse the exact `cmd_reference` md5-comparison pattern (D-05) already implemented for the qsvencc reference: two isolated (non-concurrent) `av1_vaapi` encodes of the same scene, compare `md5sum` | Same mechanism, same fail-loud philosophy, zero new code shape needed — only the encoder invocation inside the loop changes |

**Key insight:** every non-trivial primitive this phase needs (PSNR measurement, determinism verification, GPU-exclusivity gating, timeout-bounded encode invocation, corruption classification) already exists, proven, in `lib.sh` from Phase 1. The only genuinely new logic is (1) the av1_vaapi command construction itself, (2) the PTS/DTS reorder probe, and (3) the cross-scene best-match search loop — everything else should be reused verbatim, not reimplemented.

## Common Pitfalls

### Pitfall 1: `pict_type` is not a valid B-frame/reorder verification signal for AV1

**What goes wrong:** A probe step checks `ffprobe -show_entries frame=pict_type` and sees only `I`/`P`, concludes "no B-frames," which is directionally correct here but for the wrong reason — and could equally give a **false negative** in a future environment/driver where reordering genuinely IS happening, since AV1's `INTER_FRAME` type covers both ordinary forward-prediction and bidirectional/hidden-reference prediction indistinguishably at the parser level.
**Why it happens:** AV1 has no bitstream-level "B slice" flag the way H.264/HEVC do; `pict_type` for AV1 is derived from the coarser `frame_type` field (`KEY_FRAME`/`INTER_FRAME`/`INTRA_ONLY_FRAME`/`SWITCH_FRAME`), which says nothing about reference-direction or reordering.
**How to avoid:** Use the PTS/DTS-equality test (Pattern 1) — remux the raw `.obu` output into a container with real timestamps (`-r <fps>` at remux time) and check `pts == dts` per frame. Any mismatch is proof of real reordering; all-equal is proof none occurred. Verified working in this session.
**Warning signs:** A probe or plan step that references `pict_type`/`key_frame` fields from `ffprobe` as the B-frame verification method for an AV1 stream.

### Pitfall 2: hard frame/time cutoff on a `scale_vaapi`-filtered pipeline throws a nonzero exit despite valid output

**What goes wrong:** Any `av1_vaapi` command using `-frames:v N` or `-t N` to bound a measurement (exactly what every harness scene/trim needs) reliably produces `ffmpeg` exit code 244 with a trailing `[vf#0:0] Error while filtering: Cannot allocate memory` / `Failed to inject frame into filter network` message — even though `ffprobe` confirms the output file has the full, correct frame count and valid PSNR-comparable content. Reproduced deterministically at frame counts 20/21/22/24/25/28/30/40 without the fix, and reproduced as fixed (exit 0, 3/3) with the fix applied.
**Why it happens:** `scale_vaapi`'s default internal hardware-frame pool size is undersized relative to what the encoder+filter pipeline needs when the pipeline is torn down mid-flight by a hard frame-count/duration limit (a benign shutdown race in the VA surface pool, not a real encode failure).
**How to avoid:** Add `extra_hw_frames=64` to the `scale_vaapi` filter string: `-vf 'scale_vaapi=format=p010:extra_hw_frames=64'`. This option was empirically confirmed to be a real, accepted `scale_vaapi` filter option on this ffmpeg build (a deliberately-invalid filter option name was tested for contrast and correctly produced a hard "Option not found" parse error — `extra_hw_frames` does not).
**Warning signs:** Any av1_vaapi harness iteration reporting `EXEC_FAILURE` from a nonzero `run_encode()` exit code while its output `.obu` file is nonzero-sized and has the expected frame count via `ffprobe -count_frames` — this is the signature of the unfixed gotcha, not a genuine encode failure. **If this fix is not applied, the harness's existing strict exit-code gate (`lib.sh` `run_encode()`) will misclassify every av1_vaapi measurement iteration as `EXEC_FAILURE`, silently producing zero usable data for the whole phase** — this is the single highest-priority implementation risk found in this research.

### Pitfall 3: `-ss` placement before vs. after `-i` matters critically on this source file

**What goes wrong:** Placing `-ss <timestamp>` AFTER `-i <source>` (as opposed to before) forces ffmpeg's "accurate seek" mode, which sequentially decodes from the start of the file up to the target timestamp. On this ~2-hour, very-frequent-keyframe 21GB source, this can take many minutes for a deep-timeline scene (e.g. 923 at `01:16:14.167`), trivially exceeding the harness's `ENCODE_TIMEOUT=120` and causing every iteration to `TIMEOUT`.
**Why it happens:** ffmpeg's `-ss` semantics change based on position relative to `-i` — before `-i` it is a fast input-level (keyframe-seek) operation; after `-i` it is an accurate-but-slow output-level operation. It is easy to misplace when copy-adapting a command.
**How to avoid:** Always place `-ss` before `-i`, exactly as the existing `ctrl_encode()` in `lib.sh` already does for the `av1_qsv` control. Verified in this session: `-ss` before `-i` completed a 30-frame encode near-instantly; `-ss` after `-i` for the same target did not complete within 20 seconds (was still decoding from the start).
**Warning signs:** An av1_vaapi iteration that times out (`TIMEOUT` status) at a much higher rate than the paired `av1_qsv` control in the same run — the control already uses the correct `-ss`-before`-i` placement, so a lopsided timeout rate specifically on the new av1_vaapi path is a strong signal of this exact mistake.

### Pitfall 4: the encoder's own capability log line is not proof of functional behavior

**What goes wrong:** `av1_vaapi`'s own verbose log prints `Using intra, P- and B-frames (supported references: 3 / 1)` regardless of whether real reordering subsequently occurs in the output bitstream — this line reflects the *driver's reported capability query*, not what the encoder actually produced for a given run. Trusting this line as confirmation that the D-02 B-frame leg is "active" would be incorrect; the PTS/DTS test in this same session showed zero reordering across 100 frames despite this exact log line being present.
**Why it happens:** The capability string is generated once at encoder init from a VA-API capability query (`vaQueryConfigAttributes` or similar), independent of whether the specific GOP/RC configuration passed actually triggers use of that capability.
**How to avoid:** Never gate the D-02 triad-caveat decision on this log line alone; always confirm with the PTS/DTS-equality output-level test (Pattern 1).
**Warning signs:** A probe report or plan that cites "ffmpeg's own log confirms B-frame support" as evidence for the B-frame leg being reproducible, without an accompanying output-bitstream-level (PTS/DTS or equivalent) check.

### Pitfall 5: don't over-interpret the `-bf`/`-b_depth` bitstream-size delta as proof of the reference-surface-reuse mechanism

**What goes wrong:** `-bf 5 -b_depth 3` vs. `-bf 0` produced measurably different output file sizes (1,031,603 vs. 862,759 bytes for the same 100 frames), which could be misread as evidence that "B-frames are partially working" or that the long-lived-reference-surface condition (the actual mechanism the trigger triad's leg (c) depends on) is present. It is not conclusive either way — the size delta could equally be explained by additional forward-only reference slots, different rate-control lookahead behavior, or other RC-side effects unrelated to hidden/reordered frames.
**Why it happens:** File-size deltas are a weak, indirect signal; only PTS/DTS reordering is a direct, unambiguous signal of the specific mechanism (long-lived reference surfaces held across a reorder window) the bug's trigger triad requires.
**How to avoid:** Report the PTS/DTS finding (no reordering observed) as the D-02 conclusion for the B-frame leg; treat the file-size delta as a noted-but-inconclusive observation, not evidence toward or against triad reproduction. See Open Questions for a recommended follow-up probe variant.
**Warning signs:** A finding write-up that cites file-size differences as primary evidence for or against B-frame-leg reproducibility.

### Pitfall 6: don't reuse the qsvencc self-reference for av1_vaapi classification

**What goes wrong:** Already locked as D-04, but worth restating as an implementation trap: the qsvencc reference frame (`scratch/repro/reference/frame299_ref.png`) encodes scene 923 with a completely different encoder/codepath than `av1_vaapi` — even a perfectly clean av1_vaapi frame will NOT match it (different quantization, different rate-control, different bitstream). Comparing av1_vaapi test frames against the qsvencc reference would make every single av1_vaapi frame look "corrupt" regardless of the real concurrency bug.
**How to avoid:** Build a dedicated av1_vaapi self-reference (isolated single-session encode + determinism check, D-04/D-05) before any av1_vaapi concurrency measurement, stored separately from the qsvencc reference (e.g. `reference/frame299_vaapi_ref.png`, distinct filename).
**Warning signs:** Any av1_vaapi PSNR classification reading suspiciously low (near the ~13 dB qsvencc corrupt-frame signature) on effectively every iteration, including iterations expected to be clean — the canary for "wrong reference used."

## Code Examples

Verified patterns from direct testing in this environment (2026-07-23):

### Working full-HW av1_vaapi encode command (verified, corrects STACK.md's untested example)

```bash
# Source: direct testing, this session [VERIFIED via ffprobe: pix_fmt=yuv420p10le,
# profile=Main, exit=0, correct frame count]
ffmpeg -y -nostdin -hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128 \
  -ss "$SEEK" -i "$SRC" -frames:v "$FRAMES" \
  -vf 'scale_vaapi=format=p010:extra_hw_frames=64' \
  -c:v av1_vaapi -profile:v main -low_power 1 \
  -g 300 -bf 5 -b_depth 3 -refs 4 -rc_mode ICQ -global_quality 24 \
  -tiles 1x1 \
  "$OUT.obu" -hide_banner -loglevel error
```

Key differences from the STACK.md draft command that this research corrects:
- `-vf 'scale_vaapi=format=p010:extra_hw_frames=64'` replaces `-vf 'format=p010,hwupload=extra_hw_frames=32'` — the latter errors immediately on hardware-decoded input.
- `-low_power 1` explicit (STACK.md's draft omitted it) — although ffmpeg silently falls back to the LP entrypoint anyway (confirmed via log: `Using VAAPI entrypoint VAEntrypointEncSliceLP (8)` even when `-low_power 0` was explicitly requested, since no full-power AV1 entrypoint exists on this hardware), setting it explicitly documents intent and avoids relying on an undocumented fallback.
- `extra_hw_frames=64` addition is the Pitfall 2 fix, mandatory for any command using `-frames:v`/`-t`.

### B-frame/reorder verification (D-02 probe)

```bash
# Source: this session [VERIFIED: 100/100 frames showed pts==dts on this hardware]
ffmpeg -y -nostdin -hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128 \
  -ss "$SEEK" -i "$SRC" -frames:v 100 \
  -vf 'scale_vaapi=format=p010:extra_hw_frames=64' \
  -c:v av1_vaapi -profile:v main -low_power 1 \
  -g 300 -bf 5 -b_depth 3 -refs 4 -rc_mode ICQ -global_quality 24 -r 24 \
  "$W/probe.mkv" -hide_banner -loglevel error

ffprobe -v error -select_streams v:0 -show_entries frame=pts,dts -of csv=p=0 "$W/probe.mkv" \
  | awk -F, '$1!=$2{print "REORDER at pts="$1; n++} END{print n+0" reordered frames out of total"}'
```

### Sanity check confirming `extra_hw_frames` is a genuine, accepted filter option (not silently ignored)

```bash
# Source: this session -- contrast test proving unknown options DO hard-error,
# so extra_hw_frames's silent acceptance is real, not a parser quirk.
ffmpeg -y ... -vf 'scale_vaapi=format=p010:totally_bogus_opt=64' ... 2>&1
# -> "Error applying option 'totally_bogus_opt' to filter 'scale_vaapi': Option not found"
# -> exit code 8, hard failure (confirms bogus options DO error; extra_hw_frames does not)
```

## State of the Art

| Old Approach (STACK.md's untested example, written before live verification) | Current Approach (verified this session) | When Changed | Impact |
|--------------------------------------------------------------------------|---------------------------------------------|---------------|--------|
| `-vf 'format=p010,hwupload=extra_hw_frames=32'` after `-hwaccel_output_format vaapi` | `-vf 'scale_vaapi=format=p010:extra_hw_frames=64'` | Verified 2026-07-23, this research session | The old form errors immediately (`Impossible to convert...`); planner/executor must use `scale_vaapi`, not `hwupload`, for a HW-frame-to-HW-frame P010 conversion |
| "AV1 VAAPI encoder supports B-pictures via `FF_HW_FLAG_B_PICTURES`" cited as confirmation the B-frame leg is reproducible (STACK.md, MEDIUM confidence, source-flag-only) | Empirically NO reordering occurs on this hardware (PTS==DTS for all 100 test frames) despite the flag and despite `-bf`/`-b_depth` being accepted without error | Verified 2026-07-23 | The theoretical source-level capability does not translate to functional behavior on this specific hardware/entrypoint combination — planners should treat D-03's PARTIAL-TRIAD path as the expected outcome |
| Assume `pict_type` from ffprobe is a valid signal for B-frame usage | `pict_type` is unreliable for AV1 (no native B-slice concept); use PTS/DTS equality instead | Discovered this session | Any future probe/verification logic referencing `pict_type` for AV1 B-frame detection should be corrected |

**Deprecated/outdated:** The STACK.md `av1_vaapi` command draft (lines 86-105 of that file) should not be copied verbatim into the phase's implementation — use the corrected command in Code Examples above instead.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `-b_depth`/`-bf`'s file-size delta reflects *some* RC/reference-structure change but not true reordering (Pitfall 5) | Common Pitfalls #5 | If the delta actually does correlate with a form of the long-lived-reference-surface condition the bug needs, dismissing it entirely could cause the phase to under-probe a partially-viable triad leg. Mitigated by Open Question #1 recommending a follow-up probe variant before finalizing the PARTIAL-TRIAD caveat. |
| A2 | `extra_hw_frames=64` is sufficient headroom for the full 3-way concurrent (not just single-session) av1_vaapi measurement — only tested single-session in this research pass | Pitfall 2 / Code Examples | If 64 is insufficient under 3-way concurrent contention, the same exit-244 gotcha could resurface under load even with the fix applied partially; the phase's own D-02/first concurrent run should re-verify exit codes are clean before trusting the full N=20 batch. |
| A3 | The `intel_gpu_top`/`igt-gpu-tools` diagnostic tooling mentioned in Phase-1's `STACK.md` is not needed for this phase (not re-verified live here) | (not directly used in this phase's core path) | Low risk — this phase's core measurement does not depend on it; only relevant if a future debugging need arises during execution. |

## Open Questions

1. **Does `-bf`/`-b_depth` induce any behaviorally-relevant reference structure short of true reordering?**
   - What we know: output bitstream size measurably differs between `-bf 5 -b_depth 3` and `-bf 0` for identical 100-frame input; PTS/DTS shows zero reordering in either case.
   - What's unclear: whether this reflects genuinely more reference slots / longer-lived reference surfaces held by the encoder (which is the actual mechanism leg (c)+(a) jointly need), or purely a rate-control/lookahead side effect unrelated to reference-surface lifetime.
   - Recommendation: this is inconclusive with the tools available in this research pass; the phase's own D-02 probe step should report the PTS/DTS finding as definitive for "no display/decode reordering" but explicitly avoid the stronger claim "no reference-surface-lifetime effect whatsoever" — phrase the PARTIAL-TRIAD caveat narrowly and accurately.

2. **Would other low_power-compatible flag combinations unlock true reordering?**
   - What we know: three variants tested (`-bf 5 -b_depth 3`, `-bf 0`, encoder default) all showed `pts==dts` (no reordering).
   - What's unclear: whether a different `-g`/`-refs`/explicit `-b_depth 1` combination might behave differently; the flag space was not exhaustively swept.
   - Recommendation: cheap to try one more variant (a few seconds each) during the phase's own D-02 execution before finalizing the "B-frame leg unsupported" caveat — not required before planning, since the current evidence is already strong (100% consistent across 3 independent tests) and the cost of being slightly overcautious in the caveat is low.

3. **Content-origin cross-match scan granularity (D-09/D-10 implementation detail, Claude's discretion per CONTEXT.md).**
   - What we know: each scene is small (111-362 frames), and `psnr_of()` on two already-extracted PNGs is fast (sub-second); a full scan of both other concurrent scenes per corrupt frame is well under 1000 total ffmpeg invocations across the whole historical qsvencc batch (Phase 1's 9+8=17 known corrupt iterations × ~2 scenes × ~200-360 candidate frames each) plus any new av1_vaapi corrupt frames.
   - What's unclear: nothing blocking — this is purely a discretionary implementation choice.
   - Recommendation: full scan (not sampled), given the low absolute cost — this maximizes confidence in the cross-match result over saving a trivial amount of wall-clock time.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|--------------|-----------|---------|----------|
| `ffmpeg` (system) | av1_vaapi encode, av1_qsv control, PSNR/content-match | ✓ | 6.1.1-3ubuntu5 (VAAPI+libvpl enabled) `[VERIFIED]` | `/usr/local/bin/ffmpeg-8.1` available as alternate build if needed |
| VA-API AV1 `VAEntrypointEncSliceLP` | av1_vaapi encode path | ✓ | `iHD` 26.2.2, `libva` 2.23.0 / VA-API 1.23 `[VERIFIED via vainfo]` | none needed — this is the only entrypoint and it works |
| `/dev/dri/renderD128` | GPU exclusivity for reference/measurement steps | ✓ | — | — |
| `scratch/repro/runs/itNN/` raw `.obu` artifacts (Phase 1) | D-09/D-10 qsvencc content cross-match reuse | ✓ present on disk `[VERIFIED: ls confirms it01..it20 present with c923/c928/c1129.obu each]` | — | if missing at execute time, would require re-running the qsvencc N=20 batch (expensive, ~20+ GPU-bound iterations) — the plan should verify presence as an early gate |
| Python 3 (stdlib) | `print_batch_summary` extension, cross-match search glue | ✓ | already used by existing `harness.sh` | — |

No missing dependencies block this phase. Everything required was directly available and exercised in this research session.

## Security Domain

This phase extends a local, single-user, non-network-facing diagnostic bash harness — most ASVS categories do not apply.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | No | N/A — no auth surface; local CLI harness |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A — governed entirely by filesystem permissions; `/data` read-only per D-09 (unchanged, carried from Phase 1) |
| V5 Input Validation | Yes (narrow) | Batch-size `N` for any new `run-batch-vaapi [N]` subcommand must follow the existing `WR-08` pattern in `harness.sh` (`[[ "$n_requested" =~ ^[1-9][0-9]*$ ]]` before use) — a non-numeric `N` must not silently no-op or crash the Python summary |
| V6 Cryptography | No | N/A — no secrets or crypto in this harness; `md5sum` used only for determinism-comparison (non-adversarial context), not security |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|-----------------------|
| Silent exit-code misclassification understating the true corruption rate (Pitfall 2) | Tampering-by-omission (a real corrupt/valid measurement silently excluded from the reported denominator) | Fix at the source (`extra_hw_frames=64`), preserving the existing fail-closed philosophy (CR-01/WR-09) rather than loosening the exit-code gate — a loosened gate would risk the opposite failure mode (accepting a genuinely broken encode as valid) |

## Sources

### Primary (HIGH confidence)
- Direct empirical testing on this environment: `ffmpeg -h encoder=av1_vaapi`, `vainfo`, and 15+ live `av1_vaapi`/`av1_qsv` encode invocations, PTS/DTS reorder analysis, exit-code reproduction sweep (20/21/22/24/25/28/30/40 frames), `extra_hw_frames` sanity/contrast test — all performed 2026-07-23 in this research session.
- `scratch/repro/harness.sh`, `scratch/repro/lib.sh` — read in full; existing primitives (`psnr_of`, `classify_corrupt`, `ctrl_encode`, `require_gpu_exclusive`, `cleanup_gpu_procs`) confirmed reusable verbatim.
- `.planning/phases/01-harness-control-environment-fingerprinting/01-EVIDENCE.md`, `01-CONTEXT.md` — Phase-1 certified baseline and carried decisions.
- `.planning/phases/02-in-container-triangulation-av1-vaapi/02-CONTEXT.md` — this phase's locked decisions (D-01..D-11).
- `.planning/research/PITFALLS.md`, `.planning/research/STACK.md` — Phase-1 research; STACK.md's `av1_vaapi` example command was tested directly and found to require correction (see State of the Art).
- `PROJECT.md` (repo root handoff) — trigger-triad definition, reproducer recipe, worker-function-pattern rule.

### Secondary (MEDIUM confidence)
- `github.com/FFmpeg/FFmpeg` `libavfilter/vf_scale_vaapi.c` (WebFetch, 2026-07-23) — confirmed `scale_vaapi`'s documented per-filter AVOption table (`w`/`h`/`format`/`mode`/etc.); did not show `extra_hw_frames` in that specific dump, but the option's functional acceptance was independently confirmed empirically via direct testing on the installed build (contrast test against a deliberately-invalid option name, which correctly hard-errored).

### Tertiary (LOW confidence)
- WebSearch for `ffmpeg vaapi filter extra_hw_frames option scale_vaapi` — inconclusive, did not surface a definitive source-level confirmation; superseded by the direct empirical verification above, which is the actual basis for this finding, not the web search.

## Metadata

**Confidence breakdown:**
- B-frame-leg non-reproducibility finding: HIGH — directly, repeatably reproduced live in this environment via an unambiguous PTS/DTS test, cross-checked against a methodologically-flawed alternative (`pict_type`) to explain why prior/naive checks could mislead.
- Harness-breaking exit-244 gotcha and its fix: HIGH — deterministically reproduced (failing) across 8 frame counts and reproduced (fixed) across 3 repeat runs with the `extra_hw_frames` addition.
- Exact rate-control/tile/GOP flag mapping recommendations: MEDIUM — functional and tested, but the "best" mapping to qsvencc's `--icq 24` semantics is a discretionary choice (per CONTEXT.md), not independently re-verified for bitrate/quality parity in this pass.
- Content cross-match technique: MEDIUM-HIGH — the underlying primitive (`psnr_of`) is Phase-1-proven; the specific cross-scene search loop was designed but not executed end-to-end against a real historical corrupt frame in this research pass (left as an implementation task, not a research gap).

**Research date:** 2026-07-23
**Valid until:** ~7 days — this research is tied to the exact live driver/ffmpeg build state of this specific environment (`iHD` 26.2.2, ffmpeg 6.1.1-3ubuntu5, kernel 6.19.14-200.fc43), any of which could change; re-verify the PTS/DTS reorder finding and the `extra_hw_frames` fix if the environment's ffmpeg or `iHD` version drifts before this phase executes.
