# Phase 3: Host-Side Levers — Firmware & Xe Migration - Context

**Gathered:** 2026-10-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver DIAG-01: an honest, evidence-backed record of which host-side changes are possible from this environment (kernel cmdline / modprobe, firmware update, reboot, privilege level) — from inside the dev container AND from the host itself (Fedora 43 NAS, kernel `6.19.14-200.fc43`, Arc A380) — plus the current GuC/HuC and linux-firmware versions, and a ready-to-run runbook for the deferred levers (GuC/HuC update, `i915`→`Xe`) so they can be executed later without re-analysis.

Out of scope (deferred to v2, per the 2026-10-01 roadmap change): actually applying any host-side change, rebooting, or measuring corruption rates under a changed firmware/driver (DIAG-03/04/05). The bug is already fixed at application level (upstream rigaya/QSVEnc `45003f15`, verified on our A380 in 02.1-EVIDENCE.md); these levers would only test the "root cause below the API" hypothesis.

</domain>

<decisions>
## Implementation Decisions

### Data sources for DIAG-01
- **D-01:** Capture capability from BOTH sides: (a) everything observable inside the dev container (already known: root without `CAP_SYS_ADMIN`/`CAP_SYS_MODULE`, `dmesg` and debugfs blocked, `/sys/module/i915/parameters/*` unreadable, no reboot; host kernel cmdline visible via `/proc/cmdline`; both `i915` and `xe` drivers present under `/sys/bus/pci/drivers/`); (b) the host, via a read-only script the executor prepares and the operator runs on the NAS, returning its output at a `checkpoint:human-action`.
- **D-02:** The host script is strictly read-only — no package installs, no `modprobe`, no `grubby`, no reboot, no writes outside a temp/output file. It records: privilege level (`id`, sudo availability), kernel cmdline and boot method (`grubby --info=DEFAULT` read-only), loaded GPU driver and PCI id, `xe`/`i915` module availability (`modinfo`), GuC/HuC loaded versions (`dmesg` / `journalctl -k` lines for GuC/HuC/DMC on the DG2), installed `linux-firmware` (and `intel-gpu-firmware` if split) package version(s) and whether a newer one is available (`dnf list --upgrades` / `dnf check-update`, read-only), firmware files present for DG2 under `/lib/firmware/i915/`, iHD/libvpl/libmfx-gen package versions, and whether reboots are possible (operator answer, captured in the checkpoint, not tested).
- **D-03:** Also record the current GuC/HuC and linux-firmware versions (not only yes/no capabilities) — needed for a possible report to Intel and as the baseline for a later DIAG-03.
- **D-04:** Honest reporting: anything the host output does not prove is marked "unknown", anything impossible from the container is marked "blocked from container — requires host-owner action". Never infer a capability without evidence.

### Deferred levers documentation
- **D-05:** Write a ready-to-run runbook for each deferred lever (GuC/HuC firmware update; `i915`→`Xe` via `i915.force_probe=!56a5 xe.force_probe=56a5` or the current Fedora-43-correct equivalent), each with: purpose (what hypothesis it tests), prerequisites, exact commands for Fedora 43, how to confirm the low-power AV1 HW encode path is still active under Xe (dmesg GuC/HuC lines, `vainfo`, `qsvencc --check-features`) BEFORE trusting any clean result, rollback steps, and how to re-run the measurement.
- **D-06:** The runbook's measurement must use the archived STOCK 8.31 binary (`scratch/bins/stock-8.31/qsvencc`, sha256 `f4282c49…`) through the unmodified harness — the fixed builds hide the bug and would make any lever look clean. One changed variable per reboot cycle, paired ffmpeg control per batch (carried forward from DIAG-05 / Phase 1 rules).
- **D-07:** Runbook commands are written but NOT executed in this phase; mark them "untested — verify on first use" where they cannot be validated read-only.

### Phase process
- **D-08:** Lightweight process: skip the research step (domain already covered by Phases 1/2/2.1 and the host data comes from the operator), produce a single plan with a `checkpoint:human-action` for the host script output; keep the plan-checker. Executor runs on the main tree (no worktree), commits are authorized on `master`.

### Claude's Discretion
- Script name/location (suggested: `.planning/phases/03-host-side-levers-firmware-xe-migration/tools/host_probe.sh`, git-tracked) and output format.
- Exact Fedora 43 commands in the runbook (dnf/grubby/modprobe.d syntax), provided they follow D-05..D-07.
- Where the DIAG-01 record lives (suggested: `03-EVIDENCE.md`, git-tracked, verbatim host output snapshot) and the runbook file name (suggested: `03-RUNBOOK.md`).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase definition and scope change
- `.planning/ROADMAP.md` §"Phase 3" — reduced goal, scope-change note (2026-10-01), success criteria
- `.planning/REQUIREMENTS.md` — DIAG-01 (active); DIAG-03/04/05 under "v2 → Host-Side Root-Cause Experiments (deferred)"

### Prior evidence
- `scratch/repro/fingerprint.txt` (git-ignored, Phase-1 output) and `.planning/phases/01-harness-control-environment-fingerprinting/01-EVIDENCE.md` — environment fingerprint, `guc_huc: UNAVAILABLE: dmesg blocked (no CAP_SYS_ADMIN in this container)`
- `.planning/phases/01-harness-control-environment-fingerprinting/01-CONTEXT.md` — harness rules (paired control, detection-N vs validation-N)
- `.planning/phases/02.1-source-level-fix-qsvencc-surface-sync-lifetime/02.1-EVIDENCE.md` — mechanism (timing window, root cause probably below the API), stock/fixed binaries and sha256, upstream fix 45003f15 verification
- `.planning/research/PITFALLS.md` and `.planning/research/STACK.md` — earlier notes on GuC/HuC, Xe force_probe on PCI `56a5`, low-power AV1 entrypoint

### Harness and binaries (for the runbook)
- `scratch/repro-831/harness.sh`, `scratch/repro-831/lib.sh` — unmodified harness copy (git-ignored)
- `.planning/phases/02.1-source-level-fix-qsvencc-surface-sync-lifetime/tools/cand-tools/` — cand_setup.sh / cand_screen.sh (PATH-shim screening without modifying the harness)
- `.planning/phases/02.1-source-level-fix-qsvencc-surface-sync-lifetime/tools/d01-tools/d01_md5.sh` — whole-file md5 oracle
- `scratch/bins/stock-8.31/qsvencc` — archived stock binary (must be used for lever measurements)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scratch/repro/harness.sh probe` — already writes the container-side fingerprint (kernel, driver, PCI id, vainfo, GuC/HuC attempt); reuse its field names for consistency.
- cand tooling + md5 oracle from 02.1 — the measurement procedure the runbook should reference instead of inventing a new one.

### Established Patterns
- Git-tracked `*-EVIDENCE.md` with verbatim snapshots of git-ignored runtime outputs (Phases 1, 2, 2.1).
- Measurements fail closed; blocked/unknown is reported explicitly, never silently skipped.

### Integration Points
- The final report (Phase 4) consumes `03-EVIDENCE.md` (capabilities, versions) and `03-RUNBOOK.md` (deferred levers).

</code_context>

<specifics>
## Specific Ideas

- Host is a Fedora 43 NAS (`root=/dev/mapper/fedora_nas-root`, `console=ttyS1,115200`); both `i915` and `xe` are present in the running kernel, the GPU is bound to `i915`.
- Upstream already fixed the bug at application level (45003f15); the deferred levers matter only for explaining the root cause (e.g. to Intel), so the runbook should state that motivation.

</specifics>

<deferred>
## Deferred Ideas

- Executing the GuC/HuC update and the Xe switch with before/after measurements (DIAG-03/04/05) — v2, operator decision.
- Reporting the suspected below-API ordering issue to intel/media-driver or the i915/xe maintainers — after the deferred experiments, operator decision.

</deferred>

---

*Phase: 03-host-side-levers-firmware-xe-migration*
*Context gathered: 2026-10-03*
