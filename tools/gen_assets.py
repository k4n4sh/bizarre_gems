#!/usr/bin/env python3
"""Generates every art and sound asset of the game from code.

Run from the project root:  python3 tools/gen_assets.py
Needs: rsvg-convert (librsvg), Pillow, numpy.
"""
import math, os, subprocess, wave, struct, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = lambda *p: os.path.join(ROOT, "assets", *p)
STORE = lambda *p: os.path.join(ROOT, "store", *p)

GEMS = [  # name, base colour, cut
    ("ruby",       "#e2334c", "square"),
    ("sapphire",   "#2f6ff0", "kite"),
    ("emerald",    "#17a866", "octagon"),
    ("amethyst",   "#9a4fe6", "hexagon"),
    ("topaz",      "#f28a22", "round"),
    ("citrine",    "#f4c62e", "star"),
    ("pearl",      "#ece8f2", "pearl"),
    ("rosequartz", "#f25fae", "heart"),
    ("aquamarine", "#3fd6dc", "drop"),
    ("peridot",    "#a6dc3a", "triangle"),
]


def svg_to_png(svg, path, w, h=None):
    h = h or w
    subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), "-o", path], input=svg.encode(), check=True)


def shade(hexc, f):
    n = int(hexc[1:], 16)
    r, g, b = n >> 16, (n >> 8) & 255, n & 255
    t = 0 if f < 0 else 255
    p = abs(f)
    return "#%02x%02x%02x" % tuple(round((t - c) * p + c) for c in (r, g, b))


def outline(cut):
    P = []
    def poly(n, rot, rx=1, ry=1):
        for i in range(n):
            a = rot + i * 2 * math.pi / n
            P.append((math.cos(a) * rx, math.sin(a) * ry))
    if cut == "square":
        P += [(-.78, -.9), (.78, -.9), (.9, -.78), (.9, .78), (.78, .9), (-.78, .9), (-.9, .78), (-.9, -.78)]
    elif cut == "kite":
        P += [(0, .98), (-.95, -.25), (-.55, -.82), (.55, -.82), (.95, -.25)]
    elif cut == "octagon":
        P += [(-.5, -.95), (.5, -.95), (.82, -.62), (.82, .62), (.5, .95), (-.5, .95), (-.82, .62), (-.82, -.62)]
    elif cut == "hexagon":
        poly(6, 0, .97, .9)
    elif cut == "round":
        poly(12, math.pi / 12, .95, .95)
    elif cut == "star":
        for i in range(8):
            a = -math.pi / 2 + i * math.pi / 4
            r = .48 if i % 2 else 1
            P.append((math.cos(a) * r, math.sin(a) * r))
    elif cut == "triangle":
        P += [(0, -.95), (.98, .82), (-.98, .82)]
    elif cut == "heart":
        for i in range(24):
            t = i / 24 * 2 * math.pi
            P.append((16 * math.sin(t) ** 3 / 17,
                      -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) / 17 - .08))
    elif cut == "drop":
        for i in range(20):
            t = i / 20 * 2 * math.pi
            P.append((math.sin(t) * math.sin(t / 2) * .95, -math.cos(t) * .95))
    return P


def pts(P):
    return " ".join("%.2f,%.2f" % p for p in P)


def gem_svg(name, base, cut, size=128):
    c = size / 2
    R = size * 0.42
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">',
           "<defs>",
           f'<radialGradient id="sh" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#000" stop-opacity="0.45"/><stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>',
           f'<linearGradient id="body" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{shade(base, .45)}"/><stop offset="0.45" stop-color="{base}"/><stop offset="1" stop-color="{shade(base, -.55)}"/></linearGradient>',
           f'<linearGradient id="tbl" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{shade(base, .6)}"/><stop offset="1" stop-color="{shade(base, .05)}"/></linearGradient>',
           f'<radialGradient id="pearl" cx="0.32" cy="0.28" r="0.75"><stop offset="0" stop-color="#ffffff"/><stop offset="0.45" stop-color="{base}"/><stop offset="0.85" stop-color="#a9a1b8"/><stop offset="1" stop-color="#7d7590"/></radialGradient>',
           f'<linearGradient id="iri" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#ffbee6" stop-opacity="0.22"/><stop offset="0.5" stop-color="#aae6ff" stop-opacity="0.12"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>',
           "</defs>"]
    out.append(f'<ellipse cx="{c + size*.03:.1f}" cy="{c + R*.95:.1f}" rx="{R*1.05:.1f}" ry="{R*.38:.1f}" fill="url(#sh)"/>')
    if cut == "pearl":
        out.append(f'<circle cx="{c}" cy="{c}" r="{R*.88:.1f}" fill="url(#pearl)"/>')
        out.append(f'<circle cx="{c}" cy="{c}" r="{R*.88:.1f}" fill="url(#iri)"/>')
        out.append(f'<ellipse cx="{c - R*.32:.1f}" cy="{c - R*.38:.1f}" rx="{R*.16:.1f}" ry="{R*.1:.1f}" fill="#fff" fill-opacity="0.9" transform="rotate(-34 {c - R*.32:.1f} {c - R*.38:.1f})"/>')
    else:
        P = [(c + x * R, c + y * R) for x, y in outline(cut)]
        T = [(c + x * R * .52, c + y * R * .52 - R * .04) for x, y in outline(cut)]
        sw = max(1, size * .02)
        out.append(f'<polygon points="{pts(P)}" fill="url(#body)" stroke="{shade(base, -.6)}" stroke-width="{sw:.2f}" stroke-linejoin="round"/>')
        step = 3 if len(P) > 12 else 1
        for i in range(0, len(P), step):
            j = (i + step) % len(P)
            mx, my = (P[i][0] + P[j][0]) / 2 - c, (P[i][1] + P[j][1]) / 2 - c
            light = (-mx - my) / (R * 2)
            fill, op = ("#fff", .08 + light * .35) if light > 0 else ("#000", .06 - light * .35)
            out.append(f'<polygon points="{pts([P[i], P[j], T[j], T[i]])}" fill="{fill}" fill-opacity="{op:.3f}" stroke="#fff" stroke-opacity="0.18" stroke-width="{max(.6, size*.008):.2f}"/>')
        out.append(f'<polygon points="{pts(T)}" fill="url(#tbl)" stroke="#fff" stroke-opacity="0.35" stroke-width="{max(.6, size*.008):.2f}"/>')
        out.append(f'<ellipse cx="{c - R*.28:.1f}" cy="{c - R*.34:.1f}" rx="{R*.14:.1f}" ry="{R*.06:.1f}" fill="#fff" fill-opacity="0.85" transform="rotate(-40 {c - R*.28:.1f} {c - R*.34:.1f})"/>')
    out.append("</svg>")
    return "\n".join(out)


ICONS = {  # 64x64 white glyphs
    "pause": '<rect x="16" y="12" width="11" height="40" rx="3"/><rect x="37" y="12" width="11" height="40" rx="3"/>',
    "play": '<path d="M20 12 L52 32 L20 52 Z" stroke-linejoin="round"/>',
    "sound_on": '<path d="M10 24h10l14-11v38L20 40H10z"/><path d="M41 22c4 3 4 17 0 20M47 15c9 7 9 27 0 34" fill="none" stroke="#fff" stroke-width="4.5" stroke-linecap="round"/>',
    "sound_off": '<path d="M10 24h10l14-11v38L20 40H10z"/><path d="M42 24l14 16M56 24L42 40" fill="none" stroke="#fff" stroke-width="4.5" stroke-linecap="round"/>',
    "music_on": '<path d="M24 14l26-6v34" fill="none" stroke="#fff" stroke-width="5" stroke-linejoin="round"/><path d="M24 14v34" stroke="#fff" stroke-width="5"/><ellipse cx="17" cy="48" rx="9" ry="7"/><ellipse cx="43" cy="42" rx="9" ry="7"/>',
    "music_off": '<path d="M24 14l26-6v34" fill="none" stroke="#fff" stroke-width="5" stroke-linejoin="round"/><path d="M24 14v34" stroke="#fff" stroke-width="5"/><ellipse cx="17" cy="48" rx="9" ry="7"/><ellipse cx="43" cy="42" rx="9" ry="7"/><path d="M8 8L56 56" stroke="#fff" stroke-width="5" stroke-linecap="round"/>',
    "trophy": '<path d="M18 8h28v14c0 10-6 17-14 17s-14-7-14-17z"/><path d="M18 13H9c0 9 4 14 11 15M46 13h9c0 9-4 14-11 15" fill="none" stroke="#fff" stroke-width="4"/><rect x="28" y="38" width="8" height="9"/><rect x="18" y="47" width="28" height="8" rx="2"/>',
    "home": '<path d="M8 31L32 10l24 21" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/><path d="M15 29v25h12V40h10v14h12V29L32 15z"/>',
    "video": '<rect x="6" y="14" width="52" height="36" rx="7"/><path d="M27 23l13 9-13 9z" fill="#1b1408"/>',
    "shuffle": '<path d="M8 20h12c12 0 14 24 26 24h8M8 44h12c5 0 8-4 10-8M38 26c2-3 5-6 8-6h8" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round"/><path d="M50 12l8 8-8 8zM50 36l8 8-8 8z"/>',
    "calendar": '<rect x="8" y="12" width="48" height="44" rx="6" fill="none" stroke="#fff" stroke-width="5"/><rect x="8" y="12" width="48" height="12" rx="4"/><rect x="18" y="5" width="6" height="14" rx="2"/><rect x="40" y="5" width="6" height="14" rx="2"/><rect x="18" y="31" width="9" height="8" rx="1.5"/><rect x="31" y="31" width="9" height="8" rx="1.5"/><rect x="18" y="42" width="9" height="8" rx="1.5"/>',
    "rotate": '<rect x="20" y="6" width="24" height="42" rx="5" fill="none" stroke="#fff" stroke-width="4"/><rect x="28" y="40" width="8" height="3" rx="1.5"/><path d="M10 40c0 8 6 14 14 16" fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round"/><path d="M20 50l6 7-9 2z"/>',
    "crown": '<path d="M8 46L12 18l13 13 7-17 7 17 13-13 4 28z"/><rect x="8" y="49" width="48" height="7" rx="2"/>',
    "back": '<path d="M40 10L18 32l22 22" fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>',
    "info": '<circle cx="32" cy="32" r="25" fill="none" stroke="#fff" stroke-width="5"/><circle cx="32" cy="19" r="4"/><rect x="28.5" y="27" width="7" height="22" rx="3"/>',
    "map": '<path d="M6 14l16-6 20 6 16-6v42l-16 6-20-6-16 6z" fill="none" stroke="#fff" stroke-width="5" stroke-linejoin="round"/><path d="M22 8v42M42 14v42" stroke="#fff" stroke-width="4"/>',
    "tasks": '<rect x="10" y="6" width="44" height="52" rx="6" fill="none" stroke="#fff" stroke-width="5"/><path d="M18 22l5 5 9-10M18 40l5 5 9-10" fill="none" stroke="#fff" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/><rect x="36" y="22" width="12" height="4" rx="2"/><rect x="36" y="40" width="12" height="4" rx="2"/>',
    "star": '<path d="M32 4l8.5 17.5 19.5 2.8-14 13.6 3.3 19.3L32 48l-17.3 9.2L18 37.9 4 24.3l19.5-2.8z"/>',
    "lock": '<rect x="12" y="28" width="40" height="30" rx="6"/><path d="M20 28v-8a12 12 0 0 1 24 0v8" fill="none" stroke="#fff" stroke-width="6"/>',
    "crystal": '<path d="M20 8h24l12 16-24 34L8 24z"/><path d="M8 24h48M20 8l12 16 12-16M32 24v34" fill="none" stroke="#000" stroke-opacity="0.25" stroke-width="3"/>',
    "hint": '<path d="M32 6a18 18 0 0 0-10 33v7h20v-7A18 18 0 0 0 32 6z"/><rect x="23" y="49" width="18" height="5" rx="2"/><rect x="26" y="56" width="12" height="4" rx="2"/>',
    "strikes": '<circle cx="32" cy="32" r="24" fill="none" stroke="#fff" stroke-width="5"/><circle cx="32" cy="32" r="13" fill="none" stroke="#fff" stroke-width="5"/><circle cx="32" cy="32" r="4"/>',
    "gift": '<rect x="8" y="26" width="48" height="32" rx="4"/><rect x="5" y="17" width="54" height="11" rx="3"/><rect x="28" y="17" width="8" height="41" fill="#000" fill-opacity="0.3"/><path d="M32 17c-6-12-20-8-14 0M32 17c6-12 20-8 14 0" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round"/>',
    "medal": '<path d="M20 4h10l6 16H26zM34 4h10l-6 16h-10z"/><circle cx="32" cy="40" r="18"/><circle cx="32" cy="40" r="11" fill="none" stroke="#000" stroke-opacity="0.3" stroke-width="4"/>',
    "puzzle": '<path d="M8 20h14a6 6 0 1 1 12 0h14v14a6 6 0 1 0 0 12v14H34a6 6 0 1 0-12 0H8V46a6 6 0 1 1 0-12z"/>',
    "hand": '<path d="M26 6a5 5 0 0 1 10 0v22l3-1a5 5 0 0 1 6 3l1 2a5 5 0 0 1 6 3v10c0 10-7 17-17 17h-4c-7 0-12-4-15-10l-7-13a5 5 0 0 1 8-6l9 9z"/>',
    "link": '<rect x="6" y="20" width="30" height="24" rx="12" fill="none" stroke="#fff" stroke-width="7"/><rect x="28" y="20" width="30" height="24" rx="12" fill="none" stroke="#fff" stroke-width="7"/>',
    "ticket": '<path d="M6 18a4 4 0 0 1 4-4h44a4 4 0 0 1 4 4v7a7 7 0 0 0 0 14v7a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4v-7a7 7 0 0 0 0-14z"/><path d="M32 22l3 7 7 .6-5.3 4.6 1.7 7-6.4-3.9-6.4 3.9 1.7-7-5.3-4.6 7-.6z" fill="#000" fill-opacity=".55"/>',
    "chart": '<rect x="8" y="34" width="10" height="22" rx="2"/><rect x="27" y="20" width="10" height="36" rx="2"/><rect x="46" y="8" width="10" height="48" rx="2"/>',
    "next": '<path d="M24 12l20 20-20 20" fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>',
    "prev": '<path d="M40 12L20 32l20 20" fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>',
    "door": '<path d="M14 8h28v48H14z" fill="none" stroke="#fff" stroke-width="6" stroke-linejoin="round"/><path d="M34 32h22M48 24l8 8-8 8" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>',
    "check": '<path d="M12 34l14 14 26-30" fill="none" stroke="#fff" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>',
    "restart": '<path d="M48 22A19 19 0 1 0 51 36" fill="none" stroke="#fff" stroke-width="5.5" stroke-linecap="round"/><path d="M42 10l12 2-2 12z"/>',
}


def gear_path(teeth=8, r_out=28, r_in=21, hole=9, c=32):
    pts_ = []
    for i in range(teeth * 4):
        a = i * 2 * math.pi / (teeth * 4) - math.pi / 2
        r = r_out if i % 4 in (1, 2) else r_in
        pts_.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d = "M" + " L".join("%.2f %.2f" % p for p in pts_) + " Z"
    d += f" M{c + hole} {c} A{hole} {hole} 0 1 0 {c - hole} {c} A{hole} {hole} 0 1 0 {c + hole} {c} Z"
    return f'<path fill-rule="evenodd" d="{d}"/>'


# bright "toy" palette for the board tiles, same order as GEMS
TOY = ["#ff4d5e", "#3d8bff", "#22c97a", "#a35cff", "#ff9a2e", "#ffcf33", "#dfe5f0", "#ff6fb5", "#2fd6e0", "#9be03a"]


def tile_svg(base, cut, size=128):
    """A glossy, bevelled toy tile in `base` colour with the gem's silhouette embossed on it."""
    c = size / 2
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}"><defs>',
           f'<linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{shade(base, .3)}"/>'
           f'<stop offset="0.55" stop-color="{base}"/><stop offset="1" stop-color="{shade(base, -.3)}"/></linearGradient>',
           f'<linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{shade(base, .75)}"/>'
           f'<stop offset="1" stop-color="{shade(base, .35)}"/></linearGradient>',
           '</defs>']
    out.append(f'<rect x="7" y="11" width="114" height="112" rx="24" fill="#000" fill-opacity="0.32"/>')
    out.append(f'<rect x="6" y="5" width="116" height="112" rx="24" fill="{shade(base, -.38)}"/>')
    out.append(f'<rect x="6" y="5" width="116" height="104" rx="24" fill="url(#b)"/>')
    out.append(f'<rect x="10" y="9" width="108" height="96" rx="20" fill="none" stroke="#fff" stroke-opacity="0.35" stroke-width="3"/>')
    out.append(f'<rect x="16" y="12" width="96" height="34" rx="15" fill="#fff" fill-opacity="0.26"/>')
    R = 32
    if cut == "pearl":
        out.append(f'<circle cx="{c}" cy="{c - 2}" r="{R * .82}" fill="url(#g)" stroke="{shade(base, -.45)}" stroke-width="3"/>')
    else:
        P = [(c + x * R, c - 2 + y * R) for x, y in outline(cut)]
        out.append(f'<polygon points="{pts(P)}" fill="url(#g)" stroke="{shade(base, -.45)}" stroke-width="3" stroke-linejoin="round"/>')
    out.append(f'<ellipse cx="{c - 12}" cy="{c - 16}" rx="8" ry="4.5" fill="#fff" fill-opacity="0.85" transform="rotate(-35 {c - 12} {c - 16})"/>')
    out.append("</svg>")
    return "\n".join(out)


# Bright mode block palettes (6 colours each): soft, juicy, never neon. The board cycles
# through them on big combos and new boards, together with the background.
BLOCK_PALETTES = [
    ["#ef5f67", "#f59e45", "#f6c94e", "#5cc87a", "#4b9cf0", "#a477e0"],  # candy
    ["#f0857a", "#f2b65a", "#5ccfb0", "#36b5d8", "#4a7fd6", "#8f7ae6"],  # ocean
    ["#e0507f", "#f07f6a", "#f2c14e", "#8bc34a", "#5b8def", "#b05fd6"],  # berry
    ["#e86a5a", "#e9a03b", "#d9c64a", "#4fb36a", "#3f9fb0", "#7d6fd0"],  # forest
    ["#ff6b8b", "#ffa463", "#ffd966", "#6ed9a9", "#60a5fa", "#c084fc"],  # night
]
BLOCK_SYMBOL = ["square", "round", "star", "octagon", "kite", "hexagon"]


def block_svg(base, cut, size=128):
    """A chunky bevelled block: light top face, darker lower edge, glossy corner, faint emboss."""
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}"><defs>',
           f'<linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{shade(base, .18)}"/>'
           f'<stop offset="1" stop-color="{shade(base, -.06)}"/></linearGradient></defs>',
           f'<rect x="6" y="10" width="116" height="114" rx="16" fill="#000" fill-opacity="0.22"/>',
           f'<rect x="6" y="6" width="116" height="114" rx="16" fill="{shade(base, -.32)}"/>',
           f'<rect x="6" y="6" width="116" height="104" rx="16" fill="url(#f)"/>',
           f'<polygon points="6,22 22,6 106,6 122,22 106,26 22,26" fill="#fff" fill-opacity="0.28"/>',
           f'<rect x="18" y="18" width="92" height="80" rx="10" fill="{shade(base, .08)}"/>',
           f'<rect x="18" y="18" width="92" height="80" rx="10" fill="none" stroke="{shade(base, -.18)}" stroke-opacity="0.35" stroke-width="3"/>',
           f'<circle cx="30" cy="30" r="6" fill="#fff" fill-opacity="0.75"/>']
    P = [(64 + x * 22, 58 + y * 22) for x, y in outline(cut)]
    out.append(f'<polygon points="{pts(P)}" fill="{shade(base, -.25)}" fill-opacity="0.22" stroke="#fff" stroke-opacity="0.2" stroke-width="2" stroke-linejoin="round"/>')
    out.append("</svg>")
    return "\n".join(out)


# Bright mode looks: the first glossy tile style, with big bold silhouettes chosen to be as
# different from each other as possible. Look 0 is the original palette, then five more.
BRIGHT_SHAPES = ["heart", "kite", "triangle", "star", "round", "square"]
BRIGHT_LOOKS = [["#ff4d5e", "#3d8bff", "#22c97a", "#ffcf33", "#ff9a2e", "#a35cff"]] + [
    [p[0], p[4], p[3], p[2], p[1], p[5]] for p in BLOCK_PALETTES] + [
    ["#f4a6b8", "#5c84c9", "#8fe3cf", "#f0d58a", "#c7d7ea", "#b8a6f2"],   # 6 winter (season)
    ["#c8283c", "#2e8f8f", "#7ccf3a", "#e8e0c8", "#f07b1d", "#7b3fb5"],   # 7 halloween (season)
    ["#d64a5a", "#3f6fd6", "#2fa36b", "#e6b93c", "#c88a4a", "#9aa3b5"],   # 8 gold (7-day streak)
]


def bright_tile_svg(base, cut, size=128):
    """Glossy toy tile like the first look, with a large white silhouette outlined in the
    tile's dark shade so the shape reads at a glance even without colour."""
    c = size / 2
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}"><defs>',
           f'<linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{shade(base, .3)}"/>'
           f'<stop offset="0.55" stop-color="{base}"/><stop offset="1" stop-color="{shade(base, -.3)}"/></linearGradient>',
           '<linearGradient id="w" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/>'
           f'<stop offset="1" stop-color="{shade(base, .78)}"/></linearGradient></defs>',
           '<rect x="7" y="11" width="114" height="112" rx="24" fill="#000" fill-opacity="0.32"/>',
           f'<rect x="6" y="5" width="116" height="112" rx="24" fill="{shade(base, -.38)}"/>',
           '<rect x="6" y="5" width="116" height="104" rx="24" fill="url(#b)"/>',
           '<rect x="10" y="9" width="108" height="96" rx="20" fill="none" stroke="#fff" stroke-opacity="0.35" stroke-width="3"/>',
           '<rect x="16" y="12" width="96" height="30" rx="14" fill="#fff" fill-opacity="0.22"/>']
    R = 38
    dark = shade(base, -.5)
    if cut == "round":
        out.append(f'<circle cx="{c}" cy="{c - 2}" r="{R * .8}" fill="url(#w)" stroke="{dark}" stroke-width="5"/>')
    else:
        P = [(c + x * R, c - 2 + y * R) for x, y in outline(cut)]
        out.append(f'<polygon points="{pts(P)}" fill="url(#w)" stroke="{dark}" stroke-width="5" stroke-linejoin="round"/>')
    out.append("</svg>")
    return "\n".join(out)


def make_specials():
    """Joker tile (rainbow with a white star) and the crate overlay drawn on boxes."""
    j = ('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><defs>'
         '<linearGradient id="r" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff5d7a"/>'
         '<stop offset="0.3" stop-color="#ffc94d"/><stop offset="0.55" stop-color="#4fd18b"/>'
         '<stop offset="0.8" stop-color="#4b9cf0"/><stop offset="1" stop-color="#a477e0"/></linearGradient></defs>'
         '<rect x="7" y="11" width="114" height="112" rx="24" fill="#000" fill-opacity="0.32"/>'
         '<rect x="6" y="5" width="116" height="112" rx="24" fill="#3a2a6a"/>'
         '<rect x="6" y="5" width="116" height="104" rx="24" fill="url(#r)"/>'
         '<rect x="10" y="9" width="108" height="96" rx="20" fill="none" stroke="#fff" stroke-opacity="0.5" stroke-width="3"/>'
         '<rect x="16" y="12" width="96" height="30" rx="14" fill="#fff" fill-opacity="0.25"/>')
    P = [(64 + x * 40, 58 + y * 40) for x, y in outline("star")]
    j += f'<polygon points="{pts(P)}" fill="#fff" stroke="#3a2a6a" stroke-width="5" stroke-linejoin="round"/></svg>'
    svg_to_png(j, A("tiles", "joker.png"), 128)
    box = ('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
           '<rect x="8" y="8" width="112" height="106" rx="14" fill="none" stroke="#8a5a2b" stroke-width="14"/>'
           '<rect x="8" y="8" width="112" height="106" rx="14" fill="none" stroke="#c98a4a" stroke-width="8"/>'
           '<path d="M16 16L112 106M112 16L16 106" stroke="#8a5a2b" stroke-width="12" stroke-linecap="round"/>'
           '<path d="M16 16L112 106M112 16L16 106" stroke="#d99c5a" stroke-width="6" stroke-linecap="round"/>'
           + "".join(f'<circle cx="{x}" cy="{y}" r="4" fill="#5b3a1a"/>' for x, y in ((14, 14), (114, 14), (14, 108), (114, 108)))
           + '</svg>')
    svg_to_png(box, A("tiles", "box.png"), 128)
    # ice: a pale blue sheet with cracks and a glint, drawn over a frozen gem
    ice = ('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
           '<rect x="4" y="4" width="120" height="114" rx="22" fill="#cfefff" fill-opacity=".62" stroke="#ffffff" stroke-width="6"/>'
           '<path d="M18 30l26 14 8 26M110 22L84 46l6 30M30 104l24-22 30 4" fill="none" stroke="#fff" stroke-width="4" stroke-opacity=".9"/>'
           '<path d="M22 20l20-8M96 108l14-10" stroke="#fff" stroke-width="7" stroke-linecap="round"/></svg>')
    svg_to_png(ice, A("tiles", "ice.png"), 128)
    # bomb badge (the count is drawn by the game on top of it)
    bomb = ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
            '<path d="M40 14c4-6 10-6 14-2" fill="none" stroke="#8a5a2b" stroke-width="4" stroke-linecap="round"/>'
            '<circle cx="55" cy="10" r="5" fill="#ffcf33"/><circle cx="55" cy="10" r="2.5" fill="#ff5d3a"/>'
            '<circle cx="30" cy="36" r="24" fill="#1d1d2b" stroke="#ff5d3a" stroke-width="4"/>'
            '<rect x="34" y="10" width="10" height="10" rx="2" fill="#3a3a52" transform="rotate(35 39 15)"/>'
            '<ellipse cx="22" cy="26" rx="6" ry="4" fill="#fff" fill-opacity=".35"/></svg>')
    svg_to_png(bomb, A("tiles", "bomb.png"), 64)
    # chameleon: a rainbow ring with a little eye
    ch = ('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><defs>'
          '<linearGradient id="c" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff5d7a"/>'
          '<stop offset="0.33" stop-color="#ffc94d"/><stop offset="0.66" stop-color="#4fd18b"/><stop offset="1" stop-color="#4b9cf0"/></linearGradient></defs>'
          '<rect x="5" y="5" width="118" height="112" rx="24" fill="none" stroke="url(#c)" stroke-width="9" stroke-dasharray="20 9"/>'
          '<circle cx="104" cy="22" r="15" fill="#4fd18b" stroke="#1d4a2b" stroke-width="3"/>'
          '<circle cx="106" cy="22" r="7" fill="#fff"/><circle cx="108" cy="22" r="3.5" fill="#111"/></svg>')
    svg_to_png(ch, A("tiles", "chameleon.png"), 128)


# ---------------- collection packs: each its own tile and its own six pictures ----------------
# Pack index = tile look index. Pack 0 keeps the glossy shape tiles.
# Each icon is SVG drawn in a 128 box around (64, 60) using {c} (main colour) and {d} (dark outline).
PACK_ICONS = {
    1: [  # sweets
        '<circle cx="64" cy="52" r="26" fill="{c}" stroke="{d}" stroke-width="4"/><path d="M64 52m-16 0a16 16 0 1 1 16 16a10 10 0 1 1 -8-12" fill="none" stroke="#fff" stroke-width="5"/><rect x="61" y="78" width="6" height="26" rx="3" fill="#fff" stroke="{d}" stroke-width="2"/>',
        '<path d="M22 44l18 16-18 16zM106 44l-18 16 18 16z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><ellipse cx="64" cy="60" rx="28" ry="20" fill="{c}" stroke="{d}" stroke-width="4"/><path d="M50 48l28 24M60 44l24 20" stroke="#fff" stroke-opacity=".7" stroke-width="4"/>',
        '<circle cx="64" cy="60" r="32" fill="{c}" stroke="{d}" stroke-width="4"/><circle cx="64" cy="60" r="11" fill="#fff" stroke="{d}" stroke-width="4"/><path d="M46 42l4 3M80 40l-3 4M86 66l-4 2M44 72l4-2M70 84l-2-4" stroke="#fff" stroke-width="5" stroke-linecap="round"/>',
        '<path d="M38 64h52l-8 32H46z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><path d="M34 64c0-16 10-26 20-26 4-10 16-10 20 0 10 0 20 10 20 26z" fill="#fff" stroke="{d}" stroke-width="4"/><circle cx="64" cy="30" r="6" fill="#ff4d5e" stroke="{d}" stroke-width="3"/>',
        '<path d="M64 92C30 70 30 40 48 38c8-1 14 5 16 12 2-7 8-13 16-12 18 2 18 32-16 54z" fill="{c}" stroke="{d}" stroke-width="4"/><ellipse cx="52" cy="50" rx="6" ry="4" fill="#fff" fill-opacity=".8"/>',
        '<path d="M64 24l10 22 24 3-18 16 5 24-21-12-21 12 5-24-18-16 24-3z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><circle cx="56" cy="54" r="3" fill="{d}"/><circle cx="72" cy="54" r="3" fill="{d}"/>',
    ],
    2: [  # ocean
        '<path d="M28 60c14-22 44-22 58 0-14 22-44 22-58 0z" fill="{c}" stroke="{d}" stroke-width="4"/><path d="M86 60l18-16v32z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><circle cx="44" cy="56" r="4" fill="{d}"/>',
        '<path d="M64 94L30 52c0-18 16-28 34-28s34 10 34 28z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><path d="M64 94V30M64 94L46 34M64 94L82 34M64 94L36 46M64 94L92 46" stroke="{d}" stroke-width="3"/>',
        '<path d="M64 22l9 26 27-2-21 17 9 26-24-15-24 15 9-26-21-17 27 2z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><circle cx="64" cy="60" r="5" fill="#fff" fill-opacity=".7"/>',
        '<path d="M64 24c14 20 24 34 24 46a24 24 0 0 1-48 0c0-12 10-26 24-46z" fill="{c}" stroke="{d}" stroke-width="4"/><ellipse cx="56" cy="68" rx="5" ry="9" fill="#fff" fill-opacity=".7"/>',
        '<path d="M26 80c10-34 40-44 58-30 10 8 6 22-6 22-8 0-10-10-2-12" fill="none" stroke="{d}" stroke-width="12" stroke-linecap="round"/><path d="M26 80c10-34 40-44 58-30 10 8 6 22-6 22-8 0-10-10-2-12" fill="none" stroke="{c}" stroke-width="6" stroke-linecap="round"/>',
        '<circle cx="64" cy="30" r="8" fill="none" stroke="{c}" stroke-width="6"/><path d="M64 38v54M48 52h32M34 72c4 16 16 22 30 22s26-6 30-22" fill="none" stroke="{c}" stroke-width="7" stroke-linecap="round"/>',
    ],
    3: [  # fruit
        '<path d="M50 70C52 48 60 36 76 28M78 70C76 50 76 38 76 28" fill="none" stroke="#4f8a2b" stroke-width="4"/><circle cx="48" cy="78" r="16" fill="{c}" stroke="{d}" stroke-width="4"/><circle cx="80" cy="76" r="16" fill="{c}" stroke="{d}" stroke-width="4"/><circle cx="43" cy="73" r="4" fill="#fff" fill-opacity=".7"/>',
        '<path d="M64 96C40 80 34 58 40 46c6-8 16-8 24-4 8-4 18-4 24 4 6 12 0 34-24 50z" fill="{c}" stroke="{d}" stroke-width="4"/><path d="M48 40l8-12 8 10 8-10 8 12z" fill="#4fb36a" stroke="{d}" stroke-width="3" stroke-linejoin="round"/>' + "".join(f'<circle cx="{x}" cy="{y}" r="2.5" fill="#fff"/>' for x, y in ((52, 56), (64, 60), (76, 56), (58, 72), (70, 72), (64, 84))),
        "".join(f'<circle cx="{x}" cy="{y}" r="11" fill="{{c}}" stroke="{{d}}" stroke-width="3"/>' for x, y in ((52, 44), (76, 44), (64, 56), (42, 62), (86, 62), (54, 74), (74, 74), (64, 90))) + '<path d="M64 34l10-12" stroke="#4f8a2b" stroke-width="4"/>',
        '<path d="M22 60c10-24 74-24 84 0-10 24-74 24-84 0z" fill="{c}" stroke="{d}" stroke-width="4"/><ellipse cx="50" cy="54" rx="10" ry="4" fill="#fff" fill-opacity=".6"/>',
        '<circle cx="64" cy="60" r="32" fill="{c}" stroke="{d}" stroke-width="4"/><circle cx="64" cy="60" r="24" fill="#fff" fill-opacity=".35"/>' + "".join(f'<path d="M64 60L{64 + 24 * __import__("math").cos(a * 0.785):.1f} {60 + 24 * __import__("math").sin(a * 0.785):.1f}" stroke="{{d}}" stroke-width="2.5"/>' for a in range(8)),
        '<path d="M64 42c-20-12-38 4-34 24 4 22 20 34 34 28 14 6 30-6 34-28 4-20-14-36-34-24z" fill="{c}" stroke="{d}" stroke-width="4"/><path d="M64 42c0-10 2-16 6-20" stroke="#6b4a2a" stroke-width="4"/><path d="M70 30c10-6 20-2 22 4-10 4-18 2-22-4z" fill="#4fb36a" stroke="{d}" stroke-width="2"/>',
    ],
    4: [  # forest
        '<path d="M34 90C30 50 60 26 98 24 96 62 72 92 34 90z" fill="{c}" stroke="{d}" stroke-width="4"/><path d="M34 90C54 66 72 48 94 28" stroke="{d}" stroke-width="3"/>',
        '<path d="M40 52h48c0 26-10 42-24 42S40 78 40 52z" fill="{c}" stroke="{d}" stroke-width="4"/><path d="M34 54c0-18 14-26 30-26s30 8 30 26z" fill="#7a5230" stroke="{d}" stroke-width="4"/><path d="M64 28v-8" stroke="{d}" stroke-width="5" stroke-linecap="round"/>',
        '<path d="M26 62C26 38 44 26 64 26s38 12 38 36z" fill="{c}" stroke="{d}" stroke-width="4"/><rect x="52" y="62" width="24" height="30" rx="8" fill="#f2e6cf" stroke="{d}" stroke-width="4"/><circle cx="50" cy="44" r="6" fill="#fff"/><circle cx="76" cy="40" r="5" fill="#fff"/>',
        "".join(f'<circle cx="{64 + 18 * __import__("math").cos(a * 1.2566 - 1.57):.1f}" cy="{58 + 18 * __import__("math").sin(a * 1.2566 - 1.57):.1f}" r="14" fill="{{c}}" stroke="{{d}}" stroke-width="3"/>' for a in range(5)) + '<circle cx="64" cy="58" r="10" fill="#ffd34d" stroke="{d}" stroke-width="3"/>',
        '<path d="M64 20L88 52H76L96 80H32L52 52H40z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><rect x="58" y="80" width="12" height="16" fill="#7a5230" stroke="{d}" stroke-width="3"/>',
        '<circle cx="64" cy="42" r="15" fill="{c}" stroke="{d}" stroke-width="4"/><circle cx="48" cy="64" r="15" fill="{c}" stroke="{d}" stroke-width="4"/><circle cx="80" cy="64" r="15" fill="{c}" stroke="{d}" stroke-width="4"/><path d="M64 62c0 14 4 24 10 32" stroke="{d}" stroke-width="5" fill="none"/>',
    ],
    5: [  # space
        '<ellipse cx="64" cy="60" rx="44" ry="13" fill="none" stroke="{d}" stroke-width="9" transform="rotate(-20 64 60)"/><circle cx="64" cy="60" r="24" fill="{c}" stroke="{d}" stroke-width="4"/><ellipse cx="64" cy="60" rx="44" ry="13" fill="none" stroke="{c}" stroke-width="4" stroke-dasharray="70 70" stroke-dashoffset="-35" transform="rotate(-20 64 60)"/>',
        '<path d="M76 26A34 34 0 1 0 98 78 28 28 0 1 1 76 26z" fill="{c}" stroke="{d}" stroke-width="4"/><circle cx="52" cy="62" r="5" fill="{d}" fill-opacity=".3"/>',
        '<path d="M64 20l11 25 27 3-20 18 6 27-24-14-24 14 6-27-20-18 27-3z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/>',
        '<path d="M58 70L100 28l-28 52z" fill="{c}" fill-opacity=".55"/><circle cx="50" cy="76" r="18" fill="{c}" stroke="{d}" stroke-width="4"/><circle cx="44" cy="70" r="5" fill="#fff" fill-opacity=".7"/>',
        '<circle cx="64" cy="60" r="20" fill="{c}" stroke="{d}" stroke-width="4"/>' + "".join(f'<path d="M{64 + 26 * __import__("math").cos(a * 0.785):.1f} {60 + 26 * __import__("math").sin(a * 0.785):.1f}L{64 + 38 * __import__("math").cos(a * 0.785):.1f} {60 + 38 * __import__("math").sin(a * 0.785):.1f}" stroke="{{c}}" stroke-width="6" stroke-linecap="round"/>' for a in range(8)),
        '<path d="M64 18c16 12 18 34 14 52H50c-4-18-2-40 14-52z" fill="{c}" stroke="{d}" stroke-width="4"/><circle cx="64" cy="44" r="7" fill="#9fe3ff" stroke="{d}" stroke-width="3"/><path d="M50 62l-12 18 14-4zM78 62l12 18-14-4z" fill="#ff5d6c" stroke="{d}" stroke-width="3" stroke-linejoin="round"/><path d="M56 74l8 20 8-20" fill="#ffc83d" stroke="{d}" stroke-width="3"/>',
    ],
    6: [  # winter
        '<g stroke="{c}" stroke-width="7" stroke-linecap="round">' + "".join(f'<path d="M64 60L{64 + 34 * __import__("math").cos(a * 1.047):.1f} {60 + 34 * __import__("math").sin(a * 1.047):.1f}"/>' for a in range(6)) + '</g><circle cx="64" cy="60" r="8" fill="{c}"/>',
        '<path d="M44 92V50c0-18 10-26 24-26s22 10 22 24v44z" fill="{c}" stroke="{d}" stroke-width="4"/><path d="M44 58c-10-4-16 2-14 10 2 8 10 10 14 6" fill="{c}" stroke="{d}" stroke-width="4"/><rect x="40" y="84" width="54" height="12" rx="5" fill="#fff" stroke="{d}" stroke-width="3"/>',
        '<path d="M64 20L90 56H78L96 84H32L50 56H38z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><path d="M50 56l8 4 6-4 6 4 8-4M40 84l12-6 12 6 12-6 12 6" fill="none" stroke="#fff" stroke-width="4"/>',
        '<circle cx="64" cy="78" r="20" fill="{c}" stroke="{d}" stroke-width="4"/><circle cx="64" cy="44" r="15" fill="{c}" stroke="{d}" stroke-width="4"/><circle cx="58" cy="41" r="2.5" fill="{d}"/><circle cx="70" cy="41" r="2.5" fill="{d}"/><path d="M64 46l10 3-10 2z" fill="#ff9a2e"/>',
        '<path d="M38 82c4-6 6-14 6-26 0-14 8-24 20-24s20 10 20 24c0 12 2 20 6 26z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><circle cx="64" cy="88" r="7" fill="{c}" stroke="{d}" stroke-width="3"/><path d="M60 32a4 4 0 0 1 8 0" stroke="{d}" stroke-width="4" fill="none"/>',
        '<path d="M64 22l30 17v34L64 90 34 73V39z" fill="{c}" fill-opacity=".85" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><path d="M64 22v68M34 39l60 34M94 39L34 73" stroke="#fff" stroke-opacity=".6" stroke-width="3"/>',
    ],
    7: [  # halloween
        '<ellipse cx="64" cy="64" rx="34" ry="28" fill="{c}" stroke="{d}" stroke-width="4"/><path d="M50 40c-8 10-8 38 0 48M78 40c8 10 8 38 0 48" fill="none" stroke="{d}" stroke-width="3"/><path d="M62 36c0-8 4-12 8-14" stroke="#4f8a2b" stroke-width="5"/><path d="M50 60l6-6 6 6zM66 60l6-6 6 6zM50 74c8 6 20 6 28 0" fill="{d}" stroke="{d}" stroke-width="3"/>',
        '<path d="M36 96V54c0-18 12-30 28-30s28 12 28 30v42l-8-8-7 8-6-8-7 8-6-8-7 8z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><ellipse cx="54" cy="54" rx="5" ry="7" fill="{d}"/><ellipse cx="74" cy="54" rx="5" ry="7" fill="{d}"/>',
        '<path d="M64 52c-10-14-26-16-42-6 8 2 12 8 10 16 8-6 14-2 16 6 4-6 10-8 16-6 6-2 12 0 16 6 2-8 8-12 16-6-2-8 2-14 10-16-16-10-32-8-42 6z" fill="{c}" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><circle cx="64" cy="58" r="10" fill="{c}" stroke="{d}" stroke-width="4"/><path d="M58 50l-2-8M70 50l2-8" stroke="{d}" stroke-width="4"/>',
        '<path d="M64 22L96 92H32z" fill="#fff" stroke="{d}" stroke-width="4" stroke-linejoin="round"/><path d="M50 52L78 52 86 70H42z" fill="{c}"/><path d="M42 70h44l10 22H32z" fill="#ffc83d"/><path d="M64 22L96 92H32z" fill="none" stroke="{d}" stroke-width="4" stroke-linejoin="round"/>',
        '<path d="M78 24A36 36 0 1 0 100 82 30 30 0 1 1 78 24z" fill="{c}" stroke="{d}" stroke-width="4"/>',
        '<g fill="none" stroke="{c}" stroke-width="4">' + "".join(f'<path d="M64 60L{64 + 40 * __import__("math").cos(a * 0.785):.1f} {60 + 40 * __import__("math").sin(a * 0.785):.1f}"/>' for a in range(8)) + "".join(f'<circle cx="64" cy="60" r="{r}"/>' for r in (12, 24, 36)) + '</g>',
    ],
}
PACK_COLORS = {
    1: ["#ff6fb5", "#ffb547", "#c27bff", "#ff8a5c", "#ff4d6d", "#ffd84d"],
    2: ["#ff9a5c", "#f2a3c7", "#ffcf4d", "#4fc3f7", "#2fd6c7", "#8fa6ff"],
    3: ["#d8283c", "#ff5d7a", "#8a4fd6", "#ffd84d", "#ff9a2e", "#7ccf3a"],
    4: ["#6abf4b", "#b97a3c", "#e2453c", "#ff8fc7", "#2f8a4f", "#4fd18b"],
    5: ["#ff9a5c", "#fff1a8", "#ff7eb6", "#5fd4ff", "#ff5a4f", "#c3cfff"],
    6: ["#3d8bdf", "#ff6f7a", "#4fb88b", "#ffffff", "#ffcf4d", "#8fd3ff"],
    7: ["#ff8a1d", "#f2f2f2", "#7b4fd6", "#ff5d3a", "#ffe08a", "#cfd8dc"],
}
PACK_TILE = {1: "candy", 2: "bubble", 3: "pastel", 4: "wood", 5: "space", 6: "ice", 7: "spooky", 8: "gold"}


def pack_tile_svg(style, icon, color, size=128):
    d = shade(color, -.55)
    bg = {
        "candy": ('<circle cx="64" cy="66" r="56" fill="#000" fill-opacity=".25"/><circle cx="64" cy="62" r="56" fill="#fff0f7"/>'
                  '<circle cx="64" cy="62" r="56" fill="none" stroke="#ff9ccf" stroke-width="6" stroke-dasharray="12 10"/>'),
        "bubble": ('<circle cx="64" cy="64" r="56" fill="#0b4a6b" fill-opacity=".35"/><circle cx="64" cy="62" r="56" fill="#bfeaff" fill-opacity=".55" stroke="#e8f8ff" stroke-width="4"/>'
                   '<path d="M30 40a40 40 0 0 1 30-20" stroke="#fff" stroke-width="6" stroke-linecap="round" fill="none"/>'),
        "pastel": ('<rect x="7" y="11" width="114" height="112" rx="26" fill="#000" fill-opacity=".2"/><rect x="6" y="5" width="116" height="112" rx="26" fill="#fff6e8"/>'
                   '<rect x="12" y="11" width="104" height="100" rx="22" fill="none" stroke="#f2d9b8" stroke-width="4"/>'),
        "wood": ('<rect x="7" y="11" width="114" height="112" rx="14" fill="#000" fill-opacity=".3"/><rect x="6" y="5" width="116" height="112" rx="14" fill="#a8743f"/>'
                 '<path d="M6 30h116M6 62h116M6 94h116" stroke="#8a5a2b" stroke-width="3"/><rect x="6" y="5" width="116" height="112" rx="14" fill="none" stroke="#6b4421" stroke-width="5"/>'),
        "space": (f'<rect x="7" y="11" width="114" height="112" rx="22" fill="#000" fill-opacity=".35"/><rect x="6" y="5" width="116" height="112" rx="22" fill="#141a3e"/>'
                  f'<circle cx="64" cy="60" r="44" fill="{color}" fill-opacity=".18"/><circle cx="26" cy="24" r="2" fill="#fff"/><circle cx="100" cy="98" r="2" fill="#fff"/><circle cx="104" cy="28" r="1.5" fill="#fff"/>'
                  f'<rect x="6" y="5" width="116" height="112" rx="22" fill="none" stroke="{color}" stroke-opacity=".7" stroke-width="3"/>'),
        "ice": ('<rect x="7" y="11" width="114" height="112" rx="18" fill="#000" fill-opacity=".2"/><rect x="6" y="5" width="116" height="112" rx="18" fill="#cfeeff"/>'
                '<path d="M12 22l18-10M98 108l18-10M14 90l10 8" stroke="#fff" stroke-width="4" stroke-linecap="round"/><rect x="6" y="5" width="116" height="112" rx="18" fill="none" stroke="#fff" stroke-width="5"/>'),
        "spooky": ('<rect x="7" y="11" width="114" height="112" rx="20" fill="#000" fill-opacity=".35"/><rect x="6" y="5" width="116" height="112" rx="20" fill="#2a1638"/>'
                   '<rect x="6" y="5" width="116" height="112" rx="20" fill="none" stroke="#ff8a1d" stroke-opacity=".8" stroke-width="4"/>'),
        "gold": ('<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff2b8"/><stop offset=".45" stroke-color="#e6b93c" stop-color="#e6b93c"/><stop offset="1" stop-color="#8a6a1e"/></linearGradient></defs>'
                 '<rect x="7" y="11" width="114" height="112" rx="20" fill="#000" fill-opacity=".3"/><rect x="6" y="5" width="116" height="112" rx="20" fill="url(#g)"/>'
                 '<rect x="14" y="13" width="100" height="96" rx="14" fill="#3a2a10" fill-opacity=".85"/>'),
    }[style]
    body = icon.replace("{c}", color).replace("{d}", d)
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">{bg}{body}</svg>'


def neon_tile_svg(color, cut, size=128):
    """Season pass pack: dark glass tile with the shape drawn as a glowing neon tube."""
    c = size / 2
    R = 36
    if cut == "round":
        shape = f'<circle cx="{c}" cy="{c - 2}" r="{R * .8}"'
    else:
        P = [(c + x * R, c - 2 + y * R) for x, y in outline(cut)]
        shape = f'<polygon points="{pts(P)}"'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">'
            '<defs><filter id="g" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="5"/></filter></defs>'
            '<rect x="7" y="11" width="114" height="112" rx="22" fill="#000" fill-opacity=".4"/>'
            '<rect x="6" y="5" width="116" height="112" rx="22" fill="#0d0b1e"/>'
            f'<rect x="8" y="7" width="112" height="108" rx="20" fill="none" stroke="{color}" stroke-opacity=".35" stroke-width="2"/>'
            f'{shape} fill="none" stroke="{color}" stroke-width="12" filter="url(#g)" stroke-linejoin="round"/>'
            f'{shape} fill="none" stroke="{color}" stroke-width="6" stroke-linejoin="round"/>'
            f'{shape} fill="none" stroke="#fff" stroke-opacity=".85" stroke-width="2" stroke-linejoin="round"/></svg>')


def glass_tile_svg(color, cut, size=128):
    """Season pass pack: stained glass, facets of the colour split by dark lead lines."""
    c = size / 2
    R = 36
    if cut == "round":
        shape = f'<circle cx="{c}" cy="{c - 2}" r="{R * .8}"'
    else:
        P = [(c + x * R, c - 2 + y * R) for x, y in outline(cut)]
        shape = f'<polygon points="{pts(P)}"'
    facets = "".join(f'<path d="{d}" fill="{shade(color, f)}"/>' for d, f in (
        ("M6 5h58L6 60z", .25), ("M64 5h58v55z", -.1), ("M6 60L64 5l58 55-58 57z", 0), ("M6 60v57h58z", -.25), ("M122 60v57H64z", .1)))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">'
            '<clipPath id="k"><rect x="6" y="5" width="116" height="112" rx="16"/></clipPath>'
            '<rect x="7" y="11" width="114" height="112" rx="16" fill="#000" fill-opacity=".35"/>'
            f'<g clip-path="url(#k)">{facets}<path d="M6 60L64 5l58 55-58 57zM64 5v112M6 60h116" fill="none" stroke="#2a2030" stroke-width="3"/></g>'
            f'{shape} fill="#fff" fill-opacity=".9" stroke="#2a2030" stroke-width="6" stroke-linejoin="round"/>'
            '<rect x="6" y="5" width="116" height="112" rx="16" fill="none" stroke="#2a2030" stroke-width="6"/></svg>')


NEON_COLORS = ["#ff3d8b", "#33e1ff", "#7dff5a", "#ffe53d", "#ff8a1f", "#b06bff"]
GLASS_COLORS = ["#d8283c", "#2a6fd6", "#1fa36a", "#e8b622", "#e8701c", "#8a3fcf"]


def make_packs():
    for k in range(6):
        svg_to_png(neon_tile_svg(NEON_COLORS[k], BRIGHT_SHAPES[k]), A("tiles", f"look_9_{k}.png"), 128)
        svg_to_png(glass_tile_svg(GLASS_COLORS[k], BRIGHT_SHAPES[k]), A("tiles", f"look_10_{k}.png"), 128)
    for look in range(1, 9):
        for k in range(6):
            if look == 8:  # gold: the faceted classic gems set on gold
                g = gem_svg("", ["#e2334c", "#2f6ff0", "#17a866", "#f4c62e", "#f28a22", "#9a4fe6"][k],
                            ["square", "kite", "octagon", "star", "round", "hexagon"][k], 96)
                inner = g[g.index(">") + 1: g.rindex("</svg>")]
                svg = pack_tile_svg("gold", f'<g transform="translate(16 12)">{inner}</g>', "#e6b93c")
            else:
                svg = pack_tile_svg(PACK_TILE[look], PACK_ICONS[look][k], PACK_COLORS[look][k])
            svg_to_png(svg, A("tiles", f"look_{look}_{k}.png"), 128)


def make_tiles():
    for look, pal in enumerate(BRIGHT_LOOKS):
        for i, col in enumerate(pal):
            svg_to_png(bright_tile_svg(col, BRIGHT_SHAPES[i]), A("tiles", f"look_{look}_{i}.png"), 128)
    for t, pal in enumerate(BLOCK_PALETTES):
        for i, col in enumerate(pal):
            svg_to_png(block_svg(col, BLOCK_SYMBOL[i]), A("tiles", f"block_{t}_{i}.png"), 128)
    for i, (name, _base, cut) in enumerate(GEMS):
        svg_to_png(tile_svg(TOY[i], cut), A("tiles", f"tile_{i}.png"), 128)
    # empty slot: a soft rounded hollow
    slot = ('<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">'
            '<rect x="6" y="6" width="84" height="84" rx="18" fill="#000" fill-opacity="0.28"/>'
            '<rect x="6" y="6" width="84" height="84" rx="18" fill="none" stroke="#fff" stroke-opacity="0.08" stroke-width="3"/>'
            '<rect x="10" y="10" width="76" height="14" rx="7" fill="#000" fill-opacity="0.18"/></svg>')
    svg_to_png(slot, A("ui", "slot_tile.png"), 96)


def make_previews():
    """Small board previews for the mode cards, built from the game's own gem art."""
    w, h, c = 360, 220, 40
    rnd = random.Random(11)
    # classic: faceted gems on velvet
    velvet = Image.open(A("ui", "velvet.png")).convert("RGBA")
    pv = Image.new("RGBA", (w, h))
    for yy in range(0, h, 256):
        for xx in range(0, w, 256):
            pv.paste(velvet, (xx, yy))
    pv.alpha_composite(Image.open(A("ui", "vignette.png")).resize((w, h)))
    for gy in range(5):
        for gx in range(9):
            if rnd.random() < 0.78:
                g = Image.open(A("gems", f"gem_{rnd.randrange(10)}.png")).convert("RGBA").resize((c - 2, c - 2), Image.LANCZOS)
                pv.alpha_composite(g, (3 + gx * c, 12 + gy * c))
    pv.save(A("ui", "preview_classic.png"))
    # bright: glossy tiles on a blue gradient
    y = np.linspace(0, 1, h)[:, None]
    top, bot = np.array([61, 99, 224]), np.array([27, 44, 140])
    grad = (top * (1 - y) + bot * y)[:, None, :].repeat(w, 1).reshape(h, w, 3)
    pb = Image.fromarray(np.dstack([grad, np.full((h, w), 255)]).astype(np.uint8), "RGBA")
    slot = Image.open(A("ui", "slot_tile.png")).convert("RGBA").resize((c, c), Image.LANCZOS)
    for gy in range(5):
        for gx in range(9):
            pb.alpha_composite(slot, (0 + gx * c, 10 + gy * c))
            if rnd.random() < 0.7:
                t = Image.open(A("tiles", f"look_0_{rnd.randrange(6)}.png")).convert("RGBA").resize((c - 2, c - 2), Image.LANCZOS)
                pb.alpha_composite(t, (1 + gx * c, 11 + gy * c))
    pb.save(A("ui", "preview_bright.png"))


def make_icons():
    ICONS["settings"] = gear_path()
    # settings controls: a pill switch (on/off) and a round slider knob
    sw = ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="36" viewBox="0 0 64 36">'
          '<rect x="2" y="3" width="60" height="30" rx="15" fill="{bg}" stroke="#d2ab55" stroke-width="2"/>'
          '<circle cx="{cx}" cy="18" r="11" fill="{knob}"/></svg>')
    svg_to_png(sw.format(bg="#d2ab55", cx=47, knob="#1b1408"), A("ui", "switch_on.png"), 64, 36)
    svg_to_png(sw.format(bg="#0b2224", cx=17, knob="#8ea6a1"), A("ui", "switch_off.png"), 64, 36)
    knob = ('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">'
            '<circle cx="16" cy="16" r="13" fill="#f7e2a8" stroke="#8a6a2a" stroke-width="2"/></svg>')
    svg_to_png(knob, A("ui", "knob.png"), 32)
    for name, body in ICONS.items():
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" fill="#fff">{body}</svg>'
        svg_to_png(svg, A("ui", f"icon_{name}.png"), 64)


def make_textures():
    rng = np.random.default_rng(7)
    # velvet cloth: seamless fine noise over deep bottle green
    n = rng.normal(0, 6.5, (256, 256))
    n = (n + np.roll(n, 1, 0) * .5 + np.roll(n, 1, 1) * .5) / 2
    base = np.array([18, 50, 52], float)
    img = np.clip(base[None, None, :] + n[..., None] * np.array([.8, 1, 1]), 0, 255).astype(np.uint8)
    Image.fromarray(img).save(A("ui", "velvet.png"))
    # vignette (alpha only)
    s = 512
    y, x = np.mgrid[0:s, 0:s] / (s - 1) * 2 - 1
    d = np.clip(np.sqrt(x * x + y * y) / 1.35, 0, 1)
    a = (d ** 2.2 * 190).astype(np.uint8)
    v = np.zeros((s, s, 4), np.uint8); v[..., 3] = a
    Image.fromarray(v).save(A("ui", "vignette.png"))
    # pressed slot
    s = 96
    y, x = np.mgrid[0:s, 0:s] - (s - 1) / 2
    r = np.sqrt(x * x + (y + 3) ** 2) / (s * .44)
    alpha = np.where(r < 1, (0.36 - 0.2 * r) * 255, 0)
    rim = np.clip(1 - abs(np.sqrt(x * x + y * y) / (s * .44) - 1) * 14, 0, 1) * (y > 0) * 22
    sl = np.zeros((s, s, 4), np.uint8)
    sl[..., :3] = np.where(rim[..., None] > 0, 255, 0)
    sl[..., 3] = np.clip(alpha + rim, 0, 255)
    slot_img = Image.fromarray(sl).filter(ImageFilter.GaussianBlur(1.2))
    rr = s * .44 * (0.3 / 0.42)  # gold ring at 0.3 cell radius (the texture spans 0.84 cell)
    ImageDraw.Draw(slot_img).ellipse([s / 2 - rr, s / 2 - rr, s / 2 + rr, s / 2 + rr], outline=(210, 171, 85, 70), width=3)
    slot_img.save(A("ui", "slot.png"))
    # soft round glow, tinted in code (gem halos, ambient light)
    s = 128
    y, x = np.mgrid[0:s, 0:s] - (s - 1) / 2
    d = np.clip(np.sqrt(x * x + y * y) / (s / 2), 0, 1)
    gl = np.zeros((s, s, 4), np.uint8)
    gl[..., :3] = 255
    gl[..., 3] = ((1 - d) ** 2.4 * 255).astype(np.uint8)
    Image.fromarray(gl).save(A("fx", "glow.png"))
    # sparkle for knock-out particles
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
           '<defs><radialGradient id="g"><stop offset="0" stop-color="#fff" stop-opacity="0.9"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient></defs>'
           '<circle cx="32" cy="32" r="22" fill="url(#g)"/>'
           '<path d="M32 2 C34 26 38 30 62 32 C38 34 34 38 32 62 C30 38 26 34 2 32 C26 30 30 26 32 2Z" fill="#fff"/></svg>')
    svg_to_png(svg, A("fx", "sparkle.png"), 64)


# ---------------- sound ----------------
SR = 44100


def write_wav(path, x):
    x = np.clip(x, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32000).astype("<i2").tobytes())


def liven(x, room=0.22, width=0.5, drive=1.4):
    """Make a dry synth effect sound alive: a detuned double for width, a short room tail and
    a touch of saturation, then normalise to the original peak."""
    x = np.asarray(x, float)
    peak = np.max(np.abs(x)) + 1e-9
    d1, d2 = int(.009 * SR), int(.017 * SR)
    idx = np.arange(len(x))
    y = x.copy()
    y[d1:] += width * .6 * np.interp(idx[: len(x) - d1] * 1.006, idx, x)
    y[d2:] += width * .4 * np.interp(idx[: len(x) - d2] * .994, idx, x)
    rng = np.random.default_rng(len(x))
    n_ir = int(.45 * SR)
    ir = rng.normal(0, 1, n_ir) * np.exp(-np.arange(n_ir) / (.11 * SR))
    ir[: int(.004 * SR)] = 0  # pre-delay
    wet = np.convolve(y, ir)[: len(y) + int(.35 * SR)] * room / np.sqrt(n_ir) * 6
    y = np.pad(y, (0, len(wet) - len(y))) + wet
    y = np.tanh(y * drive) / np.tanh(drive)
    return y / (np.max(np.abs(y)) + 1e-9) * peak


def write_sfx(path, x):
    write_wav(path, liven(x))


def env(n, attack=0.004, decay=0.25):
    t = np.arange(n) / SR
    return np.minimum(t / attack, 1) * np.exp(-t / decay)


def bell(freq, dur, decay=.35, vol=.5):
    n = int(SR * dur); t = np.arange(n) / SR
    x = sum(a * np.sin(2 * np.pi * freq * m * t) * np.exp(-t / (decay / m ** .6))
            for m, a in ((1, 1), (2.76, .45), (5.4, .22), (8.93, .1)))
    return x * env(n, .002, 10) * vol


def make_sounds():
    rng = np.random.default_rng(3)
    # knock-outs: crystal chime, brighter and fuller with more gems
    for k, notes in ((2, (1046.5, 1318.5)), (3, (1046.5, 1318.5, 1568)), (4, (1046.5, 1318.5, 1568, 2093))):
        n = int(SR * 1.0); x = np.zeros(n)
        for i, f in enumerate(notes):
            o = int(i * .045 * SR); b = bell(f, 1.0 - i * .045, .3, .32)
            x[o:o + len(b)] += b[:n - o]
        click = rng.normal(0, 1, int(SR * .02)) * env(int(SR * .02), .0005, .004) * .35
        x[:len(click)] += click
        write_sfx(A("audio", f"knock{k}.wav"), x * .8)
    # miss: dull thud on cloth
    n = int(SR * .22); t = np.arange(n) / SR
    thud = np.sin(2 * np.pi * (110 - 50 * t / .22) * t) * env(n, .002, .06)
    noise = rng.normal(0, 1, n) * env(n, .001, .02) * .25
    write_sfx(A("audio", "miss.wav"), (thud * .8 + noise) * .9)
    # tick for the last seconds
    n = int(SR * .06)
    write_sfx(A("audio", "tick.wav"), bell(2400, .06, .015, .35)[:n])
    # ui click
    write_sfx(A("audio", "click.wav"), bell(1800, .08, .02, .3))
    # start: rising arpeggio
    n = int(SR * .9); x = np.zeros(n)
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        o = int(i * .08 * SR); b = bell(f, .9 - i * .08, .25, .3); x[o:o + len(b)] += b
    write_sfx(A("audio", "start.wav"), x)
    # game over: falling three notes
    n = int(SR * 1.3); x = np.zeros(n)
    for i, f in enumerate((783.99, 659.25, 523.25)):
        o = int(i * .16 * SR); b = bell(f, 1.3 - i * .16, .45, .32); x[o:o + len(b)] += b
    write_sfx(A("audio", "over.wav"), x)
    # bonus time
    write_sfx(A("audio", "bonus.wav"), bell(1568, .5, .2, .3) + np.pad(bell(2093, .42, .2, .25), (int(.08 * SR), 0))[:int(SR * .5)])
    make_combo_sounds(rng)
    make_voices()
    make_bright_sounds(rng)
    # Background music is supplied as OGG files; asset generation leaves it untouched.


def arpeggio(notes, step, tail, decay=.3, vol=.28):
    n = int(SR * (step * len(notes) + tail)); x = np.zeros(n)
    for i, f in enumerate(notes):
        o = int(i * step * SR); b = bell(f, n / SR - i * step, decay, vol); x[o:o + len(b)] += b[:n - o]
    return x


def shimmer(rng, dur, vol=.12):
    """Glittery noise: many tiny high bells at random times."""
    n = int(SR * dur); x = np.zeros(n)
    for _ in range(int(dur * 40)):
        o = rng.integers(0, int(n * .8)); f = rng.uniform(2500, 6000)
        b = bell(f, .25, .05, vol * rng.uniform(.4, 1)); x[o:o + len(b)] += b[:n - o]
    return x * np.linspace(1, .2, n)


def make_combo_sounds(rng):
    # combo tier up: quick rising fifth
    write_sfx(A("audio", "combo_up.wav"), arpeggio((1174.7, 1760, 2349.3), .05, .45, .2, .26))
    # combo lost: soft falling pair
    write_sfx(A("audio", "combo_break.wav"), arpeggio((880, 659.25), .09, .35, .15, .18))
    # precise combo: major arpeggio with glitter
    x = arpeggio((783.99, 987.77, 1174.7, 1567.98), .07, 1.0, .35, .26)
    x[:len(shimmer(rng, 1.0))] += shimmer(rng, 1.0)[:len(x)]
    write_sfx(A("audio", "precise.wav"), x * .85)
    # perfect combo: two-octave fanfare, low thump, long glitter
    n = int(SR * 1.8)
    x = np.zeros(n)
    a = arpeggio((523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98, 2093), .055, 1.2, .45, .24); x[:len(a)] += a[:n]
    t = np.arange(int(SR * .35)) / SR
    x[:len(t)] += np.sin(2 * np.pi * (90 - 40 * t) * t) * np.exp(-t / .12) * .6
    g = shimmer(rng, 1.8, .14); x[:len(g)] += g
    write_sfx(A("audio", "perfect.wav"), np.tanh(x * 1.2) * .8)


def pluck(freq, dur, vol=.3, bright=1.0):
    n = int(SR * dur); t = np.arange(n) / SR
    x = (np.sin(2 * np.pi * freq * t) + .5 * bright * np.sin(4 * np.pi * freq * t) + .25 * bright * np.sin(6 * np.pi * freq * t))
    return x * np.exp(-t / (dur * .35)) * np.minimum(t / .003, 1) * vol


def pop(freq, dur=.16, vol=.5):
    """Bubbly pop: a quick downward pitch sweep with a soft click."""
    n = int(SR * dur); t = np.arange(n) / SR
    f = freq * (1.6 - .6 * np.minimum(t / (dur * .5), 1))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / (dur * .28)) * np.minimum(t / .002, 1) * vol


def marimba(freq, dur=.5, vol=.4):
    """Glassy marimba: fundamental plus a bright 4th partial, fast decay, soft mallet click."""
    n = int(SR * dur); t = np.arange(n) / SR
    x = (np.sin(2 * np.pi * freq * t) * np.exp(-t / .25) + .35 * np.sin(2 * np.pi * freq * 3.98 * t) * np.exp(-t / .06)
         + .15 * np.sin(2 * np.pi * freq * 9.1 * t) * np.exp(-t / .02))
    return x * np.minimum(t / .002, 1) * vol


def fm_ding(freq, dur=.45, vol=.4, index=3.0, ratio=3.5):
    """Clean arcade 'ding': a small FM bell with a bright attack that mellows quickly."""
    n = int(SR * dur); t = np.arange(n) / SR
    mod = index * np.exp(-t / .06) * np.sin(2 * np.pi * freq * ratio * t)
    x = np.sin(2 * np.pi * freq * t + mod) * np.exp(-t / (dur * .35))
    x += .25 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t / (dur * .15))
    return x * np.minimum(t / .0015, 1) * vol


def whoosh(dur, f0, f1, vol=.25, seed=5):
    """Rising filtered-noise sweep."""
    n = int(SR * dur); t = np.arange(n) / SR
    noise = np.random.default_rng(seed).normal(0, 1, n)
    out = np.zeros(n); y1 = y2 = 0.0
    fc = f0 * (f1 / f0) ** (t / dur)
    for i in range(n):  # simple resonant band-pass that follows fc
        g = 2 * np.sin(np.pi * fc[i] / SR)
        y1 += g * (noise[i] - y1 - .6 * y2)
        y2 += g * y1
        out[i] = y1
    env_ = np.sin(np.pi * np.minimum(t / dur, 1)) ** 1.5
    return out / (np.max(np.abs(out)) + 1e-9) * env_ * vol


def _mix(*parts):
    n = max(len(p) for p, _ in parts)
    x = np.zeros(n)
    for p, off in parts:
        o = int(off * SR)
        x[o:o + len(p)] += p[:max(0, n - o)]
    return x


def make_bright_sounds(rng):
    """Bright mode: arcade-style dings that climb with the combo (the game plays the knock at
    rising pitches), whooshes and chord hits for combo steps, and bells."""
    for k in (2, 3, 4):
        x = _mix((fm_ding(880, .45, .42), 0), (fm_ding(1760, .3, .12, 1.5), .005))
        if k >= 3:
            x = _mix((x, 0), (fm_ding(1318.5, .4, .2), .03))
        if k >= 4:
            x = _mix((x, 0), (fm_ding(2637, .35, .12), .05), (shimmer(rng, .4, .06), .02))
        write_sfx(A("audio", f"b_knock{k}.wav"), x)
    n = int(SR * .25); t = np.arange(n) / SR
    write_sfx(A("audio", "b_miss.wav"), np.sin(2 * np.pi * (180 - 60 * t / .25) * t) * np.exp(-t / .07) * .5)
    write_sfx(A("audio", "b_combo_up.wav"), _mix((whoosh(.28, 400, 4000, .2), 0),
        (fm_ding(1046.5, .3, .3), .18), (fm_ding(1568, .3, .3), .23), (fm_ding(2093, .45, .32), .28)))
    cb = marimba(392, .4, .25)
    m2 = np.pad(marimba(330, .3, .2), (int(.08 * SR), 0))
    cb[:min(len(cb), len(m2))] += m2[:min(len(cb), len(m2))]
    write_sfx(A("audio", "b_combo_break.wav"), cb)
    chord = _mix((fm_ding(1046.5, .9, .3), 0), (fm_ding(1318.5, .9, .26), 0), (fm_ding(1568, .9, .26), 0))
    write_sfx(A("audio", "b_precise.wav"), _mix((whoosh(.35, 300, 5000, .25, 7), 0), (_kick() * .6, .33), (chord, .33),
        (shimmer(rng, .9, .1), .35)))
    arp = [(fm_ding(f, .6, .26), .32 + i * .05) for i, f in enumerate((523, 659, 784, 1047, 1319, 1568, 2093, 2637))]
    big = _mix((whoosh(.36, 250, 6000, .28, 9), 0), (_kick(), .34), (_snare(rng) * .5, .34), *arp,
               (shimmer(rng, 1.6, .12), .4))
    write_sfx(A("audio", "b_perfect.wav"), np.tanh(big * 1.2) * .8)
    write_sfx(A("audio", "b_start.wav"), arpeggio((784, 988, 1175, 1568), .06, .5, .2, .24))
    write_sfx(A("audio", "b_bonus.wav"), arpeggio((1568, 2093), .06, .35, .12, .22))
    write_sfx(A("audio", "b_over.wav"), arpeggio((784, 659, 523, 392), .12, .9, .3, .25))
    write_sfx(A("audio", "b_tick.wav"), marimba(1760, .08, .25))
    # new events
    st = bell(1760, .6, .25, .35)
    s2 = np.pad(bell(2637, .5, .2, .2), (int(.05 * SR), 0))
    st[:min(len(st), len(s2))] += s2[:min(len(st), len(s2))]
    write_sfx(A("audio", "b_star.wav"), st)
    write_sfx(A("audio", "b_hint.wav"), arpeggio((1318.5, 1760), .08, .4, .2, .2))
    x = arpeggio((523, 784, 1047, 1568, 2093), .07, 1.0, .35, .24); g = shimmer(rng, 1.2, .1)
    x = np.pad(x, (0, max(0, len(g) - len(x)))); x[:len(g)] += g
    write_sfx(A("audio", "b_level.wav"), x)
    n = int(SR * 1.8); t = np.arange(n) / SR
    sweep = np.sin(2 * np.pi * np.cumsum(300 + 1800 * (t / 1.8) ** 1.5) / SR) * np.exp(-t / .9) * .15
    x = sweep.copy()
    a = arpeggio((1047, 1319, 1568, 2093, 2637, 3136), .09, 1.2, .5, .22); x[:min(n, len(a))] += a[:min(n, len(a))]
    g = shimmer(rng, 1.8, .14); x[:len(g)] += g
    write_sfx(A("audio", "b_clear.wav"), np.tanh(x * 1.3) * .8)


def _kick():
    n = int(SR * .22); t = np.arange(n) / SR
    return np.sin(2 * np.pi * (55 + 90 * np.exp(-t / .03)) * t) * np.exp(-t / .09)


def _snare(rng):
    n = int(SR * .16); t = np.arange(n) / SR
    return (rng.normal(0, 1, n) * .6 + np.sin(2 * np.pi * 190 * t) * .5) * np.exp(-t / .05)


def _hat(rng):
    n = int(SR * .05); t = np.arange(n) / SR
    x = rng.normal(0, 1, n); x = x - np.convolve(x, np.ones(4) / 4, "same")
    return x * np.exp(-t / .012) * .5


def _lead(freq, dur, vol=.12):
    """Soft square-ish lead: odd harmonics, quick attack, gentle vibrato."""
    n = int(SR * dur); t = np.arange(n) / SR
    vib = 1 + .004 * np.sin(2 * np.pi * 5.5 * t)
    ph = 2 * np.pi * freq * vib * t
    x = np.sin(ph) + np.sin(3 * ph) / 3 + np.sin(5 * ph) / 6
    env_ = np.minimum(t / .01, 1) * np.exp(-t / (dur * .9))
    return x * env_ * vol




VOICE_LINES = {"great": "Great!", "super": "Super!", "amazing": "Amazing!", "incredible": "Incredible!",
               "perfect": "Perfect!", "clear": "Board clear!", "levelup": "Level up!"}


PIPER_SPEAKER = 575  # LibriTTS-R speaker: a lively male voice (~135 Hz) with the widest intonation


def make_voices():
    """Announcer call-outs. With Piper (set PIPER_DIR to the folder holding the piper binary and
    voice.onnx, the en_US-libritts_r-medium voice, CC BY 4.0) they sound like a real person;
    otherwise espeak-ng is used. Light processing only: level, a little glue, a short room."""
    import shutil, tempfile
    piper_dir = os.environ.get("PIPER_DIR", "")
    piper = os.path.join(piper_dir, "piper", "piper") if piper_dir else ""
    use_piper = piper and os.path.exists(piper)
    if not use_piper and not shutil.which("espeak-ng"):
        print("no speech synthesiser found, keeping existing voice files")
        return
    for name, text in VOICE_LINES.items():
        with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
            if use_piper:
                subprocess.run([piper, "--model", os.path.join(piper_dir, "voice.onnx"), "--speaker", str(PIPER_SPEAKER),
                                "--length_scale", "0.88", "--noise_scale", "0.95", "--noise_w", "1.0", "--output_file", tmp.name],
                               input=text.encode(), check=True, capture_output=True)
            else:
                subprocess.run(["espeak-ng", "-v", "en-us+m3", "-s", "135", "-p", "62", "-w", tmp.name, text], check=True)
            with wave.open(tmp.name) as w:
                sr = w.getframerate()
                x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32768
        x = np.interp(np.linspace(0, len(x) - 1, int(len(x) * SR / sr)), np.arange(len(x)), x)
        nz = np.nonzero(np.abs(x) > 0.01)[0]
        if len(nz):
            x = x[max(0, nz[0] - int(.01 * SR)): nz[-1] + int(.05 * SR)]  # trim silence
        write_wav(A("audio", f"voice_{name}.wav"), natural(x))


def natural(x):
    """Keep the voice human: level it, gently even out the peaks, add the faintest room."""
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = np.tanh(x * 1.3) / np.tanh(1.3)
    y = liven(x, room=.06, width=.05, drive=1.0)
    return y / (np.max(np.abs(y)) + 1e-9) * .9


def brutal(x):
    """Deep arena-announcer treatment: about two semitones lower, a heavy low end, drive and hard
    compression, then a couple of short arena reflections and a tail."""
    x = x / (np.max(np.abs(x)) + 1e-9)
    k = 2 ** (-2.2 / 12)  # resample lower: deeper pitch and bigger formants
    x = np.interp(np.arange(0, len(x) - 1, k), np.arange(len(x)), x)
    lp = np.zeros_like(x); a = 0.0
    for i, v in enumerate(x):  # one-pole low-pass for the weight underneath
        a += .08 * (v - a); lp[i] = a
    x = x + 1.6 * lp
    x = np.tanh(x * 3.2) * .55 + np.tanh(x * 1.2) * .45  # grit plus body
    x = np.tanh(x / (np.max(np.abs(x)) + 1e-9) * 2.4)  # squash
    y = np.pad(x, (0, int(.6 * SR)))
    for delay, gain in ((.085, .32), (.17, .18), (.26, .09)):
        d = int(delay * SR); y[d:d + len(x)] += gain * x
    y = liven(y, room=.28, width=.25, drive=1.3)
    return y / (np.max(np.abs(y)) + 1e-9) * .95




def font(path, size):
    return ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", path), size)


def prism_diamond_svg(size):
    """A brilliant-cut diamond seen from the side, each facet a different hue (the 'bizarre' gem)."""
    c, R = size / 2, size * 0.46
    cy = c - R * 0.22
    P = lambda x, y: (c + x * R, cy + y * R)
    T = [P(-.62, -.42), P(-.24, -.42), P(.24, -.42), P(.62, -.42)]
    G = [P(-.97, -.1), P(-.5, -.1), P(0, -.1), P(.5, -.1), P(.97, -.1)]
    B = P(0, .95)
    M = [P(-.42, .42), P(.42, .42)]
    facets = [  # (points, hue)
        ([T[0], G[0], G[1]], "#7ee8fa"), ([T[0], T[1], G[1]], "#c9b6ff"), ([T[1], G[1], G[2]], "#ff9ed2"),
        ([T[1], T[2], G[2]], "#fff4c9"), ([T[2], G[2], G[3]], "#9ef0c0"), ([T[2], T[3], G[3]], "#ffd27a"),
        ([T[3], G[3], G[4]], "#8fb8ff"),
        ([G[0], G[1], M[0]], "#3aa0e8"), ([G[1], G[2], M[0]], "#9b5cf0"), ([M[0], G[2], B], "#e8508f"),
        ([G[2], G[3], M[1]], "#f0a53a"), ([G[3], G[4], M[1]], "#2fc28a"), ([M[1], G[2], B], "#4f7df5"),
        ([G[0], M[0], B], "#2370c8"), ([G[4], M[1], B], "#1d9a6c"),
    ]
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}"><defs>']
    for i, (_, hue) in enumerate(facets):
        out.append(f'<linearGradient id="f{i}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{shade(hue, .35)}"/>'
                   f'<stop offset="1" stop-color="{shade(hue, -.25)}"/></linearGradient>')
    out.append('<radialGradient id="glint"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>')
    out.append("</defs>")
    hull = [T[0], T[3], G[4], B, G[0]]
    out.append(f'<polygon points="{pts(hull)}" fill="#14243a" stroke="#0b1424" stroke-width="{size*.03:.1f}" stroke-linejoin="round"/>')
    for i, (poly, _) in enumerate(facets):
        out.append(f'<polygon points="{pts(poly)}" fill="url(#f{i})" stroke="#ffffff" stroke-opacity="0.55" stroke-width="{size*.006:.1f}" stroke-linejoin="round"/>')
    out.append(f'<polygon points="{pts(hull)}" fill="none" stroke="#0b1424" stroke-width="{size*.012:.1f}" stroke-linejoin="round"/>')
    # highlights on the crown
    out.append(f'<polygon points="{pts([T[1], T[2], P(.05, -.28), P(-.3, -.28)])}" fill="#fff" fill-opacity="0.45"/>')
    gx, gy = P(-.42, -.3)
    out.append(f'<circle cx="{gx:.1f}" cy="{gy:.1f}" r="{R*.16:.1f}" fill="url(#glint)" fill-opacity="0.9"/>')
    out.append("</svg>")
    return "\n".join(out)


def make_icon(ground):
    """Store icon 512x512 (opaque, the platform rounds corners) and the 256 px project icon."""
    S = 1024  # draw at 2x, downscale for clean edges
    ic = ground(S, S)
    # warm glow behind the strike point
    y, x = np.mgrid[0:S, 0:S]
    d = np.sqrt((x - S / 2) ** 2 + (y - S * .47) ** 2) / (S * .5)
    glow = np.zeros((S, S, 4), np.uint8)
    glow[..., 0], glow[..., 1], glow[..., 2] = 247, 214, 140
    glow[..., 3] = (np.clip(1 - d, 0, 1) ** 2.2 * 150).astype(np.uint8)
    ic.alpha_composite(Image.fromarray(glow))
    dr = ImageDraw.Draw(ic)
    cx, cy = S // 2, int(S * .47)
    # the cross strike: tapered golden beams
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        for w, a in ((34, 60), (18, 140), (8, 255)):
            dr.line([(cx, cy), (cx + dx * S * .44, cy + dy * S * .44)], fill=(247, 226, 168, a), width=w)
    # gem pairs at the ends of the cross
    gsz = 230
    for i, (x0, y0) in zip((0, 0, 2, 2), ((cx, 112), (cx, S - 128), (112, cy), (S - 112, cy))):
        g = Image.open(A("gems", f"gem_{i}.png")).convert("RGBA").resize((gsz, gsz), Image.LANCZOS)
        ic.alpha_composite(g, (int(x0 - gsz / 2), int(y0 - gsz / 2)))
    # the big prismatic diamond in the middle
    tmp = os.path.join(ROOT, "store", ".diamond.png")
    svg_to_png(prism_diamond_svg(560), tmp, 560)
    dia = Image.open(tmp).convert("RGBA"); os.remove(tmp)
    sh = Image.new("RGBA", dia.size, (0, 0, 0, 0)); sh.putalpha(dia.getchannel("A").point(lambda a: a * .55))
    sh = sh.filter(ImageFilter.GaussianBlur(18))
    ic.alpha_composite(sh, (cx - 280 + 10, cy - 280 + 26))
    ic.alpha_composite(dia, (cx - 280, cy - 280))
    # sparkles
    sp = Image.open(A("fx", "sparkle.png")).convert("RGBA")
    for (sx, sy, ss) in ((cx + 210, cy - 205, 120), (cx - 250, cy + 150, 80), (cx + 150, cy + 210, 64), (cx - 190, cy - 230, 56)):
        ic.alpha_composite(sp.resize((ss, ss), Image.LANCZOS), (sx - ss // 2, sy - ss // 2))
    out = ic.convert("RGB").resize((512, 512), Image.LANCZOS)
    out.save(STORE("icon_512.png"))
    out.resize((256, 256), Image.LANCZOS).save(os.path.join(ROOT, "icon.png"))


def make_branding():
    """App icon, Yandex store icon (512) and cover (800x470)."""
    os.makedirs(STORE(), exist_ok=True)
    gem = lambda i, s: Image.open(A("gems", f"gem_{i}.png")).convert("RGBA").resize((s, s), Image.LANCZOS)
    velvet = Image.open(A("ui", "velvet.png")).convert("RGBA")
    vign = Image.open(A("ui", "vignette.png"))

    def ground(w, h):
        g = Image.new("RGBA", (w, h))
        for yy in range(0, h, 256):
            for xx in range(0, w, 256):
                g.paste(velvet, (xx, yy))
        g.alpha_composite(vign.resize((w, h)))
        return g

    def beams(d, cx, cy, L, w):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            d.line([(cx, cy), (cx + dx * L, cy + dy * L)], fill=(247, 226, 168, 230), width=w)

    make_icon(ground)

    # cover 800x470
    w, h = 800, 470
    cv = ground(w, h)
    d = ImageDraw.Draw(cv)
    rnd = random.Random(5)
    for gx in range(9):
        for gy in range(5):
            if rnd.random() < .55:
                g = gem(rnd.randrange(10), 64)
                g.putalpha(g.getchannel("A").point(lambda a: a * .45))
                cv.alpha_composite(g, (12 + gx * 88, 18 + gy * 92))
    cv.alpha_composite(Image.new("RGBA", (w, 210), (10, 19, 21, 200)), (0, 130))
    base = cv
    # one cover per catalogue language: the title differs between them
    for lang, title, sub in (
        ("ru", "Алмазная братва", "Выбивай пары камней крестом на время"),
        ("en", "Bizarre Gems", "Knock out gem pairs with a cross strike"),
        ("tr", "Bizarre Gems", "Taş çiftlerini çapraz vuruşla kır"),
    ):
        cv = base.copy()
        d = ImageDraw.Draw(cv)
        size = 74
        while True:
            tf = font("RussoOne-Regular.ttf", size)
            tw = d.textlength(title, font=tf)
            if tw <= w - 70: break
            size -= 2
        d.text(((w - tw) / 2 + 3, 158 + 4), title, font=tf, fill=(0, 0, 0, 160))
        d.text(((w - tw) / 2, 158), title, font=tf, fill=(232, 196, 108, 255))
        sf = font("Manrope-Variable.ttf", 28)
        sf.set_variation_by_axes([650])
        d.text(((w - d.textlength(sub, font=sf)) / 2, 262), sub, font=sf, fill=(241, 232, 212, 255))
        cv.convert("RGB").save(STORE(f"cover_800x470_{lang}.png"))


def main():
    for d in ("gems", "tiles", "ui", "fx", "audio"):
        os.makedirs(A(d), exist_ok=True)
    for i, (name, base, cut) in enumerate(GEMS):
        svg_to_png(gem_svg(name, base, cut, 128), A("gems", f"gem_{i}.png"), 128)
    make_icons()
    make_textures()
    make_tiles()
    make_packs()
    make_specials()
    make_previews()
    make_sounds()
    make_branding()
    print("assets written")


if __name__ == "__main__":
    main()
