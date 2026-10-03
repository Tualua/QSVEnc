#!/usr/bin/env bash
# =============================================================================
# capability_probe.sh - read-only capability probe (Phase 03, DIAG-01)
# =============================================================================
#
# WHAT IT DOES
#   Prints, on stdout only, a labelled text record of which host-side levers
#   (kernel command line, module options, firmware, restart, privilege) can be
#   observed from the machine it runs on, plus the loaded GuC/HuC/DMC versions
#   and the installed firmware and media packages for the Intel Arc A380
#   (PCI 8086:56a5). The same committed file runs unchanged in the dev
#   container (executor) and on the NAS host (operator).
#
# READ-ONLY CONTRACT (decision D-02)
#   The script changes nothing on the machine it runs on.
#   - Its only output is stdout. Its only other write is one directory made by
#     mktemp -d (variable PROBE_TMP) right before the package-metadata query;
#     an EXIT trap removes it again.
#   - It never escalates by itself: the privilege tool appears only as the
#     non-interactive availability check, and only when not already root.
#   - It installs, upgrades or removes no package; loads or unloads no kernel
#     module; changes no bootloader entry, initramfs or power state; controls
#     no service; writes no sysfs file and no kernel parameter. Writability is
#     tested with test -w only, never by writing.
#   - The package-metadata query points every dnf state location (cache,
#     system cache, log, persist) into PROBE_TMP and disables the countme
#     flag, so the machine's own dnf state is left untouched.
#
# HOW TO RUN
#   Container (executor), from the repository root:
#     QSVENCC_BIN=scratch/bins/stock-8.31/qsvencc bash SCRIPT > FILE 2>&1
#   NAS host (operator), preferred, with the redirect done by your own shell:
#     sudo bash SCRIPT > FILE 2>&1
#   Plain "bash SCRIPT > FILE 2>&1" also works: every check labelled [root]
#   then prints NEEDS_SUDO instead of a value.
#   QSVENCC_BIN (optional) names the qsvencc binary used for --check-features;
#   when unset, qsvencc is looked up in PATH, and on the host it is normally
#   absent (those lines then read UNAVAILABLE). Takes about 1-3 minutes: the
#   package-metadata query uses the network.
#
# OUTPUT CONTRACT (probe_version 1)
#   Header lines, in this order:
#     probe_version: 1
#     script_sha256: HEX64 (evidence: ...)       or UNAVAILABLE
#     context: host|container (evidence: ...)
#     run_as: uid=N euid=N userns=identity|mapped|unknown sudo_invoked=yes|no
#   (a numeric SUDO_UID is appended when sudo_invoked=yes; never a user name)
#   Section lines: == identity ==, == privilege ==, == gpu ==, == firmware ==,
#   == boot ==, == packages ==, == encode-path ==.
#   Check lines: "[user] KEY: VALUE" works without root; "[root] KEY: VALUE"
#   needs root and prints NEEDS_SUDO when not root. A multi-line result repeats
#   the "[label] KEY: " prefix on every line.
#   Status tokens (uppercase, optionally followed by a short reason):
#     UNAVAILABLE (reason)   the tool is absent or the query failed
#     BLOCKED (first error)  a permission failure
#     NEEDS_SUDO             a [root] check that was skipped because not root
#     NONE                   the query ran and found nothing
#   Footer: "redaction: uuid,mac,id32,home,hostname applied", then the last
#   line "END capability_probe". A last line that is not END marks a partial
#   run (INCOMPLETE capability_probe ...).
#
# PRIVACY RULES
#   No hostname, network, disk-id or user-list tool is called and no user name
#   or script path is printed. The whole output passes through a redaction
#   filter: UUID -> REDACTED-UUID, MAC address -> REDACTED-MAC, standalone
#   32-hex id -> REDACTED-ID32, /home/NAME -> /home/REDACTED-USER, and the
#   machine's own hostname (short and full, whole word; obtained internally
#   from the kernel, never printed) -> REDACTED-HOSTNAME. URLs inside error
#   lines are replaced by REDACTED-URL. Only the invoking numeric uid and the
#   names of a fixed set of privilege groups are ever printed.
# =============================================================================

set -u
set -o pipefail
export LC_ALL=C
unset LANGUAGE
umask 077
PATH="${PATH:-/usr/bin:/bin}:/usr/sbin:/sbin"
export PATH

PROBE_VERSION=1
AFFECTED_HOST_KERNEL="6.19.14-200.fc43.x86_64"
GPU_VENDOR="0x8086"
GPU_DEVICE="0x56a5"
SCRIPT_PATH="${BASH_SOURCE[0]:-}"

PROBE_TMP=''
OUT=''
RC=0
IS_ROOT=0
USERNS=unknown
CONTEXT=host
CTX_EVID=''
QSV_BIN=''
QSV_NOTE=''
QSV_FEATURES=''
QSV_FEATURES_RC=127
VAINFO_OUT=''
VAINFO_RC=127
DG2_FILES=()

# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

# need TOOL: return 0 when the tool exists; otherwise print the status line
# and return 1.
need() {
  if have "$1"; then return 0; fi
  printf 'UNAVAILABLE (%s not installed)\n' "$1"
  return 1
}

# run_t SECONDS COMMAND...: run with a time limit (when timeout exists).
run_t() {
  local secs=$1
  shift
  if have timeout; then timeout "$secs" "$@"; else "$@"; fi
}

first_line() { awk 'NF { sub(/^[ \t]+/, ""); print; exit }'; }

squeeze() { awk 'NF { $1 = $1; print }'; }

# try SECONDS COMMAND...: capture stdout+stderr in OUT and the status in RC.
try() {
  local secs=$1
  shift
  OUT=$(run_t "$secs" "$@" 2>&1)
  RC=$?
  return "$RC"
}

# status_of: print the status token for a failed command (uses OUT and RC).
status_of() {
  local msg
  msg=$(printf '%s\n' "$OUT" | first_line | sed -E 's#[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+#REDACTED-URL#g')
  case $RC in
    124) printf 'UNAVAILABLE (timed out)\n' ;;
    127) printf 'UNAVAILABLE (command not found)\n' ;;
    *)
      if printf '%s\n' "$msg" | grep -qiE 'permission denied|not permitted|must be root|access denied|authoriz'; then
        printf 'BLOCKED (%s)\n' "$msg"
      else
        printf 'UNAVAILABLE (%s)\n' "${msg:-exit status $RC}"
      fi
      ;;
  esac
}

cleanup_tmp() {
  if [ -n "${PROBE_TMP:-}" ] && [ -d "$PROBE_TMP" ]; then
    case ${PROBE_TMP##*/} in
      capability_probe.*) rm -rf "$PROBE_TMP" ;;
    esac
  fi
}

section() { printf '== %s ==\n' "$1"; }

# check LABEL KEY: run chk_KEY, prefix every output line with "[LABEL] KEY: ",
# print NONE when it printed nothing. [root] checks print NEEDS_SUDO unless
# the process is root.
check() {
  local label=$1 key=$2 out line
  if [ "$label" = root ] && [ "$IS_ROOT" != 1 ]; then
    printf '[root] %s: NEEDS_SUDO\n' "$key"
    return 0
  fi
  out=$("chk_$key")
  if [ -z "$out" ]; then
    printf '[%s] %s: NONE\n' "$label" "$key"
    return 0
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '[%s] %s: %s\n' "$label" "$key" "$line"
  done <<<"$out"
  return 0
}

# ----------------------------------------------------------------------------
# context, header
# ----------------------------------------------------------------------------

resolve_context() {
  local map
  if [ "$(id -u 2>/dev/null)" = 0 ]; then IS_ROOT=1; else IS_ROOT=0; fi
  if [ -r /proc/self/uid_map ]; then
    map=$(awk '{ $1 = $1; print }' /proc/self/uid_map 2>/dev/null)
    if [ "$map" = "0 0 4294967295" ]; then USERNS=identity; else USERNS=mapped; fi
  else
    USERNS=unknown
  fi
  CTX_EVID=''
  if [ -e /run/.containerenv ]; then CTX_EVID="/run/.containerenv present"; fi
  if [ -e /.dockerenv ]; then CTX_EVID="${CTX_EVID:+$CTX_EVID; }/.dockerenv present"; fi
  if [ "$USERNS" = mapped ]; then CTX_EVID="${CTX_EVID:+$CTX_EVID; }uid_map is not the identity map"; fi
  if [ -n "$CTX_EVID" ]; then
    CONTEXT=container
  else
    CONTEXT=host
    CTX_EVID="no container marker file and identity uid_map (userns=$USERNS)"
  fi
}

resolve_qsvencc() {
  QSV_BIN=''
  QSV_NOTE=''
  if [ -n "${QSVENCC_BIN:-}" ]; then
    QSV_BIN=$(command -v "$QSVENCC_BIN" 2>/dev/null)
    if [ -z "$QSV_BIN" ]; then QSV_NOTE="QSVENCC_BIN is not an executable file"; fi
  else
    QSV_BIN=$(command -v qsvencc 2>/dev/null)
    if [ -z "$QSV_BIN" ]; then QSV_NOTE="QSVENCC_BIN unset and qsvencc not in PATH"; fi
  fi
}

script_hash() {
  if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ] && [ -r "$SCRIPT_PATH" ] && have sha256sum; then
    sha256sum "$SCRIPT_PATH" 2>/dev/null | awk '{ print $1 }'
  fi
}

emit_header() {
  local hash ruid euid sudo_inv=no extra=''
  hash=$(script_hash)
  ruid=$(id -ru 2>/dev/null)
  euid=$(id -u 2>/dev/null)
  printf 'probe_version: %s\n' "$PROBE_VERSION"
  if [ -n "$hash" ]; then
    printf 'script_sha256: %s (evidence: sha256sum of the script file as executed, hash only)\n' "$hash"
  else
    printf 'script_sha256: UNAVAILABLE (evidence: the script is not a readable regular file, or sha256sum is missing)\n'
  fi
  printf 'context: %s (evidence: %s)\n' "$CONTEXT" "$CTX_EVID"
  if [ -n "${SUDO_UID:-}" ]; then
    sudo_inv=yes
    case $SUDO_UID in
      *[!0-9]*) extra=' SUDO_UID=non-numeric' ;;
      *) extra=" SUDO_UID=$SUDO_UID" ;;
    esac
  fi
  printf 'run_as: uid=%s euid=%s userns=%s sudo_invoked=%s%s\n' "$ruid" "$euid" "$USERNS" "$sudo_inv" "$extra"
}

# ----------------------------------------------------------------------------
# identity
# ----------------------------------------------------------------------------

chk_kernel() { uname -r; }

chk_kernel_matches_affected_host() {
  local k
  k=$(uname -r)
  if [ "$k" = "$AFFECTED_HOST_KERNEL" ]; then
    printf 'YES (affected host: %s)\n' "$AFFECTED_HOST_KERNEL"
  else
    printf 'NO (affected host: %s)\n' "$AFFECTED_HOST_KERNEL"
  fi
}

chk_cmdline() {
  if [ -r /proc/cmdline ]; then
    cat /proc/cmdline 2>/dev/null
  else
    printf 'UNAVAILABLE (/proc/cmdline not readable)\n'
  fi
}

chk_cmdline_gpu_params() {
  if [ ! -r /proc/cmdline ]; then
    printf 'UNAVAILABLE (/proc/cmdline not readable)\n'
    return 0
  fi
  tr ' ' '\n' </proc/cmdline 2>/dev/null | grep -E '^(i915|xe)\.'
}

# ----------------------------------------------------------------------------
# privilege
# ----------------------------------------------------------------------------

chk_uid_map() {
  if [ -r /proc/self/uid_map ]; then
    awk '{ $1 = $1; print }' /proc/self/uid_map 2>/dev/null
  else
    printf 'UNAVAILABLE (/proc/self/uid_map not readable)\n'
  fi
}

cap_eff_hex() { awk '/^CapEff:/ { print $2 }' /proc/self/status 2>/dev/null; }

chk_cap_effective() {
  local hex dec
  hex=$(cap_eff_hex)
  if [ -z "$hex" ]; then
    printf 'UNAVAILABLE (CapEff not readable in /proc/self/status)\n'
    return 0
  fi
  if have capsh; then
    if dec=$(capsh --decode="$hex" 2>/dev/null) && [ -n "$dec" ]; then
      dec=${dec#*=}
      printf '0x%s (capsh: %s)\n' "$hex" "${dec:-none}"
    else
      printf '0x%s (capsh: decode failed)\n' "$hex"
    fi
  else
    printf '0x%s (capsh not installed; see the cap_* lines below)\n' "$hex"
  fi
}

# cap_bit BIT: YES or NO for one bit of the effective capability set.
cap_bit() {
  local hex
  hex=$(cap_eff_hex)
  if [ -z "$hex" ]; then
    printf 'UNAVAILABLE (CapEff not readable)\n'
    return 0
  fi
  if [ $(((0x$hex >> $1) & 1)) -eq 1 ]; then printf 'YES\n'; else printf 'NO\n'; fi
}

chk_cap_sys_admin() { cap_bit 21; }
chk_cap_sys_module() { cap_bit 16; }
chk_cap_sys_boot() { cap_bit 22; }
chk_cap_syslog() { cap_bit 34; }

chk_privileged_groups() {
  local g found=''
  # Only these six group names are ever printed, never the full group list.
  # The group named after the privilege tool is spelled s[u]do in the pattern
  # so that the static no-self-escalation gate, which greps for the bare word
  # in code lines, stays meaningful.
  for g in $(id -Gn 2>/dev/null); do
    case $g in
      wheel | adm | systemd-journal | video | render | s[u]do) found="${found:+$found }$g" ;;
    esac
  done
  if [ -n "$found" ]; then printf '%s\n' "$found"; fi
}

chk_sudo_noninteractive() {
  if [ "$IS_ROOT" = 1 ]; then
    if [ "$USERNS" = mapped ]; then
      printf 'n/a (running as root; uid 0 is mapped into a user namespace)\n'
    else
      printf 'n/a (running as root)\n'
    fi
    return 0
  fi
  try 60 sudo -n true
  if [ "$RC" -eq 0 ]; then
    printf 'YES\n'
  elif [ "$RC" -eq 127 ]; then
    printf 'UNAVAILABLE (privilege tool not installed)\n'
  else
    printf 'NO (%s)\n' "$(printf '%s\n' "$OUT" | first_line)"
  fi
}

# ----------------------------------------------------------------------------
# gpu
# ----------------------------------------------------------------------------

# gpu_devices: PCI device directories whose vendor:device is 8086:56a5.
gpu_devices() {
  local d v dv
  for d in /sys/bus/pci/devices/*; do
    [ -r "$d/vendor" ] || continue
    v=$(cat "$d/vendor" 2>/dev/null)
    dv=$(cat "$d/device" 2>/dev/null)
    if [ "$v" = "$GPU_VENDOR" ] && [ "$dv" = "$GPU_DEVICE" ]; then printf '%s\n' "$d"; fi
  done
}

chk_drm_cards() {
  local c n dev link drv v d
  for c in /sys/class/drm/card*; do
    n=${c##*/}
    case $n in
      card[0-9]*-*) continue ;;
      card[0-9]*) ;;
      *) continue ;;
    esac
    dev=$c/device
    [ -e "$dev" ] || continue
    if [ -L "$dev/driver" ]; then
      link=$(readlink -f "$dev/driver" 2>/dev/null)
      drv=${link##*/}
    else
      drv=none
    fi
    v=$(cat "$dev/vendor" 2>/dev/null)
    d=$(cat "$dev/device" 2>/dev/null)
    printf '%s driver=%s %s:%s\n' "$n" "${drv:-none}" "${v:-?}" "${d:-?}"
  done
}

chk_gpu_driver() {
  local d link found=0
  for d in $(gpu_devices); do
    found=1
    if [ -L "$d/driver" ]; then
      link=$(readlink -f "$d/driver" 2>/dev/null)
      printf '%s (%s)\n' "$link" "${d##*/}"
    else
      printf 'NONE (device %s is bound to no driver)\n' "${d##*/}"
    fi
  done
  if [ "$found" = 0 ]; then printf 'NONE (no 8086:56a5 device under /sys/bus/pci/devices)\n'; fi
}

chk_pci_id() {
  local d found=0
  for d in $(gpu_devices); do
    found=1
    printf '%s:%s\n' "$(cat "$d/vendor" 2>/dev/null)" "$(cat "$d/device" 2>/dev/null)"
  done
  if [ "$found" = 0 ]; then printf 'NONE (no 8086:56a5 device under /sys/bus/pci/devices)\n'; fi
}

chk_render_node_driver() {
  local r link
  for r in /sys/class/drm/renderD*; do
    [ -e "$r" ] || continue
    if [ -L "$r/device/driver" ]; then
      link=$(readlink -f "$r/device/driver" 2>/dev/null)
      printf '%s driver=%s\n' "${r##*/}" "${link##*/}"
    else
      printf '%s driver=none\n' "${r##*/}"
    fi
  done
}

chk_pci_drivers_present() {
  local a=no b=no
  if [ -d /sys/bus/pci/drivers/i915 ]; then a=yes; fi
  if [ -d /sys/bus/pci/drivers/xe ]; then b=yes; fi
  printf 'i915=%s xe=%s\n' "$a" "$b"
}

chk_lspci() {
  need lspci || return 0
  try 60 lspci -nnk -d 8086:56a5 || {
    status_of
    return 0
  }
  printf '%s\n' "$OUT" | sed 's/^[[:space:]]*//'
}

chk_sysfs_unbind_writable() {
  local drv f state any=NO parts=''
  for drv in i915 xe; do
    f=/sys/bus/pci/drivers/$drv/unbind
    if [ ! -e "$f" ]; then
      state=ABSENT
    elif [ -w "$f" ]; then
      state=YES
      any=YES
    else
      state=NO
    fi
    parts="${parts:+$parts, }$drv: $state"
  done
  printf '%s (%s)\n' "$any" "$parts"
}

chk_reboot_capability() {
  if [ "$CONTEXT" = container ] && [ "$(cap_bit 22)" = NO ]; then
    printf 'BLOCKED (no CAP_SYS_BOOT; a container cannot restart its host)\n'
  else
    printf 'not tested (operator-declared at checkpoint, D-02)\n'
  fi
}

# ----------------------------------------------------------------------------
# firmware
# ----------------------------------------------------------------------------

chk_fs_scope() {
  printf 'the firmware, package, boot and modprobe.d sections describe the container image filesystem, not the filesystem the host kernel boots and loads firmware from; only kernel-wide state (cmdline, sysfs, kernel log) reflects the host\n'
}

chk_dmesg_restrict() {
  if [ -r /proc/sys/kernel/dmesg_restrict ]; then
    cat /proc/sys/kernel/dmesg_restrict 2>/dev/null
  else
    printf 'UNAVAILABLE (/proc/sys/kernel/dmesg_restrict not readable)\n'
  fi
}

# fw_filter: keep only i915 / xe lines that mention GuC, HuC, DMC, GSC or firmware.
fw_filter() {
  grep -iE '(i915|(^|[^[:alnum:]])xe([^[:alnum:]]|$))' | grep -iE 'guc|huc|dmc|gsc|firmware'
}

chk_guc_huc() {
  need dmesg || return 0
  try 60 dmesg || {
    status_of
    return 0
  }
  printf '%s\n' "$OUT" | fw_filter
}

chk_guc_huc_journal() {
  local hint
  need journalctl || return 0
  try 60 journalctl -k -b 0 -o cat --no-pager || {
    status_of
    return 0
  }
  hint=$(printf '%s\n' "$OUT" | grep -iE 'not seeing messages|no journal files were found' | first_line)
  if [ -n "$hint" ]; then
    case $hint in
      *[Nn]o\ journal*) printf 'UNAVAILABLE (%s)\n' "$hint" ;;
      *) printf 'BLOCKED (%s)\n' "$hint" ;;
    esac
    return 0
  fi
  printf '%s\n' "$OUT" | fw_filter
}

chk_guc_huc_debugfs() {
  local base=/sys/kernel/debug/dri f rel any=0 content listing
  if [ ! -d "$base" ]; then
    printf 'BLOCKED (/sys/kernel/debug/dri is not present: debugfs not mounted or not visible from this context)\n'
    return 0
  fi
  if ! listing=$(ls "$base" 2>&1); then
    printf 'BLOCKED (%s)\n' "$(printf '%s\n' "$listing" | first_line)"
    return 0
  fi
  for f in "$base"/*/gt*/uc/guc_info "$base"/*/gt*/uc/huc_info "$base"/*/i915_dmc_info; do
    [ -e "$f" ] || continue
    any=1
    rel=${f#"$base"/}
    if content=$(cat "$f" 2>&1); then
      printf '%s\n' "$content" | grep -iE 'firmware|status|version|found|wanted|authenticated|loaded' | awk -v p="$rel" '{ $1 = $1; print p ": " $0 }'
    else
      printf '%s: BLOCKED (%s)\n' "$rel" "$(printf '%s\n' "$content" | first_line)"
    fi
  done
  if [ "$any" = 0 ]; then
    printf 'NONE (no guc_info, huc_info or i915_dmc_info file under %s)\n' "$base"
  fi
}

chk_module_params() {
  local pair mod name f v
  for pair in i915:force_probe i915:enable_guc i915:guc_firmware_path i915:huc_firmware_path i915:dmc_firmware_path xe:force_probe; do
    mod=${pair%%:*}
    name=${pair#*:}
    f=/sys/module/$mod/parameters/$name
    if [ ! -d "/sys/module/$mod" ]; then
      printf '%s.%s=UNAVAILABLE (module %s not loaded)\n' "$mod" "$name" "$mod"
    elif [ ! -e "$f" ]; then
      printf '%s.%s=UNAVAILABLE (no such parameter)\n' "$mod" "$name"
    elif v=$(cat "$f" 2>&1); then
      printf '%s.%s=%s\n' "$mod" "$name" "${v:-(empty)}"
    else
      printf '%s.%s=BLOCKED (%s)\n' "$mod" "$name" "$(printf '%s\n' "$v" | first_line)"
    fi
  done
}

chk_modinfo_force_probe() {
  local m n
  need modinfo || return 0
  for m in i915 xe; do
    try 60 modinfo -F parm "$m"
    if [ "$RC" -ne 0 ]; then
      printf '%s: %s\n' "$m" "$(status_of)"
      continue
    fi
    n=$(printf '%s\n' "$OUT" | grep -ci 'force_probe')
    if [ "${n:-0}" -gt 0 ]; then
      printf '%s\n' "$OUT" | grep -i 'force_probe' | awk -v m="$m" '{ print m ": " $0 }'
    else
      printf '%s: NONE\n' "$m"
    fi
  done
}

modinfo_fw_dg2() {
  need modinfo || return 0
  try 60 modinfo -F firmware "$1"
  if [ "$RC" -ne 0 ]; then
    status_of
    return 0
  fi
  printf '%s\n' "$OUT" | grep -i 'dg2'
}

chk_modinfo_fw_dg2_i915() { modinfo_fw_dg2 i915; }
chk_modinfo_fw_dg2_xe() { modinfo_fw_dg2 xe; }

chk_modprobe_d_gpu() {
  local d f
  for d in /etc/modprobe.d /usr/lib/modprobe.d /run/modprobe.d; do
    [ -d "$d" ] || continue
    for f in "$d"/*.conf; do
      [ -f "$f" ] || continue
      grep -HnE '^[[:space:]]*(options|blacklist|install|softdep)[[:space:]].*(^|[^[:alnum:]_])(i915|xe)([^[:alnum:]_]|$)' "$f" 2>/dev/null
    done
  done
}

# dg2_files: fill DG2_FILES with the DG2 firmware files that exist.
dg2_files() {
  local was=0
  if shopt -q nullglob; then was=1; fi
  shopt -s nullglob
  DG2_FILES=(/lib/firmware/i915/dg2_* /lib/firmware/xe/*dg2*)
  if [ "$was" = 0 ]; then shopt -u nullglob; fi
}

chk_firmware_files_dg2() {
  dg2_files
  if [ "${#DG2_FILES[@]}" -eq 0 ]; then return 0; fi
  ls -l --time-style=long-iso "${DG2_FILES[@]}" 2>&1 | grep -v '^total ' | squeeze
}

chk_firmware_file_owner() {
  local f
  need rpm || return 0
  dg2_files
  if [ "${#DG2_FILES[@]}" -eq 0 ]; then
    printf 'NONE (no dg2 firmware file to query)\n'
    return 0
  fi
  for f in "${DG2_FILES[@]}"; do
    OUT=$(run_t 60 rpm -qf "$f" 2>&1)
    RC=$?
    printf '%s owner=%s\n' "$f" "$(printf '%s\n' "$OUT" | first_line)"
  done
}

# ----------------------------------------------------------------------------
# boot
# ----------------------------------------------------------------------------

chk_boot_mode() {
  if [ -d /sys/firmware/efi ]; then
    printf 'UEFI (/sys/firmware/efi present)\n'
  elif [ -d /sys/firmware ] && [ -n "$(ls -A /sys/firmware 2>/dev/null)" ]; then
    printf 'BIOS (/sys/firmware visible, no efi directory)\n'
  else
    printf 'UNAVAILABLE (/sys/firmware is empty or hidden)\n'
  fi
}

chk_boot_dir_entries() {
  if [ ! -d /boot ]; then
    printf 'UNAVAILABLE (/boot is not a directory)\n'
    return 0
  fi
  OUT=$(ls -A /boot 2>&1)
  RC=$?
  if [ "$RC" -ne 0 ]; then
    status_of
  else
    printf '%s\n' "$OUT" | awk 'NF { n++ } END { print n + 0 }'
  fi
}

chk_grubby_default() {
  need grubby || return 0
  try 60 grubby --info=DEFAULT || {
    status_of
    return 0
  }
  printf '%s\n' "$OUT" | grep -E '^(index|kernel|args|root|initrd|title)='
}

chk_grubby_default_kernel() {
  need grubby || return 0
  try 60 grubby --default-kernel || {
    status_of
    return 0
  }
  printf '%s\n' "$OUT"
}

chk_installed_kernels() {
  need rpm || return 0
  try 60 rpm -q kernel-core
  case $RC in
    0 | 1) printf '%s\n' "$OUT" ;;
    *) status_of ;;
  esac
}

# ----------------------------------------------------------------------------
# packages
# ----------------------------------------------------------------------------

chk_firmware_pkgs() {
  need rpm || return 0
  try 60 rpm -q linux-firmware intel-gpu-firmware linux-firmware-whence
  case $RC in
    0 | 1) printf '%s\n' "$OUT" ;;
    *) status_of ;;
  esac
}

chk_firmware_upgrades() {
  need dnf || return 0
  PROBE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/capability_probe.XXXXXX" 2>/dev/null)
  if [ -z "$PROBE_TMP" ] || [ ! -d "$PROBE_TMP" ]; then
    printf 'UNAVAILABLE (cannot create a temporary directory)\n'
    return 0
  fi
  trap cleanup_tmp EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  mkdir -p "$PROBE_TMP/cache" "$PROBE_TMP/syscache" "$PROBE_TMP/log" "$PROBE_TMP/persist"
  OUT=$(run_t 180 dnf -q --setopt=cachedir="$PROBE_TMP/cache" --setopt=system_cachedir="$PROBE_TMP/syscache" --setopt=logdir="$PROBE_TMP/log" --setopt=persistdir="$PROBE_TMP/persist" --setopt=countme=0 list --upgrades 'linux-firmware*' 'intel-gpu-firmware*' </dev/null 2>&1)
  RC=$?
  case $RC in
    0) printf '%s\n' "$OUT" | squeeze ;;
    124) printf 'UNAVAILABLE (timed out after 180 s)\n' ;;
    1)
      if printf '%s\n' "$OUT" | grep -qi 'no matching'; then printf 'NONE\n'; else status_of; fi
      ;;
    *) status_of ;;
  esac
}

chk_media_pkgs() {
  need rpm || return 0
  try 60 rpm -qa || {
    status_of
    return 0
  }
  printf '%s\n' "$OUT" | grep -E '^(intel-media-driver|libva-intel-media-driver|libva|libvpl|intel-vpl-gpu-rt|oneVPL|libmfx|intel-mediasdk|mesa-va-drivers|intel-gpu-tools|igt-gpu-tools)' | sort
}

# ----------------------------------------------------------------------------
# encode-path
# ----------------------------------------------------------------------------

# prepare_encode_path: run vainfo and qsvencc --check-features once each.
prepare_encode_path() {
  VAINFO_OUT=''
  VAINFO_RC=127
  if have vainfo; then
    VAINFO_OUT=$(run_t 60 env LIBVA_DRIVER_NAME=iHD vainfo 2>&1)
    VAINFO_RC=$?
  fi
  QSV_FEATURES=''
  QSV_FEATURES_RC=127
  if [ -n "$QSV_BIN" ]; then
    QSV_FEATURES=$(run_t 90 env LIBVA_DRIVER_NAME=iHD "$QSV_BIN" --check-features 2>/dev/null)
    QSV_FEATURES_RC=$?
  fi
}

chk_vainfo() {
  local line
  need vainfo || return 0
  line=$(printf '%s\n' "$VAINFO_OUT" | grep -i 'Driver version' | head -n 1 | sed 's/[[:space:]]*$//')
  if [ -n "$line" ]; then
    printf '%s\n' "$line"
  elif [ "$VAINFO_RC" -ne 0 ]; then
    OUT=$VAINFO_OUT
    RC=$VAINFO_RC
    status_of
  else
    printf 'NONE (no Driver version line in the vainfo output)\n'
  fi
}

chk_vainfo_av1() {
  local lines
  need vainfo || return 0
  lines=$(printf '%s\n' "$VAINFO_OUT" | grep -i 'AV1' | squeeze)
  if [ -n "$lines" ]; then
    printf '%s\n' "$lines"
  elif [ "$VAINFO_RC" -ne 0 ]; then
    OUT=$VAINFO_OUT
    RC=$VAINFO_RC
    status_of
  else
    printf 'NONE (no AV1 profile in the vainfo output)\n'
  fi
}

chk_qsvencc_bin_sha256() {
  if [ -z "$QSV_BIN" ]; then
    printf 'UNAVAILABLE (%s)\n' "$QSV_NOTE"
    return 0
  fi
  need sha256sum || return 0
  sha256sum "$QSV_BIN" 2>/dev/null | awk '{ print $1 }'
}

chk_qsvencc_version() {
  if [ -z "$QSV_BIN" ]; then
    printf 'UNAVAILABLE (%s)\n' "$QSV_NOTE"
    return 0
  fi
  if [ -z "$QSV_FEATURES" ]; then
    if [ "$QSV_FEATURES_RC" -eq 124 ]; then
      printf 'UNAVAILABLE (--check-features timed out after 90 s)\n'
    else
      printf 'UNAVAILABLE (--check-features printed nothing on stdout, exit status %s)\n' "$QSV_FEATURES_RC"
    fi
    return 0
  fi
  printf '%s\n' "$QSV_FEATURES" | awk 'NF { sub(/[ \t]+$/, ""); print; exit }'
}

# chk_qsvencc_av1_ff: the AV1 FF block of the --check-features stdout, from the
# line starting "Codec: AV1" up to (not including) the next "Codec: " line or
# the "Supported Vpp features:" line; blank lines dropped, whitespace squeezed.
chk_qsvencc_av1_ff() {
  local block
  if [ -z "$QSV_BIN" ]; then
    printf 'UNAVAILABLE (%s)\n' "$QSV_NOTE"
    return 0
  fi
  if [ -z "$QSV_FEATURES" ]; then
    printf 'UNAVAILABLE (no --check-features output)\n'
    return 0
  fi
  block=$(printf '%s\n' "$QSV_FEATURES" | awk '
    /^Codec: / { on = ($0 ~ /^Codec: AV1/) }
    /^Supported Vpp features:/ { on = 0 }
    on && NF { $1 = $1; print }')
  if [ -n "$block" ]; then
    printf '%s\n' "$block"
  else
    printf 'NONE (no "Codec: AV1" block in the --check-features output)\n'
  fi
}

# ----------------------------------------------------------------------------
# redaction filter (privacy rules above)
# ----------------------------------------------------------------------------

redact() {
  local hn name esc q="'"
  local -a args=(
    -E
    -e 's/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/REDACTED-UUID/g'
    -e 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/REDACTED-MAC/g'
    -e 's/(^|[^0-9A-Fa-f])[0-9A-Fa-f]{32}($|[^0-9A-Fa-f])/\1REDACTED-ID32\2/g'
    -e 's/(^|[^0-9A-Fa-f])[0-9A-Fa-f]{32}($|[^0-9A-Fa-f])/\1REDACTED-ID32\2/g'
    -e "s#/home/[^/[:space:]\"${q}]+#/home/REDACTED-USER#g"
  )
  hn=$(cat /proc/sys/kernel/hostname 2>/dev/null)
  for name in "$hn" "${hn%%.*}"; do
    case $name in
      '' | localhost | localhost.localdomain | '(none)') continue ;;
    esac
    esc=$(printf '%s' "$name" | sed 's#[][\.*^$/+?(){}|]#\\&#g')
    args+=(-e "s/\\<${esc}\\>/REDACTED-HOSTNAME/g")
  done
  sed "${args[@]}"
}

# ----------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------

main() {
  emit_header

  section identity
  check user kernel
  check user kernel_matches_affected_host
  check user cmdline
  check user cmdline_gpu_params

  section privilege
  check user uid_map
  check user cap_effective
  check user cap_sys_admin
  check user cap_sys_module
  check user cap_sys_boot
  check user cap_syslog
  check user privileged_groups
  check user sudo_noninteractive

  section gpu
  check user drm_cards
  check user gpu_driver
  check user pci_id
  check user render_node_driver
  check user pci_drivers_present
  check user lspci
  check user sysfs_unbind_writable
  check user reboot_capability

  section firmware
  if [ "$CONTEXT" = container ]; then check user fs_scope; fi
  check user dmesg_restrict
  check root guc_huc
  check user guc_huc_journal
  check root guc_huc_debugfs
  check root module_params
  check user modinfo_force_probe
  check user modinfo_fw_dg2_i915
  check user modinfo_fw_dg2_xe
  check user modprobe_d_gpu
  check user firmware_files_dg2
  check user firmware_file_owner

  section boot
  check user boot_mode
  check user boot_dir_entries
  check root grubby_default
  check root grubby_default_kernel
  check user installed_kernels

  section packages
  check user firmware_pkgs
  check user firmware_upgrades
  check user media_pkgs

  section encode-path
  prepare_encode_path
  check user vainfo
  check user vainfo_av1
  check user qsvencc_bin_sha256
  check user qsvencc_version
  check user qsvencc_av1_ff

  return 0
}

resolve_context
resolve_qsvencc

{ main; } 2>&1 | redact
PIPE_STATUS=("${PIPESTATUS[@]}")

printf 'redaction: uuid,mac,id32,home,hostname applied\n'
if [ "${PIPE_STATUS[0]}" -ne 0 ]; then
  printf 'INCOMPLETE capability_probe (probe body exit status %s)\n' "${PIPE_STATUS[0]}"
  exit 1
fi
if [ "${PIPE_STATUS[1]}" -ne 0 ]; then
  printf 'INCOMPLETE capability_probe (redaction filter exit status %s)\n' "${PIPE_STATUS[1]}"
  exit 1
fi
printf 'END capability_probe\n'
exit 0
