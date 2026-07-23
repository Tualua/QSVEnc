# Feature Research

**Domain:** Diagnostic/investigation project — root-cause resolution of silent cross-session frame corruption in concurrent Intel QSV AV1 encoding (qsvencc / oneVPL / iHD / drm-i915 stack)
**Researched:** 2026-07-23
**Confidence:** MEDIUM (prior-art findings are HIGH confidence — validated by two agents across multiple build cycles per handoff §3/§5; net-new host-side levers are MEDIUM/LOW confidence — untried in this environment, current-driver-state verified via web search 2026-07-23)

Note on framing: this is not a product with users — it is an investigation whose "customers" are (a) the correctness invariant of the `enpipe` pipeline and (b) whoever consumes the Definition-of-Done report (root PROJECT.md §10). "Table stakes" = deliverables without which the investigation cannot be trusted as complete. "Differentiators" = the actual resolution paths that could close the bug or route around it. "Anti-features" = analytically exhausted or explicitly out-of-scope work per `.planning/PROJECT.md`.

## Feature Landscape

### Table Stakes (Investigation Is Worthless Without These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Deterministic reproduction harness (923/928/1129 scenes, 3-way concurrent `qsvencc`) | Without a repro, no experiment (driver swap, firmware, etc.) can be judged to have worked or not. Root PROJECT.md §4 gives the exact seek/trim/command recipe already validated by prior session. | MEDIUM | Fully in-container/in-repo; no host access needed. Uses `/data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv` read-only; outputs to isolated workdir (never `/data`). Must re-run 15-20 iterations per config to get a stable frequency estimate (prior freq band 33-65% is wide — noisy signal, needs enough trials). |
| PSNR-vs-reference detection at ~15.74 dB | This is the *only* way corruption is detected — frame count alone passes silently (that is the whole bug). Without this exact check the harness cannot distinguish "clean" from "corrupted." | LOW | Reuses prior session's exact protocol: extract frame at known hotspot offset via ffmpeg, `ffmpeg -lavfi psnr` against isolated-run reference. `qsvencc --psnr/--ssim` requires OpenCL — do not depend on it (root PROJECT.md metrics constraint); use external ffmpeg per Context §"Metrics constraint" in `.planning/PROJECT.md`. |
| ffmpeg `av1_qsv` IMMUNE control experiment | Establishes the harness is measuring the right thing (if ffmpeg also corrupts here, the environment differs from the handoff and every other result must be reinterpreted). Also the load-bearing evidence that the driver *can* isolate correctly — motivates the enpipe workaround options (§7) and rules out "driver is fundamentally broken." | LOW-MEDIUM | Needs ffmpeg built/available with `av1_qsv` + `vpp_qsv=format=p010le` + `GopRefDist:6 BRefType:pyramid` support — verify ffmpeg version has these knobs before relying on the control. Must run at the same concurrency (3-way, ideally also 5-way per handoff) to match prior methodology. |
| Environment/kernel fingerprinting (`uname -r`, i915-vs-Xe, iHD version, GuC/HuC firmware version) | The single highest-value fork in the whole investigation (handoff §6): if this environment's kernel/driver differs from the affected `6.19.14-200.fc43` host and the bug does not reproduce, that alone is the fix. `.planning/PROJECT.md` already confirms same kernel version is reported — but "same `uname -r` string" is necessary, not sufficient, to conclude "same effective driver stack" (module vs distro build variance, GuC/HuC version can differ even on identical kernel). | LOW | Commands: `uname -r`; `ls /dev/dri`, `cat /sys/kernel/debug/dri/*/name` or `lspci -k -d ::0380` to see bound driver module; `vainfo` for iHD version; `dmesg \| grep -i -E 'guc\|huc'` or `intel_gpu_top`/`sysfs` firmware version nodes for GuC/HuC. Some of these need elevated privileges that may not be available in a container — flag if blocked. |
| Per-frame content-verification gate on joined output | Defense-in-depth requirement explicit in both PROJECT.md files: whichever fix/workaround is chosen, `count_frames` alone must never again be the only invariant. This is a deliverable independent of root-cause resolution — it should ship even if host-side levers fully "fix" this host, because other hosts/kernels may still be vulnerable. | MEDIUM | Design-level deliverable for `enpipe` (recommendation only — `enpipe` repo not present, per Out of Scope). Likely VMAF or PSNR gate comparing final joined `movie.obu` against source at matching frame offsets. Needs to define: threshold, sampling density (every frame vs spot-check), and failure action (reject chunk / re-encode / alert). This is a *design spec*, not code, since enpipe source is unavailable here. |

### Differentiators (The Actual Resolution Paths)

| Feature | Value Proposition | Complexity | Notes |
|---------|--------------------|------------|-------|
| i915 → Xe driver migration test | Most-promising untried lever per handoff §6 ("наиболее перспективно") — Xe uses a materially different BO/context isolation model than i915, which is exactly the layer implicated as root cause. If it clears the bug, it is a clean host-side fix requiring no enpipe code change. | HIGH | **Host-side, outside container.** Verified 2026-07-23: i915 is still the Linux default for Arc A-series (including DG2/A380) as of current kernels; Xe is available but requires explicit `xe.force_probe=<pci-id>` (or blacklisting i915) at boot, i.e. a host kernel-parameter change + reboot. This is very likely **blocked** in a devcontainer — flag as a host-owner action item, not something this investigation can execute unassisted. Requires user/host-admin cooperation. |
| GuC/HuC firmware update test | Untried per handoff §6; firmware governs command-submission scheduling (GuC) and low-power encode (HuC) — plausible locus for cross-context BO aliasing under concurrent submission. | MEDIUM-HIGH | **Host-side** (firmware blobs live in `/lib/firmware/i915/`, loaded by the i915/Xe module at boot; updating requires new `linux-firmware` package + reboot or module reload). Likely requires host package manager access outside container scope. Lower priority than Xe migration per handoff ("наиболее перспективно" was assigned to Xe, not firmware) but cheaper to test if `linux-firmware` can be updated without a full driver switch. |
| `av1_vaapi` (pure VA-API path, bypassing oneVPL/qsvencc entirely) | Handoff calls this "непроверенный дешёвый эксперимент" — quieter/simpler API surface than oneVPL, may sidestep whatever cross-session aliasing qsvencc's OR-combined VA pool triggers, without waiting on host-side driver/firmware changes. | LOW-MEDIUM | **In-container** — no host access needed, same iHD driver already installed. Verified via web search 2026-07-23: intel/media-driver's iHD backend does support AV1 encode on DG2 via VAAPI (HuC-based low-power VDEnc path), so `ffmpeg -c:v av1_vaapi` (or a raw `vaapi-encode` harness) is expected to be exercisable today. This is a genuinely cheap test to run *before* pursuing the two host-side levers above, since it needs no host cooperation — should be sequenced first among differentiators for cost reasons even though the handoff lists it last. |
| §7 workaround recommendation for enpipe — three concrete options, each with measured throughput cost in this environment | This is the actual deliverable if no host-side lever pans out: enpipe needs a documented, correctness-first tradeoff decision backed by numbers from this environment, not the prior host. | MEDIUM | Recommendation only (enpipe repo absent — Out of Scope for code changes). Sub-features: <br>**A. `--avsw`** (SW-decode + HW-encode): keeps 10-bit + B-pyramid + DV/HDR; prior measured cost 310→125 fps single-session in the old environment — must re-measure fps in *this* environment/hardware (Arc A380 CPU pairing may differ). LOW implementation cost (one flag change in `chunk.py`), MEDIUM measurement cost. <br>**B. `--jobs 1`** (serialize): 0% corruption by construction (removes concurrency entirely); simplest possible change (`JOBS` env default or CLI), but throughput cost is the full ×(job count) — must quantify against this GPU/scene mix. LOW complexity. <br>**C. ffmpeg `av1_qsv` migration**: clean at full speed per control experiment, but per handoff is a "КРУПНЫЙ рерайт" — seek/trim reimplementation, Dolby Vision RPU passthrough, HDR10+ signaling, metrics — HIGH complexity and HIGH risk specifically for the DV/HDR features that were the reason qsvencc was chosen over ffmpeg in the first place. This option should be evaluated but not silently recommended given that risk. |

### Anti-Features (Deliberately NOT Build)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|----------------|------------------|-------------|
| Re-patching qsvencc surface-attribute/allocator code (`qsv_allocator_va.cpp`, `qsv_pipeline.cpp:1708-1822`) | Superficially "the" fix, since the code path exists in-repo (this checkout, `.planning/codebase/`) and is directly editable — feels like the tractable lever compared to host/kernel work. | Analytically exhausted per handoff §5 across 3 build cycles and 2 independent agents: `rt_format` patch inert (iHD already honors `VASurfaceAttribPixelFormat`), `VASurfaceAttribUsageHint` variants inert, `--async-depth 1` inert, `--disable-va` segfaults 100%. Allocator pools are already process-local and separate — there is no allocator-level knob left to turn. Root cause confirmed in kernel (drm/i915), not userspace, by full userspace-stack replacement (iHD 25.2.3→26.2.2) having zero effect. Re-trying wastes build cycles on a dead end. | Pursue host-side levers (Xe, GuC/HuC, differentiators above) or enpipe-side workarounds (§7); if a genuine upstream fix is later found, it belongs in drm/i915 kernel or intel/media-driver, not qsvencc. |
| Full-file re-encode of the Cold Eyes source for testing | Feels like a more "complete" or "realistic" validation than point scenes. | 171,390-frame source; full re-encode per test iteration would make each experiment (of which many are needed: baseline, per-driver-config, per-workaround) prohibitively slow, without adding diagnostic value — the three harness scenes (923/928/1129) already reproduce the exact hotspot offsets and known-bad frames. Wastes GPU time that is a scarce shared resource in this environment (single Arc A380, sequential plan execution required per PROJECT.md constraint). | Use the three point scenes only, as the harness recipe (root PROJECT.md §4) specifies. Reserve full-file re-encode exclusively for the final tech-debt cleanup (regenerating the shipped Cold Eyes encode) after a fix is validated — a one-time, end-of-project action, not a per-experiment step. |
| Writing reproduction/experiment outputs (or anything) into `/data` | `/data` now appears writable in this environment (unlike the prior read-only container), which invites "just write outputs next to the source, it's simpler." | `/data` holds the only copy of source media referenced by this investigation; corrupting or cluttering it breaks reproducibility for future sessions and risks the exact kind of silent-corruption class this project exists to prevent, applied to the input side. `.planning/PROJECT.md` Out of Scope and Constraints both flag this explicitly ("read-only-by-policy even if writable"). | All experiment outputs, extracted frames, intermediate `.obu` files, and reference frames go to an isolated writable workdir outside `/data`. |
| Blindly recommending "just update the driver" as the fix | Surface-plausible: newer driver = more bugfixes, and it is the cheapest-sounding recommendation to write down. | Deep-research (17 sources, per handoff §5) found **no** relevant fix for concurrent/multi-session/cross-session corruption in iHD ≤26.1.5 or vpl-gpu-rt changelogs — and this project's own prior test already replaced the entire userspace stack (iHD 25.2.3→26.2.2) with zero effect, confirming the bug is not a userspace driver-version issue at all (it is kernel-side). Recommending a driver bump as "the fix" without new evidence would repeat a already-falsified hypothesis. | If host-side fingerprinting (table stakes) finds this environment already has a *materially newer* driver/kernel *and* the bug fails to reproduce, that is new evidence and should be reported as such — but "update to latest iHD" is not, on its own, a valid recommendation to hand to the user or to enpipe. |

## Feature Dependencies

```
Environment/kernel fingerprinting (table stakes)
    └──gates──> i915→Xe migration test (differentiator)
    └──gates──> GuC/HuC firmware update test (differentiator)
                (both need current-state facts before host-owner can act)

Deterministic reproduction harness (table stakes)
    └──requires──> PSNR-vs-reference detection at ~15.74 dB (table stakes)
    └──requires──> ffmpeg av1_qsv IMMUNE control (table stakes, validates harness itself)
                       └──also produces evidence for──> §7 Option C (ffmpeg migration) feasibility

Reproduction harness ──reused-by──> i915→Xe migration test
Reproduction harness ──reused-by──> GuC/HuC firmware test
Reproduction harness ──reused-by──> av1_vaapi alternative test
Reproduction harness ──reused-by──> §7 workaround throughput measurements (A/B/C)

Per-frame content-verification gate (table stakes) ──independent-of──> all differentiators
    (ships regardless of which/whether a root-cause fix is found — defense in depth)

i915→Xe migration test ──conflicts-with──> GuC/HuC firmware update test (as simultaneous experiments)
    (both are host-side kernel/driver-module changes on the single shared Arc A380;
     PROJECT.md's "sequential plan execution" constraint means these must run one-at-a-time,
     not layered together, or a positive result cannot be attributed to either lever alone)

av1_vaapi alternative test ──no-dependency-on──> host-side levers
    (can and should run before/independent of Xe or firmware changes — cheapest, in-container test)
```

### Dependency Notes

- **Fingerprinting gates the two host-side differentiators:** you cannot meaningfully propose or evaluate an i915→Xe switch or a GuC/HuC firmware bump without first knowing the *current* bound driver and firmware versions — this is why fingerprinting is table stakes rather than a differentiator itself.
- **The reproduction harness is the shared substrate for every experiment:** it must be built once and reused unmodified across all differentiator tests (Xe, firmware, av1_vaapi, and each §7 workaround), otherwise cross-experiment frequency comparisons (33-65% band) are not comparable.
- **The ffmpeg control validates the harness, not just the driver:** if the control ever stops being clean in this environment, that is a signal the harness or environment has diverged from the handoff's assumptions, and all other results in that run should be treated as suspect until the control is re-established.
- **Xe migration and GuC/HuC firmware conflict as simultaneous host changes:** both mutate the same single-GPU host driver stack; running them concurrently (or without reverting between tests) would make it impossible to attribute a fix (or non-fix) to either lever specifically. The project's existing "sequential plan execution" constraint already mandates this ordering for GPU experiments generally.
- **The per-frame content-verification gate is deliberately decoupled from root-cause resolution:** it is listed as table stakes precisely because its value does not depend on which differentiator (if any) succeeds — per PROJECT.md's Core Value, correctness must be defended even if no clean host-side fix is found.

## MVP Definition

### Launch With (v1) — Definition of Done per root PROJECT.md §10

- [ ] Reproduction harness executed in this environment with recorded frequency + PSNR signature — essential to know if this host reproduces at all
- [ ] ffmpeg `av1_qsv` control run alongside every reproduction pass — essential to validate the harness is measuring the right thing
- [ ] Full environment fingerprint (kernel, i915/Xe, iHD version, GuC/HuC version) recorded — essential, this is the single highest-leverage fork in the whole investigation
- [ ] At least the cheapest differentiator (`av1_vaapi` alternative) attempted, since it needs no host cooperation and directly informs whether a quieter API surface alone resolves the bug
- [ ] A concrete §7 recommendation for enpipe, with throughput numbers measured in *this* environment (not just carried over from the prior host) — essential because the whole point of this investigation is an actionable recommendation, not just a diagnosis
- [ ] Per-frame content-verification gate designed (spec-level, since enpipe code is out of reach) — essential defense-in-depth deliverable regardless of other outcomes

### Add After Validation (v1.x)

- [ ] i915→Xe driver migration test — trigger: once fingerprinting confirms this host is still on i915 and the bug reproduces, and a host-owner is available to apply the kernel parameter + reboot
- [ ] GuC/HuC firmware update test — trigger: only if Xe migration is unavailable/blocked or inconclusive, since it is a secondary lever per the handoff's own prioritization
- [ ] Re-measurement of §7 Option A/B throughput at higher iteration counts — trigger: once a recommendation direction is chosen, to tighten confidence on the specific numbers reported to the user

### Future Consideration (v2+)

- [ ] Corrected re-encode of the shipped Cold Eyes file (frames 39121/61365/73734/110079/110992/136249) — defer until after a fix/workaround is validated and the user explicitly decides to act on the acknowledged tech debt (root PROJECT.md §0/§10, `.planning/PROJECT.md` Active requirements); full-file re-encode is expensive and should not gate the investigation's core findings
- [ ] Actual implementation of the chosen §7 workaround inside `enpipe` — defer entirely; out of scope for this checkout since the `enpipe` repo is not present here, this project delivers only the recommendation

## Feature Prioritization Matrix

| Feature | Investigative Value | Implementation/Execution Cost | Priority |
|---------|---------------------|-------------------------------|----------|
| Reproduction harness (923/928/1129, 3-way) | HIGH | MEDIUM | P1 |
| PSNR-vs-reference detection (~15.74 dB) | HIGH | LOW | P1 |
| ffmpeg av1_qsv IMMUNE control | HIGH | LOW-MEDIUM | P1 |
| Environment/kernel fingerprinting | HIGH | LOW | P1 |
| Per-frame content-verification gate design | HIGH | MEDIUM | P1 |
| `av1_vaapi` alternative test | MEDIUM-HIGH | LOW-MEDIUM | P1 (cheapest differentiator — do before host-side asks) |
| §7 workaround throughput measurement (A/B) | HIGH | MEDIUM | P1 |
| §7 workaround feasibility assessment (C, ffmpeg migration) | MEDIUM | MEDIUM (assessment only, not implementation) | P2 |
| i915→Xe driver migration test | HIGH (most-promising per handoff) | HIGH (host access, reboot, may be blocked) | P2 — pursue if host access available, else report as recommended-but-blocked |
| GuC/HuC firmware update test | MEDIUM | MEDIUM-HIGH (host access) | P3 |
| Corrected re-encode of shipped Cold Eyes file | LOW (tech debt, not investigation) | HIGH (full-file, 171K frames) | P3, user's discretion |

**Priority key:**
- P1: Must have for a complete, trustworthy Definition of Done
- P2: Should have if host access/time permits; otherwise report as a recommended-but-untested/blocked next step
- P3: Nice to have or explicitly deferred to user discretion

## Cross-Repo / Host-Access Dependency Summary

| Deliverable | Blocked by absent `enpipe` repo? | Blocked by host access (outside container)? |
|-------------|:---:|:---:|
| Reproduction harness + PSNR detection | No | No |
| ffmpeg av1_qsv control | No | No |
| Environment/kernel fingerprinting | No | Partially — some fingerprinting commands (e.g. `dmesg`, driver-debugfs, firmware version nodes) may need elevated container privileges not guaranteed to be present; degrade gracefully to `uname -r` + `vainfo` if so |
| `av1_vaapi` alternative test | No | No |
| i915→Xe migration test | No | **Yes** — requires host kernel boot parameter change + reboot; cannot be executed from inside the container under any circumstance |
| GuC/HuC firmware update test | No | **Yes** — requires host package manager / firmware blob update, likely outside container filesystem and privilege scope |
| §7 recommendation content (A/B throughput numbers) | No (measurable in-container) | No |
| §7 recommendation content (C feasibility narrative) | Partially — full risk assessment of DV/HDR passthrough rewrite would benefit from reading actual `chunk.py`, which is absent; this project can only reason from the handoff's description of it | No |
| Actual `enpipe` code change (any §7 option) | **Yes — repo not present, explicitly Out of Scope** | N/A |
| Per-frame content-verification gate implementation | **Yes — spec/recommendation only** | No |
| Corrected re-encode of shipped file | No | No |

## Sources

- `.planning/PROJECT.md` (this project's Active requirements, Validated findings, Out of Scope, Constraints) — HIGH confidence, primary source of record for what has already been established
- Root `PROJECT.md` handoff document (§0-§10: mission, trigger triad, root-cause chain, reproducer recipe, exhausted negatives, untried host-side levers, workaround solution space, enpipe code map, gotchas, Definition of Done) — HIGH confidence, prior debugging session's validated findings across multiple build cycles and 2 independent agents
- WebSearch, 2026-07-23: "Intel Arc A380 DG2 Xe driver vs i915 kernel default" — MEDIUM confidence (multiple community/Phoronix sources agree i915 remains default for Arc A-series as of 2026, Xe requires explicit `xe.force_probe=<pci-id>` override); confirms host-side migration test requires a boot-parameter change, not just a package install
- WebSearch, 2026-07-23: "intel-media-driver av1_vaapi encode support DG2" — MEDIUM confidence (intel/media-driver GitHub README/DeepWiki indicate AV1 encode support on DG2 via VDEnc/HuC low-power path); confirms `av1_vaapi` is a viable, currently-supported code path on this hardware, not a dead end
- Referenced but not directly read in this pass: `scene-chunk-frame-mismatch.md` (300-line debugging history) and `qsvenc-upstream-issue.md` (upstream draft) — cited by the handoff as the full backing detail; treat as HIGH confidence extensions of the handoff's summary if consulted directly during execution

---
*Feature research for: QSV concurrent-encode frame-corruption investigation*
*Researched: 2026-07-23*
