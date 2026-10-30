#!/usr/bin/env python3
"""Downloads the CC0 assets the game uses (Poly Haven, ambientCG). Safe to re-run."""
import io, json, os, sys, urllib.request, zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UA = {"User-Agent": "horyzont-dev"}

PH_TEX = {
    "4k": ["rock_face_03", "coast_land_rocks_01", "sparse_grass", "forest_floor", "gravel_road",
           "coast_sand_01", "asphalt_02", "dirt"],
    "2k": ["pine_bark", "bark_brown_02", "jolcham_oak_bark_01", "lichen_rock"],
}
PH_MODELS = ["rock_moss_set_01", "rock_moss_set_02", "rock_07", "rock_09", "boulder_01", "stone_01",
             "rock_face_01", "rock_face_02", "namaqualand_boulder_02", "fern_02", "shrub_02", "shrub_03",
             "shrub_04", "shrub_sorrel_01", "weed_plant_02", "nettle_plant", "dandelion_01",
             "tree_stump_01", "dead_tree_trunk", "dry_branches_medium_01"]
ACG = ["LeafSet016", "LeafSet024", "LeafSet022", "LeafSet020", "LeafSet014", "Foliage001", "Foliage002",
       "Foliage003", "Foliage004", "Foliage006", "Foliage007", "Foliage008"]


def fetch(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()


def save(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = fetch(url)
    with open(path + ".part", "wb") as f:
        f.write(data)
    os.rename(path + ".part", path)
    print("ok", os.path.relpath(path, ROOT), len(data) // 1024, "kB", flush=True)


def poly_tex(asset, res):
    files = json.loads(fetch("https://api.polyhaven.com/files/" + asset))
    for key, short in (("Diffuse", "diffuse"), ("nor_gl", "nor_gl"), ("arm", "arm")):
        entry = files[key][res]["jpg"]
        save(entry["url"], f"{ROOT}/assets/textures/{asset}/{asset}_{short}_{res}.jpg")


def poly_model(asset):
    files = json.loads(fetch("https://api.polyhaven.com/files/" + asset))
    g = files["gltf"]["2k"]["gltf"]
    out = f"{ROOT}/assets/models/{asset}"
    save(g["url"], f"{out}/{asset}.gltf")
    for rel, entry in g.get("include", {}).items():
        rel = os.path.normpath(rel)
        if rel.startswith("..") or os.path.isabs(rel):
            continue
        save(entry["url"], f"{out}/{rel}")


def ambient(asset):
    out = f"{ROOT}/assets/foliage/src/{asset}"
    if os.path.isdir(out) and os.listdir(out):
        return
    data = fetch(f"https://ambientcg.com/get?file={asset}_2K-JPG.zip")
    os.makedirs(out, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for name in z.namelist():
            base = os.path.basename(name)
            if base.lower().endswith(".jpg"):
                with open(f"{out}/{base}", "wb") as f:
                    f.write(z.read(name))
    print("ok", asset, len(data) // 1024, "kB", flush=True)


def guarded(fn, *args):
    try:
        fn(*args)
    except Exception as e:
        print("FAILED", fn.__name__, args, e, flush=True)


if __name__ == "__main__":
    for asset in ACG:
        guarded(ambient, asset)
    for res, items in PH_TEX.items():
        for asset in items:
            guarded(poly_tex, asset, res)
    for asset in PH_MODELS:
        guarded(poly_model, asset)
    print("done", flush=True)
