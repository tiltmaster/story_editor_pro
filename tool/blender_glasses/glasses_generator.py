"""Reproducible mobile AR glasses generator for Blender 4.3+.

Face space is +X subject-right, +Y up, -Z forward. The object origin is the
midpoint between the eyes and one Blender unit is one meter. Mesh construction
uses the data API; operators are reserved for export, import, render, and save.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

import bmesh
import bpy
from mathutils import Vector

ASSET_ID = "ar_glasses_classic"
ROOT_COLLECTION = "COL_AR_Glasses"
ASSET_SCENE = "SCN_AR_Glasses_Generated"
IPD_M = 0.064
TARGET_WIDTH_M = 0.14
FRAME_Z_M = -0.018


@dataclass(frozen=True)
class LodSpec:
    name: str
    rim: int
    cross: int
    bridge: int
    temple: int
    lens: int
    budget: tuple[int, int]


LODS = (
    LodSpec("LOD0", 64, 8, 15, 43, 64, (3000, 6000)),
    LodSpec("LOD1", 40, 6, 11, 31, 40, (1500, 3000)),
    LodSpec("LOD2", 24, 4, 8, 20, 24, (700, 1200)),
)


class Builder:
    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.materials: list[int] = []

    def vertex(self, value: Sequence[float] | Vector) -> int:
        self.vertices.append(tuple(float(value[i]) for i in range(3)))
        return len(self.vertices) - 1

    def face(self, values: Iterable[int], material: int = 0) -> None:
        self.faces.append(tuple(values))
        self.materials.append(material)


def add_rim(b: Builder, cx: float, spec: LodSpec) -> None:
    rx, ry, tube = 0.0295, 0.021, 0.00225
    start = len(b.vertices)
    for major in range(spec.rim):
        theta = math.tau * major / spec.rim
        ct, st = math.cos(theta), math.sin(theta)
        radial = Vector((ct / rx, st / ry, 0)).normalized()
        center = Vector((cx + rx * ct, ry * st, FRAME_Z_M))
        for minor in range(spec.cross):
            phi = math.tau * minor / spec.cross
            offset = radial * (tube * math.cos(phi))
            offset.z += tube * math.sin(phi)
            b.vertex(center + offset)
    for major in range(spec.rim):
        nm = (major + 1) % spec.rim
        for minor in range(spec.cross):
            nn = (minor + 1) % spec.cross
            b.face((
                start + major * spec.cross + minor,
                start + nm * spec.cross + minor,
                start + nm * spec.cross + nn,
                start + major * spec.cross + nn,
            ))


def _frame(tangent: Vector) -> tuple[Vector, Vector]:
    tangent.normalize()
    ref = Vector((1, 0, 0))
    a = ref - tangent * ref.dot(tangent)
    if a.length_squared < 1e-8:
        ref = Vector((0, 1, 0))
        a = ref - tangent * ref.dot(tangent)
    a.normalize()
    return a, tangent.cross(a).normalized()


def add_tube(b: Builder, points: list[Vector], radii: list[float], cross: int, material: int = 0) -> None:
    start = len(b.vertices)
    for i, point in enumerate(points):
        tangent = points[1] - points[0] if i == 0 else (
            points[-1] - points[-2] if i == len(points) - 1 else points[i + 1] - points[i - 1]
        )
        a, c = _frame(tangent)
        for section in range(cross):
            angle = math.tau * section / cross
            b.vertex(point + a * math.cos(angle) * radii[i] + c * math.sin(angle) * radii[i])
    for i in range(len(points) - 1):
        for section in range(cross):
            ns = (section + 1) % cross
            b.face((
                start + i * cross + section,
                start + (i + 1) * cross + section,
                start + (i + 1) * cross + ns,
                start + i * cross + ns,
            ), material)
    first_center, last_center = b.vertex(points[0]), b.vertex(points[-1])
    last = start + (len(points) - 1) * cross
    for section in range(cross):
        ns = (section + 1) % cross
        b.face((first_center, start + ns, start + section), material)
        b.face((last_center, last + section, last + ns), material)


def add_lens(b: Builder, cx: float, segments: int) -> None:
    rx, ry, thickness = 0.0278, 0.0193, 0.00055
    front_z, back_z = FRAME_Z_M - thickness / 2, FRAME_Z_M + thickness / 2
    front = len(b.vertices)
    for z in (front_z, back_z):
        for i in range(segments):
            theta = math.tau * i / segments
            b.vertex((cx + rx * math.cos(theta), ry * math.sin(theta), z))
    back = front + segments
    front_center, back_center = b.vertex((cx, 0, front_z)), b.vertex((cx, 0, back_z))
    for i in range(segments):
        ni = (i + 1) % segments
        b.face((front_center, front + ni, front + i), 1)
        b.face((back_center, back + i, back + ni), 1)
        b.face((front + i, back + i, back + ni, front + ni), 1)


def build_geometry(spec: LodSpec) -> Builder:
    b = Builder()
    for side in (-1.0, 1.0):
        add_rim(b, side * IPD_M / 2, spec)
        add_lens(b, side * IPD_M / 2, spec.lens)

        points, radii = [], []
        for i in range(spec.temple):
            t = i / (spec.temple - 1)
            points.append(Vector((
                side * (0.0662 + 0.00115 * math.sin(math.pi * t) - 0.0015 * t),
                0.0035 - 0.006 * t - 0.0045 * t * t,
                FRAME_Z_M + 0.002 + 0.122 * t,
            )))
            tip = max(0, (t - 0.72) / 0.28)
            radii.append(0.0017 + 0.00105 * tip * tip)
        add_tube(b, points, radii, spec.cross)

        pad_steps = max(6, spec.bridge // 2)
        points, radii = [], []
        for i in range(pad_steps):
            t = i / (pad_steps - 1)
            points.append(Vector((side * (0.0085 + 0.0012 * t), -0.006 - 0.009 * t, FRAME_Z_M + 0.001 + 0.003 * t)))
            radii.append(0.00115 + 0.00035 * t)
        add_tube(b, points, radii, spec.cross, 1)

    points, radii = [], []
    for i in range(spec.bridge):
        t = i / (spec.bridge - 1)
        points.append(Vector((-0.004 + 0.008 * t, 0.0045 + 0.0055 * math.sin(math.pi * t), FRAME_Z_M)))
        radii.append(0.00175 + 0.0002 * math.sin(math.pi * t))
    add_tube(b, points, radii, spec.cross)
    return b


def _input(shader, name: str, value) -> None:
    if shader and shader.inputs.get(name):
        shader.inputs[name].default_value = value


def make_materials() -> tuple[bpy.types.Material, bpy.types.Material]:
    frame = bpy.data.materials.get("MAT_Frame_Graphite") or bpy.data.materials.new("MAT_Frame_Graphite")
    frame.use_nodes = True
    frame.diffuse_color = (0.006, 0.008, 0.012, 1)
    shader = frame.node_tree.nodes.get("Principled BSDF")
    _input(shader, "Base Color", frame.diffuse_color)
    _input(shader, "Metallic", 0.02)
    _input(shader, "Roughness", 0.82)
    _input(shader, "Specular IOR Level", 0.12)

    lens = bpy.data.materials.get("MAT_Lens_Smoke") or bpy.data.materials.new("MAT_Lens_Smoke")
    lens.use_nodes = True
    lens.diffuse_color = (0.012, 0.045, 0.06, 0.48)
    shader = lens.node_tree.nodes.get("Principled BSDF")
    _input(shader, "Base Color", (0.004, 0.025, 0.035, 1))
    _input(shader, "Roughness", 0.46)
    _input(shader, "Specular IOR Level", 0.16)
    _input(shader, "IOR", 1.45)
    _input(shader, "Transmission Weight", 0.0)
    _input(shader, "Alpha", 0.48)
    if hasattr(lens, "surface_render_method"):
        lens.surface_render_method = "DITHERED"
    return frame, lens


def remove_collection(collection: bpy.types.Collection) -> None:
    for child in list(collection.children):
        remove_collection(child)
    for obj in list(collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(collection)


def purge_generated_orphans() -> None:
    """Remove only unused datablocks produced by this generator or GLB round-trips."""
    prefixes = ("SM_AR_Glasses_", "CAM_AR_Glasses_", "LGT_AR_Glasses_", "COL_AR_Glasses")
    for datablocks in (bpy.data.meshes, bpy.data.cameras, bpy.data.lights, bpy.data.collections):
        for block in list(datablocks):
            if block.users == 0 and block.name.startswith(prefixes):
                datablocks.remove(block)
    for material in list(bpy.data.materials):
        if material.users == 0 and (
            material.name.startswith("MAT_Frame_Graphite.")
            or material.name.startswith("MAT_Lens_Smoke.")
            or material.name.startswith("Material.")
        ):
            bpy.data.materials.remove(material)


def clean_root(replace: bool) -> bpy.types.Collection:
    existing = bpy.data.collections.get(ROOT_COLLECTION)
    if existing:
        if not replace:
            raise RuntimeError(f"{ROOT_COLLECTION} exists; confirm Replace Existing to rebuild")
        remove_collection(existing)
        purge_generated_orphans()
    root = bpy.data.collections.new(ROOT_COLLECTION)
    bpy.context.scene.collection.children.link(root)
    return root


def activate_asset_scene() -> bpy.types.Scene:
    """Use a dedicated scene in interactive Blender; preserve the artist's scene."""
    if bpy.context.window is None:
        # The CLI is documented for --factory-startup, so its current scene is disposable.
        return bpy.context.scene
    scene = bpy.data.scenes.get(ASSET_SCENE) or bpy.data.scenes.new(ASSET_SCENE)
    bpy.context.window.scene = scene
    return scene


def canonicalize_asset_file(scene: bpy.types.Scene) -> None:
    """Make a clean source .blend after the MCP caller verified a disposable scene."""
    if bpy.context.window is None:
        return
    for other in list(bpy.data.scenes):
        if other is not scene:
            bpy.data.scenes.remove(other)
    for obj in list(bpy.data.objects):
        if obj.users == 0:
            bpy.data.objects.remove(obj)
    for blocks in (bpy.data.collections, bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for block in list(blocks):
            if block.users == 0:
                blocks.remove(block)
    for material in list(bpy.data.materials):
        if material.users == 0:
            bpy.data.materials.remove(material)
    purge_generated_orphans()


def finalize_canonical_collections(root: bpy.types.Collection) -> None:
    """Remove import-created collection datablocks after round-trip validation."""
    allowed = {root}
    pending = list(root.children)
    while pending:
        collection = pending.pop()
        allowed.add(collection)
        pending.extend(collection.children)
    for collection in list(bpy.data.collections):
        if collection not in allowed:
            bpy.data.collections.remove(collection)
    for blocks in (bpy.data.meshes, bpy.data.cameras, bpy.data.lights):
        for block in list(blocks):
            if block.users == 0:
                blocks.remove(block)
    for material in list(bpy.data.materials):
        if material.users == 0:
            bpy.data.materials.remove(material)


def make_object(spec: LodSpec, collection: bpy.types.Collection, materials) -> bpy.types.Object:
    built = build_geometry(spec)
    name = f"SM_AR_Glasses_Classic_{spec.name}"
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(built.vertices, [], built.faces)
    for material in materials:
        mesh.materials.append(material)
    for polygon, material in zip(mesh.polygons, built.materials, strict=True):
        polygon.material_index = material
        polygon.use_smooth = True
    mesh.validate(clean_customdata=True)
    mesh.update(calc_edges=True)
    uv = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = ((co.x + 0.072) / 0.144, (co.y + 0.026) / 0.052)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    for key, value in {
        "asset_id": ASSET_ID, "lod": spec.name, "units": "meters",
        "origin": "midpoint_between_eyes", "forward_axis": "-Z", "up_axis": "+Y",
        "nominal_ipd_m": IPD_M, "nominal_frame_width_m": TARGET_WIDTH_M,
    }.items():
        obj[key] = value
    return obj


def bounds(obj: bpy.types.Object) -> tuple[list[float], list[float], list[float]]:
    coords = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    low = [min(p[i] for p in coords) for i in range(3)]
    high = [max(p[i] for p in coords) for i in range(3)]
    return low, high, [high[i] - low[i] for i in range(3)]


def triangle_count(obj: bpy.types.Object) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def validate_object(obj: bpy.types.Object, spec: LodSpec) -> dict:
    mesh = obj.data
    triangles = triangle_count(obj)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    non_manifold = sum(not edge.is_manifold for edge in bm.edges)
    loose = sum(not vertex.link_faces for vertex in bm.verts)
    bm.free()
    low, high, dimensions = bounds(obj)
    names = [material.name for material in mesh.materials]
    checks = {
        "triangle_budget": spec.budget[0] <= triangles <= spec.budget[1],
        "material_budget": len(names) <= 2,
        "material_naming": all(name.startswith("MAT_") for name in names),
        "object_naming": obj.name.startswith("SM_"),
        "origin_at_eye_midpoint": obj.location.length <= 1e-8,
        "rotation_applied": sum(abs(v) for v in obj.rotation_euler) <= 1e-8,
        "scale_applied": all(abs(v - 1) <= 1e-8 for v in obj.scale),
        "frame_width": 0.135 <= dimensions[0] <= 0.145,
        "manifold": non_manifold == 0,
        "no_loose_vertices": loose == 0,
        "has_uvs": bool(mesh.uv_layers),
    }
    return {
        "object": obj.name, "lod": spec.name, "triangles": triangles,
        "vertices": len(mesh.vertices), "polygons": len(mesh.polygons), "materials": names,
        "bounds_m": {"min": low, "max": high},
        "dimensions_m": {"width": dimensions[0], "height": dimensions[1], "depth": dimensions[2]},
        "non_manifold_edges": non_manifold, "loose_vertices": loose,
        "checks": checks, "passed": all(checks.values()),
    }


def write_mesh_json(obj: bpy.types.Object, path: Path, normalized: bool = False) -> dict:
    mesh = obj.data
    mesh.calc_loop_triangles()
    scale = 1 / IPD_M if normalized else 1
    low, high, _ = bounds(obj)
    data = {
        "schema_version": 1, "asset_id": ASSET_ID, "lod": obj["lod"],
        "units": "nominal_ipd" if normalized else "meters",
        "meters_per_unit": IPD_M if normalized else 1.0,
        "coordinate_system": {"right": "+X", "up": "+Y", "forward": "-Z"},
        "origin": [0, 0, 0],
        "eye_centers": [[-0.5, 0, 0], [0.5, 0, 0]] if normalized else [[-IPD_M/2, 0, 0], [IPD_M/2, 0, 0]],
        "nominal_eye_distance": 1.0 if normalized else IPD_M,
        "recommended_scale": "tracked_ipd / nominal_eye_distance",
        "bounds": {"min": [[round(v * scale, 7) for v in low][i] for i in range(3)], "max": [round(v * scale, 7) for v in high]},
        "vertices": [[round(v * scale, 7) for v in vertex.co] for vertex in mesh.vertices],
        "normals": [[round(v, 7) for v in vertex.normal] for vertex in mesh.vertices],
        "triangles": [list(triangle.vertices) for triangle in mesh.loop_triangles],
        "triangle_material_ids": [mesh.polygons[t.polygon_index].material_index for t in mesh.loop_triangles],
        "material_groups": [
            {"material_id": i, "name": material.name, "base_color_rgba": [round(v, 6) for v in material.diffuse_color]}
            for i, material in enumerate(mesh.materials)
        ],
    }
    path.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    return {"vertices": len(data["vertices"]), "triangles": len(data["triangles"]), "bytes": path.stat().st_size}


def select_only(obj: bpy.types.Object) -> None:
    # Selection may persist on objects in other scenes. Deselect globally so a
    # use_selection GLB export cannot leak artist/default-scene objects.
    for item in bpy.data.objects:
        try:
            item.select_set(False)
        except RuntimeError:
            pass
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def export_glb(obj: bpy.types.Object, path: Path) -> dict:
    select_only(obj)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
        export_yup=True,
        export_apply=True,
    )
    if not path.is_file() or not path.stat().st_size:
        raise RuntimeError(f"GLB export failed: {path}")
    return {"bytes": path.stat().st_size}


def verify_glb(path: Path) -> dict:
    before = set(bpy.data.objects)
    before_scenes = set(bpy.data.scenes)
    before_collections = set(bpy.data.collections)
    before_meshes = set(bpy.data.meshes)
    before_materials = set(bpy.data.materials)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = [obj for obj in bpy.data.objects if obj not in before and obj.type == "MESH"]
    result = {
        "mesh_objects": len(imported),
        "triangles": sum(triangle_count(obj) for obj in imported),
        "materials": sorted({mat.name for obj in imported for mat in obj.data.materials if mat}),
    }
    for obj in [obj for obj in bpy.data.objects if obj not in before]:
        bpy.data.objects.remove(obj, do_unlink=True)
    for scene in [scene for scene in bpy.data.scenes if scene not in before_scenes]:
        bpy.data.scenes.remove(scene)
    for collection in [collection for collection in bpy.data.collections if collection not in before_collections and collection.users == 0]:
        bpy.data.collections.remove(collection)
    for mesh in [mesh for mesh in bpy.data.meshes if mesh not in before_meshes and mesh.users == 0]:
        bpy.data.meshes.remove(mesh)
    for material in [material for material in bpy.data.materials if material not in before_materials and material.users == 0]:
        bpy.data.materials.remove(material)
    if not imported:
        raise RuntimeError(f"GLB round-trip returned no mesh: {path}")
    return result


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def preview_setup(root: bpy.types.Collection, lod0: bpy.types.Object) -> bpy.types.Object:
    collection = bpy.data.collections.new("COL_AR_Glasses_Preview")
    root.children.link(collection)
    camera_data = bpy.data.cameras.new("CAM_AR_Glasses_Hero")
    camera = bpy.data.objects.new("CAM_AR_Glasses_Hero", camera_data)
    camera_data.lens = 54
    collection.objects.link(camera)
    bpy.context.scene.camera = camera
    for name, location, energy, size, color in (
        ("LGT_AR_Glasses_Key", (-0.16, 0.12, -0.16), 4.0, 0.16, (0.72, 0.82, 1.0)),
        ("LGT_AR_Glasses_Rim", (0.18, 0.05, 0.08), 2.5, 0.12, (0.35, 0.55, 1.0)),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.shape, data.size, data.color = energy, "DISK", size, color
        light = bpy.data.objects.new(name, data)
        light.location = location
        look_at(light, Vector((0, 0, 0.015)))
        collection.objects.link(light)
    for child in root.children:
        child.hide_render = child.name.startswith("COL_AR_Glasses_LOD") and not child.name.endswith("LOD0")
    lod0.hide_render = False
    return camera


def render(camera: bpy.types.Object, path: Path, angle: bool) -> None:
    scene = bpy.context.scene
    # Blender 5.2 LTS renamed the public enum back to BLENDER_EEVEE.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage = 1024, 512, 100
    scene.render.filepath = str(path)
    if angle:
        yaw = math.radians(25)
        distance = 0.50
        camera.location = Vector((distance * math.sin(yaw), 0, -distance * math.cos(yaw)))
        camera.rotation_euler = (0, math.pi - yaw, 0)
    else:
        camera.location = Vector((0, 0, -0.34))
        camera.rotation_euler = (0, math.pi, 0)
    bpy.ops.render.render(write_still=True)
    if not path.is_file():
        raise RuntimeError(f"Render failed: {path}")


def manifest(reports: dict[str, dict]) -> dict:
    return {
        "schema_version": 1, "asset_id": ASSET_ID, "display_name": "Classic Graphite Glasses",
        "license": "Procedurally generated in-repository; no external asset dependencies",
        "units": "meters",
        "coordinate_system": {"right": "+X", "up": "+Y", "forward": "-Z", "face_depth": "+Z", "gltf_conversion": "+Y up"},
        "origin": {"position_m": [0, 0, 0], "definition": "midpoint_between_eyes"},
        "dimensions_m": reports["LOD0"]["dimensions_m"],
        "anchor": {
            "type": "eye_midpoint", "nominal_ipd_m": IPD_M, "nominal_frame_width_m": TARGET_WIDTH_M,
            "position_offset_m": [0, 0, 0], "rotation_offset_euler_deg": [0, 0, 0], "scale_multiplier": 1,
            "recommended_scale_formula": "tracked_ipd_m / 0.064",
            "smoothing": {"position_half_life_ms": 55, "rotation_half_life_ms": 45, "scale_half_life_ms": 80},
        },
        "materials": [
            {"id": 0, "name": "MAT_Frame_Graphite", "base_color_rgba": [0.006, 0.008, 0.012, 1]},
            {"id": 1, "name": "MAT_Lens_Smoke", "base_color_rgba": [0.012, 0.045, 0.06, 0.48]},
        ],
        "lods": [
            {"id": spec.name, "triangles": reports[spec.name]["triangles"], "vertices": reports[spec.name]["vertices"],
             "glb": f"{ASSET_ID}_{spec.name.lower()}.glb", "mesh_json": f"{ASSET_ID}_{spec.name.lower()}.mesh.json",
             "target_triangle_range": list(spec.budget)} for spec in LODS
        ],
        "runtime_mesh": {"file": "runtime_mesh.json", "source_lod": "LOD2", "units": "nominal_ipd", "meters_per_unit": IPD_M, "maximum_triangles": 1200},
        "fallback": {"transparent_front_png": f"{ASSET_ID}_front.png"},
        "source": {"blend": f"source/{ASSET_ID}.blend", "generator": "tool/blender_glasses/glasses_generator.py"},
    }


def build_asset(output_dir: str | Path, replace_existing: bool = False, canonicalize_file: bool = False) -> dict:
    output = Path(output_dir).resolve()
    source = output / "source"
    output.mkdir(parents=True, exist_ok=True)
    source.mkdir(parents=True, exist_ok=True)
    asset_scene = activate_asset_scene()
    root = clean_root(replace_existing)
    materials = make_materials()
    objects, reports = {}, {}
    for spec in LODS:
        collection = bpy.data.collections.new(f"COL_AR_Glasses_{spec.name}")
        root.children.link(collection)
        objects[spec.name] = make_object(spec, collection, materials)
        reports[spec.name] = validate_object(objects[spec.name], spec)
        if not reports[spec.name]["passed"]:
            failed = [key for key, value in reports[spec.name]["checks"].items() if not value]
            raise RuntimeError(f"{spec.name} validation failed: {', '.join(failed)}")
    if canonicalize_file:
        canonicalize_asset_file(asset_scene)
    exports = {}
    for spec in LODS:
        glb = output / f"{ASSET_ID}_{spec.name.lower()}.glb"
        mesh = output / f"{ASSET_ID}_{spec.name.lower()}.mesh.json"
        exports[spec.name] = {"glb": export_glb(objects[spec.name], glb), "mesh": write_mesh_json(objects[spec.name], mesh), "roundtrip": verify_glb(glb)}
    runtime = write_mesh_json(objects["LOD2"], output / "runtime_mesh.json", normalized=True)
    if runtime["triangles"] > 1200:
        raise RuntimeError("runtime_mesh.json exceeds 1,200 triangles")
    camera = preview_setup(root, objects["LOD0"])
    render(camera, output / f"{ASSET_ID}_front.png", False)
    render(camera, output / f"{ASSET_ID}_preview.png", True)
    (output / "manifest.json").write_text(json.dumps(manifest(reports), indent=2), encoding="utf-8")
    checks = {
        "collection_naming": all(c.name.startswith("COL_") for c in root.children),
        "maximum_two_materials": len(materials) <= 2,
        "all_lods_passed": all(report["passed"] for report in reports.values()),
        "glb_roundtrip": all(exports[name]["roundtrip"]["triangles"] == reports[name]["triangles"] for name in exports),
        "runtime_mesh_budget": runtime["triangles"] <= 1200,
    }
    validation = {"schema_version": 1, "asset_id": ASSET_ID, "status": "PASS" if all(checks.values()) else "FAIL", "passed": all(checks.values()), "blender_version": bpy.app.version_string, "objects": reports, "exports": exports, "runtime_mesh": runtime, "checks": checks}
    (output / "validation.json").write_text(json.dumps(validation, indent=2), encoding="utf-8")
    if not validation["passed"]:
        raise RuntimeError("Final validation failed; inspect validation.json")
    if canonicalize_file:
        finalize_canonical_collections(root)
    blend = source / f"{ASSET_ID}.blend"
    previous_save_versions = bpy.context.preferences.filepaths.save_version
    try:
        # Generated deliverables are reproducible; do not leave .blend1 backups.
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(blend), check_existing=False)
    finally:
        bpy.context.preferences.filepaths.save_version = previous_save_versions
    return {"status": "PASS", "asset_id": ASSET_ID, "output_dir": str(output), "blend": str(blend), "lods": reports, "runtime_mesh": runtime}
