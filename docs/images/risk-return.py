"""Draw the README's risk-return sketch.

Run from anywhere (needs matplotlib and numpy):
    python docs/images/risk-return.py

Inputs: none; every label and position is set below. Coordinates are
pixels of the 1280x800 output, origin at the top left, so a point can be
moved by reading its position off the current PNG.

Output: docs/images/risk-return.png (next to this script), overwritten.
"""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import FancyArrowPatch

OUT = Path(__file__).with_name("risk-return.png")
W, H, DPI = 1280, 800, 200

GREEN = "#009900"
RED = "#990000"
AXIS = "#7f8c8d"
CURVE = "#95a5a6"
CIRCLE = "#ecb02a"
FONT = 11

# Points on the frontier: (x, y, label, label y offset); labels sit to the right.
FRONTIER = [
    (230, 603, "No AI", 11),
    (269, 536, "Web app copy-paste", 10),
    (373, 401, "Manual mode,\ncheck everything", 20),
    (658, 266, "Manual mode,\nkinda check everything", 11),
]

fig = plt.figure(figsize=(W / DPI, H / DPI), dpi=DPI)
ax = fig.add_axes([0, 0, 1, 1])
ax.set_xlim(0, W)
ax.set_ylim(H, 0)
ax.axis("off")

# Axes with arrowheads.
for start, end in [((179, 640), (179, 46)), ((179, 640), (1256, 640))]:
    ax.add_patch(FancyArrowPatch(start, end, arrowstyle="-|>", mutation_scale=12,
                                 color=AXIS, lw=1.2, shrinkA=0, shrinkB=0))
ax.text(120, 345, "Net return\n(research output, 12 months)", rotation=90,
        ha="center", va="center", fontsize=FONT, linespacing=1.5)
ax.text(716, 697, "Risk\n(prob. of losing more than $100k in 12 months)",
        ha="center", va="center", fontsize=FONT, linespacing=1.5)
ax.text(1195, 711, "not to scale", ha="center", va="center",
        fontsize=FONT * 0.72, style="italic", color=AXIS)

# Frontier: a concave curve through the non-YOLO points.
x = np.linspace(232, 1043, 300)
y = 640 - 31.5 * (x - 226) ** 0.4
ax.plot(x, y, ls=(0, (4, 2.5)), color=CURVE, lw=1.3, zorder=1)

for px, py, label, dy in FRONTIER:
    ax.plot(px, py, "o", ms=8, color=GREEN, zorder=3)
    ax.text(px + 28, py + dy, label, ha="left", va="center", fontsize=FONT,
            color=GREEN, linespacing=1.5)

ax.plot(994, 199, "o", ms=8, color=RED, zorder=3)
ax.text(900, 127, "YOLO mode,\nno container", ha="left", va="center",
        fontsize=FONT, color=RED, linespacing=1.5)

ax.plot(372, 267, "o", ms=10, color=RED, zorder=3)
ax.text(373, 206, "Auto mode,\nClaude default", ha="center", va="center",
        fontsize=FONT, color=RED, weight="bold", linespacing=1.5)

# "Me?" with a hand-drawn circle.
ax.plot(502, 127, "*", ms=19, color=RED, zorder=3)
ax.text(537, 134, "Me?", ha="left", va="center", fontsize=FONT, color=RED,
        weight="bold")
t = np.linspace(-0.1 * np.pi, 2.05 * np.pi, 200)
wobble = 1 + 0.05 * np.sin(2 * t + 1) + 0.02 * (t - np.pi) / np.pi
ax.plot(548 + 95 * wobble * np.cos(t), 128 + 57 * wobble * np.sin(t),
        color=CIRCLE, lw=2, solid_capstyle="round", zorder=2)

fig.savefig(OUT, dpi=DPI, facecolor="white")
print(f"wrote {OUT}")
