"""Generates a good and a bad store folder for check_store_assets.py tests.
Usage: python3 make_assets.py <out-dir>"""
import os
import random
import sys

from PIL import Image, ImageDraw

out = sys.argv[1]
random.seed(7)


def scene(w, h, sky, ground, accent, busy_bottom=False):
    img = Image.new("RGB", (w, h), sky)
    d = ImageDraw.Draw(img)
    d.rectangle([0, int(h * 0.55), w, h], fill=ground)
    d.ellipse([int(w * 0.3), int(h * 0.15), int(w * 0.6), int(h * 0.65)], fill=accent)
    d.rectangle([int(w * 0.65), int(h * 0.3), int(w * 0.8), int(h * 0.6)], fill=(250, 250, 250))
    if busy_bottom:
        for x in range(0, w, 12):
            d.line([x, int(h * 0.87), x + 6, h], fill=(255, 255, 255), width=3)
            d.line([x, h, x + 6, int(h * 0.87)], fill=(0, 0, 0), width=3)
    return img


good = os.path.join(out, "good")
os.makedirs(os.path.join(good, "thumbnails"), exist_ok=True)
icon = Image.new("RGB", (512, 512), (255, 196, 0))
d = ImageDraw.Draw(icon)
d.ellipse([96, 96, 416, 416], fill=(40, 20, 90))
d.rectangle([200, 180, 312, 400], fill=(255, 255, 255))
icon.save(os.path.join(good, "icon.png"))
scene(1920, 1080, (120, 190, 255), (70, 160, 70), (230, 60, 60)).save(os.path.join(good, "thumbnails", "1-truck.jpg"), quality=90)
scene(1920, 1080, (30, 20, 60), (60, 40, 30), (80, 230, 120)).convert("RGB").transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(good, "thumbnails", "2-night.jpg"), quality=90)
open(os.path.join(good, "title.txt"), "w").write("Undead Eats\n")
open(os.path.join(good, "description.txt"), "w").write(
    "Undead Eats is a co-op food truck survival game: cook burgers by day, defend your truck from zombies by night. "
    "How many nights can your crew survive?\n\n"
    "- Cook, serve and upgrade with up to 4 friends\n- Build turrets and fight 10 waves of zombies\n- New recipes every update\n\n"
    "Play on Desktop, Mobile and Tablet!"
)

bad = os.path.join(out, "bad")
os.makedirs(os.path.join(bad, "thumbnails"), exist_ok=True)
Image.new("RGB", (300, 200), (128, 128, 128)).save(os.path.join(bad, "icon.png"))
noise = Image.frombytes("RGB", (1920, 1080), bytes(random.getrandbits(8) for _ in range(1920 * 1080 * 3)))
noise.save(os.path.join(bad, "thumbnails", "1-noise.png"))  # > 3 MB
scene(1000, 1000, (20, 20, 30), (200, 200, 40), (40, 90, 230)).transpose(Image.FLIP_TOP_BOTTOM).save(os.path.join(bad, "thumbnails", "2-square.jpg"))
scene(1920, 1080, (240, 220, 160), (150, 100, 40), (90, 40, 20), busy_bottom=True).transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(bad, "thumbnails", "3-busy.jpg"), quality=90)
scene(1920, 1080, (120, 190, 255), (70, 160, 70), (230, 60, 60)).save(os.path.join(bad, "thumbnails", "4-same.jpg"), quality=90)
scene(1920, 1080, (120, 190, 255), (70, 160, 70), (231, 61, 61)).save(os.path.join(bad, "thumbnails", "5-same-again.jpg"), quality=85)
open(os.path.join(bad, "thumbnails", "6-clip.webp"), "wb").write(b"RIFF")
open(os.path.join(bad, "title.txt"), "w").write("\U0001F525\U0001F525\U0001F525 FREE ROBUX OBBY OBBY OBBY \U0001F525\n")
open(os.path.join(bad, "description.txt"), "w").write(
    "The best game ever!!! " + "Lots of fun. " * 80 + "\nControls: WASD to move, press E to interact. #obby #fun #robux"
)
print("ok")
