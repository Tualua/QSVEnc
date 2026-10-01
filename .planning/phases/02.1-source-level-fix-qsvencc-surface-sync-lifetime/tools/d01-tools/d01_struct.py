#!/usr/bin/env python3
"""d01_struct.py -- AV1 coded-frame order of an .obu from ffmpeg's trace_headers BSF (no GPU).
usage: ffmpeg -hide_banner -loglevel debug -nostdin -i X.obu -c copy -bsf:v trace_headers -f null - 2> trace.txt
       d01_struct.py trace.txt [disp_lo disp_hi]
Prints KEY frame positions and, for display indices disp_lo..disp_hi, the coded sequence
(hidden ARF / shown / show_existing_frame) -> shows which frame is the mini-GOP anchor."""
import re, sys
lines = open(sys.argv[1]).read().splitlines()
frames, cur = [], None
def val(l):
    m = re.search(r'=\s*(-?\d+)\s*$', l); return int(m.group(1)) if m else None
for l in lines:
    if re.search(r'\bshow_existing_frame\b', l):
        cur = {'show_existing': val(l)}; frames.append(cur); continue
    if cur is None: continue
    for k in ('frame_type','show_frame','order_hint','refresh_frame_flags','frame_to_show_map_idx'):
        if re.search(r'\b%s\b' % k, l) and k not in cur: cur[k] = val(l)
disp = 0
for i, f in enumerate(frames):
    shown = f['show_existing'] == 1 or f.get('show_frame') == 1
    f['coded'] = i; f['disp'] = disp if shown else None
    disp += shown
print("coded frames:", len(frames), "shown:", disp)
print("KEY (coded, display):", [(f['coded'], f['disp']) for f in frames if f.get('frame_type') == 0 and f['show_existing'] == 0])
if len(sys.argv) >= 4:
    lo, hi = int(sys.argv[2]), int(sys.argv[3])
    sel = [f for f in frames if f['disp'] is not None and lo <= f['disp'] <= hi]
    a = min(f['coded'] for f in sel) - 3; b = max(f['coded'] for f in sel) + 2
    for f in frames[a:b]:
        print({k: v for k, v in f.items() if k not in ('coded',)}, 'coded#', f['coded'])
