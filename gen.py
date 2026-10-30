#!/usr/bin/env python3
"""Build-time table generator for BLOKK 3D (TVC 64K, 4-colour mode).

Produces tables.inc:
  - pit size constants, layout constants (panel, gauge)
  - perspective tables SX[z*8+x], SY[z*8+y]  (256-aligned pages)
  - grid display list (static pit wireframe)
  - layer fill patterns for top faces and (darker) side faces
  - 3x5 font (ASCII 32..90) as 4-colour pixel masks
  - piece orientation records: rotation transitions, lattice extents,
    cubes, merged wireframe edges
"""
import sys

W, H, D = 5, 5, 10          # pit size (cells)
CX, CY = 100, 120           # screen centre of the pit (4-colour pixels / lines)
S0 = 38                     # cell size at the opening (z = 0), pixels
BOTTOM_RATIO = 1 / 3        # cell size at the bottom relative to the opening
XASPECT = 1.0               # horizontal pixel aspect correction

PANEL_COL = 50              # panel starts at byte column 50 (x = 200)
GAUGE_X1, GAUGE_X2 = 204, 227
GAUGE_TOP, GAUGE_BOTTOM = 110, 233

F = D * BOTTOM_RATIO / (1 - BOTTOM_RATIO)   # s(z) = S0 * F / (F + z)


def scale(z):
    return S0 * F / (F + z)


def sx(z, x):
    return int(round(CX + (x - W / 2) * scale(z) * XASPECT))


def sy(z, y):
    return int(round(CY + (y - H / 2) * scale(z)))


assert sx(0, W) < PANEL_COL * 4 - 2 and sx(0, 0) >= 0 and sy(0, 0) >= 0 and sy(0, H) <= 239


# ---------------------------------------------------------------- colours
def byte4(colors):
    """4 pixels (left..right), colour 0..3 -> TVC 4-colour byte.
    MAME: colour of pixel i = BIT(d,3-i)*2 + BIT(d,7-i)."""
    b = 0
    for i, c in enumerate(colors):
        if c & 1:
            b |= 1 << (7 - i)
        if c & 2:
            b |= 1 << (3 - i)
    return b


def checker(a, b):
    return byte4([a, b, a, b]), byte4([b, a, b, a])


def solid(a):
    return byte4([a] * 4), byte4([a] * 4)


def stripes(a, b):
    return byte4([a] * 4), byte4([b] * 4)


# colour 1 = grid (green), colour 2 = blocks (red), colour 3 = falling piece (white)
LAYER_PATTERNS = [solid(2), checker(2, 1), solid(1), checker(2, 0), stripes(2, 1), checker(1, 0)]


def side_of(p):
    """darker side face: top pattern on even rows, black on odd rows."""
    return p[0], 0


# ---------------------------------------------------------------- font 3x5
from font import FONT3x5


def glyph(ch):
    rows = FONT3x5.get(ch, "111 101 101 101 111").split()
    out = []
    for r in rows:
        m = 0
        for i, bit in enumerate(r):
            if bit == '1':
                m |= 0x88 >> i
        out.append(m)
    return out


# ---------------------------------------------------------------- pieces
PIECES = [
    ("I1", [(0, 0, 0)]),                                # 1x1x1 kocka
    ("I3", [(-1, 0, 0), (0, 0, 0), (1, 0, 0)]),
    ("V3", [(0, 0, 0), (1, 0, 0), (0, 1, 0)]),
    ("I4", [(-1, 0, 0), (0, 0, 0), (1, 0, 0), (2, 0, 0)]),
    ("L4", [(-1, 0, 0), (0, 0, 0), (1, 0, 0), (1, 1, 0)]),
    ("T4", [(-1, 0, 0), (0, 0, 0), (1, 0, 0), (0, 1, 0)]),
    ("S4", [(-1, 0, 0), (0, 0, 0), (0, 1, 0), (1, 1, 0)]),
    ("O4", [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0)]),
    ("B4", [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)]),   # tripod
    ("SL", [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 1, 1)]),   # screw left
    ("SR", [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 0, 1)]),   # screw right
]

# rotation ops in key order: Q A W S E D
ROTS = [
    lambda x, y, z: (x, -z, y),    # Q: x+
    lambda x, y, z: (x, z, -y),    # A: x-
    lambda x, y, z: (z, y, -x),    # W: y+
    lambda x, y, z: (-z, y, x),    # S: y-
    lambda x, y, z: (-y, x, z),    # E: z+
    lambda x, y, z: (y, -x, z),    # D: z-
]


def canon(cubes):
    return tuple(sorted(cubes))


def edges_of(cubes):
    occ = set(cubes)
    unit = set()
    for (cx, cy, cz) in cubes:
        for a in range(3):
            for j in (0, 1):
                for k in (0, 1):
                    p = [cx, cy, cz]
                    b, c = [i for i in range(3) if i != a]
                    p[b] += j
                    p[c] += k
                    unit.add((a, tuple(p)))
    vis = []
    for a, p in unit:
        b, c = [i for i in range(3) if i != a]
        cells = []
        for db, dc in ((-1, -1), (0, -1), (-1, 0), (0, 0)):
            q = list(p)
            q[b] += db
            q[c] += dc
            cells.append(tuple(q) in occ)
        n = sum(cells)
        if n in (1, 3) or (n == 2 and ((cells[0] and cells[3]) or (cells[1] and cells[2]))):
            vis.append((a, p))
    lines = {}
    for a, p in vis:
        b, c = [i for i in range(3) if i != a]
        lines.setdefault((a, p[b], p[c]), []).append(p[a])
    out = []
    for (a, pb, pc), ts in lines.items():
        ts.sort()
        b, c = [i for i in range(3) if i != a]
        start = prev = ts[0]
        for t in ts[1:] + [None]:
            if t is not None and t == prev + 1:
                prev = t
                continue
            p = [0, 0, 0]
            p[a], p[b], p[c] = start, pb, pc
            out.append((a, tuple(p), prev - start + 1))
            if t is not None:
                start = prev = t
    out.sort(key=lambda e: (e[0] == 2, e))
    return out


orients = []
orient_index = {}
piece_first = []
for name, cubes in PIECES:
    base = canon(cubes)
    assert min(c[2] for c in base) >= 0
    if base not in orient_index:
        orient_index[base] = len(orients)
        orients.append(base)
    piece_first.append(orient_index[base])
    todo = [base]
    while todo:
        o = todo.pop()
        for r in ROTS:
            n = canon(r(*c) for c in o)
            if n not in orient_index:
                orient_index[n] = len(orients)
                orients.append(n)
                todo.append(n)

assert len(orients) < 256
trans = [[orient_index[canon(r(*c) for c in o)] for r in ROTS] for o in orients]
for o in orients:
    for c in o:
        assert all(-2 <= v <= 2 for v in c), o

# ---------------------------------------------------------------- grid list
grid = []   # (type, a, b, c, d): 0=hline(y,x1,x2) 1=vline(x,y1,y2) 2=line(x1,y1,x2,y2)
for z in range(D + 1):
    grid.append((0, sy(z, 0), sx(z, 0), sx(z, W), 0))
    grid.append((0, sy(z, H), sx(z, 0), sx(z, W), 0))
    grid.append((1, sx(z, 0), sy(z, 0), sy(z, H), 0))
    grid.append((1, sx(z, W), sy(z, 0), sy(z, H), 0))
for x in range(W + 1):
    for y in (0, H):
        grid.append((2, sx(0, x), sy(0, y), sx(D, x), sy(D, y)))
for y in range(1, H):
    for x in (0, W):
        grid.append((2, sx(0, x), sy(0, y), sx(D, x), sy(D, y)))
for x in range(1, W):
    grid.append((1, sx(D, x), sy(D, 0), sy(D, H), 0))
for y in range(1, H):
    grid.append((0, sy(D, y), sx(D, 0), sx(D, W), 0))

# ---------------------------------------------------------------- gauge
cell = (GAUGE_BOTTOM - GAUGE_TOP + 1) // D
assert cell >= 4
gauge_y = [GAUGE_TOP + i * cell for i in range(D)]       # z = 0 at the top

# ---------------------------------------------------------------- emit
L = []
e = L.append
e("; generated by gen.py -- do not edit")
e(f"PIT_W equ {W}")
e(f"PIT_H equ {H}")
e(f"PIT_D equ {D}")
nflat = sum(1 for _, c in PIECES if all(v[2] == 0 for v in c))
assert all(all(v[2] == 0 for v in c) for _, c in PIECES[:nflat]), "flat pieces must come first"
e(f"NPIECES equ {len(PIECES)}")
e(f"NFLAT equ {nflat}")
e(f"NORIENTS equ {len(orients)}")
e(f"SPAWN_X equ {W // 2}")
e(f"SPAWN_Y equ {H // 2}")
e(f"PANEL_COL equ {PANEL_COL}")
e(f"GAUGE_X1 equ {GAUGE_X1}")
e(f"GAUGE_X2 equ {GAUGE_X2}")
e(f"GAUGE_H equ {cell - 2}")
e(f"PIT_CX equ {CX}")
e(f"PIT_CY equ {CY}")
e("")
e("    align 256")
e("SXTAB:")
for z in range(D + 1):
    e("    db " + ",".join(str(sx(z, x)) if x <= W else "0" for x in range(8)))
e("    align 256")
e("SYTAB:")
for z in range(D + 1):
    e("    db " + ",".join(str(sy(z, y)) if y <= H else "0" for y in range(8)))
e("")
# quarter-layer tables for the falling piece: row zq = 4*z (+ fraction), 8 bytes per row
QROWS = 4 * D + 1
assert QROWS * 8 <= 512


def sxq(zq, x):
    return int(round(CX + (x - W / 2) * scale(zq / 4) * XASPECT))


def syq(zq, y):
    return int(round(CY + (y - H / 2) * scale(zq / 4)))


for z in range(D + 1):
    for x in range(W + 1):
        assert sxq(4 * z, x) == sx(z, x) and syq(4 * z, x) == sy(z, x)
e("    align 256")
e("SXQ:")
for zq in range(QROWS):
    e("    db " + ",".join(str(sxq(zq, x)) if x <= W else "0" for x in range(8)))
e("    align 256")
e("    ds 256")
e("SYQ:")
for zq in range(QROWS):
    e("    db " + ",".join(str(syq(zq, y)) if y <= H else "0" for y in range(8)))
e("    align 256")
e("    ds 256")
e("LAYERPAT:   ; per depth z: even-row byte, odd-row byte (top faces)")
for z in range(D):
    a, b = LAYER_PATTERNS[z % len(LAYER_PATTERNS)]
    e(f"    db ${a:02X},${b:02X}")
e("SIDEPAT:    ; per depth z: side faces (darker)")
for z in range(D):
    a, b = side_of(LAYER_PATTERNS[z % len(LAYER_PATTERNS)])
    e(f"    db ${a:02X},${b:02X}")
e("GAUGE_Y:")
e("    db " + ",".join(str(v) for v in gauge_y))
e("")
e("FONT:       ; ASCII 32..90, 5 rows of pixel masks")
for code in range(32, 91):
    e(f"    db " + ",".join(f"${v:02X}" for v in glyph(chr(code))) + f"   ; '{chr(code)}'")
e("")
e(f'PITSIZE_STR: db "{W}X{H}X{D}",0')
e("")
e("GRIDLIST:")
for g in grid:
    e("    db " + ",".join(str(v) for v in g))
e("    db $FF")
e("")
# ---------------------------------------------------------------- sound effects
# step = (frames, frequency Hz, volume 0..15); TVC: f = 195312.5 / (4096 - pitch)
def pitch(f):
    return max(0, min(4094, int(round(4096 - 195312.5 / f))))


SFX = {
    "MOVE":   [(1, 1500, 5)],
    "ROT":    [(1, 900, 7), (1, 1200, 7)],
    "DROP":   [(1, 1600, 8), (1, 1200, 8), (1, 900, 8), (1, 650, 9), (1, 480, 10), (1, 180, 13), (1, 130, 11), (2, 95, 8)],
    "LOCK":   [(1, 180, 13), (1, 130, 11), (2, 95, 8)],
    "WHOOSH": [(1, 1600, 8), (1, 1400, 8), (1, 1200, 8), (1, 1000, 8), (1, 850, 8), (1, 700, 9), (1, 600, 9), (1, 500, 9), (1, 420, 10), (1, 350, 10)],
    "CLEAR1": [(3, 523, 12), (3, 659, 12), (3, 784, 12), (6, 1047, 12)],
    "CLEARN": [(2, 523, 13), (2, 659, 13), (2, 784, 13), (2, 1047, 13), (2, 1319, 13), (2, 1568, 13), (8, 2093, 13)],
    "LEVEL":  [(4, 784, 14), (4, 1047, 14), (4, 1319, 14), (10, 1568, 14), (4, 1319, 12), (12, 2093, 14)],
    "OVER":   [(8, 392, 13), (8, 330, 12), (8, 262, 11), (16, 196, 10)],
    "TITLE":  [(5, 523, 10), (5, 659, 10), (5, 784, 10), (5, 659, 10), (5, 784, 10), (12, 1047, 11)],
}
for name, steps in SFX.items():
    e(f"SFX_{name}:")
    for fr, f, v in steps:
        p = pitch(f)
        e(f"    db {fr},${p & 255:02X},${p >> 8:02X},{v}   ; {f} Hz")
    e("    db 0")
e("")
e("PIECE_FIRST:")
e("    db " + ",".join(str(v) for v in piece_first))
e("")
e("ORPTR:")
for i in range(len(orients)):
    e(f"    dw OR_{i}")
total_edges = 0
for i, o in enumerate(orients):
    ed = edges_of(list(o))
    total_edges += len(ed)
    xs = [c[0] for c in o]
    ys = [c[1] for c in o]
    zs = [c[2] for c in o]
    ext = [min(xs), max(xs) + 1, min(ys), max(ys) + 1, min(zs), max(zs) + 1]
    e(f"OR_{i}:")
    e("    db " + ",".join(str(t) for t in trans[i]))
    e("    db " + ",".join(str(v & 255) for v in ext))
    e(f"    db {len(o)}")
    e("    db " + ",".join(f"{c[0] & 255},{c[1] & 255},{c[2] & 255}" for c in o))
    e(f"    db {len(ed)}")
    for a, p, ln in ed:
        lx, ly, lz = (v + 2 for v in p)
        assert 0 <= lx <= 5 and 0 <= ly <= 5 and 0 <= lz <= 5 and 1 <= ln <= 5
        e(f"    db ${(a << 6) | (ly << 3) | lx:02X},${(ln << 4) | lz:02X}")

open(sys.argv[1] if len(sys.argv) > 1 else "tables.inc", "w").write("\n".join(L) + "\n")
print(f"pit {W}x{H}x{D}, orientations {len(orients)}, edges {total_edges}, grid items {len(grid)}, "
      f"gauge cell {cell}", file=sys.stderr)
