# Phase 3: Host-Side Levers — Discussion Log

> Audit trail only. Downstream agents read 03-CONTEXT.md, not this file.

**Date:** 2026-10-03
**Areas discussed:** data sources for DIAG-01, form of deferred levers, phase process

## Data sources for DIAG-01
| Question | Options | Selected |
|---|---|---|
| Where does host-capability data come from? | container + host output (rec.) / container only / operator describes host | **container + read-only host script run by the operator** |
| What to record beyond capabilities? | GuC/HuC + linux-firmware versions (rec.) / capabilities only | **versions too** |

## Deferred levers
| Question | Options | Selected |
|---|---|---|
| Form | ready-to-run runbook (rec.) / short list | **runbook** |

## Process
| Question | Options | Selected |
|---|---|---|
| Phase process | lightweight: no research, one plan + checkpoint (rec.) / full GSD cycle | **lightweight** |

## Context gathered before questions
Container probe: root without CAP_SYS_ADMIN/CAP_SYS_MODULE; dmesg/debugfs blocked; i915 params unreadable; /proc/cmdline shows Fedora 43 host kernel; both i915 and xe drivers present, GPU bound to i915.

## Deferred
- Executing DIAG-03/04/05; reporting to Intel.
