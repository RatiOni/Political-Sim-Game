"""
Procedural continent geometry — the FALLBACK map when ui/assets/worldmap.png
is missing. Nine countries tile a 3×3 partition over a shared 4×4 node
lattice; every border is midpoint-displacement fractal noise keyed to its
endpoints, so adjacent countries generate the identical jagged line (no gaps).
Deterministic: fixed seeds → the same continent every launch.
"""

import math
import random
from collections import Counter

# Non-uniform grid dividers (bigger countries get more room). j=col (x), i=row (y).
_XS = [6, 28, 60, 94]     # column edges: widths 22, 32, 34 (centre & east larger)
_YS = [7, 31, 64, 94]     # row edges: heights 24, 33, 30 (middle band tallest)

# Which country occupies each grid cell (row, col), row 0 = north.
CELL_COUNTRY = {
    (0, 0): "nueva_costa", (0, 1): "veldoria", (0, 2): "solheim",
    (1, 0): "merova",      (1, 1): "ardenia",  (1, 2): "krasova",
    (2, 0): "qadir",       (2, 1): "terand",   (2, 2): "valmora",
}

# Deliberate targets for the four interior junction nodes: non-aligned so the
# internal borders slant rather than run as a rigid grid, while still giving
# the larger countries more room.
_INTERIOR_TARGET = {
    (1, 1): (24, 30),
    (1, 2): (66, 26),
    (2, 1): (31, 66),
    (2, 2): (58, 69),
}

_COAST_ROUGHNESS = 0.22     # land↔sea edges: jagged shoreline
_BORDER_ROUGHNESS = 0.12    # internal borders: gentler
_FRACTAL_DEPTH = 4          # subdivision passes per edge (→ 16 segments)


def _node_pos(i, j):
    """Deterministic position for lattice node (i,j)."""
    rnd = random.Random(hash(("node", i, j)) & 0xffffffff)
    interior = i in (1, 2) and j in (1, 2)
    if interior:
        bx, by = _INTERIOR_TARGET[(i, j)]
        jit = 3.0
        return (bx + (rnd.random() * 2 - 1) * jit, by + (rnd.random() * 2 - 1) * jit)
    bx, by = _XS[j], _YS[i]
    amp = 7.0
    dx = (rnd.random() * 2 - 1) * amp
    dy = (rnd.random() * 2 - 1) * amp
    # Push boundary nodes outward from centre so the coast bulges organically.
    vx, vy = bx - 50.0, by - 50.0
    blen = math.hypot(vx, vy) or 1.0
    push = 5.0
    return (bx + dx + vx / blen * push, by + dy + vy / blen * push)


_NODES = {(i, j): _node_pos(i, j) for i in range(4) for j in range(4)}


def _cell_nodes(r, c):
    """The four corner node-ids of grid cell (r,c), clockwise from top-left."""
    return [(r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c)]


# An edge shared by two cells is an internal border; one used once is coastline.
_edge_count = Counter()
for _rc in CELL_COUNTRY:
    _loop = _cell_nodes(*_rc)
    for _k in range(4):
        _edge_count[tuple(sorted([_loop[_k], _loop[(_k + 1) % 4]]))] += 1


def _fractal_edge(a, b, roughness, seed):
    """Midpoint-displacement polyline from a to b (inclusive)."""
    rnd = random.Random(seed)
    pts = [a, b]
    for depth in range(_FRACTAL_DEPTH):
        scale = roughness * (0.55 ** depth)
        out = []
        for k in range(len(pts) - 1):
            p, q = pts[k], pts[k + 1]
            out.append(p)
            mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
            dx, dy = q[0] - p[0], q[1] - p[1]
            length = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / length, dx / length  # perpendicular
            disp = (rnd.random() * 2 - 1) * scale * length
            out.append((mx + nx * disp, my + ny * disp))
        out.append(pts[-1])
        pts = out
    return pts


_edge_cache = {}
def _edge_points(na, nb):
    """Fractal points from node na to nb — identical (reversed) for the country
    on the other side of the border, so shared borders match exactly."""
    key = tuple(sorted([na, nb]))
    if key not in _edge_cache:
        a, b = _NODES[key[0]], _NODES[key[1]]
        roughness = _COAST_ROUGHNESS if _edge_count[key] == 1 else _BORDER_ROUGHNESS
        _edge_cache[key] = _fractal_edge(a, b, roughness, hash(("edge", key)) & 0xffffffff)
    pts = _edge_cache[key]
    return pts if (na, nb) == key else list(reversed(pts))


def _clamp(v):
    return max(2.0, min(98.0, v))


def _build():
    shapes, anchors = {}, {}
    for (r, c), cid in CELL_COUNTRY.items():
        loop = _cell_nodes(r, c)
        poly = []
        for k in range(4):
            seg = _edge_points(loop[k], loop[(k + 1) % 4])
            poly.extend(seg[:-1])  # drop last point; the next edge starts there
        shapes[cid] = [(round(_clamp(x), 1), round(_clamp(y), 1)) for (x, y) in poly]
        cxs = [_NODES[n][0] for n in loop]
        cys = [_NODES[n][1] for n in loop]
        anchors[cid] = (round(sum(cxs) / 4, 1), round(sum(cys) / 4, 1))
    return shapes, anchors


COUNTRY_SHAPES, COUNTRY_LABEL_ANCHOR = _build()
