#!/usr/bin/env python3
"""Trace the Limehead · Mix artwork from the supplied reference screenshot.

Usage:
    ffmpeg -i SCREENSHOT.jpg -vf "crop=934:498:250:62" -f rawvideo -pix_fmt rgb24 reference.rgb
    python3 scripts/trace_limehead.py reference.rgb native/LimeheadTrace.swift

SCREENSHOT is the 1280 x 720 capture the user supplied. The crop is the player's own
pixel space, which `LimeGeometry` uses (934 x 498: ffmpeg rounds a 935 px crop of this
4:2:0 source down to an even width). Only the Python standard library is needed.

What is traced, and how:

* Head outline: the dome against the desktop (a "lime" test that also rejects the
  teal wallpaper stripe), the sides where the head's dark edge line crosses the wings
  (per-row darkest point, smoothed), and the jaw and chin against the desktop (flood
  fill of desktop colours), joined into one closed outline.
* Head and face shading: the green channel, with the player's own controls painted out
  first (screen, title pill, buttons, window keys, seek groove, icons, mouse pointer)
  because the app draws live versions of those on top. Every 8 levels (31 in all) the
  outlines of the region at least that bright are found by marching squares with
  linear interpolation and kept to within 0.12 px. Each is filled with the reference's
  median colour for that brightness band, so stacking them darkest first reproduces
  the shading line for line.
* Screen: the outline of the red visualiser area; the part hidden by the title pill is
  completed as the straight top edge it is.
* Wings: each wing's outline and green shading the same way (panel contents painted
  out, since the app draws the mixer and playlist there), and each speaker separately:
  its outline plus 27 grey brightness layers, so silver is never averaged with green.
"""
import math
import sys

W, H = 934, 498
EPSILON = 0.12                       # outline tolerance in pixels
GREEN_LEVELS = list(range(10, 256, 8))
GREY_LEVELS = list(range(12, 256, 9))

# Player controls the app draws itself (painted out of the traced shading).
BUTTONS = [(395, 62), (426, 62), (458, 62), (488, 62), (539, 62)]
KEYS = (443, 13, 480, 31)
PILL = (355, 84, 576, 115)
SEEK = (367, 277, 569, 293)
ICONS = [(341, 272, 363, 295), (570, 272, 592, 295), (450, 294, 483, 326)]
POINTER = (531, 90, 555, 123)
LEFT_PANEL = (107.5, 125.5, 310.0, 295.5)
RIGHT_PANEL = (613.5, 126.5, 822.0, 295.5)
LEFT_SPEAKERS = [(48, 161), (66, 226), (64, 283)]
DESKTOP_ICON = (0, 108, 8, 139)      # "My Network Places" icon touching the left pod
WALLPAPER_STRIPE = (575, 40, 933, 112)  # teal wallpaper band resting on the right wing
RIGHT_SPEAKERS = [(886, 160), (865, 226), (868, 283)]


# ---------------------------------------------------------------- image access

def load(path):
    data = open(path, "rb").read()
    assert len(data) == W * H * 3, "expected a %d x %d rgb24 crop, got %d bytes" % (W, H, len(data))
    return data


def pixel(data, x, y):
    i = (y * W + x) * 3
    return data[i], data[i + 1], data[i + 2]


def sample(data, box, fn):
    x0, y0, w, h = box
    return [[fn(*pixel(data, x, y)) for x in range(x0, x0 + w)] for y in range(y0, y0 + h)]


def lum(r, g, b):
    return 0.299 * r + 0.587 * g + 0.114 * b


def desktop(r, g, b):
    """Anything that is not green and not deep shadow: the desktop behind the player."""
    if max(r, g, b) < 70:
        return False
    return not (g > r + 8 and g > b + 8)


def lime(r, g, b):
    """Positive on the lime head, negative on the blue desktop and teal wallpaper."""
    return min(g - r, g - 2.2 * b)


def neutral(r, g, b):
    """Silver, grey and black speaker parts."""
    return max(r, g, b) - min(r, g, b) < 60 and not (g > r + 20 and g > b + 20)


# ---------------------------------------------------------------- grid helpers

def flood(passable, seeds):
    h, w = len(passable), len(passable[0])
    seen = [[False] * w for _ in range(h)]
    stack = list(seeds)
    while stack:
        x, y = stack.pop()
        if 0 <= x < w and 0 <= y < h and not seen[y][x] and passable[y][x]:
            seen[y][x] = True
            stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    return seen


def border(w, h):
    return ([(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] +
            [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)])


def fill_holes(mask):
    h, w = len(mask), len(mask[0])
    outside = flood([[not v for v in row] for row in mask], border(w, h))
    return [[not outside[y][x] for x in range(w)] for y in range(h)]


def dilate(mask):
    h, w = len(mask), len(mask[0])
    return [[mask[y][x] or (x > 0 and mask[y][x - 1]) or (x < w - 1 and mask[y][x + 1]) or
             (y > 0 and mask[y - 1][x]) or (y < h - 1 and mask[y + 1][x]) for x in range(w)] for y in range(h)]


def blur3(a):
    """Separable 1-2-1 blur with clamped edges."""
    h, w = len(a), len(a[0])
    tmp = []
    for row in a:
        tmp.append([(row[max(0, x - 1)] + 2 * row[x] + row[min(w - 1, x + 1)]) / 4 for x in range(w)])
    return [[(tmp[max(0, y - 1)][x] + 2 * tmp[y][x] + tmp[min(h - 1, y + 1)][x]) / 4 for x in range(w)] for y in range(h)]


def inpaint_rows(values, holes):
    """Replace each run of hole pixels by a straight blend of its row neighbours."""
    h, w = len(values), len(values[0])
    for y in range(h):
        row, mask = values[y], holes[y]
        x = 0
        while x < w:
            if not mask[x]:
                x += 1
                continue
            start = x
            while x < w and mask[x]:
                x += 1
            left = row[start - 1] if start > 0 else None
            right = row[x] if x < w else None
            if left is None and right is None:
                continue
            if left is None:
                left = right
            if right is None:
                right = left
            for k in range(start, x):
                row[k] = left + (right - left) * (k - start + 1) / (x - start + 1)


def extend_rows(values, inside):
    """Outside the shape, carry each row's edge values outward (the drawing is clipped)."""
    h, w = len(values), len(values[0])
    spans = []
    for y in range(h):
        xs = [x for x in range(w) if inside[y][x]]
        spans.append((xs[0], xs[-1]) if xs else None)
    for y in range(h):
        if spans[y] is None:
            near = min((abs(k - y), k) for k in range(h) if spans[k] is not None)[1]
            values[y] = list(values[near])
            continue
        lo, hi = spans[y]
        for x in range(lo):
            values[y][x] = values[y][lo]
        for x in range(hi + 1, w):
            values[y][x] = values[y][hi]


def rasterize(poly, box):
    """Even-odd fill of a polygon onto the box's pixel centres."""
    x0, y0, w, h = box
    mask = [[False] * w for _ in range(h)]
    for row in range(h):
        yc = y0 + row + 0.5
        xs = []
        for i in range(len(poly)):
            (xa, ya), (xb, yb) = poly[i - 1], poly[i]
            if (ya <= yc < yb) or (yb <= yc < ya):
                xs.append(xa + (yc - ya) * (xb - xa) / (yb - ya))
        xs.sort()
        for k in range(0, len(xs) - 1, 2):
            start = max(0, int(math.ceil(xs[k] - x0 - 0.5)))
            end = min(w - 1, int(math.floor(xs[k + 1] - x0 - 0.5)))
            for col in range(start, end + 1):
                mask[row][col] = True
    return mask


def box_mask(box, rects=(), circles=()):
    x0, y0, w, h = box
    mask = [[False] * w for _ in range(h)]
    for (ax, ay, bx, by) in rects:
        for y in range(max(0, int(ay) - y0), min(h, int(math.ceil(by)) - y0 + 1)):
            for x in range(max(0, int(ax) - x0), min(w, int(math.ceil(bx)) - x0 + 1)):
                mask[y][x] = True
    for (cx, cy, r) in circles:
        for y in range(max(0, int(cy - r) - y0), min(h, int(cy + r) - y0 + 2)):
            for x in range(max(0, int(cx - r) - x0), min(w, int(cx + r) - x0 + 2)):
                if (x + x0 + 0.5 - cx) ** 2 + (y + y0 + 0.5 - cy) ** 2 <= r * r:
                    mask[y][x] = True
    return mask


def union(*masks):
    return [[any(m[y][x] for m in masks) for x in range(len(masks[0][0]))] for y in range(len(masks[0]))]


# ---------------------------------------------------------------- contours

EDGES = {1: ["LB"], 2: ["BR"], 3: ["LR"], 4: ["TR"], 6: ["TB"], 7: ["LT"], 8: ["LT"],
         9: ["TB"], 11: ["TR"], 12: ["LR"], 13: ["BR"], 14: ["LB"]}


def contours(values, threshold, x0, y0, pad=-1000.0):
    """Closed iso-lines around `values >= threshold`, in artwork coordinates."""
    h, w = len(values), len(values[0])
    pw, ph = w + 2, h + 2
    v = [[pad] * pw] + [[pad] + list(row) + [pad] for row in values] + [[pad] * pw]

    def point(key):
        kind, x, y = key
        if kind == "h":
            a, b = v[y][x], v[y][x + 1]
            f = 0.5 if a == b else (threshold - a) / (b - a)
            gx, gy = x + f, y
        else:
            a, b = v[y][x], v[y + 1][x]
            f = 0.5 if a == b else (threshold - a) / (b - a)
            gx, gy = x, y + f
        return (x0 + gx - 0.5, y0 + gy - 0.5)

    links, segments = {}, []
    for cy in range(ph - 1):
        top, bottom = v[cy], v[cy + 1]
        for cx in range(pw - 1):
            a, b, c, d = top[cx], top[cx + 1], bottom[cx + 1], bottom[cx]
            idx = (a >= threshold) << 3 | (b >= threshold) << 2 | (c >= threshold) << 1 | (d >= threshold)
            if idx == 0 or idx == 15:
                continue
            if idx == 5:
                pairs = ["LT", "BR"] if (a + b + c + d) / 4 >= threshold else ["TR", "LB"]
            elif idx == 10:
                pairs = ["TR", "LB"] if (a + b + c + d) / 4 >= threshold else ["LT", "BR"]
            else:
                pairs = EDGES[idx]
            keys = {"T": ("h", cx, cy), "R": ("v", cx + 1, cy), "B": ("h", cx, cy + 1), "L": ("v", cx, cy)}
            for pair in pairs:
                s = (keys[pair[0]], keys[pair[1]])
                links.setdefault(s[0], []).append(len(segments))
                links.setdefault(s[1], []).append(len(segments))
                segments.append(s)
    used = [False] * len(segments)
    loops = []
    for start in range(len(segments)):
        if used[start]:
            continue
        used[start] = True
        first, current = segments[start]
        keys = [first]
        while current != first:
            keys.append(current)
            nxt = next((i for i in links[current] if not used[i]), None)
            if nxt is None:
                break
            used[nxt] = True
            a, b = segments[nxt]
            current = b if a == current else a
        loops.append([point(k) for k in keys])
    return loops


def rdp(points, eps):
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        (x1, y1), (x2, y2) = points[i], points[j]
        dx, dy = x2 - x1, y2 - y1
        norm = math.hypot(dx, dy)
        best, index = 0.0, -1
        for k in range(i + 1, j):
            px, py = points[k]
            d = abs(dy * px - dx * py + x2 * y1 - y2 * x1) / norm if norm else math.hypot(px - x1, py - y1)
            if d > best:
                best, index = d, k
        if index >= 0 and best > eps:
            keep[index] = True
            stack += [(i, index), (index, j)]
    return [p for p, k in zip(points, keep) if k]


def simplify_loop(points, eps=EPSILON):
    if len(points) < 6:
        return points
    far = max(range(len(points)), key=lambda i: (points[i][0] - points[0][0]) ** 2 + (points[i][1] - points[0][1]) ** 2)
    return rdp(points[:far + 1], eps)[:-1] + rdp(points[far:] + [points[0]], eps)[:-1]


def area(points):
    return abs(sum(points[i][0] * points[i - 1][1] - points[i - 1][0] * points[i][1] for i in range(len(points)))) / 2


def split_chain(loop, split, below):
    """Longest run of a closed outline on one side of y = split, ends cut exactly at split."""
    n = len(loop)
    side = [(p[1] >= split) if below else (p[1] <= split) for p in loop]

    def cross(a, b):
        f = (split - a[1]) / (b[1] - a[1])
        return (a[0] + (b[0] - a[0]) * f, float(split))
    best = None
    for s in range(n):
        if not side[s] or side[s - 1]:
            continue
        chain = [cross(loop[s - 1], loop[s])]
        i = s
        while side[i % n] and len(chain) <= n:
            chain.append(loop[i % n])
            i += 1
        chain.append(cross(loop[(i - 1) % n], loop[i % n]))
        if best is None or len(chain) > len(best):
            best = chain
    return best


def mask_outline(mask, x0, y0, passes=1, average=0):
    """Sub-pixel outline of a binary mask, softened so it sits on the anti-aliasing.
    `average` > 0 also smooths the outline with a moving average of that many points on
    each side (for edges whose pixels classify unevenly, like silver against green)."""
    soft = [[255.0 if v else 0.0 for v in row] for row in mask]
    for _ in range(passes):
        soft = blur3(soft)
    loop = max(contours(soft, 127.5, x0, y0), key=area)
    if average:
        n = len(loop)
        loop = [(sum(loop[(i + k) % n][0] for k in range(-average, average + 1)) / (2 * average + 1),
                 sum(loop[(i + k) % n][1] for k in range(-average, average + 1)) / (2 * average + 1)) for i in range(n)]
    return loop


# ---------------------------------------------------------------- shading layers

def shading(values, inside, colour_pixels, levels, x0, y0):
    """Brightness layers of `values` (already painted out and extended), with colours
    taken as the median reference colour of each band over `colour_pixels`."""
    bands = [[] for _ in range(len(levels) + 1)]
    for (x, y, c) in colour_pixels:
        v = values[y - y0][x - x0]
        bands[sum(1 for t in levels if v >= t)].append(c)
    colours = []
    for members in bands:
        if members:
            mid = len(members) // 2
            colours.append(tuple(sorted(c[k] for c in members)[mid] for k in range(3)))
        else:
            colours.append(None)
    # Empty bands borrow the nearest filled neighbour.
    for i in range(len(colours)):
        if colours[i] is None:
            near = min((abs(k - i), k) for k in range(len(colours)) if colours[k] is not None)[1]
            colours[i] = colours[near]
    hexes = [(c[0] << 16) | (c[1] << 8) | c[2] for c in colours]
    layers = []
    for i, t in enumerate(levels):
        loops = [simplify_loop(loop) for loop in contours(values, t, x0, y0)]
        loops = [loop for loop in loops if len(loop) >= 3 and area(loop) >= 0.2]
        if loops:
            layers.append((hexes[i + 1], loops))
    return hexes[0], layers


# ---------------------------------------------------------------- the pieces

def trace_screen(data):
    box = (326, 80, 280, 205)
    x0, y0, w, h = box
    def passable(x, y):
        r, g, b = pixel(data, x, y)
        if POINTER[0] <= x <= POINTER[2] and POINTER[1] <= y <= POINTER[3]:
            return y >= 113                       # under the pointer: screen below the pill
        return not (g > r + 12 and g > b + 12)
    grid = [[passable(x, y) for x in range(x0, x0 + w)] for y in range(y0, y0 + h)]
    region = fill_holes(flood(grid, [(466 - x0, 190 - y0)]))
    loop = simplify_loop(mask_outline(region, x0, y0))
    # The pill hides the middle of the screen's straight top edge. Measure that edge in the
    # visible corners beside the pill, drop the outline that runs round the pill, and put
    # the straight edge back.
    def top_of(x):
        column = [region[y][x - x0] for y in range(h)]
        return y0 + column.index(True)
    top = (top_of(354) + top_of(355) + top_of(577) + top_of(578)) / 4.0
    gap = [i for i, p in enumerate(loop) if p[1] < 114.5 and 352 <= p[0] <= 580]
    assert gap, "no outline under the pill"
    n = len(loop)
    # Rotate so the hidden run is contiguous at the end, then replace it.
    start = next(i for i in gap if (i - 1) % n not in gap)
    rotated = loop[start:] + loop[:start]
    kept = [p for p in rotated if not (p[1] < 114.5 and 352 <= p[0] <= 580)]
    before, after = kept[-1], kept[0]
    edge = [(352.0, top), (580.0, top)] if before[0] < after[0] else [(580.0, top), (352.0, top)]
    print("screen top edge y %.1f (corners x 354/355/577/578 -> %s)" % (top, [top_of(x) for x in (354, 355, 577, 578)]))
    return region, box, kept + edge


def trace_head(data, screen_region, screen_box):
    # Dome: lime against desktop, above the wings.
    dome_box = (314, 0, 300, 121)
    dome = sample(data, dome_box, lime)
    dome_loop = max(contours(blur3(dome), 0.0, dome_box[0], dome_box[1]), key=area)
    dome_chain = split_chain(dome_loop, 112, below=False)
    if dome_chain[0][0] > dome_chain[-1][0]:
        dome_chain.reverse()                      # left crossing, over the top, right crossing

    # Jaw and chin: head against desktop, below the wings.
    jaw_box = (314, 280, 300, 218)
    passable = sample(data, jaw_box, desktop)
    jw, jh = jaw_box[2], jaw_box[3]
    background = flood(passable, [(x, jh - 1) for x in range(jw)] + [(0, y) for y in range(jh)] + [(jw - 1, y) for y in range(jh)])
    jaw_mask = [[not background[y][x] for x in range(jw)] for y in range(jh)]
    jaw_chain = split_chain(mask_outline(jaw_mask, jaw_box[0], jaw_box[1]), 312, below=True)
    if jaw_chain[0][0] < jaw_chain[-1][0]:
        jaw_chain.reverse()                       # right crossing, round the chin, left crossing

    # Sides: the head's dark edge line where it crosses the wings. It always lies in these
    # bands (the screen bezel starts inside them, the wing panels outside them).
    def darkest(y, band, toward_inside):
        xs = range(band[0], band[1] + 1)
        values = {x: lum(*pixel(data, x, y)) for x in range(xs[0] - 1, xs[-1] + 2)}
        low = min(values[x] for x in xs)
        near = [x for x in xs if values[x] <= low + 1.0]
        x = max(near) if toward_inside > 0 else min(near)
        a, b, c = values[x - 1], values[x], values[x + 1]
        denom = a - 2 * b + c
        offset = max(-0.5, min(0.5, 0.5 * (a - c) / denom)) if denom > 0 else 0.0
        return x + 0.5 + offset
    raw_left, raw_right = {}, {}
    for y in range(118, 300):
        raw_left[y] = darkest(y, (318, 333), +1)
        raw_right[y] = darkest(y, (597, 612), -1)

    def smooth(raw):
        ys = sorted(raw)
        median = {y: sorted(raw[k] for k in ys if abs(k - y) <= 2)[len([k for k in ys if abs(k - y) <= 2]) // 2] for y in ys}
        return {y: sum(median[k] for k in ys if abs(k - y) <= 2) / len([k for k in ys if abs(k - y) <= 2]) for y in ys}
    left, right = smooth(raw_left), smooth(raw_right)

    def side(values, top_x, bottom_x):
        out = {}
        for y in range(113, 312):
            if y < 118:
                out[y] = top_x + (values[118] - top_x) * (y - 112) / 6
            elif y < 300:
                out[y] = values[y]
            else:
                out[y] = values[299] + (bottom_x - values[299]) * (y - 299) / 13
        return out
    left_side = side(left, dome_chain[0][0], jaw_chain[-1][0])
    right_side = side(right, dome_chain[-1][0], jaw_chain[0][0])

    outline = (dome_chain + [(right_side[y], float(y)) for y in range(113, 312)] + jaw_chain +
               [(left_side[y], float(y)) for y in range(311, 112, -1)])
    outline = simplify_loop(outline, 0.05)

    # Shading: green channel with the app's own controls painted out.
    box = (314, 0, 300, 498)
    x0, y0, w, h = box
    inside = rasterize(outline, box)
    holes = box_mask(box, rects=[KEYS, PILL, SEEK, POINTER] + ICONS,
                     circles=[(cx, cy, 15) for cx, cy in BUTTONS])
    sx0, sy0 = screen_box[0], screen_box[1]
    for y in range(len(screen_region)):
        for x in range(len(screen_region[0])):
            if screen_region[y][x]:
                gy, gx = sy0 + y - y0, sx0 + x - x0
                if 0 <= gy < h and 0 <= gx < w:
                    holes[gy][gx] = True
    holes = dilate(holes)
    values = sample(data, box, lambda r, g, b: float(g))
    inpaint_rows(values, holes)
    extend_rows(values, inside)
    values = blur3(values)
    colour_pixels = [(x0 + x, y0 + y, pixel(data, x0 + x, y0 + y)) for y in range(h) for x in range(w)
                     if inside[y][x] and not holes[y][x]]
    base, layers = shading(values, inside, colour_pixels, GREEN_LEVELS, x0, y0)
    return outline, base, layers, (left, right, dome_chain, jaw_chain)


def green(r, g, b):
    return g > r + 8 and g > b + 8


def trace_wing(data, box, panel, speaker_seeds, seed, exclude=()):
    x0, y0, w, h = box
    # The wing is everything green connected to its bevel (head included: it is drawn
    # over the wing), with the speakers' holes filled. Desktop icons and the video's
    # black border are not green, so they stay out.
    passable = sample(data, box, green)
    for (ax, ay, bx, by) in exclude:
        for y in range(max(0, ay - y0), min(h, by - y0 + 1)):
            for x in range(max(0, ax - x0), min(w, bx - x0 + 1)):
                passable[y][x] = False
    inside = fill_holes(flood(passable, [(seed[0] - x0, seed[1] - y0)]))
    outline = simplify_loop(mask_outline(inside, x0, y0))

    speakers, speaker_holes = [], [[False] * w for _ in range(h)]
    grey = sample(data, box, neutral)
    for (sx, sy) in speaker_seeds:
        region = fill_holes(flood(grey, [(sx - x0, sy - y0)]))
        count = sum(sum(row) for row in region)
        assert 400 < count < 6000, "speaker at %s: %d px" % ((sx, sy), count)
        speaker_outline = simplify_loop(mask_outline(region, x0, y0, passes=2, average=2))
        values = sample(data, box, lambda r, g, b: lum(r, g, b))
        extend_rows(values, region)
        values = blur3(values)
        colour_pixels = [(x0 + x, y0 + y, pixel(data, x0 + x, y0 + y)) for y in range(h) for x in range(w) if region[y][x]]
        base, layers = shading(values, region, colour_pixels, GREY_LEVELS, x0, y0)
        # The rim of a round speaker seen at an angle is an ellipse: take the traced
        # region's centre and tilt (second moments) and the traced outline's area.
        pts = [(x0 + x + 0.5, y0 + y + 0.5) for y in range(h) for x in range(w) if region[y][x]]
        mx = sum(p[0] for p in pts) / len(pts)
        my = sum(p[1] for p in pts) / len(pts)
        sxx = sum((p[0] - mx) ** 2 for p in pts) / len(pts)
        syy = sum((p[1] - my) ** 2 for p in pts) / len(pts)
        sxy = sum((p[0] - mx) * (p[1] - my) for p in pts) / len(pts)
        tr, det = sxx + syy, sxx * syy - sxy * sxy
        l1 = tr / 2 + math.sqrt(max(0.0, tr * tr / 4 - det))
        l2 = tr / 2 - math.sqrt(max(0.0, tr * tr / 4 - det))
        theta = 0.5 * math.atan2(2 * sxy, sxx - syy)
        a, b = 2 * math.sqrt(l1), 2 * math.sqrt(l2)
        k = math.sqrt(area(speaker_outline) / (math.pi * a * b))
        a, b = a * k, b * k
        ca, sa = math.cos(theta), math.sin(theta)
        def radial_error(p):
            dx, dy = p[0] - mx, p[1] - my
            u, v = (dx * ca + dy * sa) / a, (-dx * sa + dy * ca) / b
            r = math.hypot(u, v)
            return (r - 1) * math.hypot(u * a, v * b) / max(r, 1e-9)
        errors = [radial_error(p) for p in speaker_outline]
        rms = math.sqrt(sum(e * e for e in errors) / len(errors))
        ellipse = [(mx + a * math.cos(t) * ca - b * math.sin(t) * sa, my + a * math.cos(t) * sa + b * math.sin(t) * ca)
                   for t in (2 * math.pi * i / 160 for i in range(160))]
        speakers.append((ellipse, base, layers, (mx, my, a, b, math.degrees(theta), rms, max(abs(e) for e in errors))))
        for y in range(h):
            for x in range(w):
                if region[y][x]:
                    speaker_holes[y][x] = True

    values = sample(data, box, lambda r, g, b: float(g))
    speaker_holes = dilate(speaker_holes)
    inpaint_rows(values, speaker_holes)
    # Panel contents: one flat panel colour (the app draws the mixer / playlist there).
    px0, py0, px1, py1 = panel
    inner = box_mask(box, rects=[(px0 + 3, py0 + 3, px1 - 3, py1 - 3)])
    for y in range(h):
        for x in range(w):
            if inner[y][x]:
                values[y][x] = 93.0
    extend_rows(values, inside)
    colour_pixels = [(x0 + x, y0 + y, pixel(data, x0 + x, y0 + y)) for y in range(h) for x in range(w)
                     if inside[y][x] and not speaker_holes[y][x] and not inner[y][x]]
    base, layers = shading(values, inside, colour_pixels, GREEN_LEVELS, x0, y0)
    return outline, base, layers, speakers


# ---------------------------------------------------------------- output

def encode(loops):
    return "|".join(" ".join("%.2f,%.2f" % p for p in loop) for loop in loops)


def shape_literal(outline, base, layers, indent):
    pad = " " * indent
    lines = ["Shape(outline: \"%s\"," % encode([outline]),
             pad + "      base: 0x%06x," % base,
             pad + "      layers: ["]
    for colour, loops in layers:
        lines.append(pad + "        (0x%06x, \"%s\")," % (colour, encode(loops)))
    lines.append(pad + "      ])")
    return "\n".join(lines)


def main(source, target):
    data = load(source)
    screen_region, screen_box, screen = trace_screen(data)
    head_outline, head_base, head_layers, debug = trace_head(data, screen_region, screen_box)
    left = trace_wing(data, (0, 104, 350, 226), LEFT_PANEL, LEFT_SPEAKERS, (200, 119), [DESKTOP_ICON])
    right = trace_wing(data, (584, 104, 350, 226), RIGHT_PANEL, RIGHT_SPEAKERS, (735, 119), [WALLPAPER_STRIPE])

    with open(target, "w") as out:
        out.write("import CoreGraphics\n\n")
        out.write("// Generated by scripts/trace_limehead.py from the supplied reference screenshot.\n")
        out.write("// Do not edit by hand: re-run the script. Coordinates are in LimeGeometry's 935 x 498 space.\n")
        out.write("enum LimeTrace {\n")
        out.write("    /// A traced shape: its outline, the colour under its layers, and brightness layers\n")
        out.write("    /// (darkest first) as fill colour + closed outlines \"x,y x,y|x,y ...\" (even-odd).\n")
        out.write("    struct Shape {\n        let outline: String\n        let base: UInt32\n")
        out.write("        let layers: [(colour: UInt32, outlines: String)]\n    }\n\n")
        out.write("    static let head = %s\n\n" % shape_literal(head_outline, head_base, head_layers, 4))
        out.write("    /// Screen outline (the part under the title pill completed as a straight edge).\n")
        out.write("    static let screen = \"%s\"\n\n" % encode([screen]))
        for name, (outline, base, layers, speakers) in (("left", left), ("right", right)):
            out.write("    static let %sWing = %s\n\n" % (name, shape_literal(outline, base, layers, 4)))
            out.write("    static let %sSpeakers: [Shape] = [\n" % name)
            for (s_outline, s_base, s_layers, _) in speakers:
                out.write("        %s,\n" % shape_literal(s_outline, s_base, s_layers, 8))
            out.write("    ]\n\n")
        out.write("}\n")

    def count(layers):
        return sum(len(loop) for _, loops in layers for loop in loops)
    print("head: outline %d pts, %d layers, %d pts" % (len(head_outline), len(head_layers), count(head_layers)))
    print("screen: %d pts, x %.1f..%.1f, y %.1f..%.1f" % (len(screen), min(p[0] for p in screen), max(p[0] for p in screen),
                                                        min(p[1] for p in screen), max(p[1] for p in screen)))
    for name, (outline, base, layers, speakers) in (("left", left), ("right", right)):
        print("%s wing: outline %d pts x %.1f..%.1f y %.1f..%.1f, %d layers, %d pts" % (
            name, len(outline), min(p[0] for p in outline), max(p[0] for p in outline),
            min(p[1] for p in outline), max(p[1] for p in outline), len(layers), count(layers)))
        for (s_outline, s_base, s_layers, (mx, my, a, b, angle, rms, worst)) in speakers:
            print("   speaker centre (%.2f, %.2f) semi-axes %.2f x %.2f tilt %.1f deg; traced edge vs ellipse rms %.2f px, worst %.2f px; %d layers, %d pts" % (
                mx, my, a, b, angle, rms, worst, len(s_layers), count(s_layers)))
    lsides, rsides, dome_chain, jaw_chain = debug
    print("dome crossings", dome_chain[0], dome_chain[-1], "top y %.2f" % min(p[1] for p in dome_chain))
    print("jaw crossings", jaw_chain[0], jaw_chain[-1], "chin y %.2f" % max(p[1] for p in jaw_chain))
    for y in (118, 130, 150, 170, 190, 210, 230, 250, 270, 290, 299):
        print("   side y %d: left %.2f right %.2f" % (y, lsides[y], rsides[y]))
    print("pill row y=99:", " ".join("%d:%02x%02x%02x" % ((x,) + pixel(data, x, 99)) for x in range(350, 366)))
    print("pill row y=99:", " ".join("%d:%02x%02x%02x" % ((x,) + pixel(data, x, 99)) for x in range(564, 580)))
    print("pill col x=470:", " ".join("%d:%02x%02x%02x" % ((y,) + pixel(data, 470, y)) for y in range(80, 92)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
