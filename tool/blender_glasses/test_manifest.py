"""Pure-Python contract test for Blender-generated artifacts."""

import json
import sys
from pathlib import Path


def validate(root: Path) -> list[str]:
    errors = []
    required = {
        "manifest.json", "validation.json", "runtime_mesh.json",
        "ar_glasses_classic_lod0.glb", "ar_glasses_classic_lod1.glb",
        "ar_glasses_classic_lod2.glb",
        "ar_glasses_classic_lod0.mesh.json", "ar_glasses_classic_lod1.mesh.json",
        "ar_glasses_classic_lod2.mesh.json",
        "ar_glasses_classic_front.png", "ar_glasses_classic_preview.png",
        "source/ar_glasses_classic.blend",
    }
    missing = sorted(name for name in required if not (root / name).is_file())
    if missing:
        return ["missing: " + ", ".join(missing)]
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    validation = json.loads((root / "validation.json").read_text(encoding="utf-8"))
    runtime = json.loads((root / "runtime_mesh.json").read_text(encoding="utf-8"))
    width = manifest.get("dimensions_m", {}).get("width", 0)
    if manifest.get("schema_version") != 1: errors.append("manifest schema")
    if manifest.get("coordinate_system", {}).get("forward") != "-Z": errors.append("forward axis")
    if not 0.135 <= width <= 0.145: errors.append(f"frame width {width}")
    if validation.get("status") != "PASS" or not validation.get("passed"): errors.append("Blender validation")
    if len(manifest.get("materials", [])) > 2: errors.append("material count")
    if len(runtime.get("triangles", [])) > 1200: errors.append("runtime triangle budget")
    if runtime.get("units") != "nominal_ipd" or runtime.get("nominal_eye_distance") != 1.0: errors.append("runtime normalization")
    if len(runtime.get("vertices", [])) != len(runtime.get("normals", [])): errors.append("normal count")
    if len(runtime.get("triangles", [])) != len(runtime.get("triangle_material_ids", [])): errors.append("material id count")
    for lod in manifest.get("lods", []):
        if not lod["target_triangle_range"][0] <= lod["triangles"] <= lod["target_triangle_range"][1]: errors.append(lod["id"] + " budget")
    return errors


if __name__ == "__main__":
    failures = validate(Path(sys.argv[1] if len(sys.argv) > 1 else "assets/ar/glasses").resolve())
    if failures:
        print("FAIL: " + "; ".join(failures))
        raise SystemExit(1)
    print("PASS: files, manifest, budgets, axes, and runtime mesh contract")
