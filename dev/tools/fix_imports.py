#!/usr/bin/env python3
"""Makes every texture under assets/ import with mipmaps and VRAM compression."""
import glob, os, re
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
n = 0
for path in glob.glob(ROOT + "/assets/**/*.import", recursive=True):
    if "/src/" in path or path.endswith((".gltf.import", ".bin.import")):
        continue
    s = open(path).read()
    if 'importer="texture"' not in s:
        continue
    t = s
    t = re.sub(r"compress/mode=\d", "compress/mode=2", t)
    t = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", t)
    t = re.sub(r"detect_3d/compress_to=\d", "detect_3d/compress_to=0", t)
    low = os.path.basename(path).lower()
    if "nor_gl" in low or "_normal." in low:
        t = re.sub(r"compress/normal_map=\d", "compress/normal_map=1" if "_normal.png" not in low else "compress/normal_map=2", t)
    if t != s:
        open(path, "w").write(t)
        n += 1
print("patched", n)
