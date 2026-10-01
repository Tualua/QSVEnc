#!/usr/bin/env python3
"""Decode a QSVTRC01 file written by qsv_surf_trace.h. usage: qsv_trace_dump.py <file> [--csv]"""
import struct, sys
F = "<QQQqIiiiiHH"                                  # t_ns surf memid ts vaid frame a b c ev pool  (56 bytes)
NAMES = {1:"POOL",2:"GET_FREE",3:"DEC_CALL",4:"VPP_CALL",5:"ENC_CALL",6:"BS_SYNC",7:"POLL"}
d = open(sys.argv[1], "rb").read()
assert d[:8] == b"QSVTRC01", "bad magic"
recsz, cnt = struct.unpack_from("<II", d, 8)
assert recsz == struct.calcsize(F) == 56
t0 = None
print("t_us\tev\tpool\tframe\tts\tsurf\tmemid\tvaid\ta\tb\tc")
for k in range(cnt):
    t, surf, memid, ts, vaid, frame, a, b, c, ev, pool = struct.unpack_from(F, d, 16 + k * recsz)
    t0 = t if t0 is None else t0
    print(f"{(t - t0)/1000:.1f}\t{NAMES.get(ev, ev)}\t{pool}\t{frame}\t{ts}\t{surf:#x}\t{memid:#x}\t{vaid:#x}\t{a}\t{b}\t{c}")
