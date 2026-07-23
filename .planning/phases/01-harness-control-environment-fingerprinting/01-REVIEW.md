---
phase: 01-harness-control-environment-fingerprinting
reviewed: 2026-07-23T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - scratch/repro/harness.sh
  - scratch/repro/lib.sh
findings:
  critical: 1
  warning: 10
  info: 3
  total: 14
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-07-23
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Reviewed the two-file bash reproduction/measurement harness (`harness.sh` + `lib.sh`)
for the QSV concurrent-encode corruption bug. The scripts are unusually well
documented and the `set -e` policy, GPU-exclusivity gating, timeout handling, and
Wilson-CI statistics are largely sound. However, the core measurement path has a
**BLOCKER-class soundness defect**: a *failed* PSNR measurement (missing/truncated
test frame, dead ffmpeg, missing reference) is silently classified as **clean**
(`corrupt=0`). For a corruption-*detection* instrument this inverts the safe
default and can mask the exact bug being measured — the more catastrophically an
output is corrupted (frame extraction fails entirely), the more likely it is scored
clean. Several WARNING-level robustness and measurement-completeness issues follow
(orphaned background encodes on interrupt, a vacuous `N_actual` metric, background
ffmpeg without `-nostdin`, control immunity PSNR-checked for only 1 of 3 scenes,
missing preflight for the required reference artifacts, and a post-measurement
exclusivity race that can permanently starve 928/1129 reference generation).

## Critical Issues

### CR-01: Failed/empty PSNR measurement is silently classified as CLEAN (false negatives mask the bug)

**File:** `scratch/repro/harness.sh:259-278`, `366-368`, `391-393`
**Issue:**
`psnr_of()` runs ffmpeg with no error check (line 261), then `awk` over the stats
file (line 263). If the psnr stage fails — because the test frame `-i "$test_png"`
was never produced, the reference PNG is missing, or ffmpeg errored — the stats file
is empty/absent and `psnr_of` emits an **empty string** to stdout. That empty value
flows into `classify_corrupt()`:

```bash
if [[ "$p" == "inf" || -z "$p" ]]; then
  echo 0            # <-- empty => "clean"
```

Compounding this, the frame-extraction ffmpeg at line 366 has **no error check**:
```bash
ffmpeg -y -i "$obu" -vf "select='eq(n\,$off)'" ... "$test_png" ...
psnr_db[$scene]="$(psnr_of "$test_png" "$ref_png" "$statsfile")"
```
So if a concurrent encode produced a truncated/broken `.obu` (the strongest possible
corruption signal), frame extraction fails, `test_png` is absent, `psnr_of` returns
empty, and the row is emitted as `status=OK, psnr_db=, corrupt=0` — recorded as a
clean sample. This directly biases the baseline corruption fraction *downward* and
defeats the harness's stated purpose (D-04 detection).

Note the asymmetry: the control path (line 397) treats an empty psnr conservatively
(`p+0 >= 30` is false → `CONTROL_INVALID`), which is the correct direction. Only the
*measurement* side fails open.

**Fix:** Make measurement failures an explicit distinct outcome, never `clean`.
```bash
# in cmd_run_iter, guard extraction and measurement:
if ! ffmpeg -y -nostdin -i "$obu" -vf "select='eq(n\,$off)'" -vsync 0 \
     -frames:v 1 "$test_png" -hide_banner -loglevel error || [[ ! -s "$test_png" ]]; then
  psnr_db[$scene]="NA"; corrupt[$scene]="NA"      # emit MEASURE_FAILURE, exclude from denominator
  continue
fi
raw="$(psnr_of "$test_png" "$ref_png" "$statsfile")"
if [[ -z "$raw" ]]; then
  psnr_db[$scene]="NA"; corrupt[$scene]="NA"      # measurement failed -> not "clean"
else
  psnr_db[$scene]="$raw"; corrupt[$scene]="$(classify_corrupt "$raw")"
fi
```
And in `classify_corrupt`, only `inf` should map to `0`; an empty argument should be
an error/`NA`, never `0`.

## Warnings

### WR-01: No trap — an interrupted iteration orphans background encodes on the GPU

**File:** `scratch/repro/harness.sh:308-319`, `374-382`; `scratch/repro/lib.sh:81-91`
**Issue:** The 3-way qsvencc measurement and the 3-way control each launch three
background jobs and only `cleanup_gpu_procs` at the *end* of `cmd_run_iter` reclaims
them. There is no `trap ... INT TERM EXIT`. A Ctrl-C (or any mid-iteration failure
under `set -u`) leaves qsvencc/ffmpeg processes bound to `renderD128`, which then
trips the next run's exclusivity gate — the very contamination the harness works hard
to avoid elsewhere.
**Fix:** Install a cleanup trap that kills known background PIDs:
```bash
trap 'cleanup_gpu_procs' INT TERM
# and track/kill $p1 $p2 $p3 / $cp1 $cp2 $cp3 explicitly on early exit
```

### WR-02: `n_actual` is incremented on every loop pass and therefore always equals `n_requested`

**File:** `scratch/repro/harness.sh:582-614`
**Issue:** Both branches of the loop body increment `n_actual` exactly once (line 605
in the not-idle/continue branch, line 613 in the normal branch). There is no path
through the loop that does *not* increment it, so `n_actual == n_requested` for every
run. The summary presents `N_requested` vs `N_actual` "with exclusion breakdown"
(lines 502-505) as if they can diverge, but they never do — the distinction is
vacuous and misleading. Worse, `control_invalid/n_actual` (line 540) uses this count
as a denominator even though iterations where `run_iter` produced *no* `result.csv`
(line 610 guard fails) still incremented `n_actual`, so the denominator can exceed the
number of rows actually in `report.csv`.
**Fix:** Define `n_actual` as iterations that produced usable rows, e.g. only
increment inside the `if [[ -f .../result.csv ]]` block, and count the contaminated
skip separately — or drop the metric and derive all counts in the Python summary from
the CSV (which already tallies statuses).

### WR-03: Background ffmpeg encodes run without `-nostdin`

**File:** `scratch/repro/harness.sh:183` (via `374-378`)
**Issue:** `ctrl_encode` launches ffmpeg, and it is invoked as three concurrent
background jobs (lines 374-378) with stdin left attached to the terminal. ffmpeg reads
keyboard commands from stdin by default; multiple backgrounded ffmpeg instances
sharing a tty can contend for/consume stdin and put the terminal into an odd state,
and a backgrounded ffmpeg reading EOF/garbage can exit early. Scripts that background
ffmpeg should always pass `-nostdin`.
**Fix:** Add `-nostdin` to the ffmpeg invocation in `ctrl_encode` (and to the
inline extraction ffmpegs at lines 153, 167, 249, 366, 391 for good measure), or
redirect stdin: `run_encode "$logfile" ffmpeg -nostdin ...`.

### WR-04: Control immunity is PSNR-validated for scene 923 only; 928/1129 controls are exit-code-checked but never compared

**File:** `scratch/repro/harness.sh:374-398`; reference at `160-171`
**Issue:** All three control encodes run (cp1/cp2/cp3) and their exit codes gate
`control_clean`, but only scene 923's control frame is PSNR-compared against a control
reference (`ffref_299.png`). No control reference PNG is ever generated for 928/1129
(only line 168 creates `ffref_299.png`). So the claim "ffmpeg av1_qsv is immune under
its own 3-way concurrency" is PSNR-substantiated for one scene and merely
"didn't crash" for the other two. If av1_qsv corruption were scene-dependent, the
control could pass while silently corrupting 928/1129, and every qsvencc finding for
those scenes would still be validated against an unverified control.
**Fix:** Either generate control references for 928/1129 and PSNR-check all three
control frames before setting `control_clean`, or document explicitly that the control
gate is 923-only and scope the CONTROL_INVALID invalidation to scene 923.

### WR-05: `run-batch`/`run-iter` do not preflight the required reference artifacts — a batch run before `reference` silently yields all CONTROL_INVALID

**File:** `scratch/repro/harness.sh:299-421`, `565-618`
**Issue:** `cmd_run_iter` depends on `$W/control_reference/ffref_299.png` (line 393)
and the qsvencc references. `cmd_run_batch` never checks these exist before looping.
If an operator runs `run-batch` without first running `reference`, the control PSNR
comparison at line 393 fails (missing reference PNG → empty psnr → `control_clean=0`),
so *every* iteration is marked `CONTROL_INVALID` and the entire (potentially hours-long)
batch is wasted with no useful data and no early, loud error.
**Fix:** Preflight in `cmd_run_batch` before the loop:
```bash
[[ -f "$W/control_reference/ffref_299.png" && -f "$W/reference/frame299_ref.png" ]] \
  || { echo "ABORT: run 'reference' first (missing reference artifacts)" >&2; exit 1; }
```

### WR-06: Post-measurement exclusivity race can permanently starve 928/1129 reference generation

**File:** `scratch/repro/harness.sh:343-345`, `237-252`
**Issue:** In `cmd_run_iter`, `ensure_scene_reference` runs *after* the 3-way
measurement `wait` but *before* `cleanup_gpu_procs` (which only runs at line 417). It
calls `require_gpu_exclusive`, but the harness's own comments (lines 586-587, 42-45)
acknowledge VA-surface/`renderD128` release is async to process exit. So immediately
after the measurement encodes exit, the GPU may still show clients, `require_gpu_exclusive`
fails, `ref_fail=1`, and the whole iteration is scored `EXEC_FAILURE`. Because 928/1129
references are generated lazily here and this race recurs every iteration, those
references may *never* get generated, converting the entire batch to EXEC_FAILURE.
**Fix:** Generate all three references up front in `cmd_reference` (mirroring 923),
or add the same idle-wait/retry loop used in `cmd_run_batch` before calling
`require_gpu_exclusive` inside `ensure_scene_reference`.

### WR-07: PID-reuse TOCTOU in `cleanup_gpu_procs` — `kill -9` on a recycled PID

**File:** `scratch/repro/lib.sh:81-91`
**Issue:** `gpu_clients` captures `PID` + cmdline, then `cleanup_gpu_procs` re-parses
the string and `kill -9`s the PID if the *captured* cmdline matched qsvencc/ffmpeg.
Between listing and killing, the PID can be reaped and reused by an unrelated process,
which would then be SIGKILLed. The cmdline check happens against the stale captured
string, not the process at kill time. Low probability in a container, but it is a real
correctness/safety race, and `kill -9` gives the target no chance to release GPU state
cleanly (aggravating the async-release problem this function exists to solve).
**Fix:** Re-verify the cmdline at kill time and prefer graceful termination first:
```bash
grep -qaE 'qsvencc|ffmpeg' "/proc/$pid/cmdline" 2>/dev/null || continue
kill "$pid" 2>/dev/null; sleep 0.2; kill -9 "$pid" 2>/dev/null || true
```

### WR-08: `n_requested` is not validated numeric — non-numeric input silently no-ops the loop and crashes the Python summary

**File:** `scratch/repro/harness.sh:565`, `583`, `435-439`
**Issue:** `run-batch foo` passes `foo` to `seq 1 "$n_requested"` (produces nothing →
zero iterations, empty report) and then to the Python summary via `N_REQUESTED=foo`,
where `int(os.environ["N_REQUESTED"])` (line 439) raises `ValueError` and aborts with a
traceback rather than a clean usage error.
**Fix:** Validate at entry: `[[ "$n_requested" =~ ^[1-9][0-9]*$ ]] || { echo "N must be a positive integer" >&2; exit 2; }`.

### WR-09: `timeout` has no `--kill-after`, and the inline PSNR/extraction ffmpegs run with no timeout at all

**File:** `scratch/repro/lib.sh:68-72`; `scratch/repro/harness.sh:261`, `366`, `391`
**Issue:** `run_encode` uses `timeout "${ENCODE_TIMEOUT}" "$@"` with no `-k`. If an
encode ignores SIGTERM (a hung GPU job is a plausible failure mode here), `timeout`
delivers SIGTERM and then waits indefinitely, so the "timeout" protection never
force-kills. Separately, the frame-extraction and PSNR ffmpeg calls (lines 261, 366,
391) run entirely outside `run_encode`/`timeout`; a hang there blocks the whole harness
with no bound.
**Fix:** Use `timeout -k 10 "${ENCODE_TIMEOUT}" "$@"`, and route the inline ffmpeg
extraction/PSNR calls through `run_encode` (or wrap them in `timeout`) so no stage can
hang unboundedly.

### WR-10: md5 determinism check treats empty==empty as a pass

**File:** `scratch/repro/harness.sh:128-135`
**Issue:** `md5_a` / `md5_b` are captured through a pipe (`md5sum ... | awk ...`). With
only `set -u` (no `pipefail`), if `md5sum` fails or is unavailable, both variables
become empty strings and `[[ "$md5_a" != "$md5_b" ]]` is false, so the determinism gate
(D-05, a hard precondition) reports "OK" on two empty hashes. The upstream `|| exit 1`
guards on the encodes make this unlikely, but the gate itself should not pass on empty.
This is the same fail-open pattern as CR-01.
**Fix:** Assert non-empty and equal:
```bash
[[ -n "$md5_a" && "$md5_a" == "$md5_b" ]] || { echo "ABORT: determinism check invalid ($md5_a / $md5_b)" >&2; exit 1; }
```

## Info

### IN-01: `gpu_clients` uses non-local loop/temp variables (CONVENTION)

**File:** `scratch/repro/lib.sh:38-45`
**Issue:** `t`, `pidfd`, and `pid` are assigned without `local`, leaking into the
global namespace. The convention elsewhere in these files is to declare function
locals (`cmd_run_iter`, `cleanup_gpu_procs`, etc. all use `local`). Callers currently
invoke `gpu_clients` via command substitution/process substitution (subshells) so the
leak is masked, but the deviation is real and fragile if a future caller invokes it
directly.
**Fix:** `local t pidfd pid` at the top of `gpu_clients`.

### IN-02: Scene lookup `case` statements have no default arm (CONVENTION)

**File:** `scratch/repro/harness.sh:194-228`
**Issue:** `scene_seek`/`scene_trim`/`scene_offset`/`scene_ref_obu`/`scene_ref_png`
silently echo an empty string for an unknown scene id. Under `set -u` this is not an
error, so a typo'd scene would propagate an empty seek/trim/offset into an encode
rather than failing loudly. Convention in this codebase (e.g. the `main` dispatcher at
640-644) is to have an explicit `*)` error arm.
**Fix:** Add `*) echo "unknown scene: $1" >&2; return 1 ;;` to each lookup.

### IN-03: Multi-match globs / multi-line greps can embed newlines into single-line fingerprint fields (CONVENTION)

**File:** `scratch/repro/harness.sh:92-95`, `101-103`
**Issue:** `cat /sys/bus/pci/drivers/i915/*/vendor` (and `.../device`) can match more
than one PCI device, and `dmesg | grep -iE 'guc|huc'` typically returns many lines.
These multi-line values are then interpolated into what are documented as single-line
fields (`pci_id: ${pci_vendor}:${pci_device}`, `guc_huc: ...`), producing a malformed
fingerprint that is harder to parse and to compare against the affected-host baseline.
**Fix:** Collapse to a single line, e.g. `... | head -n1` for the PCI ids and
`... | tail -n1` (or a count/summary) for the guc/huc lines.

---

_Reviewed: 2026-07-23_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
