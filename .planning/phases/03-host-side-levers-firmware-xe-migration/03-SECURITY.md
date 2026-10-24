---
phase: 3
slug: host-side-levers-firmware-xe-migration
status: verified
threats_open: 0
asvs_level: 1
created: 2026-10-24
---

# Phase 3 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Scope: documentation/evidence artifacts and one read-only bash probe under `.planning/`. No application code.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| container -> host | The executor has no host access; the operator runs repository code on the NAS, normally as root | Probe script (in), probe stdout (out) |
| probe output -> git | Host data crosses into git-tracked files that may later be pushed | Host kernel log, package, firmware, cmdline data; potentially user names, paths, third-party repo URLs (sensitive) |
| runbook -> future host changes | Written commands will later run as root on the NAS | Boot args, firmware package, initramfs (availability-critical) |
| lever result -> conclusions | A batch under a changed driver or firmware may not exercise the same encode path | Measurement validity |
| agent -> git index | Unrelated uncommitted files exist in the working tree | Unrelated work-in-progress files |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation (evidence) | Status |
|-----------|----------|-----------|-------------|-----------------------|--------|
| T-03-01 | Tampering | tools/capability_probe.sh run as root on the NAS | mitigate | `bash -n` passes on the committed script (re-run in this audit). Comment-filtered grep of code lines: no banned state-changing program (rm only at `capability_probe.sh:157`, restricted to `capability_probe.*` dirs under PROBE_TMP); only `rpm -q/-qf/-qa`, `grubby --info/--default-kernel`, `dnf ... list --upgrades` (lines 635, 678, 689, 700, 709, 720, 734, 746); no redirect into `/etc /sys /proc /boot /usr /lib /var`; the privilege tool appears only as `sudo -n true` (line 353) and only when not root (lines 345-352); writability via `test -w` only (line 459); the only file creation is `mktemp -d` + `mkdir -p` under PROBE_TMP (lines 711, 719) with an EXIT trap cleanup (lines 153-159, 716); dnf state redirected into PROBE_TMP via `--setopt=cachedir/system_cachedir/logdir/persistdir/countme=0` (line 720). Container run + `find -newer` write check recorded: `03-EVIDENCE.md:281` "no files created or modified outside scratch/host-levers/". Current script sha256 `1dd50376...a95d1c` equals the `script_sha256` of both the container (`03-EVIDENCE.md:163`) and the host run (`03-EVIDENCE.md:299`, match recorded at `:290`). Script history: commits 667714de (add) and b7c94b84 (one-line modprobe.d grep fix) only | closed |
| T-03-02 | Information disclosure | probe outputs and checkpoint text committed to git | mitigate | In-script positive filtering: `fw_filter` (`capability_probe.sh:495-497`), `journalctl -o cat` (line 511), grubby output restricted to `index/kernel/args/root/initrd/title` (line 675, id line dropped), group list limited to six privilege names (lines 336-340), numeric-only SUDO_UID (lines 241-244), no hostname/network/disk-id/user-list tool called (grep of code lines), `redact()` for UUID, MAC, 32-hex id, `/home/NAME`, own hostname (lines 844-863) applied to the whole output (line 938), URL redaction in error lines (line 139). Layered controls caught the one leak: dnf key-import prompts (third-party repo URLs, fingerprints, vendor e-mail) arrived via the `firmware_upgrades` capture; operator review removed them from the tracked copy (`03-EVIDENCE.md:491`, record at `:292`, `executor redactions: 2`; the other redaction is the host user name in answer (c), `:572`). Tracked files re-scanned in this audit: no `http(s)://`, fingerprint pattern or e-mail address in EVIDENCE, RUNBOOK or SUMMARY; no `/home/` path; `REDACTED-USER` marker present. Automated gate re-run: `git grep -qiwFf scratch/host-levers/.scan_terms -- .` exit status 1 (no tracked file contains a scan term). `.scan_terms` and `operator_answers.txt` are git-ignored (`git check-ignore` lists both). See Hardening Note H-01 | closed |
| T-03-03 | Denial of service | runbook lever commands on the NAS | mitigate | Nothing executed (D-07): host and container were only probed; `03-RUNBOOK.md` Command validation status table (lines 166-184) marks every mutating command; the exact marker `untested — verify on first use` appears on L1 steps 1-4 (lines 98-101), L1 rollback (113), L2 change (138, 140), L2 rollback (154-155). Per-lever `### Rollback` (lines 111, 152) and `### Emergency` (lines 115, 158: GRUB menu edit via console, older kernel entry, `.pre-fw` initramfs). Prerequisites require operator-declared restart window and console (lines 41, 92, 133). The `!` quoting pitfall is documented at line 138 (single quotes required). Runbook commit 3f602857 touched only `03-RUNBOOK.md` and `.planning/REQUIREMENTS.md` | closed |
| T-03-04 | Spoofing | lever result interpretation (measurement soundness) | mitigate | `03-RUNBOOK.md`: `## Encode-path gate` (line 70) diffs `[user]` keys against `tools/encode_path_baseline_i915.txt` (tracked, 57 lines) and states the baseline is valid only for the A380/i915 (line 72), so a changed device fails closed; per-run trigger-path lines and `cand_bitexact` md5 comparison (line 78); stock binary sha256 `f4282c49...c3cbdb` asserted (lines 50, 60); before-batch positive control, STOP if not reproduced (line 68); md5 oracle fail-closed on any `D`/`?` (lines 52, 66); paired ffmpeg control must be 0/N (line 49); N=20 detection, N=60 validation, no "clean" claim under 60 iterations (lines 53, 68, 164); one lever per reboot (L1/L2 batch IDs, line 63) | closed |
| T-03-05 | Repudiation | operator-supplied host output and answers | mitigate | `03-EVIDENCE.md`: END marker and `context: host` verified (`:289`); script hash match recorded and independently re-verified in this audit (`:290`, `:299`); verbatim snapshots with source paths (`:157`, `:283`, `:565-567`); operator answers quoted verbatim with date 2026-10-24 (`:567`); redactions disclosed and counted (`:292`), original `host_probe.txt` retained unedited in scratch. Hash mismatch label ("UNVERIFIED SCRIPT") not triggered because the hashes match | closed |
| T-03-06 | Elevation of privilege | container -> host | accept | See Accepted Risks Log AR-03-06. Corroborated by evidence: container `uid_map: 0 1010 1`, `cap_sys_admin/module/boot: NO` (`03-EVIDENCE.md:47`); probe only reads and uses `test -w` | closed |
| T-03-07 | Tampering | git history (unrelated uncommitted work) | mitigate | `git show --stat` of 667714de, b7c94b84, 7083d351, 3f602857, ebccf5d7, 4eb452b6: only phase-03 files plus `.planning/REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md` (as the plan allows). No commit touches `.planning/PROJECT.md`, `.planning/config.json`, `PROJECT.md`, `.planning/state.json`, `.planning/milestone.lock`, `.gsd/`, `HANDOFF*`, `UPSTREAM-8.31-RECHECK.md`. `git status` at audit time: those paths are still modified/untracked, exactly as before the phase | closed |
| T-03-SC | Tampering | npm/pip/cargo installs | accept | See Accepted Risks Log AR-03-SC. No install command appears in the probe's code lines (only `rpm -q*` and `dnf list --upgrades`) and no phase commit adds a dependency or lockfile | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Hardening Notes (non-blocking)

| ID | Related Threat | Note |
|----|----------------|------|
| H-01 | T-03-02 | The `firmware_upgrades` key (`capability_probe.sh:720`) captures dnf stdout and stderr unfiltered (`2>&1`), so on a host with third-party repositories dnf emitted OpenPGP key-import prompts with repo URLs, fingerprints and a vendor e-mail into the probe output. In-script redaction does not cover URLs outside error lines. The leak was contained by operator review and the executor redaction before commit. Before the probe is reused (e.g. for post-lever before/after captures in the v2 phase), recommend filtering the capture to package lines (e.g. keep only `^(linux-firmware|intel-gpu-firmware)` lines) and/or disabling third-party repos for the query (`--disablerepo` / `--repo=fedora,updates`). The script was not modified by this audit. |
| H-02 | T-03-04 | Cosmetic: the CAP-XE label in `03-EVIDENCE.md` still says "A380 currently bound to i915" while the cells describe the B50. Not security-relevant. |

---

## Unregistered Flags

None. `03-01-SUMMARY.md` `## Threat Flags` = "None."

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-03-06 | T-03-06 | The container lacks CAP_SYS_ADMIN, CAP_SYS_MODULE and CAP_SYS_BOOT and its root is mapped to an unprivileged host uid; the probe only reads and uses `test -w`; the phase performs no privileged action | operator via plan approval | 2026-10-03 |
| AR-03-SC | T-03-SC | No package installs in this phase, in the container or on the host; the runbook's later firmware upgrade uses Fedora-signed repositories and is not executed here | operator via plan approval | 2026-10-03 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-24 | 8 | 8 | 0 | bm-security-auditor |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-24
