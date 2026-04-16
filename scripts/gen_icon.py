#!/usr/bin/env python3
"""Generate ClaudeMeter app icon — bold gauge with Claude's coral palette."""
import math, os, subprocess
from PIL import Image, ImageDraw

SIZE = 1024
CENTER = SIZE // 2

# Claude's palette
BG_TOP = (30, 28, 26)
BG_BOT = (48, 44, 40)
CORAL = (217, 119, 87)
CORAL_BRIGHT = (240, 140, 100)
GAUGE_BG = (65, 60, 54)
WHITE = (245, 242, 238)
WHITE_DIM = (140, 132, 122)


def rounded_rect_mask(size, radius):
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size[0]-1, size[1]-1], radius=radius, fill=255)
    return mask


def draw_smooth_arc(img, cx, cy, radius, width, start_deg, end_deg, color):
    """Draw a smooth thick arc by stamping circles along the path."""
    r = width / 2
    arc_span = end_deg - start_deg
    # One circle per ~0.5 degree for smoothness
    steps = max(int(abs(arc_span) * 2), 1)
    draw = ImageDraw.Draw(img)
    for i in range(steps + 1):
        t = i / steps
        angle = math.radians(start_deg + arc_span * t)
        px = cx + radius * math.cos(angle)
        py = cy + radius * math.sin(angle)
        draw.ellipse([px - r, py - r, px + r, py + r], fill=color)


def make_icon(size=SIZE):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Rounded square background with gradient
    corner = int(size * 0.22)
    for y in range(size):
        t = y / size
        r = int(BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t)
        g = int(BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t)
        b = int(BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t)
        draw.line([(0, y), (size - 1, y)], fill=(r, g, b, 255))

    mask = rounded_rect_mask((size, size), corner)
    img.putalpha(mask)

    # --- Big bold gauge ---
    cx, cy = CENTER, int(CENTER * 1.12)
    gauge_r = int(size * 0.38)       # much bigger radius
    track_w = int(size * 0.11)       # much thicker track
    start_angle = 215
    end_angle = 325
    fill_pct = 0.65

    # Background track (smooth circles along arc)
    draw_smooth_arc(img, cx, cy, gauge_r, track_w, start_angle, end_angle, GAUGE_BG)

    # Filled coral arc with gradient (smooth circles)
    fill_end = start_angle + (end_angle - start_angle) * fill_pct
    grad_steps = 200
    half_w = track_w / 2
    for i in range(grad_steps + 1):
        t = i / grad_steps
        angle_deg = start_angle + (fill_end - start_angle) * t
        angle_rad = math.radians(angle_deg)
        px = cx + gauge_r * math.cos(angle_rad)
        py = cy + gauge_r * math.sin(angle_rad)
        cr = int(CORAL[0] + (CORAL_BRIGHT[0] - CORAL[0]) * t)
        cg = int(CORAL[1] + (CORAL_BRIGHT[1] - CORAL[1]) * t)
        cb = int(CORAL[2] + (CORAL_BRIGHT[2] - CORAL[2]) * t)
        draw.ellipse([px - half_w, py - half_w, px + half_w, py + half_w],
                     fill=(cr, cg, cb, 255))

    # --- Needle ---
    needle_angle_deg = start_angle + (end_angle - start_angle) * fill_pct
    needle_angle_rad = math.radians(needle_angle_deg)
    needle_len = int(gauge_r * 0.62)
    tip_x = cx + needle_len * math.cos(needle_angle_rad)
    tip_y = cy + needle_len * math.sin(needle_angle_rad)

    # Tapered needle
    for t_step in range(30):
        t = t_step / 30
        px = cx + (tip_x - cx) * t
        py = cy + (tip_y - cy) * t
        w = max(1, int(8 * (1 - t * 0.85) * (size / 1024)))
        draw.ellipse([px - w, py - w, px + w, py + w], fill=WHITE)

    # Center hub
    hub_r = int(size * 0.035)
    draw.ellipse([cx - hub_r, cy - hub_r, cx + hub_r, cy + hub_r], fill=WHITE)
    inner_hub = int(hub_r * 0.5)
    draw.ellipse([cx - inner_hub, cy - inner_hub, cx + inner_hub, cy + inner_hub],
                 fill=CORAL)

    # --- Tick marks (fewer, bolder) ---
    for i in range(4):
        t = i / 3
        angle_deg = start_angle + (end_angle - start_angle) * t
        angle_rad = math.radians(angle_deg)
        inner_r = gauge_r + int(track_w * 0.58)
        outer_r = gauge_r + int(track_w * 0.85)
        x1 = cx + inner_r * math.cos(angle_rad)
        y1 = cy + inner_r * math.sin(angle_rad)
        x2 = cx + outer_r * math.cos(angle_rad)
        y2 = cy + outer_r * math.sin(angle_rad)
        draw.line([(x1, y1), (x2, y2)], fill=WHITE_DIM, width=int(3 * size / 1024))

    return img


def save_iconset(img, out_dir):
    iconset = os.path.join(out_dir, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)

    filenames = {
        16:   "icon_16x16.png",
        32:   "icon_16x16@2x.png",
        64:   "icon_32x32@2x.png",
        128:  "icon_128x128.png",
        256:  "icon_128x128@2x.png",
        512:  "icon_256x256@2x.png",
        1024: "icon_512x512@2x.png",
    }
    filenames_extra = {
        32:  "icon_32x32.png",
        256: "icon_256x256.png",
        512: "icon_512x512.png",
    }

    for s, name in {**filenames, **filenames_extra}.items():
        resized = img.resize((s, s), Image.LANCZOS)
        resized.save(os.path.join(iconset, name))

    icns_path = os.path.join(out_dir, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns_path], check=True)
    return icns_path


if __name__ == "__main__":
    out_dir = os.path.join(os.path.dirname(__file__), "..", "Sources", "ClaudeMeter", "Resources")
    os.makedirs(out_dir, exist_ok=True)

    img = make_icon()
    icns_path = save_iconset(img, out_dir)
    print(f"Created: {icns_path}")

    preview = os.path.join(out_dir, "AppIcon_preview.png")
    img.resize((512, 512), Image.LANCZOS).save(preview)
    print(f"Preview: {preview}")
