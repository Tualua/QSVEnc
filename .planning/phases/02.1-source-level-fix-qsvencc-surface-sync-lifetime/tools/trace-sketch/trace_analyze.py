#!/usr/bin/env python3
"""trace_analyze.py -- compare corrupt (md5 D) vs clean (md5 S) hot-scene traces at chunk frame 299 (D-02).

usage: trace_analyze.py <cand-dir> [--scan scan.tsv] [--out trace_analysis.tsv] [--summary trace_summary.txt]

<cand-dir> holds runs/itNN/c923.{obu,trace} / c1129.{obu,trace} and reference/chunkSSS_ref.obu.
--scan is the d01_scan_batch.sh TSV (iter scene harness_psnr best_idx ...); best_idx is the chunk frame whose
content the corrupt frame 299 carries (the "stale" frame). stdlib only; record layout "<QQQqIiiiiHH" (56 B)
as written by qsv_surf_trace.h / decoded by qsv_trace_dump.py.

Fail closed: a missing/short trace, a missing obu or an md5 that cannot be computed makes the run class "?"
and it is excluded from the D-vs-S statistics (listed in the summary), never counted as clean.
"""
import argparse
import hashlib
import os
import statistics
import struct
import sys

F = "<QQQqIiiiiHH"
EV = {1: "POOL", 2: "GET_FREE", 3: "DEC_CALL", 4: "VPP_CALL", 5: "ENC_CALL", 6: "BS_SYNC", 7: "POLL"}
SCENES = (923, 1129)
HOT = 299
CONTRAST = range(289, 300)   # 289..299


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as fp:
        for chunk in iter(lambda: fp.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_trace(path):
    d = open(path, "rb").read()
    if d[:8] != b"QSVTRC01":
        raise ValueError("bad magic")
    recsz, cnt = struct.unpack_from("<II", d, 8)
    if recsz != struct.calcsize(F) or len(d) < 16 + cnt * recsz:
        raise ValueError("short/odd trace")
    recs = []
    t0 = None
    for k in range(cnt):
        t, surf, memid, ts, vaid, frame, a, b, c, ev, pool = struct.unpack_from(F, d, 16 + k * recsz)
        if t0 is None:
            t0 = t
        recs.append(dict(t=(t - t0) / 1000.0, surf=surf, memid=memid, ts=ts, vaid=vaid, frame=frame,
                         a=a, b=b, c=c, ev=EV.get(ev, ev), pool=pool))
    return recs


def analyse_run(recs):
    """Return {frame: row-dict} for every ENC_CALL frame of one trace."""
    slot1 = {r["surf"]: r["a"] for r in recs if r["ev"] == "POOL" and r["pool"] == 1}
    enc = {}
    for r in recs:
        if r["ev"] == "ENC_CALL" and r["frame"] >= 0 and r["frame"] not in enc:
            enc[r["frame"]] = r
    vpp = [r for r in recs if r["ev"] == "VPP_CALL" and r["pool"] == 1]
    gf = [r for r in recs if r["ev"] == "GET_FREE" and r["pool"] == 1 and r["surf"]]
    rows = {}
    last_enc_t_by_surf = {}
    for f in sorted(enc):
        e = enc[f]
        # VPP output record that produced this encoder input: last VPP_CALL with the same surface before the ENC call
        v = None
        for x in vpp:
            if x["surf"] == e["surf"] and x["t"] <= e["t"]:
                v = x
        # getFreeSurf that handed this surface to the VPP task: last GET_FREE with the same surface before that VPP call
        g = None
        if v is not None:
            for x in gf:
                if x["surf"] == e["surf"] and x["t"] <= v["t"]:
                    g = x
        prev_enc_t = last_enc_t_by_surf.get(e["surf"])
        rows[f] = dict(
            frame=f, slot=slot1.get(e["surf"], -1), surf=e["surf"],
            vpp_ts=(v["ts"] if v else None), enc_ts=e["ts"], locked=e["b"], syncpoint=e["c"], enc_sts=e["a"],
            retries=(g["c"] if g else None),
            nonfree_pop=(bin(g["b"] & 0xffffffff).count("1") if g else None),
            gap_us=((e["t"] - v["t"]) if v else None),
            reuse_gap_us=((g["t"] - prev_enc_t) if (g and prev_enc_t is not None) else None),
            t_enc=e["t"])
        last_enc_t_by_surf[e["surf"]] = e["t"]
    return rows


def load_scan(path):
    m = {}
    if not path or not os.path.exists(path):
        return m
    for ln in open(path):
        p = ln.rstrip("\n").split("\t")
        if len(p) >= 8 and p[0] != "iter":
            try:
                m[(p[0], int(p[1]))] = int(p[3])
            except ValueError:
                pass
    return m


def fmt(v):
    return "NA" if v is None else str(v)


def stats(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return "n=0"
    return "n=%d median=%s min=%s max=%s" % (len(vals), fmt(round(statistics.median(vals), 1)), fmt(min(vals)), fmt(max(vals)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cand")
    ap.add_argument("--scan")
    ap.add_argument("--out")
    ap.add_argument("--summary")
    a = ap.parse_args()
    cand = a.cand
    out = a.out or os.path.join(cand, "trace_analysis.tsv")
    summ = a.summary or os.path.join(cand, "trace_summary.txt")
    scan = load_scan(a.scan)
    refmd5 = {}
    for s in SCENES:
        rp = os.path.join(cand, "reference", "chunk%d_ref.obu" % s)
        refmd5[s] = md5_of(rp) if os.path.exists(rp) else None

    hdr = ["iter", "scene", "class", "stale_idx", "frame", "slot", "stale_slot", "same_slot_as_stale", "same_surf_as_stale",
           "vpp_ts", "enc_ts", "locked", "syncpoint", "retries", "nonfree_pop", "vpp_to_enc_gap_us", "slot_reuse_gap_us"]
    lines = ["\t".join(hdr)]
    excluded = []
    per = {}   # (cls, group) -> metric -> list ; group in {"299","pre"}
    same_slot = {"D": [0, 0], "S": [0, 0]}
    runs = sorted(d for d in os.listdir(os.path.join(cand, "runs")) if d.startswith("it"))
    nruns = 0
    for d in runs:
        it = d[2:]
        for s in SCENES:
            obu = os.path.join(cand, "runs", d, "c%d.obu" % s)
            trc = os.path.join(cand, "runs", d, "c%d.trace" % s)
            cls = "?"
            try:
                if not (os.path.exists(obu) and os.path.getsize(obu) > 0 and refmd5[s]):
                    raise ValueError("no obu/reference")
                cls = "S" if md5_of(obu) == refmd5[s] else "D"
                rows = analyse_run(load_trace(trc))
                if HOT not in rows:
                    raise ValueError("no ENC_CALL for frame 299")
            except (OSError, ValueError, struct.error) as ex:
                excluded.append("it%s/%d: %s" % (it, s, ex))
                continue
            nruns += 1
            stale = scan.get((it, s)) if cls == "D" else None
            stale_row = rows.get(stale) if stale is not None else None
            for f in CONTRAST:
                r = rows.get(f)
                if r is None:
                    continue
                ss = stale_row["slot"] if (stale_row and f == HOT) else None
                same_s = (r["slot"] == ss) if ss is not None else None
                same_p = (r["surf"] == stale_row["surf"]) if (stale_row and f == HOT) else None
                lines.append("\t".join(fmt(x) for x in (it, s, cls, stale, f, r["slot"], ss, same_s, same_p, r["vpp_ts"], r["enc_ts"],
                                                         r["locked"], r["syncpoint"], r["retries"], r["nonfree_pop"], r["gap_us"], r["reuse_gap_us"])))
                grp = "299" if f == HOT else "pre"
                for k, key in (("retries", "retries"), ("nonfree_pop", "nonfree_pop"), ("gap_us", "gap_us"),
                               ("reuse_gap_us", "reuse_gap_us"), ("locked", "locked")):
                    per.setdefault((cls, grp), {}).setdefault(k, []).append(r[key])
                if f == HOT and same_s is not None:
                    same_slot["D"][0 if same_s else 1] += 1
    open(out, "w").write("\n".join(lines) + "\n")

    ls = ["trace_analyze.py: cand=%s  traced hot-scene runs analysed=%d  (rows in %s)" % (cand, nruns, os.path.basename(out)),
          "excluded runs (fail closed, not counted): %s" % (", ".join(excluded) if excluded else "none")]
    nd = sum(1 for x in lines[1:] if x.split("\t")[2] == "D" and x.split("\t")[4] == str(HOT))
    ns = sum(1 for x in lines[1:] if x.split("\t")[2] == "S" and x.split("\t")[4] == str(HOT))
    ls.append("frame-299 runs: D=%d S=%d" % (nd, ns))
    for grp, title in (("299", "chunk frame 299"), ("pre", "frames 289..298 (contrast)")):
        ls.append("")
        ls.append("== %s ==" % title)
        for k in ("retries", "nonfree_pop", "gap_us", "reuse_gap_us", "locked"):
            for cls in ("D", "S"):
                ls.append("  %-13s %s  %s" % (k, cls, stats(per.get((cls, grp), {}).get(k, []))))
    ls.append("")
    ls.append("== stale-frame relation (D runs with a scan entry) ==")
    ls.append("  frame-299 encoder-input slot == slot of the stale frame's encoder input: yes=%d no=%d" % (same_slot["D"][0], same_slot["D"][1]))
    open(summ, "w").write("\n".join(ls) + "\n")
    print("\n".join(ls))


if __name__ == "__main__":
    sys.exit(main())
