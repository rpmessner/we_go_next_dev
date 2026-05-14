#!/usr/bin/env python3
"""Stitch MDT dungeon map tiles (10 rows x 15 cols of 128x128 PNGs) into full images."""

import os
import json
from PIL import Image

MDT_TEXTURES = "/mnt/e/World of Warcraft/_retail_/Interface/AddOns/MythicDungeonTools/Midnight/Textures"
OUTPUT_DIR = "/home/rpmessner/dev/games/wow-addons/we_go_next/we_go_next_dev/we_go_next/priv/static/images/maps"

TILE_W = 128
TILE_H = 128
COLS = 15
ROWS = 10
FULL_W = COLS * TILE_W  # 1920
FULL_H = ROWS * TILE_H  # 1280

DUNGEONS = {
    "AlgetharAcademy": "algethar_academy",
    "MagistersTerrace": "magisters_terrace",
    "MaisaraCaverns": "maisara_caverns",
    "NexusPointXenas": "nexus_point_xenas",
    "PitOfSaron": "pit_of_saron",
    "SeatOfTheTriumvirate": "seat_of_the_triumvirate",
    "Skyreach": "skyreach",
    "WindrunnerSpire": "windrunner_spire",
}

def stitch_floor(texture_dir, floor_idx):
    """Stitch a single floor's tiles into one image."""
    img = Image.new("RGBA", (FULL_W, FULL_H))

    for row in range(ROWS):
        for col in range(COLS):
            tile_num = row * COLS + col + 1
            tile_path = os.path.join(texture_dir, f"{floor_idx}_{tile_num}.png")
            if os.path.exists(tile_path):
                tile = Image.open(tile_path).convert("RGBA")
                img.paste(tile, (col * TILE_W, row * TILE_H))

    return img

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for mdt_name, slug in DUNGEONS.items():
        texture_dir = os.path.join(MDT_TEXTURES, mdt_name)
        if not os.path.exists(texture_dir):
            print(f"  SKIP {mdt_name}: texture dir not found")
            continue

        # Find all floors (look for N_1.png patterns)
        floors = set()
        for fname in os.listdir(texture_dir):
            if fname.endswith(".png") and "_" in fname:
                floor_str = fname.split("_")[0]
                try:
                    floors.add(int(floor_str))
                except ValueError:
                    pass

        for floor_idx in sorted(floors):
            img = stitch_floor(texture_dir, floor_idx)

            # Save full-res PNG
            out_path = os.path.join(OUTPUT_DIR, f"{slug}_floor{floor_idx}.png")
            img.save(out_path, "PNG", optimize=True)
            size_kb = os.path.getsize(out_path) // 1024
            print(f"  {slug}_floor{floor_idx}.png: {FULL_W}x{FULL_H}, {size_kb}KB")

            # Also save a half-res version for faster web loading
            half = img.resize((FULL_W // 2, FULL_H // 2), Image.LANCZOS)
            half_path = os.path.join(OUTPUT_DIR, f"{slug}_floor{floor_idx}_half.png")
            half.save(half_path, "PNG", optimize=True)

    print(f"\nMaps saved to {OUTPUT_DIR}")

if __name__ == "__main__":
    main()
