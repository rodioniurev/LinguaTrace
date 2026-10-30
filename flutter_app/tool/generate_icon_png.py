"""Generate a 1024x1024 PNG app icon for LinguaTrace.

Uses Pillow to draw a simplified version of the SVG icon:
- Dark rounded-rect background (#1e1e2e)
- Three overlapping speech-bubble rounded rectangles (blue, teal, mauve)

Usage:
    python generate_icon_png.py

Output:
    ../assets/icon/icon.png
"""

import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow is not installed. Run: pip install Pillow")
    sys.exit(1)

SIZE = 1024
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")
OUTPUT_PATH = os.path.join(OUTPUT_DIR, "icon.png")

# Colors (Catppuccin Mocha palette)
BG_COLOR = (30, 30, 46)        # #1e1e2e
BLUE = (137, 180, 250)         # #89b4fa
TEAL = (148, 226, 213)         # #94e2d5
MAUVE = (203, 166, 247)        # #cba6f7


def draw_rounded_rect(draw, xy, radius, fill):
    """Draw a rounded rectangle given (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill)


def apply_opacity(color, opacity, bg=BG_COLOR):
    """Blend color with background at given opacity."""
    return tuple(int(c * opacity + b * (1 - opacity)) for c, b in zip(color, bg))


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background rounded rect
    draw_rounded_rect(draw, (0, 0, SIZE - 1, SIZE - 1), radius=224, fill=BG_COLOR)

    # Speech bubbles (drawn with opacity blending against background)
    bubbles = [
        # (x, y, w, h, color, opacity)
        (180, 220, 340, 240, BLUE, 0.9),
        (340, 340, 340, 240, TEAL, 0.85),
        (500, 460, 340, 240, MAUVE, 0.8),
    ]

    for x, y, w, h, color, opacity in bubbles:
        blended = apply_opacity(color, opacity)
        # Main bubble body
        draw_rounded_rect(draw, (x, y, x + w, y + h), radius=32, fill=blended)
        # Small triangle tail below the bubble
        tail_x = x + 40
        draw.polygon(
            [(tail_x, y + h), (tail_x + 30, y + h), (tail_x + 15, y + h + 40)],
            fill=blended,
        )

    img.save(OUTPUT_PATH, "PNG")
    print(f"Icon saved to {os.path.abspath(OUTPUT_PATH)}")


if __name__ == "__main__":
    main()
