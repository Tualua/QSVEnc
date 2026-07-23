# Phase 1: Harness, Control & Environment Fingerprinting - Research

**Researched:** 2026-07-23
**Domain:** Bash-orchestrated GPU encode reproduction harness (Intel QSV/oneVPL AV1, concurrent-process frame corruption) + external-ffmpeg PSNR verification + environment fingerprinting under a restricted (non-privileged) container
**Confidence:** HIGH — nearly every claim below was directly executed and verified in this exact session/environment (not just read about), against the real `/data` source file and the real installed `qsvencc`/`ffmpeg` binaries. The few exceptions are flagged `[ASSUMED]` and listed in the Assumptions Log.

## Summary

This phase builds a bash harness, not application code. Everything it needs — `qsvencc` r4385, two ffmpeg builds (system 6.1.1 and `/usr/local/bin/ffmpeg-8.1`), `vainfo`, `intel_gpu_top` — is already installed in this environment, and this research session directly exercised the full reproduction protocol end-to-end against the real 21.4 GB source file to confirm every command in the plan actually works before the planner commits to it.

**Headline empirical result (not merely researched — reproduced live in this session):** the bug **reproduces in this environment** on the very first attempts. Four 3-way concurrent iterations were run; 3 of 4 produced a corrupt scene-923/offset-299 frame with a **highly deterministic PSNR of ~12.82–12.95 dB** (two of the three corrupt runs were byte-for-byte MSE-identical). This is a *different* numeric signature than the handoff's documented ~15.74 dB — same bug class (deterministic, well below the 30 dB threshold, reproducible), different exact value. This must be reported honestly as "reproduces, with its own deterministic signature in this environment" rather than force-fit to 15.74 dB. The paired isolated single-session reference encode was re-run twice and is **byte-identical (md5 match)** across runs, confirming D-05's determinism precondition. The paired ffmpeg `av1_qsv` control (fixed command below) ran 3-way concurrent once and produced a **PSNR-identical (inf) match** to its own isolated reference — immune, as expected, on the first try.

A second, equally important environment-specific finding: **this container has no `CAP_SYS_ADMIN`** (confirmed via `capsh --print`). `dmesg` returns "Operation not permitted", `mount -t debugfs` is denied, and `/sys/kernel/debug` does not exist. This directly blocks the literal `dmesg | grep -iE 'guc|huc'` command specified in D-08 and STACK.md — the harness's Environment Probe **must** treat this as an expected, gracefully-degraded case (report "GuC/HuC firmware: UNAVAILABLE — dmesg/debugfs blocked, no CAP_SYS_ADMIN in this container", not crash or hang). `intel_gpu_top` also crashes on this system (`Assertion 'get_num_gts' failed`, dumps core) beyond its `-L` device-listing mode — do not rely on it for concurrency observation; use the `/proc/<pid>/fdinfo` fallback instead (verified working, shown below). `lsof`/`fuser` are both absent — use a `/proc/*/fd` readlink loop for GPU-exclusivity checks (verified working, shown below).

**Primary recommendation:** build the harness exactly along the shape already validated live in this session (isolated reference → 3-way concurrent loop → offset-299 extraction → external PSNR → threshold+signature classifier → paired ffmpeg av1_qsv control, every batch), using the exact commands captured in Code Examples below (all copy-pasteable and pre-tested), and make the Environment Probe defensive against the permission gaps documented here rather than assuming a "just run dmesg" happy path.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REPRO-01 | Fingerprint environment (kernel, i915/Xe, iHD/VA-API, GuC/HuC) vs affected host `6.19.14-200.fc43` | Verified: `uname -r` = exact match. i915 binding, PCI ID, iHD/VA-API version all confirmed reachable without root. GuC/HuC via `dmesg` confirmed **blocked** in-container — Environment Probe must degrade gracefully (see Common Pitfalls / Code Examples). |
| REPRO-02 | Deterministic 3-way concurrent harness on scenes 923/928/1129, exact seek/trim, isolated writable workdir | Verified live: exact `&`/`wait` launch pattern runs all 3 scenes concurrently in ~5.5s wall-clock, all exit 0, correct frame counts (339/110/361 — note 0-indexed trim off-by-one, see Pitfalls). `scratch/` needs adding to `.gitignore` (not currently present). |
| REPRO-03 | Bit-clean single-session reference (scene 923, off=299) + PSNR-based classifier, `<30dB`=corrupt | Verified live: isolated reference is md5-identical across two independent runs (determinism confirmed). Frame extraction + `-lavfi psnr` pipeline verified end-to-end on both synthetic and real corrupted/clean frames; exact `psnr_avg:` field confirmed as the parse target. |
| REPRO-04 | Paired ffmpeg `av1_qsv` immune control every batch, expected 0/N | Verified live: exact working command constructed and fixed (`-profile main` is ambiguous in ffmpeg 6.1.1/8.1 — must be `-profile:v main`); 3-way concurrent control run produced a byte-identical/PSNR-inf match to its isolated reference on the first attempt. |
| REPRO-05 | Report corruption fraction + PSNR signature, detection-N=20 vs validation-N≈60 explicit | Rule-of-three statistics confirmed (standard, MEDIUM-HIGH citation). Live sample (N=4) already shows 3/4 (75%) — consistent with the documented 33–65% baseline range within small-N noise; classifier must report the actual measured signature value(s), not just "matches 15.74 dB", since this environment's deterministic value differs (~12.8–13.0 dB). |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Environment fingerprinting (kernel/driver/firmware) | Host OS / sysfs+VA-API userspace | — | Read-only system introspection; no application tier involved |
| Reference (isolated) encode | GPU HW-encode (qsvencc → oneVPL → iHD → i915) | Orchestration script (bash) | The encode itself runs entirely in the GPU/driver stack; bash only sequences it |
| Concurrent-encode reproduction | GPU HW-encode (3 processes) + orchestration | — | The bug is defined by concurrent GPU-tier contention; bash's only job is precise process launch/reap timing |
| Frame extraction (offset→PNG) | CPU decode (ffmpeg software AV1 decoder) | — | Deliberately CPU-only/OpenCL-free per D-04 — must not touch GPU, to keep verification independent of the GPU path under test |
| PSNR classification | CPU (ffmpeg lavfi) | Orchestration script (threshold logic) | Pure numeric comparison; script parses ffmpeg's stats output and applies the `<30dB` rule |
| Immune control (ffmpeg av1_qsv) | GPU HW-encode (separate process/pool topology) | Orchestration script | Same GPU tier as the target-under-test, deliberately run through a topologically different (per-role pool) code path |
| Corruption-rate report | Orchestration script (bash/awk/python3) | — | Aggregation-only, no GPU/decode involvement |

## Standard Stack

### Core

| Tool | Version (confirmed in this environment) | Purpose | Why Standard |
|------|-------------------------------------------|---------|---------------|
| `qsvencc` | `8.22 (r4385)`, rigaya, gcc 9.4.0, Intel Media SDK API v2.16 — at `/usr/bin/qsvencc` | Reproduction target under test | This is the exact stock build documented in the handoff as the corruption-characterized baseline (D-02). `[VERIFIED: this environment, 2026-07-23 — ran directly]` |
| `ffmpeg` (system) | `6.1.1-3ubuntu5`, built with `--enable-libvpl --disable-libmfx --enable-vaapi --enable-opencl` (no `--enable-libvmaf`) — at `/usr/bin/ffmpeg` | Frame extraction + PSNR metric engine; also usable for the `av1_qsv`/`av1_vaapi` control paths | Has `av1_qsv`, `av1_vaapi`, `h264_qsv` encoders confirmed present via `-encoders`. Does **not** have the `libvmaf` filter (only `vmafmotion`) — irrelevant to this phase (PSNR-only per D-04) but relevant for later defense-in-depth phases. `[VERIFIED: this environment]` |
| `ffmpeg-8.1` | `n8.1.2-30-g45f1910444` (2026-07-22 build), `--enable-libvmaf --enable-vaapi --enable-libvpl` — at `/usr/local/bin/ffmpeg-8.1` | Alternative control/metric engine; the one to use if VMAF is ever needed | Confirmed has `av1_qsv`, `av1_vaapi`, `h264_qsv`, and the real `libvmaf` filter. `[VERIFIED: this environment]` |
| `bash` (`&`/`wait`) | system default | 3-way concurrent process orchestration | Matches D-01's decision; verified end-to-end (3 background jobs + individual `wait $PID; $?` per job to capture per-process exit codes, not just the last). `[VERIFIED: this environment — ran the exact pattern]` |
| `vainfo` | libva 2.23.0 / VA-API 1.23, iHD driver **26.2.2** | VA-API/driver version fingerprint | Requires `LIBVA_DRIVER_NAME=iHD` env var to be set (already is, confirmed) and needs `XDG_RUNTIME_DIR` — a warning is printed but does not prevent the version info from being printed to stdout; safe to ignore the warning in scripts. `[VERIFIED: this environment]` |

### Supporting

| Tool | Status in this environment | Purpose | When to Use |
|------|------------------------------|---------|-------------|
| `readlink -f /sys/class/drm/card2/device/driver` | Works, no root needed. Resolves to `/sys/bus/pci/drivers/i915` | Confirm bound kernel driver | Environment Probe, every batch |
| `lspci -k` / `lspci -nn` | **Returns nothing in this container** (no PCI enumeration access) — but the equivalent info (`vendor 0x8086 device 0x56a5`, i.e. Arc A380/DG2-128) is directly readable from `/sys/bus/pci/drivers/i915/0000:19:00.0/{vendor,device}` | PCI ID confirmation | Use the sysfs fallback, not `lspci`, in this environment. `[VERIFIED: this environment]` |
| `dmesg` | **Blocked**: `dmesg: read kernel buffer failed: Operation not permitted` (no `CAP_SYS_ADMIN`; confirmed via `capsh --print`) | GuC/HuC firmware version, low-power encode mode confirmation | Cannot be used here. Harness must catch this failure and report "UNAVAILABLE" rather than fail the whole fingerprint step. See Common Pitfalls. |
| `mount -t debugfs` / `/sys/kernel/debug/dri/*` | **Blocked**: `mount: /sys/kernel/debug: permission denied`; path doesn't exist unmounted | Deeper per-driver debugfs (GuC info, HuC load status) | Not usable in this container at all. |
| `intel_gpu_top -L` | **Works** — correctly lists `card2 Intel Dg2 (Gen12) pci:vendor=8086,device=56A5` | Device enumeration/sanity check | Fine to use for a one-shot device-list sanity check |
| `intel_gpu_top` (live monitoring, no `-L`) | **Crashes**: `Assertion 'get_num_gts' failed`, dumps core, in ≤3s | Live engine-occupancy view during concurrent runs | Do **not** rely on it in this container. Use the `/proc/<pid>/fdinfo` fallback below instead (verified working). |
| `fuser`, `lsof` | **Both absent** (`command not found`) | GPU-exclusivity verification before "isolated" runs | Use the `/proc/*/fd` readlink loop shown in Code Examples (verified working) instead. |
| `journalctl -k` | Runs without error but reports "No journal files were found" | Alternative to `dmesg` | Not usable here either — no persistent journal in this container. |
| `awk`, `python3` | Present | Numeric aggregation (corruption fraction, PSNR stats) | `bc` is **absent** — do not use it in scripts; use `awk` or `python3` for floating-point math. `[VERIFIED: this environment]` |
| `LIBVA_TRACE=<path>` | **Works** — produces per-thread trace files (`trace.<pid>.thd-<tid>`) | Deep VA-API call tracing, if later phases need it | Confirmed functional in this session on a 5-frame test encode; not required for Phase 1's core deliverables but available if the Classifier's signature needs deeper investigation later. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `dmesg`/debugfs for GuC/HuC firmware | Nothing available in-container | No viable in-container alternative was found; must report as an honest gap in REPRO-01's deliverable, not silently omit it. If the host is ever accessible directly (outside this container), `dmesg`/debugfs would work there. |
| `intel_gpu_top` live monitoring | `/proc/<pid>/fdinfo` per-process DRM counters | fdinfo is coarser (no live percentage bars) but works reliably in this container and needs no special capability; sufficient for confirming 3 distinct GPU clients are active simultaneously. |
| `fuser`/`lsof` | `/proc/*/fd` readlink loop | Slightly more code but zero extra dependencies; verified working. |
| `ffmpeg`'s `libvmaf` filter | `-lavfi psnr` (system ffmpeg 6.1.1, this phase's actual requirement) | This phase (D-04) explicitly uses PSNR only, not VMAF — no tradeoff needed here; VMAF is a later-phase (Phase 4 defense-in-depth gate) concern, and `ffmpeg-8.1` is the build to use then. |

**Installation:** None required — every tool needed for this phase is already installed in this environment. No `npm`/`pip`/`cargo` install steps apply (this is a bash-only harness).

## Package Legitimacy Audit

**Not applicable to this phase.** The harness is a self-contained bash script that orchestrates already-installed system binaries (`qsvencc`, `ffmpeg`, `ffmpeg-8.1`, `vainfo`, `awk`, `python3`). No `npm install`/`pip install`/`cargo add` or any external package fetch occurs in this phase's scope. The slopcheck/registry-verification gate is skipped for this reason — there is nothing to audit.

## Architecture Patterns

### System Architecture Diagram

```
┌────────────────────────────────────────────────────────────────────────┐
│ ENVIRONMENT PROBE (run once per batch)                                 │
│  uname -r │ readlink driver binding │ vainfo │ dmesg (best-effort,     │
│  degrades to UNAVAILABLE) │ qsvencc --check-features (~60s, cache it)  │
└───────────────────────────────┬────────────────────────────────────────┘
                                 │ tags every report row
                                 ▼
┌────────────────────────────────────────────────────────────────────────┐
│ GPU-EXCLUSIVITY GATE  (before every "isolated"/"control" run)         │
│  /proc/*/fd readlink loop for renderD128 clients → abort if non-empty  │
└───────────────────────────────┬────────────────────────────────────────┘
                                 ▼
┌───────────────────────────┐        ┌─────────────────────────────────┐
│ REFERENCE RUNNER           │        │ CONCURRENT RUNNER                │
│ 1x isolated qsvencc,       │        │ 3x qsvencc & / 3x ffmpeg av1_qsv│
│ scene 923 only             │        │ &, scenes 923+928+1129, `wait`  │
│ → md5-verified determinism │        │ per-PID (not just last $?)      │
└──────────────┬─────────────┘        │ repeated N=20 iterations        │
               │                      └────────────────┬──────────────────┘
               ▼                                       ▼
┌────────────────────────────────────────────────────────────────────────┐
│ FRAME EXTRACTION  (ffmpeg -vf select='eq(n\,OFFSET)' -vsync 0          │
│  -frames:v 1, CPU-only decode; works identically on qsvencc/ffmpeg     │
│  .obu output since ffprobe auto-detects raw AV1 stream)                │
└───────────────────────────────┬────────────────────────────────────────┘
                                 ▼
┌────────────────────────────────────────────────────────────────────────┐
│ PSNR METRIC ENGINE  (ffmpeg -lavfi psnr=stats_file=..., parse          │
│  `psnr_avg:` field; LC_ALL=C to avoid locale issues even though this   │
│  environment is already C.UTF-8)                                       │
└───────────────────────────────┬────────────────────────────────────────┘
                                 ▼
┌────────────────────────────────────────────────────────────────────────┐
│ CLASSIFIER  (< 30 dB = corrupt; ALSO record raw dB value —             │
│  do not hard-assert == 15.74 dB, this environment's own deterministic  │
│  value is ~12.8-13.0 dB, a different but equally deterministic         │
│  signature within the same bug class)                                  │
└───────────────────────────────┬────────────────────────────────────────┘
                                 ▼
                    CORRUPTION-RATE REPORT (fraction, per-run PSNR,
                    detection-N=20 stated explicitly, control-run
                    pass/fail stated alongside every qsvencc row)
```

### Recommended Project Structure

```
scratch/repro/                  # git-ignored (add "/scratch/" to .gitignore — not currently present)
├── fingerprint.txt             # Environment Probe output (one per invocation of the harness)
├── reference/
│   ├── chunk923_ref.obu        # isolated single-session encode (md5-checked determinism)
│   └── frame299_ref.png        # extracted hotspot frame from the reference
├── control_reference/
│   ├── c923_ffref.obu          # isolated ffmpeg av1_qsv reference (own baseline, not qsvencc's)
│   └── ffref_299.png
├── runs/
│   ├── it01/
│   │   ├── c923.obu c928.obu c1129.obu     # qsvencc concurrent outputs
│   │   ├── log923.txt log928.txt log1129.txt
│   │   ├── frame299.png
│   │   └── psnr.log
│   ├── it02/ ...
│   └── ...                      # up to it20 (detection-N default per D-07)
├── control_runs/
│   ├── it01/ c923.obu c928.obu c1129.obu frame299.png psnr.log
│   └── ...                      # same N as runs/, paired every batch
└── report.csv                   # iteration, scene, psnr_db, corrupt(bool), matches_known_signature(bool), control_clean(bool)
```

### Pattern 1: Per-process exit-code capture (not just `wait`'s last status)

**What:** Launch all 3 background jobs, capture each `$!` PID immediately, then `wait $PID1; R1=$?; wait $PID2; R2=$?; wait $PID3; R3=$?` — never a bare `wait` followed by a single `$?`.
**When to use:** Every concurrent batch (qsvencc and ffmpeg control).
**Example (verified working in this session):**
```bash
qsvencc --avhw --va -i "$SRC" $COMMON --seek 01:16:14.167 --trim 0:339 -o "$W/c923.obu" > "$W/log923.txt" 2>&1 &
P1=$!
qsvencc --avhw --va -i "$SRC" $COMMON --seek 01:17:00.667 --trim 0:110 -o "$W/c928.obu" > "$W/log928.txt" 2>&1 &
P2=$!
qsvencc --avhw --va -i "$SRC" $COMMON --seek 01:34:24.583 --trim 0:361 -o "$W/c1129.obu" > "$W/log1129.txt" 2>&1 &
P3=$!
wait $P1; R1=$?
wait $P2; R2=$?
wait $P3; R3=$?
echo "exit codes: 923=$R1 928=$R2 1129=$R3"
```
Confirmed: all three complete in ~5.5s wall-clock, all exit 0, correct output sizes.

### Pattern 2: GPU-exclusivity check without `fuser`/`lsof`

**What:** Loop `/proc/*/fd/*` symlinks looking for `renderD128`.
**When to use:** Immediately before every "isolated"/"reference" run (Pitfall 1 in PITFALLS.md — measurement contamination).
**Example (verified working):**
```bash
gpu_clients() {
  for pidfd in /proc/[0-9]*/fd/*; do
    t=$(readlink "$pidfd" 2>/dev/null) || continue
    [[ "$t" == *renderD128* ]] || continue
    pid=$(echo "$pidfd" | cut -d/ -f3)
    echo "PID $pid: $(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)"
  done
}
if [[ -n "$(gpu_clients)" ]]; then
  echo "ABORT: GPU not exclusive, found: $(gpu_clients)" >&2
  exit 1
fi
```

### Pattern 3: Environment Probe with graceful degradation

**What:** Every probe line must independently catch its own failure and print `UNAVAILABLE: <reason>` rather than letting one blocked command (`dmesg`) abort the whole fingerprint.
**Example (verified working — dmesg line confirmed to hit the `||` branch in this container):**
```bash
{
  echo "kernel: $(uname -r)"
  echo "driver: $(readlink -f /sys/class/drm/card2/device/driver 2>/dev/null || echo UNAVAILABLE)"
  echo "pci_id: $(cat /sys/bus/pci/drivers/i915/*/vendor 2>/dev/null):$(cat /sys/bus/pci/drivers/i915/*/device 2>/dev/null)"
  echo "vainfo: $(LIBVA_DRIVER_NAME=iHD vainfo 2>&1 | grep -i 'Driver version' || echo UNAVAILABLE)"
  echo "guc_huc_firmware: $(dmesg 2>&1 | grep -iE 'guc|huc' || echo 'UNAVAILABLE: dmesg blocked (no CAP_SYS_ADMIN in this container)')"
} > "$W/fingerprint.txt"
```
This exact pattern was run in this session; the `dmesg` line correctly falls through to the `UNAVAILABLE` message instead of hanging or erroring the script.

### Anti-Patterns to Avoid

- **Trusting the ~15.74 dB signature as a hard equality check:** This environment's own deterministic corrupt value is ~12.82–12.95 dB (verified: two of three corrupt runs were exact MSE matches, `224151379.55`). Classify by threshold (`<30dB`) and *report* the observed value(s); do not fail/misclassify a genuinely-reproduced-but-differently-valued corruption as "not the bug."
- **Assuming `-profile main` works on ffmpeg's av1_qsv/vaapi encoders:** it is ambiguous (audio vs video profile) on both ffmpeg 6.1.1 and 8.1 tested here — always use `-profile:v main`.
- **Assuming raw `.obu` output needs a container/demuxer flag:** `ffprobe`/`ffmpeg` auto-detect and correctly report `codec_name=av1` and the right frame count directly from a bare `.obu` file in this ffmpeg version — no `-f av1` needed (verified).
- **Using `bc` for percentage/PSNR math:** absent in this container; use `awk` or `python3`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Zero-failure confidence bound | A custom statistical model for "is N clean runs enough" | Rule-of-three: 0 failures in *n* trials bounds the 95% upper CI at ≈3/n. For detection (this phase), N=20 only needs to show the ~33–65% baseline recurs — it is not a "clean" claim. Reserve N≈60 for later "fixed" claims (out of scope this phase per D-07). | Standard, well-established; reinventing a different confidence heuristic risks under- or over-claiming. `[CITED: standard statistical convention, also documented in .planning/research/PITFALLS.md]` |
| PSNR/SSIM computation | Custom pixel-diff script | `ffmpeg -lavfi psnr` (verified exact output format: `psnr_avg:<value>` in both the stdout summary line and the `stats_file`) | Battle-tested, exact field format confirmed in this session on both synthetic and real corrupted frames — no reason to hand-roll. |
| Concurrent process launch/reap | A custom process-supervisor | Plain bash `&` + per-PID `wait` (verified pattern above) | This is exactly what `enpipe`'s `ThreadPoolExecutor(max_workers=3)` does at a coarser level; bash `&`/`wait` reproduces the same concurrency shape with less code, and was directly verified to work. |
| GPU exclusivity detection | A custom `/dev/dri` locking mechanism | `/proc/*/fd` readlink loop (verified) | `fuser`/`lsof` are unavailable; this is the documented, standard fallback (also in STACK.md) and was confirmed to correctly find/report an active GPU-touching PID in this session. |

**Key insight:** every "don't hand-roll" tool in this domain was directly executed and confirmed correct in this exact session — there is no need to prototype alternatives.

## Common Pitfalls

### Pitfall 1: `dmesg`/debugfs GuC-HuC probe silently hangs or aborts the whole fingerprint step

**What goes wrong:** A naive Environment Probe script does `dmesg | grep -iE 'guc|huc'` per D-08/STACK.md literally, gets a nonzero exit + stderr ("Operation not permitted"), and either the whole script aborts (if run under `set -e`) or the corruption in exit-status propagation silently loses the rest of the fingerprint.
**Why it happens:** This container lacks `CAP_SYS_ADMIN` (confirmed via `capsh --print`); `dmesg`, `mount -t debugfs`, and `journalctl -k` are all blocked or empty here, which is not the assumption baked into D-08's literal wording.
**How to avoid:** Wrap every fingerprint probe line in its own `... || echo UNAVAILABLE: <reason>` (Pattern 3 above, verified working). Never use `set -e` for the whole Environment Probe function.
**Warning signs:** Fingerprint file missing lines entirely, or the harness script exiting early with no output.

### Pitfall 2: Reusing the documented ~15.74 dB PSNR value as a pass/fail equality check

**What goes wrong:** A classifier that does `if psnr == 15.74: corrupt` (or a narrow tolerance band around it) will **miss** this environment's real, deterministic, reproducible corruption because its value is ~12.8–13.0 dB here (confirmed 3 of 4 live iterations).
**Why it happens:** Over-fitting to a number from a different host/session rather than treating "well below 30 dB, deterministic across repeats" as the actual signature definition.
**How to avoid:** Classify strictly by threshold (`<30dB`). Separately report the observed value(s) as data, and separately note whether they match the *previously documented* 15.74 dB or are a *new* deterministic value for this environment (per Architecture research's Anti-Pattern 1: "novel low-PSNR value under a new environment is a DIFFERENT finding, not confirmation of the known bug" — but also not proof it's a different *bug*; state both possibilities honestly).
**Warning signs:** A classifier hardcoding `15.74` anywhere in its comparison logic.

### Pitfall 3: `intel_gpu_top` crashing being mistaken for "no GPU activity"

**What goes wrong:** Running `intel_gpu_top` (without `-L`) during a concurrent batch to observe engine occupancy crashes with `Assertion 'get_num_gts' failed` within ~3 seconds and dumps core — if the harness doesn't check the exit code, an empty/truncated output could be misread as "engines idle" rather than "tool crashed."
**How to avoid:** Do not use live `intel_gpu_top` monitoring in this container at all. Use `/proc/<pid>/fdinfo/*` (confirmed working — reports `drm-driver: i915`, `drm-client-id`, `drm-engine-capacity-video`, etc.) if per-process GPU activity confirmation is ever needed.
**Warning signs:** Any script invoking `intel_gpu_top` without `-L` in this container; a core dump file appearing in the workdir.

### Pitfall 4: Forgetting the `-profile:v` disambiguation on ffmpeg's QSV/VAAPI encoders

**What goes wrong:** `ffmpeg ... -c:v av1_qsv -profile main ...` prints "Please use -profile:v or -profile:a, -profile is ambiguous" — it still runs (defaults applied) but silently does *not* set the intended profile, which could confound the control run's fidelity to the qsvencc combo it's supposed to mirror.
**How to avoid:** Always write `-profile:v main` explicitly. Verified on both ffmpeg 6.1.1 and 8.1.

### Pitfall 5: Treating `scratch/` as already git-ignored

**What goes wrong:** D-01/D-09 specify a git-ignored workdir, but `.gitignore` in this repo currently has **no** `scratch/`-matching pattern (confirmed by reading the full file) — a naive `git status` check after building the harness would show untracked chunk/PNG/log files.
**How to avoid:** Add an explicit `/scratch/` (or `scratch/repro/`) line to `.gitignore` as part of harness setup, before generating any output there.

## Code Examples

All examples below were executed directly in this session against the real source file and real installed tools — not copied from documentation.

### Isolated reference encode + determinism check (D-05)

```bash
SRC="/data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv"
W="scratch/repro"
COMMON="-c av1 --icq 24 --qp-max 100 --output-depth 10 --profile main \
  --gop-len 300 --gop-ref-dist 6 --b-pyramid --tile-col 1 --tile-row 1 \
  --tune perceptual --scenario-info archive \
  --colorrange auto --colormatrix auto --colorprim auto --transfer auto --chromaloc auto"

qsvencc --avhw --va -i "$SRC" $COMMON --seek 01:16:14.167 --trim 0:339 -o "$W/reference/chunk923_ref.obu"
# Re-run once more and md5-compare to confirm determinism before trusting the reference:
qsvencc --avhw --va -i "$SRC" $COMMON --seek 01:16:14.167 --trim 0:339 -o "$W/reference/chunk923_ref_repeat.obu"
md5sum "$W/reference/chunk923_ref.obu" "$W/reference/chunk923_ref_repeat.obu"
# Verified in this session: identical md5 (ca77cc72b0cfa2cfd291f278ab62f278) both times.

ffmpeg -y -i "$W/reference/chunk923_ref.obu" -vf "select='eq(n\,299)'" -vsync 0 -frames:v 1 \
  "$W/reference/frame299_ref.png"
```

Single-scene isolated encode takes ~6s wall-clock (measured: `real 0m5.978s`, 310.79 fps, 340 frames including the leading frame from `--trim 0:339` — encoder reports 340 encoded frames for a 339-frame trim value, i.e. trim count is exclusive-end / frame count = trim+1; confirm this off-by-one against `ffprobe nb_read_frames` before trusting hotspot offset 299 against the encoder's own frame numbering).

### 3-way concurrent qsvencc run, one iteration (REPRO-02)

```bash
(
  qsvencc --avhw --va -i "$SRC" $COMMON --seek 01:16:14.167 --trim 0:339 -o "$W/runs/it01/c923.obu" > "$W/runs/it01/log923.txt" 2>&1 &
  P1=$!
  qsvencc --avhw --va -i "$SRC" $COMMON --seek 01:17:00.667 --trim 0:110 -o "$W/runs/it01/c928.obu" > "$W/runs/it01/log928.txt" 2>&1 &
  P2=$!
  qsvencc --avhw --va -i "$SRC" $COMMON --seek 01:34:24.583 --trim 0:361 -o "$W/runs/it01/c1129.obu" > "$W/runs/it01/log1129.txt" 2>&1 &
  P3=$!
  wait $P1; R1=$?
  wait $P2; R2=$?
  wait $P3; R3=$?
  echo "exit codes: 923=$R1 928=$R2 1129=$R3"
)
```
Verified: ~5.5s wall-clock for all 3, all exit 0. Ran 4 iterations live in this session: 3 of 4 produced a corrupt scene-923/offset-299 frame (PSNR ~12.82–12.95 dB, two exact MSE matches) — the bug reproduces readily in this environment.

### Frame extraction + PSNR classification (D-04)

```bash
ffmpeg -y -i "$W/runs/it01/c923.obu" -vf "select='eq(n\,299)'" -vsync 0 -frames:v 1 \
  "$W/runs/it01/frame299.png"
LC_ALL=C ffmpeg -y -i "$W/runs/it01/frame299.png" -i "$W/reference/frame299_ref.png" \
  -lavfi psnr="stats_file=$W/runs/it01/psnr.log" -f null -
awk -F'psnr_avg:' '{split($2,a," "); print a[1]}' "$W/runs/it01/psnr.log"
```
Verified exact stats_file line format: `n:1 mse_avg:224151379.55 ... psnr_avg:12.82 ...` (corrupt case) vs `psnr_avg:inf` (clean case, byte-identical frames).

### Paired ffmpeg `av1_qsv` immune control (D-06) — exact working command

```bash
ctrl_encode() {
  local seek="$1" frames="$2" out="$3"
  ffmpeg -y -hwaccel qsv -hwaccel_output_format qsv -c:v h264_qsv \
    -ss "$seek" -i "$SRC" -frames:v "$frames" \
    -vf "vpp_qsv=format=p010le" \
    -c:v av1_qsv -profile:v main -g 300 -bf 5 -refs 4 -global_quality 24 -look_ahead_depth 0 \
    -tile_cols 1 -tile_rows 1 \
    "$out" -hide_banner -loglevel error
}
# Isolated control reference:
ctrl_encode 01:16:14.167 339 "$W/control_reference/c923_ffref.obu"
# 3-way concurrent control (paired with every qsvencc batch):
(
  ctrl_encode 01:16:14.167 339 "$W/control_runs/it01/c923.obu" & P1=$!
  ctrl_encode 01:17:00.667 110 "$W/control_runs/it01/c928.obu" & P2=$!
  ctrl_encode 01:34:24.583 361 "$W/control_runs/it01/c1129.obu" & P3=$!
  wait $P1; wait $P2; wait $P3
)
```
Verified: `-profile main` alone is rejected as ambiguous by ffmpeg (both 6.1.1 and 8.1) — must be `-profile:v main`. `-bf 5 -refs 4` is the ffmpeg-side analog of qsvencc's `--gop-ref-dist 6 --b-pyramid` (5 B-frames + 1 P-frame = ref-dist 6). `[ASSUMED: exact pyramid-depth equivalence — ffprobe's pict_type field reports only I/P for AV1 OBU streams in this ffmpeg version (AV1 has no native B-slice type distinct from inter frames the way H.264 does), so pyramid structure could not be independently confirmed via pict_type; the byte-identical isolated-vs-concurrent match is strong indirect evidence the encoder path is deterministic and correctly configured, but the specific B-pyramid depth claim rests on ffmpeg's own documented `-bf`/GopRefDist mapping, not on directly-observed frame-type output.]` Live 3-way concurrent control run produced output PSNR-identical (`inf`) to its own isolated reference — immune, first try, matching the documented 35/35 clean expectation.

### GPU-exclusivity check (before any "isolated" claim)

```bash
gpu_clients() {
  for pidfd in /proc/[0-9]*/fd/*; do
    t=$(readlink "$pidfd" 2>/dev/null) || continue
    [[ "$t" == *renderD128* ]] || continue
    pid=$(echo "$pidfd" | cut -d/ -f3)
    echo "PID $pid: $(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)"
  done
}
[[ -z "$(gpu_clients)" ]] || { echo "ABORT: GPU not exclusive: $(gpu_clients)" >&2; exit 1; }
```
Verified: correctly returns empty when idle, and correctly identifies an active PID + its fds on `renderD128` when a background qsvencc job is running (`/proc/<pid>/fdinfo` further confirmed `drm-driver: i915`, `drm-client-id`, `drm-engine-capacity-video`).

### Environment fingerprint (REPRO-01, D-08) — degradation-safe

```bash
{
  echo "kernel: $(uname -r)"
  echo "kernel_matches_affected_host: $([ "$(uname -r)" = "6.19.14-200.fc43.x86_64" ] && echo YES || echo NO)"
  echo "gpu_driver: $(readlink -f /sys/class/drm/card2/device/driver 2>/dev/null || echo UNAVAILABLE)"
  echo "pci_id: $(cat /sys/bus/pci/drivers/i915/0000:19:00.0/vendor 2>/dev/null):$(cat /sys/bus/pci/drivers/i915/0000:19:00.0/device 2>/dev/null)"
  echo "vainfo: $(LIBVA_DRIVER_NAME=iHD vainfo 2>&1 | grep -i 'Driver version' || echo UNAVAILABLE)"
  echo "guc_huc: $(dmesg 2>&1 | grep -iE 'guc|huc' || echo 'UNAVAILABLE: dmesg blocked (no CAP_SYS_ADMIN)')"
} > "$W/fingerprint.txt"
cat "$W/fingerprint.txt"
```
Verified output in this session:
```
kernel: 6.19.14-200.fc43.x86_64
kernel_matches_affected_host: YES
gpu_driver: /sys/bus/pci/drivers/i915
pci_id: 0x8086:0x56a5
vainfo: vainfo: Driver version: Intel iHD driver for Intel(R) Gen Graphics - 26.2.2 ()
guc_huc: UNAVAILABLE: dmesg blocked (no CAP_SYS_ADMIN)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|-------------------|---------------|--------|
| `qsvencc --psnr`/`--ssim` for metrics (OpenCL-gated) | External ffmpeg `-lavfi psnr` on extracted frames | Already established in the handoff (§9), re-confirmed working in this session | Zero GPU/OpenCL coupling in the verification path; keeps the metric engine trustworthy regardless of whether the qsvencc-under-test path is healthy |
| Assuming a single canonical PSNR signature value (~15.74 dB) generalizes to every environment | Threshold-based classification (`<30dB`) + reporting the actual observed value(s) per environment | Discovered in this session (this environment's value is ~12.8–13.0 dB, not 15.74 dB) | Prevents both false negatives (missing a real reproduction because the exact number differs) and overclaiming ("still the same bug" without evidence it's the identical aliasing slot) |

**Deprecated/outdated:** None specific to tooling versions — `qsvencc` r4385/`ffmpeg` 6.1.1+8.1 are the current, already-installed, already-verified stack for this phase; no upgrade path is needed or in scope.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|----------------|
| A1 | `ffmpeg`'s `-bf 5 -refs 4` on `av1_qsv` produces an internal GopRefDist-6/B-pyramid structure equivalent enough to qsvencc's `--gop-ref-dist 6 --b-pyramid` to serve as a valid "identical trigger triad" control, per the handoff's own characterization of this control command | Code Examples — Paired ffmpeg control | If the ffmpeg encoder silently negotiates a shallower/different reorder structure, the control's "immunity" would not actually be testing the same trigger triad, weakening (not invalidating — the control still ran clean) the diagnostic conclusion. Confirm via `ffprobe -show_frames` reference-index fields or by cross-checking against `.planning/research/STACK.md`'s prior 35/35-clean characterization of this same command shape, not by pict_type alone (AV1 OBU streams reported only I/P via ffprobe's `pict_type` field in this ffmpeg version — inconclusive for pyramid-depth confirmation). |
| A2 | GuC/HuC firmware version is fundamentally unobtainable from inside this specific container (not just "not yet found a way") | Common Pitfalls / Standard Stack | If a future container image grants `CAP_SYS_ADMIN` or a debugfs bind-mount, `dmesg`/debugfs would become available and this conclusion would need revisiting — the harness's degradation message should say "blocked in this container" not "impossible in general," which it already does. |

**If this table is empty:** N/A — see above; both entries are narrow, already-flagged risks, not core-finding risks (the core corruption-reproduction and control-immunity findings were both directly, numerically verified, not assumed).

## Open Questions

1. **Does this environment's ~12.8–13.0 dB corrupt signature represent the *same* cross-scene content-aliasing bug as the documented ~15.74 dB, or a related-but-distinct aliasing slot?**
   - What we know: both are deterministic (repeat runs land on the same PSNR to 2 decimal places, and MSE values match exactly across some repeats), both are far below the 30 dB threshold, both occur at the exact same scene/offset (923/299), and both require the same 3-way concurrent trigger.
   - What's unclear: whether the corrupted pixel *content* actually comes from another concurrent session's scene (928 or 1129), as the original signature does, or from a different source — this would require decoding and visually/structurally comparing the corrupt frame against frames from the concurrently-running scenes 928/1129 outputs, which this research pass did not do (out of scope for a research-only pass; recommend as the first Phase-1 execution step).
   - Recommendation: the harness's Classifier should, at minimum for the first few detection-N runs, extract and eyeball (or diff) the corrupt frame against candidate donor frames from the other two concurrent scenes to confirm the cross-session content-swap mechanism, not just the PSNR-drop symptom.

2. **Is the corruption rate observed in this tiny live sample (3/4 = 75%) representative, or a small-N artifact?**
   - What we know: 75% is within (indeed above) the documented 33–65% range but N=4 is far too small to draw a rate conclusion.
   - What's unclear: the true rate for this specific environment at N=20 (Phase 1's actual detection-N target).
   - Recommendation: run the full N=20 detection batch as planned; do not treat this research session's N=4 as the reported baseline — it exists only to validate the harness mechanics work end-to-end.

3. **Should the Classifier also check scenes 928 (offset 96) and 1129 (offset 299), not just scene 923/299?**
   - What we know: D-03 locks "corruption is measured on scene 923, frame offset 299" as the primary metric; Claude's Discretion explicitly leaves "how multi-scene results are aggregated" open.
   - What's unclear: whether checking all 3 known hotspots per iteration would materially change the reported corruption fraction or just add confirmatory detail.
   - Recommendation: implement 923/299 as the required primary measurement (satisfies D-03/REPRO-03 exactly), and optionally extract+PSNR-check 928/96 and 1129/299 too as a cheap bonus signal (near-zero extra cost since those outputs already exist from the same concurrent run) — the planner should decide whether this is in-scope for Phase 1's task list or deferred.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|--------------|-----------|---------|----------|
| `qsvencc` | REPRO-02/03/04/05 (target under test) | ✓ | 8.22 (r4385) | — |
| `ffmpeg` (system) | REPRO-03/04 (extraction, PSNR, control) | ✓ | 6.1.1-3ubuntu5 | — |
| `ffmpeg-8.1` | Later-phase VMAF needs (not required this phase) | ✓ | n8.1.2-30 (2026-07-22) | System ffmpeg suffices for this phase's PSNR-only needs |
| `vainfo` | REPRO-01 (fingerprint) | ✓ | libva 2.23.0 / VA-API 1.23 / iHD 26.2.2 | — |
| `dmesg` | REPRO-01 (GuC/HuC firmware) | ✗ (no CAP_SYS_ADMIN) | — | None in-container — report `UNAVAILABLE` explicitly, do not fail the whole fingerprint |
| `/sys/kernel/debug` (debugfs) | REPRO-01 (deeper GuC/HuC/driver detail) | ✗ (mount denied) | — | None in-container |
| `intel_gpu_top` (live mode) | Optional concurrency observation (not a hard requirement) | ✗ (crashes) | 2.x (crashes on `get_num_gts`) | `/proc/<pid>/fdinfo` (verified working) |
| `intel_gpu_top -L` | Device enumeration sanity check only | ✓ | — | — |
| `fuser`/`lsof` | GPU-exclusivity checks | ✗ (both absent) | — | `/proc/*/fd` readlink loop (verified working) |
| `bc` | Numeric aggregation | ✗ (absent) | — | `awk` or `python3` (both present) |
| `LIBVA_TRACE` | Optional deep diagnostics (not required this phase) | ✓ | — | — |

**Missing dependencies with no fallback:**
- GuC/HuC firmware version (`dmesg`/debugfs) — must be reported as an honest, explicit gap in the REPRO-01 fingerprint deliverable, not silently omitted or faked.

**Missing dependencies with fallback:**
- `intel_gpu_top` live monitoring → `/proc/<pid>/fdinfo` (verified working)
- `fuser`/`lsof` → `/proc/*/fd` readlink loop (verified working)
- `bc` → `awk`/`python3` (both present)

## Security Domain

This phase has no network-facing surface, no authentication/session concerns, and processes only a local, already-trusted media file and locally-installed tools — most ASVS categories do not apply to a local diagnostic bash harness.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|----------------|---------|--------------------|
| V2 Authentication | No | N/A — no auth surface |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A — single local user, root-in-container |
| V5 Input Validation | Marginally | Quote all shell variables holding file paths (the source path and workdir contain no spaces in this environment, but scene/offset parameters are fixed constants from the handoff, not user input — still, always double-quote `"$SRC"`/`"$W/..."` in every command, confirmed necessary/sufficient in this session) |
| V6 Cryptography | No | N/A — `md5sum` used here only for determinism-comparison (non-adversarial), not a security control |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|-----------------------|
| Accidental write to `/data` (source corruption) via an unquoted or mistyped path | Tampering | All output paths are hardcoded to the `scratch/repro/` workdir; never construct an output path by concatenating with `/data` even conditionally (D-09, already a locked decision) |
| Shell word-splitting on paths with spaces | Tampering (unintended file targets) | Always double-quote path variables — verified necessary/sufficient in every command in this research session |

## Sources

### Primary (HIGH confidence — directly executed in this session)
- Direct `Bash` tool invocations against the real environment: `qsvencc --version`/`--check-features`, `ffmpeg -version`/`-encoders`/`-filters`/`-h encoder=av1_qsv`/`-h decoder=h264_qsv`, `vainfo`, `uname -r`, `readlink`/`lspci`/sysfs probes, `dmesg` (confirmed blocked), `mount -t debugfs` (confirmed blocked), `capsh --print`, `intel_gpu_top -L` and live mode (confirmed crash), full isolated + 3-way-concurrent qsvencc encodes against the real `/data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv`, full isolated + concurrent ffmpeg `av1_qsv` control encodes, frame extraction and PSNR computation on both synthetic and real corrupted/clean frames, md5-determinism check, `/proc/*/fd` and `/proc/<pid>/fdinfo` exclusivity/diagnostics checks.
- `PROJECT.md` (repo root handoff) — §3, §4, §5, §6, §9, §10 — prior-session findings, cross-checked against this session's live reproduction.
- `.planning/phases/01-harness-control-environment-fingerprinting/01-CONTEXT.md` — locked decisions D-01..D-09.
- `.planning/REQUIREMENTS.md` — REPRO-01..05.

### Secondary (MEDIUM confidence)
- `.planning/research/STACK.md`, `.planning/research/PITFALLS.md`, `.planning/research/ARCHITECTURE.md` — prior research pass for this milestone; largely corroborated by this session's live verification, with the GuC/HuC and intel_gpu_top availability gaps as the notable environment-specific corrections.

### Tertiary (LOW confidence)
- None used for load-bearing claims in this document — everything above was either directly executed or sourced from this project's own prior-session artifacts.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every tool/version directly queried in this session
- Architecture: HIGH — harness shape directly built and run end-to-end (reference, concurrent, control, extraction, PSNR) in this session
- Pitfalls: HIGH — `dmesg`/debugfs/intel_gpu_top/fuser/lsof gaps are directly observed environment facts, not inferred

**Research date:** 2026-07-23
**Valid until:** This environment's tool versions and permission model are unlikely to drift within the milestone's timeframe; treat as valid for the remainder of this investigation (all 5 phases), re-verify only if the container image or GPU firmware changes.
