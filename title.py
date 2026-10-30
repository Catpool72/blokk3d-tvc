#!/usr/bin/env python3
"""Title screen generator for BLOKK 3D.

Renders the static title screen (256x240, 4 colours) into a TVC 4-colour
bitmap, RLE-compresses it, precomputes the rotating wireframe animation and
writes title.inc (+ title_preview.png with the dynamic parts filled in).

Colour indices: 0 black, 1 blue (shadows, frame), 2 red, 3 white.
"""
import math
import sys

from font import FONT3x5

W, H = 256, 240
TITLE_PAL = (0x00, 0x41, 0x44, 0x55)          # 0 I 0 G 0 R 0 B
PREVIEW_RGB = {0: (0, 0, 0), 1: (85, 85, 255), 2: (255, 85, 85), 3: (255, 255, 255)}

img = [[0] * W for _ in range(H)]


def px(x, y, c):
    if 0 <= x < W and 0 <= y < H:
        img[y][x] = c


def rect(x1, y1, x2, y2, c):
    for y in range(y1, y2 + 1):
        for x in range(x1, x2 + 1):
            px(x, y, c)


def hline(x1, x2, y, c):
    for x in range(x1, x2 + 1):
        px(x, y, c)


def vline(x, y1, y2, c):
    for y in range(y1, y2 + 1):
        px(x, y, c)


# ------------------------------------------------------------------ text (same layout as the Z80 print_chr)
def text(col, y, s, c):
    """byte-aligned 3x5 font, rows doubled: one char = 4 px wide, 10 lines."""
    for i, ch in enumerate(s):
        rows = FONT3x5.get(ch, "111 101 101 101 111").split()
        for r, bits in enumerate(rows):
            for k, b in enumerate(bits):
                if b == '1':
                    px((col + i) * 4 + k, y + 2 * r, c)
                    px((col + i) * 4 + k, y + 2 * r + 1, c)


def center_col(s):
    return (64 - len(s)) // 2


# ------------------------------------------------------------------ cube-letter logo (own 5x7 designs)
LOGO_GLYPHS = {
    'B': ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    'L': ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    'O': ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    'K': ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    '3': ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    'D': ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
}


def cube_cell(x, y, sw, sh, e, face, shade):
    """one small block: extruded shadow down-right, then the face (1 px gap to the next block)."""
    for d in range(1, e + 1):
        rect(x + d, y + d, x + d + sw - 2, y + d + sh - 2, shade)
    rect(x, y, x + sw - 2, y + sh - 2, face)


def logo(word, x0, y0, sw, sh, e, face, shade, gap=1):
    x = x0
    for ch in word:
        g = LOGO_GLYPHS[ch]
        cells = [(cx, cy) for cy, row in enumerate(g) for cx, b in enumerate(row) if b == '1']
        for cx, cy in sorted(cells, key=lambda t: -(t[0] + t[1])):   # back to front
            cube_cell(x + cx * sw, y0 + cy * sh, sw, sh, e, face, shade)
        x += (5 + gap) * sw
    return x


CW, CH, EXT = 5, 6, 2
w1 = 5 * 6 * CW - CW              # "BLOKK"
w2 = 2 * 6 * CW - CW              # "3D"
space = 2 * CW
lx = (W - (w1 + space + w2 + EXT)) // 2
LOGO_Y = 12
logo("BLOKK", lx, LOGO_Y, CW, CH, EXT, 2, 1)
logo("3D", lx + w1 + space, LOGO_Y, CW, CH, EXT, 3, 1)

# frame
for k, c in ((0, 1), (2, 1)):
    hline(k, W - 1 - k, k, c)
    hline(k, W - 1 - k, H - 1 - k, c)
    vline(k, k, H - 1 - k, c)
    vline(W - 1 - k, k, H - 1 - k, c)

sub = "TERBELI KIRAKOS JATEK"
text(center_col(sub), 62, sub, 3)
hline(40, 215, 76, 1)

# ------------------------------------------------------------------ animation area
ANIM_CX, ANIM_CY, ANIM_R = 128, 118, 34
# small perspective pit floor under the piece (static, blue): a diamond-ish frame
# animation work rectangle (byte columns / rows) - kept black, brackets outside it
ANIM_C0, ANIM_W, ANIM_Y0, ANIM_ROWS = 18, 29, 86, 65
BL, BR = ANIM_C0 * 4 - 10, (ANIM_C0 + ANIM_W) * 4 + 9
for x in (BL, BR):
    vline(x, 86, 150, 1)
for x1, x2 in ((BL, ANIM_C0 * 4 - 1), ((ANIM_C0 + ANIM_W) * 4, BR)):
    hline(x1, x2, 86, 1)
    hline(x1, x2, 150, 1)

# ------------------------------------------------------------------ controls
lines = [
    ("NYILAK, JOYSTICK", "MOZGATAS"),
    ("Q/A  W/S  E/D", "FORGATAS"),
    ("SZOKOZ, TUZ", "EJTES"),
    ("ESC", "KILEPES"),
]
LCOL = 14
for i, (k, v) in enumerate(lines):
    y = 160 + i * 11
    text(LCOL, y, k, 2)
    text(LCOL + 18, y, ":", 1)
    text(LCOL + 20, y, v, 3)

REC_LABEL = "REKORD:"
rec_col = center_col(REC_LABEL + " 0000000")
text(rec_col, 208, REC_LABEL, 2)
HISCORE_COL = rec_col + len(REC_LABEL) + 1
HISCORE_Y = 208

BLINK = "NYOMJ SZOKOZT!"
BLINK_COL = center_col(BLINK)
BLINK_Y = 224

# ------------------------------------------------------------------ to TVC bytes + RLE
def tvc_bytes(im):
    out = bytearray()
    for y in range(H):
        for xb in range(64):
            b = 0
            for i in range(4):
                c = im[y][xb * 4 + i]
                if c & 1:
                    b |= 1 << (7 - i)
                if c & 2:
                    b |= 1 << (3 - i)
            out.append(b)
    return out


def rle(data):
    """ctrl < $80: literal run of ctrl+1 bytes; $80..$FE: repeat next byte (ctrl-$80)+3 times; $FF end."""
    out = bytearray()
    i, n = 0, len(data)
    lit = bytearray()

    def flush():
        nonlocal lit
        while lit:
            chunk = lit[:128]
            out.append(len(chunk) - 1)
            out.extend(chunk)
            lit = lit[128:]

    while i < n:
        j = i
        while j < n and data[j] == data[i] and j - i < 129:
            j += 1
        run = j - i
        if run >= 3:
            flush()
            out.append(0x80 + run - 3)
            out.append(data[i])
            i = j
        else:
            lit.append(data[i])
            i += 1
    flush()
    out.append(0xFF)
    return out


def unrle(data):
    out = bytearray()
    i = 0
    while data[i] != 0xFF:
        c = data[i]
        i += 1
        if c < 0x80:
            out.extend(data[i:i + c + 1])
            i += c + 1
        else:
            out.extend([data[i]] * (c - 0x80 + 3))
            i += 1
    return out


raw = tvc_bytes(img)
packed = rle(raw)
assert unrle(packed) == raw

# ------------------------------------------------------------------ rotating wireframe (screw piece)
cubes = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 1, 1)]
occ = set(cubes)
edges = set()
for (cx, cy, cz) in cubes:
    for a in range(3):
        for j in (0, 1):
            for k in (0, 1):
                p = [cx, cy, cz]
                b, c = [i for i in range(3) if i != a]
                p[b] += j
                p[c] += k
                q = list(p)
                q[a] += 1
                # keep only outline edges (same rule as the game)
                cells = []
                for db, dc in ((-1, -1), (0, -1), (-1, 0), (0, 0)):
                    r = list(p)
                    r[b] += db
                    r[c] += dc
                    cells.append(tuple(r) in occ)
                nn = sum(cells)
                if nn in (1, 3) or (nn == 2 and ((cells[0] and cells[3]) or (cells[1] and cells[2]))):
                    edges.add((tuple(p), tuple(q)))
verts = sorted({v for e in edges for v in e})
vidx = {v: i for i, v in enumerate(verts)}
elist = sorted((vidx[a], vidx[b]) for a, b in edges)
cxm = sum(v[0] for v in verts) / len(verts)
cym = sum(v[1] for v in verts) / len(verts)
czm = sum(v[2] for v in verts) / len(verts)

NFRAMES = 48
SCALE = 19.0
DIST = 7.0
TILT = math.radians(28)
frames = []
for f in range(NFRAMES):
    t = 2 * math.pi * f / NFRAMES
    pts = []
    for (x, y, z) in verts:
        x, y, z = x - cxm, y - cym, z - czm
        # spin around the vertical axis, then tilt towards the viewer
        x, z = x * math.cos(t) + z * math.sin(t), -x * math.sin(t) + z * math.cos(t)
        y, z = y * math.cos(TILT) - z * math.sin(TILT), y * math.sin(TILT) + z * math.cos(TILT)
        k = DIST / (DIST + z)
        sx = int(round(ANIM_CX + x * SCALE * k))
        sy = int(round(ANIM_CY + y * SCALE * k))
        pts.append((sx, sy))
    frames.append(pts)
# centre the whole animation vertically inside the frame (y 88..148)
ys = [y for f in frames for _, y in f]
dy = (88 + 148) // 2 - (min(ys) + max(ys)) // 2
frames = [[(x, y + dy) for x, y in f] for f in frames]
for f in frames:
    for x, y in f:
        assert ANIM_C0 * 4 <= x < (ANIM_C0 + ANIM_W) * 4 and ANIM_Y0 <= y < ANIM_Y0 + ANIM_ROWS, (x, y)
for y in range(ANIM_Y0, ANIM_Y0 + ANIM_ROWS):
    for x in range(ANIM_C0 * 4, (ANIM_C0 + ANIM_W) * 4):
        assert img[y][x] == 0, "anim rectangle must be empty"


# ------------------------------------------------------------------ emit
L = []
e = L.append
e("; generated by title.py -- do not edit")
e(f"TITLE_PAL0 equ ${TITLE_PAL[0]:02X}")
e(f"TITLE_PAL1 equ ${TITLE_PAL[1]:02X}")
e(f"TITLE_PAL2 equ ${TITLE_PAL[2]:02X}")
e(f"TITLE_PAL3 equ ${TITLE_PAL[3]:02X}")
e(f"HISCORE_COL equ {HISCORE_COL}")
e(f"HISCORE_Y equ {HISCORE_Y}")
e(f"BLINK_COL equ {BLINK_COL}")
e(f"BLINK_Y equ {BLINK_Y}")
e(f"ANIM_NV equ {len(verts)}")
e(f"ANIM_NE equ {len(elist)}")
e(f"ANIM_NF equ {NFRAMES}")
e(f"ANIM_C0 equ {ANIM_C0}")
e(f"ANIM_W equ {ANIM_W}")
e(f"ANIM_Y0 equ {ANIM_Y0}")
e(f"ANIM_ROWS equ {ANIM_ROWS}")
e(f'STR_BLINK:  db "{BLINK}",0')
e(f'STR_NOBLINK: db "{" " * len(BLINK)}",0')
e("STR_END:")
e("ANIM_E:")
for a, b in elist:
    e(f"    db {a * 2},{b * 2}")
e("ANIM_FP:")
for f in range(NFRAMES):
    e(f"    dw ANIM_F{f}")
for f, pts in enumerate(frames):
    e(f"ANIM_F{f}: db " + ",".join(f"{x},{y}" for x, y in pts))
e(f"TITLE_RLE:   ; {len(raw)} -> {len(packed)} bytes")
for i in range(0, len(packed), 32):
    e("    db " + ",".join(f"${b:02X}" for b in packed[i:i + 32]))
open(sys.argv[1] if len(sys.argv) > 1 else "title.inc", "w").write("\n".join(L) + "\n")

# ------------------------------------------------------------------ preview (with dynamic parts)
if len(sys.argv) > 2:
    from PIL import Image
    prev = [row[:] for row in img]
    img = prev
    text(HISCORE_COL, HISCORE_Y, "0012345", 3)
    text(BLINK_COL, BLINK_Y, BLINK, 2)

    def line(x1, y1, x2, y2):
        n = max(abs(x2 - x1), abs(y2 - y1), 1)
        for i in range(n + 1):
            px(round(x1 + (x2 - x1) * i / n), round(y1 + (y2 - y1) * i / n), 3)

    for a, b in elist:
        (x1, y1), (x2, y2) = frames[5][a], frames[5][b]
        line(x1, y1, x2, y2)
    im = Image.new("RGB", (W * 2, H * 2))
    for y in range(H):
        for x in range(W):
            c = PREVIEW_RGB[img[y][x]]
            for dx in (0, 1):
                for dy in (0, 1):
                    im.putpixel((x * 2 + dx, y * 2 + dy), c)
    im.save(sys.argv[2])

print(f"title: {len(raw)} -> {len(packed)} bytes RLE, anim {len(verts)} verts, {len(elist)} edges, "
      f"{NFRAMES} frames", file=sys.stderr)
