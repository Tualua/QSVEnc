# Pitfalls Research

**Domain:** Non-deterministic (~33-65%), hardware/kernel-level, concurrency-triggered silent GPU frame-corruption investigation (Intel QSV AV1 encode, Arc A380)
**Researched:** 2026-07-23
**Confidence:** MEDIUM-HIGH (grounded in this project's own exhausted-negatives log at `PROJECT.md` §5-9, cross-checked against public i915/Xe driver-support facts and standard statistical practice for stochastic bug validation)

## Critical Pitfalls

### Pitfall 1: Measurement contamination from concurrent GPU experiments

**What goes wrong:**
Running two "unrelated" experiments (e.g. the reproducer harness for a validation pass, and a separate throughput benchmark, or two agents/terminals both poking `/dev/dri/renderD128`) at the same time on the single shared Arc A380 changes the very thing being measured. The bug is defined by *cross-session GPU concurrency* — so any extra concurrent GPU load (your own stray process, a leftover `qsvencc` from a previous crashed run, a monitoring tool sampling `intel_gpu_top`, a background transcode) becomes an uncontrolled 4th, 5th, Nth session. It can silently raise the observed corruption rate (looks worse than reality), lower it (GPU contention changes scheduling/timing enough to mask the race), or contaminate a "control" run that was supposed to be single-session (0% baseline) and now isn't actually isolated.

**Why it happens:**
The natural instinct when investigating a slow, iterative, hardware-bound bug is to parallelize your own investigation to save wall-clock time — run the ffmpeg control in one shell while the qsvencc repro loop runs in another, or kick off the "next" experiment before confirming the current one's process tree is fully dead. On a CPU-bound bug this is harmless; on a GPU-scheduler race it is not, because the corruption's trigger condition (≥2 concurrent VA contexts contending for GEM/BO handles) is exactly what your "parallel productivity" recreates by accident.

**How to avoid:**
- Enforce **strict sequential execution** for every phase of this investigation: one GPU-touching command running at a time, full `wait` and explicit process-tree check (`pgrep -f qsvencc`, `fuser /dev/dri/renderD128`) before starting the next, even across unrelated experiments.
- Before every "isolated / control" run, positively verify no other GPU client is attached (`fuser -v /dev/dri/renderD128`, or `intel_gpu_top -L` if available) rather than assuming a prior `&`/`wait` block cleaned up.
- If two agents or shells are working in the same environment, treat `/dev/dri/renderD128` as a single-owner lock — do not run this investigation's harness in parallel with any other GPU-touching task in this environment, including unrelated builds that might invoke QSV `--check-features`.
- Log a timestamped "GPU exclusivity" note at the start/end of every measurement run so a later reviewer can audit for overlap.

**Warning signs:**
- Corruption rate for the "control" (single-session) case is not a clean 0% — any non-zero rate on isolated encode is the canary that something else was using the GPU concurrently.
- Frequency numbers vary wildly between "identical" runs of the 3-way harness (e.g. 20% one run, 70% the next) with no code/config change — suggests uncontrolled extra concurrency (or thermal/scheduling noise) rather than true measurement of the documented 33-65% baseline.
- Wall-clock durations for supposedly-identical runs differ by more than GPU-clock-boost noise would explain.

**Phase to address:**
Reproduction/baseline phase (first phase touching the GPU) — must be established as a hard operating rule before any other phase runs, since it invalidates data retroactively if violated later too.

---

### Pitfall 2: Declaring "fixed" on too few iterations of a stochastic 33-65% bug

**What goes wrong:**
A lever is tried (e.g. `--async-depth 1`, a driver bump, later `--avsw`, or a host-side change), the harness is run 3-5 times, all come back clean, and the investigation records "fixed" or "0% — confirmed clean." Given the baseline rate is 33-65% *per run* (meaning per-run at least one of the 3 concurrent sessions triggers at least one bad frame), a handful of clean runs is statistically indistinguishable from a modest but real reduction (e.g. residual 5-10% rate) — or even from no real change plus favorable random luck. This is exactly how this project already burned cycles: `--async-depth 1` initially looked promising and needed 15 runs (7/15 bad) to correctly conclude "does not fix."

**Why it happens:**
Iteration is expensive (each run touches real HW encode + decode, real I/O, real PSNR extraction), so there's schedule pressure to stop as soon as results "look" clean. Human/agent pattern-matching treats "3 zeros in a row" as strong evidence, but for a Bernoulli process with a baseline rate this high, that is very weak evidence.

**How to avoid:**
- Apply the **rule-of-three** for zero-event confidence intervals: observing 0 failures in *n* independent trials bounds the true failure rate's 95% upper confidence limit at roughly `3/n`. To claim a lever plausibly reduces the ~33-65% baseline down to "under ~5% residual" with 95% confidence, you need **n ≥ 60 clean runs** with zero failures. To distinguish "truly 0%" (i.e. rule out even a ~1% residual) you need **n ≥ 300**. The prior session's own protocol (15-20 iterations, §4) is calibrated to *detect* the baseline rate (33-65% shows up reliably in 15-20 runs) but is **not** calibrated to *confirm a fix* — that requires an order of magnitude more runs than detecting the original bug did.
- State the target confidence level *before* running the validation batch (e.g. "we will run N=60 to bound residual rate below 5%") rather than post-hoc deciding a sample felt convincing.
- Distinguish two different statistical tasks explicitly in the writeup: (a) "does X change the rate at all" (cheap — 15-20 runs can show a rate drop from 40% to under 10%), vs (b) "is X now clean / production-safe" (expensive — needs 60+ zero-failure runs).
- For workaround options already empirically validated in the prior session as "0/60" or "0/15" (§7), note the sample size next to every claim of cleanliness so the roadmap can tell which workarounds are well-validated (`--avsw` at 0/60) vs under-validated (`--gop-ref-dist 1` at only 0/15) and schedule top-up runs for the latter before recommending it as the default.

**Warning signs:**
- Any "fixed" or "clean" conclusion whose supporting evidence is fewer than ~60 zero-failure runs.
- A validation batch stopped early because early runs "looked good" rather than because a pre-declared N was reached.
- Comparing two levers' cleanliness using different sample sizes (e.g. "Lever A: 0/5, Lever B: 3/15" — Lever A is not demonstrated safer, it's under-sampled).

**Phase to address:**
Every phase that tests a lever and reports a rate (host-side lever testing phase, workaround validation phase) — the roadmap should bake a minimum-N requirement into each experiment's "done" criteria, not leave sample size to run-time judgment.

---

### Pitfall 3: False isolation — changing multiple variables and losing attribution

**What goes wrong:**
A single build/test cycle changes more than one variable at once — e.g. switching the Arc driver from i915 to Xe *and* updating GuC/HuC firmware *and* bumping a qsvencc flag in the same pass — then observes a changed corruption rate. Now it's impossible to say which change (or which combination) caused the effect. If the result is "still corrupts," you cannot rule out that one of the two changes alone would have fixed it while the other reintroduced the bug or masked the fix. If the result is "clean," you cannot tell the roadmap/user which single lever to actually flip in production, and worse, you may recommend a fix that's actually two entangled host changes that are hard for the user to reproduce or that carry other regressions (e.g. Xe driver on Alchemist currently lacks HuC support needed for hardware encode at all — see Pitfall 6 — so "Xe + new firmware" together could look "clean" merely because AV1 HW encode silently failed to engage, not because concurrency was fixed).
This project's own §5 negative-result log is itself a partial victim of this trap already avoided correctly (each patch was isolated one at a time) — the risk is in *not repeating that discipline* for the new host-side levers in §6, which are more tempting to bundle since they require slow host reconfiguration/reboots.

**Why it happens:**
Host-side levers (kernel, driver, firmware) are expensive to change (may require reboot, root, or reflashing firmware) so there's strong incentive to "batch" several plausible fixes into one reboot cycle rather than pay the cost N times.

**How to avoid:**
- One variable per build/reboot cycle, full stop — exactly the discipline the prior session already used for the qsvencc source patches (§5 table: one row per single change).
- Before changing a second variable, first re-run (and archive) the control (ffmpeg `av1_qsv`) and the qsvencc repro at the *current* single-variable state, so each step in the chain has its own labeled before/after pair.
- If a host-side change requires a reboot (kernel/firmware), treat that reboot as the expensive resource to budget for and plan the *order* of single-variable experiments up front (e.g. cheapest/most-diagnostic first) rather than deciding ad hoc mid-investigation.
- When reporting a fix, always report it as "changing X (and only X) from baseline A to state B changed the rate from R1 to R2," never as "after updating the driver and firmware, it's fixed."

**Warning signs:**
- A changelog/commit/experiment note that lists two or more host-side changes applied between the last-known-bad measurement and the next measurement.
- "It's fixed now" conclusions that arrive right after a host reboot with no isolated single-variable measurement in between.
- Inability to answer "if I only had done half of what we just did, would it still be fixed?"

**Phase to address:**
Host-side lever phase (i915→Xe, GuC/HuC firmware, kernel update) — this is the phase most likely to face schedule pressure to bundle changes since each requires a reboot; the roadmap should explicitly budget one reboot per lever.

---

### Pitfall 4: Forgetting the ffmpeg av1_qsv immune control, so a harness break looks like a fix (or vice versa)

**What goes wrong:**
The single most important sanity check this project has is that **ffmpeg `av1_qsv` with an identical HW-decode + P010 + B-pyramid combo is immune (35/35 clean)** under the same concurrency that corrupts qsvencc. This proves the driver/kernel *can* isolate correctly and that the bug is specific to qsvencc's surface-pooling behavior, not an unavoidable property of the hardware. If a later experiment (new environment, new kernel, Xe driver, new firmware) is run *without* re-running this control, two failure modes become invisible:
1. **Environment/harness regression masquerading as "bug reproduced" or "bug fixed":** if the new environment's harness itself is broken (wrong seek offsets after a media-stack change, PNG extraction failing silently, wrong reference frame), qsvencc might show 0% not because the bug is fixed but because the *measurement* is broken — and you'd only know because the control would also read as broken/wrong.
2. **A host-side fix could quietly break the control instead of fixing qsvencc:** e.g. if a kernel/driver update coincidentally starts corrupting the ffmpeg path too (regression) while qsvencc still corrupts, comparing only qsvencc results loses the signal that *the environment itself changed in a bad way*, not that qsvencc specifically got fixed or not.

**Why it happens:**
The control feels like "extra work" once the harness is trusted from the prior session — but the prior session's trust was earned in a *different* environment/host. Every new environment (new container, new driver stack, new kernel, new host lever) invalidates that trust and requires re-earning it.

**How to avoid:**
- Make the ffmpeg `av1_qsv` control a **mandatory sibling run** for every measurement of qsvencc under concurrency, in every phase, in every environment — never run the qsvencc harness alone.
- Treat "control is not 35/35 clean (or equivalent zero-failure sample) in this environment" as a stop condition: it means the harness/environment itself changed and must be re-validated before trusting *any* qsvencc-side conclusion, positive or negative.
- When reporting results, always report the pair: "qsvencc rate: X%, control (av1_qsv) rate: Y%" — never just X% alone.
- Re-run the control immediately after any host-side lever change (Xe driver, firmware, kernel), even if the primary interest is qsvencc — a lever that breaks the control is itself an important, reportable finding (e.g. "Xe driver corrupts even the previously-immune ffmpeg path" would be a major new discovery, not noise to discard).

**Warning signs:**
- Any experiment report that mentions only the qsvencc corruption rate with no corresponding control number for that same environment/run.
- A "the bug doesn't reproduce here" conclusion in a new environment where the control was never actually re-run to confirm the harness still works at all.

**Phase to address:**
Every phase from reproduction onward — this should be a standing checklist item / gate baked into the phase's "definition of done," not a one-time step in Phase 1.

---

### Pitfall 5: Trusting frame-count / `count_frames` as correctness — the silent-pass trap

**What goes wrong:**
This is the entire premise of the bug: frame *count* is preserved while frame *content* is silently swapped from another concurrent session. Any validation step in this investigation that checks only "did the output have the right number of frames" or "did the encode complete without error" will report a corrupted run as a pass. This trap can re-appear at multiple levels in this investigation itself, not just in production `enpipe`: e.g. if a future automated regression-test harness for the fix only asserts frame count/duration/exit-code, it will falsely certify a still-broken build as fixed. Likewise, any workaround comparison (§7 options A-E) that scores "success" by output size or duration parity alone, without content verification, would silently miss a residual corruption rate.

**Why it happens:**
Frame count and exit code are the cheap, fast, obvious things to check, and for the overwhelming majority of encoding bugs they *are* sufficient (most bugs are loud: crashes, wrong duration, garbled/greenscreen visible on any spot-check). This bug is specifically the rare kind engineered to defeat that cheap check, so instinctively reaching for the cheap check first is a trap by design, not by carelessness.

**How to avoid:**
- Every validation step in every phase of this investigation must extract and compare **pixel content** at the known hotspot offsets (299/299/96 for scenes 923/1129/928 respectively, per the reproducer table) against the known-clean reference, using PSNR (or VMAF) — never frame count alone.
- When designing the defense-in-depth content-verification gate deliverable (the "can never ship silently again" requirement), explicitly design it to catch a *single swapped frame in tens of thousands*, not just detect gross corruption — the historical corrupted shipped encode had exactly one bad frame per multi-hundred-thousand-frame file (e.g. frame 39121 of 171390), so any full-file check needs per-frame (or dense-sampled) granularity, not average/aggregate metrics that a single outlier frame can vanish into (mean PSNR over 171k frames barely moves from one 15.74 dB frame).
- For the gate design specifically: prefer a **minimum-per-frame** or **percentile-based** VMAF/PSNR score (e.g. "worst 0.01th percentile frame score") over a mean/average score, since averages are exactly what let a single-frame swap hide silently in a long file.

**Warning signs:**
- Any pass/fail criterion in the investigation's own tooling that references only frame count, duration, or exit code.
- A validation report presenting only mean/aggregate quality scores for long files (mean PSNR, mean VMAF) with no per-frame minimum reported.
- Reusing `enpipe`'s existing `count_frames` invariant as the acceptance test for a candidate fix, instead of re-deriving a content-level test.

**Phase to address:**
Applies to every phase that measures "is this run corrupted or clean," and is the explicit deliverable of the defense-in-depth gate design phase — that phase's design must itself avoid the trap it's meant to close.

---

### Pitfall 6: `--psnr`/`--ssim` OpenCL dependency and VMAF CSV parsing gotchas silently producing wrong numbers

**What goes wrong:**
Two distinct measurement-tooling traps, both already identified in this project's own gotchas (§9) and worth treating as standing procedural rules rather than one-off notes:
1. **`qsvencc --psnr`/`--ssim` require an OpenCL ICD** that is not reliably available in this stack (Intel ICD unavailable on this base). If invoked anyway, it may either hard-fail (loud, safe) or — more dangerously in some driver/build combinations — silently fall back or report a metric of 0/garbage that could be misread as a real corrupted-frame signal. Any content check for this investigation must go through **external ffmpeg PSNR/VMAF** on extracted frames, never `qsvencc`'s built-in flags.
2. **VMAF CSV output on a ru-locale (or any non-C locale) host** uses TAB as delimiter and comma as decimal separator, and has a decoy field: the VMAF score is field 16, but field 17 is a duplicate frame-number column, not a second score. Naive parsing with `$NF` (last field), a comma-splitting parser, or an assumption of "the last numeric column is the score" will silently extract the wrong number — most dangerously, a plausible-looking wrong number rather than an obvious error.

**Why it happens:**
Locale-dependent formatting is invisible until you diff raw output byte-for-byte; a script written and tested once (in one locale, with one libvmaf field layout) then reused across a differently-configured environment will "work" (produce a number) while being subtly wrong. OpenCL absence is easy to miss because the flag exists and may not error clearly in every version.

**How to avoid:**
- Standardize on **one fixed external command** for all PSNR/VMAF extraction in this investigation (documented, reused verbatim across phases), rather than re-deriving ad hoc ffmpeg invocations per experiment — reduces the chance of reintroducing the field/locale bug.
- Force `LC_ALL=C` (or explicit `LC_NUMERIC=C`) for any process that emits or parses numeric CSV/log output in this investigation, to eliminate the comma-decimal / locale-delimiter class of bug entirely rather than working around it in a parser.
- When parsing VMAF CSV, reference the field by **header name**, not positional index or `$NF`, if the tool supports header-based lookup; if positional parsing is unavoidable, hardcode "field 16 = vmaf score, field 17 = frame-number duplicate, do not use" as a code comment at the parse site.
- Never invoke `qsvencc --psnr`/`--ssim` in this environment; treat it as a known-broken/unavailable path (already established) and remove it from any script template used going forward.
- Spot-check the very first extracted metric value in every new environment/tooling change by eyeballing the raw CSV line before trusting the parser's output.

**Warning signs:**
- A PSNR/VMAF number that is suspiciously "clean" (e.g. always the same value, or an oddly round number) — could indicate the parser silently grabbed the wrong field or a zero/error value.
- Any script producing decimal numbers with a comma instead of a period, or numbers that don't match a manual `ffprobe`/spot-check of the same file.
- `qsvencc --psnr` output present in any script or log for this investigation at all — its mere presence is the warning sign, since it should never be invoked in this environment.

**Phase to address:**
Reproduction/harness-setup phase (the metrics-extraction tooling should be built once, correctly, and reused) — but the discipline (`LC_ALL=C`, header-based field lookup) should be re-verified any time the harness moves to a new environment/container.

---

### Pitfall 7: Assuming a container-side driver/userspace update changes host kernel behavior

**What goes wrong:**
This project's own history already contains this exact mistake and its correction: an earlier attempt updated the *userspace* media stack inside the container (iHD 25.2.3 → 26.2.2, vpl-gpu-rt, libva 2.23) — even rebuilding the container natively on a different base image (`intel/dlstreamer`) — and observed **zero change** in corruption rate/signature, which is the expected and correct result once you recognize the actual root cause sits in `drm/i915` in the **host kernel**, which a container cannot touch. The pitfall for the *current* investigation is repeating a variant of this mistake: assuming that switching container base images, updating a driver package inside the container, or even rebuilding against a newer libvpl/oneVPL release will have any effect on kernel-level GEM/BO isolation behavior. Any host-kernel-rooted bug is invisible to purely-in-container changes, and re-litigating this (a 4th "let's try a newer userspace stack" cycle) would burn a build cycle for a result that's already known.
The corollary trap is the reverse assumption: believing that *because* userspace stack changes had no effect, *no* software-side change could possibly help — this is also wrong, since correctness-preserving workarounds like `--avsw` (moving decode off the HW/VA path entirely) or `--jobs 1` (removing concurrency) are software-side and *do* work, precisely because they change the *trigger conditions* (the VA-pool/concurrency structure) rather than trying to patch the kernel's isolation from outside it.

**Why it happens:**
Container rebuilds are cheap and fast compared to host reboots/kernel changes, so there's a strong temptation to "try the easy thing first, again" even after it's been tried and shown ineffective — especially across a session boundary where the new investigator may not have fully internalized *why* the prior attempt failed (i.e., that the root cause is provably kernel-side, established via the deliberate userspace-only-swap experiment).

**How to avoid:**
- Before proposing any change, classify it explicitly as **kernel/host-side** vs **container/userspace-side** vs **application/qsvencc-flag-side**, and check that classification against the already-established root-cause location (kernel) before spending a build cycle.
- Re-read §5 (exhausted negatives) and the "root cause is in host kernel" finding (§3) before proposing any new experiment, and require any new proposal to explain specifically why it would behave differently from the already-tried userspace stack swap, if it's also a userspace-only change.
- Distinguish "will this fix the kernel bug" (only host-kernel changes qualify — Xe driver switch, kernel version bump, GuC/HuC firmware) from "will this avoid triggering the kernel bug" (software workarounds that change trigger conditions — `--avsw`, `--jobs 1`, migrating to ffmpeg's per-component `AVHWFramesContext` model) — both are valid investigation branches but must not be conflated when reporting results.

**Warning signs:**
- A new proposal to "try updating iHD/vpl-gpu-rt/libva again" or "try a different container base image" without a specific hypothesis for why this attempt differs from the already-tried userspace swap.
- Confusing "software workaround that avoids the trigger" with "software fix for the kernel bug" in the final recommendation — these are different claims and must be labeled as such.

**Phase to address:**
Should be resolved by a phase-zero orientation check ("what's already been tried and why did it fail/succeed") before any new experiment phase begins; most relevant to gating the host-side lever phase from wasting cycles on re-tried userspace changes.

---

### Pitfall 8: Xe driver switch as an untested lever that can silently disable AV1 hardware encode entirely

**What goes wrong:**
Switching the Arc A380 (Alchemist/DG2) from the `i915` driver to the newer `Xe` driver via `i915.force_probe='!<devid>' xe.force_probe=<devid>` kernel parameters is listed in this project's own untried-levers list (§6) as "most promising" for its different BO/context isolation model. However, as of current kernel/driver support, **the experimental Xe driver lacks HuC firmware support for Arc Alchemist GPUs**, and HuC is required for hardware-accelerated video encode on this generation. This means a switch to Xe could easily cause qsvencc's HW-encode path (or oneVPL's initialization) to fail outright, fall back silently to a degraded/software path, or simply refuse the AV1 HW-encode feature — which could be misread as "0% corruption, bug fixed" when in fact the encode never engaged the code path being tested at all (see also Pitfall 3's entanglement risk: a "clean" Xe result with no HuC could just mean HW-encode silently didn't run).

**Why it happens:**
The Xe driver is actively being pushed as the future default and its documentation/CLI (`xe.force_probe`) exists and appears usable, giving a false impression of readiness; the HuC/encode-capability gap for Alchemist specifically is a narrower, easy-to-miss caveat buried in driver-support matrices rather than the top-line Xe feature announcements.

**How to avoid:**
- Before switching to Xe, explicitly verify (`qsvencc --check-features` or equivalent oneVPL feature query, plus `dmesg`/driver logs for HuC load status) that AV1 hardware encode is actually available and engaged under Xe on this specific Arc A380 — do not proceed to corruption-rate measurement until this is confirmed.
- Treat "Xe driver active" and "HW AV1 encode functioning under Xe" as two separate facts to verify, in that order — if the second fails, the lever is not viable and should be recorded as such (a negative result about driver readiness, not about the corruption bug) rather than silently abandoned or misreported as a fix.
- Since this is a kernel-boot-parameter-level host change (outside the container, per the Host boundary constraint), budget it as a single, careful, well-instrumented experiment rather than a quick toggle — confirm rollback path (`i915.force_probe` restoration) before attempting, so the host isn't left in a non-functional GPU state.
- Re-run the ffmpeg av1_qsv control (Pitfall 4) under Xe as well — if Xe breaks HW encode for the control too, that's strong independent confirmation the lever isn't viable in its current state on this hardware, without needing to touch qsvencc at all.

**Warning signs:**
- Corruption rate measurement under Xe returns 0% but so does *everything* — e.g. no PSNR-measurable frames extracted, `--check-features` reporting AV1 encode unavailable, unusually fast/small output files, or qsvencc erroring/falling back rather than completing normally.
- No explicit confirmation step for "HW encode actually ran" appears between "switched to Xe" and "corruption rate measured."

**Phase to address:**
Host-side lever testing phase — the Xe experiment specifically should have "confirm HW AV1 encode functions under Xe" as an explicit prerequisite gate before any corruption-rate run under Xe is trusted.

---

### Pitfall 9: Re-attempting the analytically-exhausted qsvencc surface-attribute/allocator patch line

**What goes wrong:**
§5 of this project's handoff documents three build cycles already spent on qsvencc source patches along the surface-attribute/allocator axis (P010 `rt_format` patch, `VASurfaceAttribUsageHint` variants encoder-only and role-based, `--async-depth 1`, `--disable-va`) — all inert or destructive (`--disable-va` segfaults 100%). The stated reasoning for why this line is exhausted is sound and specific: allocator pools are already process-local and separate, so there is no allocator-level pool-separation fix left to try, and the two surface-format levers (rt_format, usage-hint) have been shown not to affect the actual VA/kernel-level surface identity that's aliasing across processes. The pitfall is a future phase re-deriving a "new" variant of the same idea (e.g. a different `VASurfaceAttribPixelFormat` combination, a different hint value, a different `AsyncDepth`/pool-size tweak) because it wasn't the *exact* patch already tried, without recognizing it's the same analytical dead end.

**Why it happens:**
Source-patching qsvencc is the most "actionable-feeling" lever available (full source access, fast rebuild, no host/reboot cost) compared to host-kernel levers (slow, requires root/reboot) or workaround adoption (feels like "giving up" on a real fix) — so there's gravitational pull back toward it even after it's been reasoned out as unproductive, especially under time pressure or when a new agent picks up the investigation without absorbing why §5 concluded what it did.

**How to avoid:**
- Treat §5's conclusion as backed by the *mechanism*, not just the specific patches tried: the corruption is inter-process kernel/driver-level BO-handle aliasing under concurrent submission, which is categorically outside what surface-attribute hints or allocator pool-locality (already true) can fix from userspace. Any new patch proposal in this space should be required to explain what *mechanism* it changes that differs from "another surface-attribute/pool variant" before being attempted.
- Keep the Out of Scope entry in `.planning/PROJECT.md` ("Source-patching qsvencc along surface-attribute/allocator lines") visible and referenced at the start of any phase that touches qsvencc source, as a standing check against scope creep back into this dead end.
- If a genuinely new idea emerges in this space (e.g. something upstream driver-side, not qsvencc-side), route it to the "report upstream to drm/i915" track (per §6) rather than another local source-patch attempt.

**Warning signs:**
- Any new task/experiment description that involves modifying `qsv_allocator_va.cpp` or surface-attribute/rt_format/usage-hint code, without an explicit note on why it differs mechanistically from the three already-tried variants.
- Renewed build cycles against local qsvencc source changes when the active investigation focus should be host-side levers or workaround validation.

**Phase to address:**
Should be enforced as a standing scope guard across all phases (already captured in the project's Out of Scope section) — most relevant to gate at the start of any phase that involves touching QSVEnc source code.

---

### Pitfall 10: Over-investing in ffmpeg av1_qsv migration given DV/HDR regression risk, before it's actually needed

**What goes wrong:**
Option C (migrate `enpipe` fully to ffmpeg `av1_qsv`) is empirically the cleanest and fastest workaround (35/35 clean, full HW speed) — which makes it tempting to treat as "the real fix" and invest significant investigation time prototyping the migration (seek/trim reimplementation, Dolby Vision RPU passthrough, HDR10+ signaling, metrics). But this project's own scope explicitly flags this as risky specifically *because* DV/HDR passthrough is unverified for ffmpeg's av1_qsv path in this pipeline, and DV/HDR preservation is stated as a primary reason qsvencc was chosen for `enpipe` in the first place. Sinking investigation time into fully prototyping this migration — before confirming whether a cheaper, already-clean, feature-preserving option (`--avsw`, already 0/60 and confirmed to preserve 10-bit + B-pyramid + DV/HDR) is sufficient for the correctness-first recommendation — risks spending the bulk of the remaining investigation budget on the highest-risk, highest-effort option when a lower-risk option already satisfies the stated Core Value (correctness first, without necessarily sacrificing throughput or features).

**Why it happens:**
"Migrate to the tool that's provably immune" has an intuitive appeal as the most thorough, permanent-feeling fix, and 35/35 clean is a more satisfying number than "avoid the trigger condition" workarounds that can feel like papering over the bug. The investigation's own framing (§7) already flags this tension, but a future phase focused on "delivering the best fix" could still drift toward over-scoping the ffmpeg migration exploration past what's needed for a *recommendation* (the actual deliverable) into something resembling an implementation attempt.

**How to avoid:**
- Keep the deliverable boundary explicit and enforced: this project delivers a **recommendation** for `enpipe` (backed by measured throughput numbers in this environment), not an implemented migration — prototyping ffmpeg av1_qsv only as far as needed to validate/refresh the existing 35/35-clean and throughput claims, not as far as building a production DV/HDR-passthrough-verified replacement.
- When evaluating Option C, budget investigation time proportional to its role in the final recommendation: since `--avsw` (Option A) already satisfies correctness + feature-preservation and only costs throughput, Option C only needs enough investigation to (a) re-confirm its cleanliness/throughput numbers in *this* environment, and (b) characterize (not resolve) the DV/HDR risk qualitatively, so the user can make an informed tradeoff — not to fully de-risk it.
- Explicitly timebox any ffmpeg-migration prototyping and cut it off once "recommendation-grade" evidence exists, resisting the pull to "finish it properly" since finishing it properly is out of scope (the `enpipe` repo isn't even present in this checkout).

**Warning signs:**
- Work items appearing that resemble implementing DV RPU passthrough, HDR10+ signaling, or seek/trim logic *for ffmpeg* in this repo, rather than characterizing the risk for the recommendation.
- Time/budget spent validating Option C measurably exceeding time spent validating Option A (`--avsw`), when A is already the closer-to-done, lower-risk, feature-preserving candidate.

**Phase to address:**
Workaround-recommendation phase — should explicitly scope Option C evaluation as "characterize and re-confirm," not "prototype to completion," and should sequence Option A's throughput measurement first since it's the more likely correctness-first recommendation.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|--------------------|-----------------|------------------|
| Skipping the ffmpeg av1_qsv control on a "quick" experiment to save time | Faster iteration | Cannot distinguish harness break from real fix/no-fix; may need to redo the whole experiment | Never for any result that will be reported or acted on; only for a throwaway sanity poke you will discard |
| Running fewer than ~60 zero-failure iterations before calling a lever "clean" | Saves GPU-hours | False confidence in a fix that has a real ~5-10% residual rate, shipping a still-broken workaround | Acceptable only as a preliminary "does this even move the needle" screen, never as the final validation basis |
| Reusing a hand-rolled VMAF/PSNR parsing script across environments without re-verifying locale/field layout | No new tooling to write | Silently wrong metric values that look plausible (Pitfall 6) | Never — always re-verify with `LC_ALL=C` and a header-based/documented field index in any new environment |
| Bundling a host driver + firmware change into one reboot cycle to save reboot time | Fewer reboots, faster wall-clock | Loses attribution; can't tell the user which single change to make in production | Only acceptable for a cheap exploratory "does anything change at all" probe, and even then must be followed by isolated single-variable reruns before reporting |
| Fully prototyping the ffmpeg av1_qsv migration "to be thorough" | Feels like delivering the "best" answer | Burns the investigation's time budget on an out-of-scope implementation, for a repo (`enpipe`) not even in this checkout | Never within this project's scope — recommendation only, per Out of Scope |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|-----------------|--------------------|
| `qsvencc --psnr`/`--ssim` | Assuming these flags work because they exist and don't error in every build | Never use them in this environment; always extract frames and measure with external ffmpeg PSNR/VMAF |
| libvmaf CSV output | Parsing with `$NF` or comma-as-decimal assumptions | Force `LC_ALL=C`, parse by header name if possible, and hardcode field 16 = score / field 17 = frame-number-duplicate if positional parsing is unavoidable |
| ffmpeg `av1_qsv` control harness | Treating it as a one-time validation done in the prior session, not re-run per environment | Re-run the control alongside every qsvencc measurement in every new environment/host-lever state |
| `/dev/dri/renderD128` shared GPU access | Assuming your own process is the only GPU client without checking | Verify exclusivity with `fuser -v /dev/dri/renderD128` / `pgrep -f qsvencc` before every "isolated" or "control" measurement |
| Rootless Podman + `/data` mount | Assuming write access works the same as root Podman, or that a container driver update reaches the host | Verify actual write permission (userns/`--group-add keep-groups`) before assuming `/data` writability, and never rely on in-container driver updates to change host-kernel behavior |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|-----------------|
| Assuming corruption rate scales linearly with job count | 3-way rate (33-65%) misapplied to estimate `enpipe`'s default `JOBS=3` production risk without re-measuring at the actual deployed concurrency | Always measure at the exact concurrency level relevant to the recommendation (3-way, matching `enpipe`'s default), not extrapolate from a different N | Any time the recommendation is generalized beyond the measured concurrency level |
| Using `--avsw` throughput numbers from a different host/GPU as a stand-in for this environment | Reported "310→125 fps" single-session numbers reused without re-measuring on this Arc A380 in this container | Re-measure Option A/B/C throughput fresh in this environment before finalizing the recommendation (per Definition of Done §10.3) | Whenever hardware, container base image, or driver stack differs from where the number was first measured |
| Treating GPU contention effects as constant across repeated runs | Later-in-session runs show different timing/rate than early runs due to thermal throttling or driver-state drift | Track run order/timestamps alongside rate; watch for drift across a long iteration batch | Long unattended batches (dozens of sequential runs) on a small discrete GPU without power/thermal headroom monitoring |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Running host-kernel-parameter changes (`i915.force_probe`, `xe.force_probe`) without a tested rollback path | Could leave the host GPU non-functional or require physical/out-of-band recovery | Confirm and document the exact rollback boot parameter before applying any Xe/i915 force-probe change; treat as a host-boundary action requiring the user's involvement per the project's Host boundary constraint |
| Trusting/reusing third-party forked qsvencc branches (e.g. the abandoned `p010-fix`/`p010-hint-*` branches noted in §9) | Unreviewed patches from throwaway experiment branches could be accidentally built/shipped instead of upstream `qsvencc` | Delete or clearly quarantine dead experiment branches (as §9 already recommends) rather than leaving them buildable/selectable |
| Writing experiment scripts that could touch `/data` under rootless-Podman with broader permissions than intended | Accidental mutation of the read-only-by-policy source media | Always target a dedicated writable workdir for all outputs; treat `/data` as read-only regardless of actual filesystem permissions, per project constraint |

## "Looks Done But Isn't" Checklist

- [ ] **"Bug reproduced" claim:** Often missing the paired ffmpeg av1_qsv control result for the same run — verify both numbers are reported together, not qsvencc alone.
- [ ] **"Lever X fixes it" claim:** Often missing an adequate zero-failure sample size — verify N ≥ ~60 clean runs (or an explicit, stated confidence rationale) before accepting.
- [ ] **"Host-side change applied" claim:** Often bundles multiple simultaneous changes (driver + firmware + kernel) — verify each change was isolated with its own before/after measurement.
- [ ] **"Xe driver tested" claim:** Often missing confirmation that HW AV1 encode actually engaged under Xe (HuC support) — verify `--check-features`/encode-path confirmation, not just "the driver loaded."
- [ ] **"Workaround validated" claim:** Often missing a fresh in-this-environment throughput re-measurement — verify numbers weren't just copied from the prior session's different host.
- [ ] **"Content verified clean" claim:** Often relies on mean/aggregate PSNR/VMAF over a long file, which can hide a single swapped frame — verify per-frame or worst-percentile scoring was used at the known hotspot offsets, not an average.
- [ ] **"Metrics computed correctly" claim:** Often silently mis-parses locale-formatted VMAF CSV or field 17 instead of 16 — verify `LC_ALL=C` was forced and the field index/name was checked against a raw CSV sample.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|----------------|------------------|
| Measurement contamination discovered after the fact (concurrent GPU use during a "control" run) | LOW-MEDIUM | Discard the contaminated run(s), re-run under verified exclusivity; cheap since GPU-hours are the only cost, no code/config to unwind |
| "Fixed" declared on too few iterations, later shown wrong | MEDIUM | Re-run to the statistically adequate N before finalizing any recommendation that depended on the premature claim; revise the recommendation if the residual rate turns out non-trivial |
| Multi-variable host change applied, can't attribute | MEDIUM-HIGH | Roll back to the last single-variable-known state (may require another reboot/host access) and re-apply changes one at a time; budget extra reboot cycles |
| Xe driver switch breaks HW encode entirely | MEDIUM (host-side) | Roll back via the documented `i915.force_probe` restoration parameter; record the AV1-encode-under-Xe gap as a negative result for this hardware generation rather than retrying blindly |
| Re-discovered dead-end qsvencc source patch attempted again | LOW | Recognize against §5/Out-of-Scope, abandon quickly, redirect effort to host-side or workaround tracks — cheap since caught by cross-referencing the existing exhausted-negatives log |
| VMAF/PSNR numbers found to be mis-parsed after several phases used them | MEDIUM | Re-run extraction with corrected locale/field handling on archived raw CSVs if still available (avoids re-encoding); if raw CSVs weren't retained, re-run affected experiments |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|----------------|
| Measurement contamination from concurrent GPU use | Reproduction/baseline phase | Control (single-session) run reads a clean 0%; GPU-exclusivity check logged for every run |
| Declaring "fixed" on too few iterations | Every lever-testing / workaround-validation phase | Reported sample size ≥ ~60 zero-failure runs (or explicit stated confidence) before any "clean"/"fixed" claim |
| False isolation (multi-variable host changes) | Host-side lever phase | Each experiment log shows exactly one changed variable vs. the immediately prior measured state |
| Missing ffmpeg av1_qsv immune control | All phases from reproduction onward | Every reported corruption rate has a paired control rate from the same run/environment |
| Frame-count silent-pass trap | All measurement phases; explicit deliverable in the defense-in-depth gate design phase | Validation logic verified to use per-frame/percentile content checks at known hotspot offsets, not aggregate/count checks |
| OpenCL/VMAF CSV parsing gotchas | Harness-setup step of the reproduction phase | `qsvencc --psnr/--ssim` absent from all scripts; `LC_ALL=C` set; VMAF field 16 vs 17 hardcoded/documented at parse site |
| Assuming container change affects host kernel | Phase-zero orientation / gate before host-side lever phase | New proposals reference and differentiate from the already-tried userspace-stack-swap negative result |
| Xe driver silently losing AV1 HW encode | Host-side lever phase | HW-encode-engaged confirmation step precedes any corruption-rate measurement under Xe |
| Re-attempting exhausted qsvencc patch line | Standing guard, all phases touching QSVEnc source | Any qsvencc source-touching task explicitly cites why it differs mechanistically from §5's tried variants |
| Over-investing in ffmpeg av1_qsv migration | Workaround-recommendation phase | Option A (`--avsw`) throughput re-measured and reported before/alongside Option C characterization; Option C scoped as "characterize," not "implement" |

## Sources

- `PROJECT.md` (root handoff) — §3 root-cause chain, §4 reproducer protocol, §5 exhausted negatives (3 build cycles), §6 untried host-side levers, §7 workaround solution space, §9 gotchas (VMAF locale/field, OpenCL, /data permissions), §10 Definition of Done — this project's own prior-session findings, treated as HIGH-confidence primary source for domain-specific pitfalls.
- `.planning/PROJECT.md` — Validated/Active/Out-of-Scope requirements, Constraints (single shared GPU, host boundary, data safety), Key Decisions (sequential execution rationale) — HIGH confidence, defines this investigation's guardrails directly.
- Rule-of-three statistical convention for zero-event confidence intervals (upper 95% CI bound ≈ 3/n for n trials with 0 observed events) — standard statistical practice, MEDIUM-HIGH confidence, applied here to translate this project's own baseline rate (33-65%) and existing sample sizes (15-20 runs, "0/60", "0/15" in §7) into concrete minimum-N guidance for validating a fix vs. merely detecting the original bug.
- [Passing through Intel Arc A380 to a Proxmox VM](https://blog.ssb-tech.net/posts/proxmox-intel-arc-a380/) and [Intel Arc & Iris Xe Linux Driver Compatibility Guide](https://www.faceofit.com/intel-arc-iris-xe-linux-driver-compatibility-guide/) — MEDIUM confidence, corroborate that Arc Alchemist/DG2 (A380) users needing AV1 hardware encode should stay on the i915 driver because the experimental Xe driver currently lacks HuC firmware support for Alchemist; used to substantiate Pitfall 8's warning that an i915→Xe switch (§6's "most promising" untried lever) risks silently disabling HW encode rather than fixing the concurrency bug. Recommend re-verifying current Xe/HuC support status directly against kernel release notes at the time this lever is actually attempted, since driver support matrices change across kernel versions.
- General Podman/rootless-container documentation on kernel module and driver boundaries (containers cannot alter host kernel modules) — MEDIUM confidence, general container-platform knowledge corroborating this project's own already-demonstrated finding (§5) that in-container userspace media-stack updates had zero effect on the kernel-rooted corruption.

---
*Pitfalls research for: hardware/kernel-level, concurrency-triggered silent GPU frame-corruption investigation (Intel QSV AV1 / Arc A380)*
*Researched: 2026-07-23*
