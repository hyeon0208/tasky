#!/usr/bin/env python3
"""F26 캐릭터 2종(낙서 곰·길쭉 냥이)의 표정 SVG를 만든다.

규격: intent/F11-캐릭터-인터랙션/ASSETS.md — 1024×1024, 투명 배경, 바닥선은 아래에서 12%(y=901).
선은 손으로 그린 듯 살짝 떨리게(같은 씨앗이라 표정이 바뀌어도 몸 선은 그대로).
사용: python3 scripts/make-characters.py <출력 폴더>  →  <출력>/<캐릭터>/<표정>.svg
PNG 변환은 scripts/make-characters.sh가 한다.
"""
import math
import os
import random
import sys

BASE = 901          # 바닥선
INK = "#1A1A1A"
W = 20              # 선 굵기


def catmull(points, closed=True, steps=18):
    """점들을 지나는 부드러운 곡선을 촘촘한 점으로"""
    pts = points[:]
    n = len(pts)
    out = []
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if closed or i > 0 else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed or i + 2 < n else p2
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    if not closed:
        out.append(pts[-1])
    return out


def wobble(pts, seed, amp=3.2):
    """법선 방향으로 부드러운 흔들림"""
    r = random.Random(seed)
    ph = [r.uniform(0, 6.28) for _ in range(3)]
    fr = [r.uniform(0.035, 0.05), r.uniform(0.09, 0.12), r.uniform(0.2, 0.26)]
    out = []
    n = len(pts)
    for i, (x, y) in enumerate(pts):
        ax, ay = pts[i - 1]
        bx, by = pts[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        l = math.hypot(dx, dy) or 1
        nx, ny = -dy / l, dx / l
        d = amp * (math.sin(i * fr[0] + ph[0]) + 0.5 * math.sin(i * fr[1] + ph[1]) + 0.25 * math.sin(i * fr[2] + ph[2])) / 1.75
        out.append((x + nx * d, y + ny * d))
    return out


def path(pts, closed=True):
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    return d + (" Z" if closed else "")


def shape(points, seed, fill="#FFFFFF", closed=True, width=W):
    p = wobble(catmull(points, closed), seed)
    f = fill if closed else "none"
    return f'<path d="{path(p, closed)}" fill="{f}" stroke="{INK}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"/>'


def ellipse_pts(cx, cy, rx, ry, k=14):
    return [(cx + rx * math.cos(2 * math.pi * i / k), cy + ry * math.sin(2 * math.pi * i / k)) for i in range(k)]


def svg(body, face, transform=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
            f'<g transform="{transform}">{body}{face}</g></svg>')


def anchor(sx=1.0, sy=1.0, rot=0.0, dx=0.0, dy=0.0):
    """바닥선 가운데를 기준으로 늘이기·기울이기"""
    return (f"translate({512 + dx},{BASE + dy}) rotate({rot}) scale({sx},{sy}) translate(-512,-{BASE})")


# ---------- 공통 얼굴 조각 ----------
def dots(xs, y, r=18):
    return "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{INK}"/>' for x in xs)


def arcs(xs, y, up=True, w=26, sw=12):
    s = -1 if up else 1
    return "".join(f'<path d="M{x - w / 2},{y} Q{x},{y + s * 16} {x + w / 2},{y}" fill="none" stroke="{INK}" stroke-width="{sw}" stroke-linecap="round"/>' for x in xs)


def line(x1, y1, x2, y2, sw=11):
    return f'<path d="M{x1},{y1} L{x2},{y2}" stroke="{INK}" stroke-width="{sw}" stroke-linecap="round"/>'


def blush(xs, y, rx=30, ry=16):
    return "".join(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="#F7B5B0" opacity="0.7"/>' for x in xs)


# ---------- 낙서 곰 (팔·꼬리 없음, 사용자 요청 2026-11-04) ----------
def superellipse(cx, cy, rx, ry, e=2.6, k=24, top=1.0):
    pts = []
    for i in range(k):
        a = 2 * math.pi * i / k
        c, sn = math.cos(a), math.sin(a)
        x = cx + rx * math.copysign(abs(c) ** (2 / e), c)
        y = cy + ry * math.copysign(abs(sn) ** (2 / e), sn) * (top if sn < 0 else 1)
        pts.append((x, y))
    return pts


def bear_body(seed=11, walk=0):
    lf, rf = (420, 604) if walk == 0 else ((392, 620) if walk == 1 else (446, 578))
    feet = shape(ellipse_pts(lf, BASE - 30, 64, 32), seed + 1) + shape(ellipse_pts(rf, BASE - 30, 64, 32), seed + 2)
    ears = shape(ellipse_pts(318, 352, 66, 62), seed + 3) + shape(ellipse_pts(706, 352, 66, 62), seed + 4)
    return ears + feet + shape(superellipse(512, 600, 280, 262, e=2.3, top=1.0), seed)


def bear(pose):
    ex, ey = (428, 596), 580          # 눈
    mx, my = 512, 636                 # 입
    face_side = 0
    t = ""
    walk = 0
    if pose in ("walk1", "walk2"):
        walk = 1 if pose == "walk1" else 2
        face_side = -70               # 옆모습: 얼굴을 왼쪽으로
    ex = tuple(x + face_side for x in ex)
    mx += face_side
    mouth_small = (f'<path d="M{mx - 22},{my - 6} Q{mx - 11},{my + 10} {mx},{my - 2} Q{mx + 11},{my + 10} {mx + 22},{my - 6}" fill="none" stroke="{INK}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>'
                   f'<path d="M{mx - 9},{my + 3} Q{mx},{my + 20} {mx + 9},{my + 3} Z" fill="#F5A3A3"/>')
    b = blush((ex[0] - 62, ex[1] + 62), ey + 52)
    if pose == "idle" or pose.startswith("walk"):
        face = dots(ex, ey) + mouth_small + b
    elif pose == "blink":
        face = arcs(ex, ey, up=False) + mouth_small + b
    elif pose == "sleep":
        face = arcs(ex, ey + 4, up=False, w=30) + f'<ellipse cx="{mx}" cy="{my + 4}" rx="9" ry="7" fill="{INK}"/>' + b
        t = anchor(rot=-6)
    elif pose in ("happy", "jump", "handup"):
        face = arcs(ex, ey + 6, up=True, w=34, sw=13) + \
            f'<path d="M{mx - 34},{my - 8} Q{mx},{my + 56} {mx + 34},{my - 8} Z" fill="#F5A3A3" stroke="{INK}" stroke-width="10" stroke-linejoin="round"/>' + b
        if pose == "jump":
            t = anchor(sx=0.97, sy=1.04, dy=-40)
        if pose == "handup":
            t = anchor(rot=8)
    elif pose == "surprised":
        face = dots(ex, ey, r=22) + "".join(f'<circle cx="{x + 7}" cy="{ey - 8}" r="7" fill="#FFFFFF"/>' for x in ex) + \
            f'<ellipse cx="{mx}" cy="{my + 10}" rx="16" ry="20" fill="#F5A3A3" stroke="{INK}" stroke-width="10"/>'
    elif pose == "sad":
        face = dots(ex, ey + 6, r=13) + line(ex[0] - 26, ey - 40, ex[0] + 18, ey - 28) + line(ex[1] - 18, ey - 28, ex[1] + 26, ey - 40) + \
            f'<path d="M{mx - 26},{my + 14} Q{mx},{my - 8} {mx + 26},{my + 14}" fill="none" stroke="{INK}" stroke-width="10" stroke-linecap="round"/>'
    elif pose == "mouthopen":
        face = dots(ex, ey - 6) + f'<ellipse cx="{mx}" cy="{my + 22}" rx="46" ry="52" fill="#E9767A" stroke="{INK}" stroke-width="11"/>' + b
    elif pose == "squish":
        face = line(ex[0] - 18, ey - 12, ex[0] + 14, ey) + line(ex[0] - 18, ey + 12, ex[0] + 14, ey) + \
            line(ex[1] + 18, ey - 12, ex[1] - 14, ey) + line(ex[1] + 18, ey + 12, ex[1] - 14, ey) + mouth_small + b
        t = anchor(sx=1.14, sy=0.8)
    elif pose == "dangle":
        face = dots(ex, ey) + mouth_small + b
        t = anchor(sx=0.9, sy=1.1, dy=-30)
    elif pose == "grumpy":
        face = line(ex[0] - 22, ey, ex[0] + 22, ey, 12) + line(ex[1] - 22, ey, ex[1] + 22, ey, 12) + \
            line(ex[0] - 26, ey - 34, ex[0] + 20, ey - 22) + line(ex[1] - 20, ey - 22, ex[1] + 26, ey - 34) + \
            line(mx - 20, my + 6, mx + 20, my + 6, 10)
    else:
        return None
    return svg(bear_body(walk=walk), face, t)


# ---------- 길쭉 냥이 ----------
def cat_body(seed=23, walk=0, fur="#F4F1EA"):
    lx = 0 if walk == 0 else (-14 if walk == 1 else 14)
    outline = [(372 + lx, 896), (370, 720), (364, 520), (368, 340), (378, 268), (398, 178), (424, 214), (452, 246),
               (512, 240), (572, 246), (600, 214), (626, 178), (646, 268), (656, 340), (660, 520), (654, 720),
               (652 - lx, 896), (580 - lx, 896), (572 - lx, 850), (512, 846), (452 + lx, 850), (444 + lx, 896)]
    whisk = ""
    r = random.Random(seed + 9)
    for side in (-1, 1):
        x0 = 512 + side * 150
        for k, dy in enumerate((-18, 0, 18)):
            whisk += shape([(x0, 400 + dy), (x0 + side * 48, 396 + dy + (k - 1) * 8 + r.uniform(-2, 2))], seed + 30 + k + side, closed=False, width=9)
    return shape(outline, seed, fill=fur) + whisk


def cat(pose):
    ex, ey = (482, 542), 392
    mx, my = 512, 422
    t = ""
    walk = 0
    if pose in ("walk1", "walk2"):
        walk = 1 if pose == "walk1" else 2
        ex, mx = (452, 510), 482
    smile = f'<path d="M{mx - 14},{my} Q{mx},{my + 14} {mx + 14},{my}" fill="none" stroke="{INK}" stroke-width="8" stroke-linecap="round"/>'
    if pose == "idle" or pose.startswith("walk"):
        face = dots(ex, ey, r=10) + smile
    elif pose == "blink":
        face = arcs(ex, ey, up=False, w=20, sw=8) + smile
    elif pose == "sleep":
        face = line(ex[0] - 11, ey, ex[0] + 11, ey, 8) + line(ex[1] - 11, ey, ex[1] + 11, ey, 8) + smile
        t = anchor(rot=-5)
    elif pose in ("happy", "jump", "handup"):
        face = arcs(ex, ey + 4, up=True, w=24, sw=9) + \
            f'<path d="M{mx - 20},{my - 4} Q{mx},{my + 32} {mx + 20},{my - 4} Z" fill="#F5A3A3" stroke="{INK}" stroke-width="8" stroke-linejoin="round"/>'
        if pose == "jump":
            t = anchor(sx=0.96, sy=1.05, dy=-40)
        if pose == "handup":
            t = anchor(rot=7)
    elif pose == "surprised":
        face = dots(ex, ey, r=15) + "".join(f'<circle cx="{x + 5}" cy="{ey - 5}" r="5" fill="#FFFFFF"/>' for x in ex) + \
            f'<ellipse cx="{mx}" cy="{my + 8}" rx="10" ry="13" fill="#F5A3A3" stroke="{INK}" stroke-width="8"/>'
    elif pose == "sad":
        face = dots(ex, ey + 4, r=9) + line(ex[0] - 18, ey - 26, ex[0] + 12, ey - 18, 8) + line(ex[1] - 12, ey - 18, ex[1] + 18, ey - 26, 8) + \
            f'<path d="M{mx - 14},{my + 10} Q{mx},{my - 4} {mx + 14},{my + 10}" fill="none" stroke="{INK}" stroke-width="8" stroke-linecap="round"/>'
    elif pose == "mouthopen":
        face = dots(ex, ey - 6, r=10) + f'<ellipse cx="{mx}" cy="{my + 18}" rx="28" ry="34" fill="#E9767A" stroke="{INK}" stroke-width="9"/>'
    elif pose == "squish":
        face = line(ex[0] - 12, ey - 9, ex[0] + 10, ey, 8) + line(ex[0] - 12, ey + 9, ex[0] + 10, ey, 8) + \
            line(ex[1] + 12, ey - 9, ex[1] - 10, ey, 8) + line(ex[1] + 12, ey + 9, ex[1] - 10, ey, 8) + smile
        t = anchor(sx=1.18, sy=0.78)
    elif pose == "dangle":
        face = dots(ex, ey, r=10) + smile
        t = anchor(sx=0.9, sy=1.12, dy=-30)
    elif pose == "grumpy":
        face = line(ex[0] - 14, ey, ex[0] + 14, ey, 9) + line(ex[1] - 14, ey, ex[1] + 14, ey, 9) + line(mx - 12, my + 4, mx + 12, my + 4, 8)
    else:
        return None
    return svg(cat_body(walk=walk), face, t)


POSES = ["idle", "blink", "sleep", "happy", "surprised", "sad", "handup", "mouthopen", "squish", "dangle", "walk1", "walk2", "grumpy", "jump"]

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "Assets/Characters"
    for name, fn in (("doodlebear", bear), ("longcat", cat)):
        os.makedirs(os.path.join(out, name), exist_ok=True)
        for p in POSES:
            s = fn(p)
            if s:
                with open(os.path.join(out, name, p + ".svg"), "w") as f:
                    f.write(s)
    print("ok")
