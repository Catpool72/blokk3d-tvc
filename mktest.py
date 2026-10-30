#!/usr/bin/env python3
"""Generate harness scripts using symbol addresses from blokk_prof.sym."""
import re, sys
sym = {}
for line in open("blokk_prof.sym"):
    m = re.match(r"(\S+): EQU 0x([0-9A-Fa-f]+)", line)
    if m: sym[m.group(1)] = int(m.group(2), 16)
P, ST = sym["PIT"], sym["piece_px"]
t = []
t += [f"dump 20 {ST} 4", "key 22 8 0x20", "key 24 8 0", f"dump 30 {ST} 4",
      "key 40 2 0x40", "key 42 2 0", f"dump 50 {ST} 4", "shot 50 t_rot.ppm",
      "key 55 8 0x40", "key 85 8 0", f"dump 90 {ST} 4"]
for y in range(5):
    for x in range(5):
        t.append(f"poke 95 {P + 9*64 + y*8 + x} 1")
t += [f"poke 95 {P + 8*64} 1", f"poke 95 {P + 8*64 + 4*8 + 4} 1",
      "key 100 7 0x20", "key 102 7 0", f"dump 125 {P + 8*64} 40", f"dump 125 {P + 9*64} 40", "shot 125 t_after.ppm"]
for i in range(8):
    f = 140 + i * 25
    t += [f"key {f} 8 {[0x40,0x20,0x02,0x04][i%4]}", f"key {f+3} 8 0", f"key {f+6} 7 0x20", f"key {f+8} 7 0"]
t += ["shot 345 t_stack.ppm", f"dump 345 {P} 640"]
open("test2.txt", "w").write("\n".join(t) + "\n")
