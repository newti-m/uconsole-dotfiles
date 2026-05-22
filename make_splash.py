#!/usr/bin/env python3
"""Generate boot splash images for uConsole."""
from PIL import Image, ImageDraw, ImageFont
import os

BG = (18, 18, 18)
FG = (220, 220, 220)
ACCENT = (100, 180, 255)

def draw_splash(w, h):
    img = Image.new("RGB", (w, h), BG)
    draw = ImageDraw.Draw(img)

    # Try to get a decent font
    font_title = None
    font_sub = None
    for path in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    ]:
        if os.path.exists(path):
            font_title = ImageFont.truetype(path, 52)
            font_sub = ImageFont.truetype(path, 22)
            break

    cx, cy = w // 2, h // 2

    # Top accent bar
    draw.rectangle([cx - 120, cy - 110, cx + 120, cy - 107], fill=ACCENT)

    # Title
    title = "uConsole"
    if font_title:
        bbox = draw.textbbox((0, 0), title, font=font_title)
        tw = bbox[2] - bbox[0]
        draw.text((cx - tw // 2, cy - 90), title, fill=FG, font=font_title)
    else:
        draw.text((cx - 60, cy - 90), title, fill=FG)

    # Subtitle
    sub = "ClockworkPi"
    if font_sub:
        bbox = draw.textbbox((0, 0), sub, font=font_sub)
        sw = bbox[2] - bbox[0]
        draw.text((cx - sw // 2, cy - 20), sub, fill=ACCENT, font=font_sub)
    else:
        draw.text((cx - 40, cy - 20), sub, fill=ACCENT)

    # Bottom accent bar
    draw.rectangle([cx - 120, cy + 20, cx + 120, cy + 23], fill=ACCENT)

    return img

# Portrait image (what we want to see on screen)
portrait = draw_splash(480, 800)
portrait.save("/home/ntm/splash_portrait.png")
print("Saved splash_portrait.png (480x800)")

# GPU firmware splash: framebuffer is landscape 800x480,
# display hardware rotates 90° CW → rotate our portrait 90° CCW
gpu_splash = portrait.rotate(90, expand=True)
gpu_splash.save("/home/ntm/splash_gpu.png")
print("Saved splash_gpu.png (800x480, pre-rotated for GPU firmware)")

# Plymouth sees the DRM-rotated framebuffer (480x800 portrait), so use portrait directly
portrait.save("/home/ntm/splash_plymouth_bg.png")
print("Saved splash_plymouth_bg.png for Plymouth theme (portrait, DRM handles rotation)")
