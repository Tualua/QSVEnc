#!/usr/bin/env bash
# cand_setup.sh -- create an isolated per-candidate harness workdir WITHOUT modifying the harness (D-08).
#   scratch/cand-<name>/ gets: byte-identical harness.sh+lib.sh (sha256-pinned), shared stock-8.31
#   references (symlinks), a copy of the candidate binary as bin/qsvencc.real, and a bin/qsvencc PATH
#   shim that (a) exports env vars from cand.env, (b) drops args listed in cand.strip, (c) appends
#   args from cand.add, (d) if QSVENC_TRACE_ENABLE=1, derives QSVENC_TRACE_FILE=<-o path minus .obu>.trace
#   so every traced run lands next to its own output in runs/itNN/.
# usage: cand_setup.sh <name> <qsvencc-binary>
# then : cd scratch/cand-<name> && PATH="$PWD/bin:$PATH" ./harness.sh run-batch 20 2>&1 | tee batch.log
set -eu
NAME="${1:?candidate name}"; BIN="${2:?path to qsvencc binary}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"          # .../scratch
W="$ROOT/cand-$NAME"
PIN_HARNESS=4aaa0b67af93f151523e722ce3a704ccf97ba39f104ffb10e576fcd4d3b9be95
PIN_LIB=f124a234ed4588269e931731553859adff48b6dfc2ea201b64f4ad167f17daac
[[ -e "$W" ]] && { echo "ABORT: $W exists (never overwrite a candidate's archived outputs)"; exit 1; }
mkdir -p "$W/bin"
cp -p "$ROOT/repro/harness.sh" "$ROOT/repro/lib.sh" "$W/"
[[ "$(sha256sum < "$W/harness.sh" | awk '{print $1}')" == "$PIN_HARNESS" ]] || { echo "ABORT: harness.sh drifted from pinned sha256"; exit 1; }
[[ "$(sha256sum < "$W/lib.sh"     | awk '{print $1}')" == "$PIN_LIB"     ]] || { echo "ABORT: lib.sh drifted from pinned sha256"; exit 1; }
ln -s ../repro-831/reference         "$W/reference"            # shared, read-only stock-8.31 isolated references
ln -s ../repro-831/control_reference "$W/control_reference"
cp -p "$ROOT/repro-831/fingerprint.txt" "$W/fingerprint.txt"
cp -p "$BIN" "$W/bin/qsvencc.real"
sha256sum "$W/bin/qsvencc.real" > "$W/bin/qsvencc.real.sha256"
: > "$W/bin/cand.env"; : > "$W/bin/cand.strip"; : > "$W/bin/cand.add"
cat > "$W/bin/qsvencc" <<'SHIM'
#!/usr/bin/env bash
# PATH shim for the unmodified harness. Do not add output to stdout/stderr (logs are parsed).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -a; [[ -s "$HERE/cand.env" ]] && source "$HERE/cand.env"; set +a
declare -a in=("$@") out=()
mapfile -t strip < <(grep -v '^[[:space:]]*$' "$HERE/cand.strip" 2>/dev/null || true)   # one arg per line; each drops itself + its value
outfile=""
for ((i=0;i<${#in[@]};i++)); do
  a="${in[i]}"; drop=0
  for s in "${strip[@]}"; do [[ "$a" == "$s" ]] && { drop=1; break; }; done
  if (( drop )); then
    # drop the option and, if the next token is not another option, its value
    if (( i+1<${#in[@]} )) && [[ "${in[i+1]}" != -* ]]; then ((i++)); fi
    continue
  fi
  [[ "$a" == "-o" && $((i+1)) -lt ${#in[@]} ]] && outfile="${in[i+1]}"
  out+=("$a")
done
if [[ -s "$HERE/cand.add" ]]; then read -r -a add < "$HERE/cand.add"; out+=("${add[@]}"); fi
[[ -n "${QSVENC_TRACE_ENABLE:-}" && -n "$outfile" ]] && export QSVENC_TRACE_FILE="${outfile%.obu}.trace"
exec "$HERE/qsvencc.real" "${out[@]}"
SHIM
chmod +x "$W/bin/qsvencc" "$W/bin/qsvencc.real"
echo "candidate dir: $W"; echo "binary sha256: $(cut -d' ' -f1 "$W/bin/qsvencc.real.sha256")"
echo "next: edit $W/bin/cand.{env,strip,add} if needed; then: cd $W && PATH=\"\$PWD/bin:\$PATH\" ./harness.sh run-batch 20 2>&1 | tee batch.log"
