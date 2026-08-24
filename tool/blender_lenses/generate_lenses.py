"""Generate two original, mobile-ready face-anchored eyewear assets."""

from __future__ import annotations

import json
import math
import tempfile
from dataclasses import dataclass
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

REPOSITORY = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = REPOSITORY / "assets" / "ar"
QA_ROOT = Path(tempfile.gettempdir()) / "story_editor_pro_ar_lens_qa"
IPD_M = 0.064
FRAME_Z_M = -0.018


@dataclass(frozen=True)
class Variant:
    slug: str
    asset_id: str
    display_name: str
    object_name: str
    frame_material: str
    lens_material: str
    frame_color: tuple[float, float, float, float]
    lens_color: tuple[float, float, float, float]


VARIANTS = (
    Variant(
        "glasses_aviator_gold", "ar_glasses_aviator_gold", "Aviator Gold Glasses",
        "SM_AR_Glasses_AviatorGold_LOD1", "MAT_Frame_Gold", "MAT_Lens_AmberSmoke",
        (0.55, 0.28, 0.045, 1.0), (0.18, 0.075, 0.018, 0.43),
    ),
    Variant(
        "glasses_visor_cyan", "ar_glasses_visor_cyan", "Cyan Shield Visor",
        "SM_AR_Glasses_VisorCyan_LOD1", "MAT_Frame_Titanium", "MAT_Lens_CyanSmoke",
        (0.075, 0.09, 0.115, 1.0), (0.015, 0.20, 0.28, 0.38),
    ),
)


class MeshBuilder:
    def __init__(self) -> None:
        self.vertices: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.materials: list[int] = []

    def vertex(self, value) -> int:
        self.vertices.append(tuple(float(value[index]) for index in range(3)))
        return len(self.vertices) - 1

    def face(self, indices: tuple[int, ...], material: int = 0) -> None:
        self.faces.append(indices)
        self.materials.append(material)


def ellipse_outline(cx: float, rx: float, ry: float, segments: int, drop: float = 0.0):
    points = []
    for index in range(segments):
        angle = math.tau * index / segments
        sine = math.sin(angle)
        points.append((cx + rx * math.cos(angle), ry * sine - drop * max(0.0, -sine) ** 2))
    return points


def shield_outline(rx: float, ry: float, segments: int):
    points = []
    for index in range(segments):
        angle = math.tau * index / segments
        sine = math.sin(angle)
        x = rx * math.cos(angle) * (1.0 - 0.08 * max(0.0, -sine))
        y = ry * sine - 0.0025 * max(0.0, -sine) ** 2
        points.append((x, y))
    return points


def add_ring(builder: MeshBuilder, outer, inner, z: float, depth: float, material: int = 0) -> None:
    count = len(outer)
    if count != len(inner):
        raise ValueError("Ring outlines must have equal vertex counts")
    front_z, back_z = z - depth / 2, z + depth / 2
    outer_front = [builder.vertex((x, y, front_z)) for x, y in outer]
    inner_front = [builder.vertex((x, y, front_z)) for x, y in inner]
    outer_back = [builder.vertex((x, y, back_z)) for x, y in outer]
    inner_back = [builder.vertex((x, y, back_z)) for x, y in inner]
    for index in range(count):
        following = (index + 1) % count
        builder.face((outer_front[index], outer_front[following], inner_front[following], inner_front[index]), material)
        builder.face((outer_back[following], outer_back[index], inner_back[index], inner_back[following]), material)
        builder.face((outer_front[following], outer_front[index], outer_back[index], outer_back[following]), material)
        builder.face((inner_front[index], inner_front[following], inner_back[following], inner_back[index]), material)


def add_plate(builder: MeshBuilder, outline, z: float, depth: float, material: int = 1) -> None:
    count = len(outline)
    front_z, back_z = z - depth / 2, z + depth / 2
    front = [builder.vertex((x, y, front_z)) for x, y in outline]
    back = [builder.vertex((x, y, back_z)) for x, y in outline]
    center_x = sum(x for x, _ in outline) / count
    center_y = sum(y for _, y in outline) / count
    front_center = builder.vertex((center_x, center_y, front_z))
    back_center = builder.vertex((center_x, center_y, back_z))
    for index in range(count):
        following = (index + 1) % count
        builder.face((front_center, front[following], front[index]), material)
        builder.face((back_center, back[index], back[following]), material)
        builder.face((front[index], front[following], back[following], back[index]), material)


def tube_frame(tangent: Vector):
    tangent.normalize()
    reference = Vector((1.0, 0.0, 0.0))
    first = reference - tangent * reference.dot(tangent)
    if first.length_squared < 1e-8:
        reference = Vector((0.0, 1.0, 0.0))
        first = reference - tangent * reference.dot(tangent)
    first.normalize()
    return first, tangent.cross(first).normalized()


def add_tube(builder: MeshBuilder, points: list[Vector], radius: float, cross: int = 5) -> None:
    start = len(builder.vertices)
    for index, point in enumerate(points):
        tangent = points[1] - points[0] if index == 0 else (
            points[-1] - points[-2] if index == len(points) - 1 else points[index + 1] - points[index - 1]
        )
        first, second = tube_frame(tangent)
        for section in range(cross):
            angle = math.tau * section / cross
            builder.vertex(point + first * math.cos(angle) * radius + second * math.sin(angle) * radius)
    for index in range(len(points) - 1):
        for section in range(cross):
            following = (section + 1) % cross
            builder.face((start + index * cross + section, start + (index + 1) * cross + section,
                          start + (index + 1) * cross + following, start + index * cross + following))
    first_center, last_center = builder.vertex(points[0]), builder.vertex(points[-1])
    last = start + (len(points) - 1) * cross
    for section in range(cross):
        following = (section + 1) % cross
        builder.face((first_center, start + following, start + section))
        builder.face((last_center, last + section, last + following))


def line_points(start: Vector, end: Vector, count: int, arch_y: float = 0.0):
    points = []
    for index in range(count):
        amount = index / (count - 1)
        point = start.lerp(end, amount)
        point.y += arch_y * math.sin(math.pi * amount)
        points.append(point)
    return points


def build_aviator() -> MeshBuilder:
    builder = MeshBuilder()
    segments = 28
    for side in (-1.0, 1.0):
        cx = side * IPD_M / 2
        add_ring(builder, ellipse_outline(cx, 0.032, 0.0225, segments, 0.004),
                 ellipse_outline(cx, 0.0277, 0.0183, segments, 0.003), FRAME_Z_M, 0.0032)
        add_plate(builder, ellipse_outline(cx, 0.0270, 0.0176, segments, 0.0028), FRAME_Z_M - 0.0002, 0.00065)
        hinge_start = Vector((side * 0.0632, 0.001, FRAME_Z_M + 0.001))
        hinge_end = Vector((side * 0.0675, -0.0015, FRAME_Z_M + 0.006))
        add_tube(builder, line_points(hinge_start, hinge_end, 4), 0.0022)
        add_tube(builder, line_points(hinge_end, Vector((side * 0.0670, -0.005, 0.048)), 10, -0.002), 0.00165)
    add_tube(builder, line_points(Vector((-0.006, 0.004, FRAME_Z_M)), Vector((0.006, 0.004, FRAME_Z_M)), 8, 0.006), 0.0017)
    add_tube(builder, line_points(Vector((-0.059, 0.020, FRAME_Z_M + 0.001)), Vector((0.059, 0.020, FRAME_Z_M + 0.001)), 14, 0.002), 0.00135)
    return builder


def build_visor() -> MeshBuilder:
    builder = MeshBuilder()
    segments = 40
    add_ring(builder, shield_outline(0.069, 0.026, segments), shield_outline(0.064, 0.021, segments), FRAME_Z_M, 0.0038)
    add_plate(builder, shield_outline(0.0632, 0.0202, segments), FRAME_Z_M - 0.0002, 0.0007)
    add_tube(builder, line_points(Vector((-0.064, 0.0225, FRAME_Z_M + 0.001)), Vector((0.064, 0.0225, FRAME_Z_M + 0.001)), 14, 0.002), 0.0017)
    for side in (-1.0, 1.0):
        hinge_start = Vector((side * 0.067, 0.002, FRAME_Z_M + 0.001))
        hinge_end = Vector((side * 0.070, 0.0, FRAME_Z_M + 0.008))
        add_tube(builder, line_points(hinge_start, hinge_end, 4), 0.0024)
        add_tube(builder, line_points(hinge_end, Vector((side * 0.069, -0.005, 0.043)), 8, -0.0015), 0.0019)
    return builder


def create_material(name: str, color, lens: bool):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = color
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color[:3], 1.0)
    shader.inputs["Metallic"].default_value = 0.0 if lens else 0.72
    shader.inputs["Roughness"].default_value = 0.32 if lens else 0.28
    if shader.inputs.get("Alpha"):
        shader.inputs["Alpha"].default_value = color[3]
    if shader.inputs.get("IOR"):
        shader.inputs["IOR"].default_value = 1.45
    if lens and hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    return material


def create_object(variant: Variant, builder: MeshBuilder, collection):
    mesh = bpy.data.meshes.new(variant.object_name)
    mesh.from_pydata(builder.vertices, [], builder.faces)
    mesh.materials.append(create_material(variant.frame_material, variant.frame_color, False))
    mesh.materials.append(create_material(variant.lens_material, variant.lens_color, True))
    for polygon, material in zip(mesh.polygons, builder.materials, strict=True):
        polygon.material_index = material
        polygon.use_smooth = True
    mesh.validate(clean_customdata=True)
    mesh.update(calc_edges=True)
    uv = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = ((co.x + 0.075) / 0.15, (co.y + 0.032) / 0.064)
    obj = bpy.data.objects.new(variant.object_name, mesh)
    collection.objects.link(obj)
    for key, value in {"asset_id": variant.asset_id, "origin": "midpoint_between_eyes",
                       "nominal_ipd_m": IPD_M, "forward_axis": "-Z", "up_axis": "+Y"}.items():
        obj[key] = value
    return obj


def triangle_count(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def bounds(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    low = [min(point[axis] for point in points) for axis in range(3)]
    high = [max(point[axis] for point in points) for axis in range(3)]
    return low, high, [high[axis] - low[axis] for axis in range(3)]


def validate(obj):
    audit = bmesh.new()
    audit.from_mesh(obj.data)
    non_manifold = sum(not edge.is_manifold for edge in audit.edges)
    loose = sum(not vertex.link_faces for vertex in audit.verts)
    audit.free()
    low, high, dimensions = bounds(obj)
    checks = {
        "runtime_triangles_under_1200": triangle_count(obj) <= 1200,
        "two_materials": len(obj.data.materials) == 2,
        "object_naming": obj.name in {variant.object_name for variant in VARIANTS},
        "material_naming": all(not material.name.rsplit(".", 1)[-1].isdigit() for material in obj.data.materials),
        "identity_rotation": sum(abs(value) for value in obj.rotation_euler) <= 1e-8,
        "identity_scale": all(abs(value - 1.0) <= 1e-8 for value in obj.scale),
        "origin_at_eye_midpoint": obj.location.length <= 1e-8,
        "frame_width": 0.135 <= dimensions[0] <= 0.145,
        "manifold": non_manifold == 0,
        "no_loose_vertices": loose == 0,
        "has_uvs": bool(obj.data.uv_layers),
    }
    return {"object": obj.name, "vertices": len(obj.data.vertices), "triangles": triangle_count(obj),
            "materials": [material.name for material in obj.data.materials],
            "bounds_m": {"min": low, "max": high},
            "dimensions_m": {"width": dimensions[0], "height": dimensions[1], "depth": dimensions[2]},
            "non_manifold_edges": non_manifold, "loose_vertices": loose,
            "checks": checks, "passed": all(checks.values())}


def write_runtime(variant: Variant, obj, path: Path) -> None:
    mesh = obj.data
    mesh.calc_loop_triangles()
    low, high, _ = bounds(obj)
    scale = 1.0 / IPD_M
    payload = {
        "schema_version": 1, "asset_id": variant.asset_id, "lod": "LOD1", "units": "nominal_ipd",
        "meters_per_unit": IPD_M, "coordinate_system": {"right": "+X", "up": "+Y", "forward": "-Z"},
        "origin": [0, 0, 0], "eye_centers": [[-0.5, 0, 0], [0.5, 0, 0]], "nominal_eye_distance": 1.0,
        "recommended_scale": "tracked_ipd / nominal_eye_distance",
        "bounds": {"min": [round(v * scale, 7) for v in low], "max": [round(v * scale, 7) for v in high]},
        "vertices": [[round(v * scale, 7) for v in vertex.co] for vertex in mesh.vertices],
        "normals": [[round(v, 7) for v in vertex.normal] for vertex in mesh.vertices],
        "triangles": [list(triangle.vertices) for triangle in mesh.loop_triangles],
        "triangle_material_ids": [mesh.polygons[t.polygon_index].material_index for t in mesh.loop_triangles],
        "material_groups": [
            {"material_id": 0, "name": variant.frame_material, "base_color_rgba": list(variant.frame_color)},
            {"material_id": 1, "name": variant.lens_material, "base_color_rgba": list(variant.lens_color)},
        ],
    }
    path.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")


def export_glb(obj, path: Path):
    for candidate in bpy.context.view_layer.objects:
        candidate.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              use_active_scene=True, export_yup=True, export_apply=True)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = [candidate for candidate in bpy.data.objects if candidate not in before and candidate.type == "MESH"]
    imported_triangles = sum(triangle_count(candidate) for candidate in imported)
    for candidate in [candidate for candidate in bpy.data.objects if candidate not in before]:
        bpy.data.objects.remove(candidate, do_unlink=True)
    return {"bytes": path.stat().st_size, "roundtrip_meshes": len(imported), "roundtrip_triangles": imported_triangles}


def look_at(obj, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_preview(scene, variant: Variant) -> Path:
    QA_ROOT.mkdir(parents=True, exist_ok=True)
    camera_data = bpy.data.cameras.new(f"CAM_{variant.asset_id}_QA")
    camera_data.lens = 58
    camera = bpy.data.objects.new(camera_data.name, camera_data)
    scene.collection.objects.link(camera)
    yaw = math.radians(22.0)
    distance = 0.42
    camera.location = Vector((distance * math.sin(yaw), 0.0, -distance * math.cos(yaw)))
    camera.rotation_euler = (0.0, math.pi - yaw, 0.0)
    scene.camera = camera
    for name, location, energy, size, color in (
        ("Key", (-0.16, 0.13, -0.17), 12.0, 0.16, (1.0, 0.84, 0.66)),
        ("Rim", (0.16, 0.07, 0.10), 6.0, 0.12, (0.35, 0.65, 1.0)),
    ):
        data = bpy.data.lights.new(f"LGT_{variant.asset_id}_{name}", "AREA")
        data.energy, data.shape, data.size, data.color = energy, "DISK", size, color
        light = bpy.data.objects.new(data.name, data)
        light.location = Vector(location)
        look_at(light, Vector((0.0, 0.0, 0.005)))
        scene.collection.objects.link(light)
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage = 900, 520, 100
    path = QA_ROOT / f"{variant.slug}_qa.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return path


def write_manifest(variant: Variant, report, exported, output: Path) -> None:
    passed = report["passed"] and exported["roundtrip_triangles"] == report["triangles"]
    manifest = {
        "schema_version": 1, "asset_id": variant.asset_id, "display_name": variant.display_name,
        "license": "Original procedural geometry authored for this repository; no external models, textures, or paid dependencies",
        "units": "meters",
        "coordinate_system": {"right": "+X", "up": "+Y", "forward": "-Z", "face_depth": "+Z", "gltf_conversion": "+Y up"},
        "origin": {"position_m": [0, 0, 0], "definition": "midpoint_between_eyes"},
        "dimensions_m": report["dimensions_m"],
        "anchor": {"type": "eye_midpoint", "nominal_ipd_m": IPD_M,
                   "nominal_frame_width_m": report["dimensions_m"]["width"],
                   "position_offset_m": [0, 0, 0], "rotation_offset_euler_deg": [0, 0, 0],
                   "scale_multiplier": 1, "recommended_scale_formula": "tracked_ipd_m / 0.064",
                   "smoothing": {"position_half_life_ms": 55, "rotation_half_life_ms": 45, "scale_half_life_ms": 80}},
        "materials": [
            {"id": 0, "name": variant.frame_material, "base_color_rgba": list(variant.frame_color)},
            {"id": 1, "name": variant.lens_material, "base_color_rgba": list(variant.lens_color)},
        ],
        "lods": [{"id": "LOD1", "triangles": report["triangles"], "vertices": report["vertices"],
                  "glb": f"{variant.slug}.glb", "mesh_json": "runtime_mesh.json", "target_triangle_range": [500, 1200]}],
        "runtime_mesh": {"file": "runtime_mesh.json", "source_lod": "LOD1", "units": "nominal_ipd",
                         "meters_per_unit": IPD_M, "maximum_triangles": 1200},
        "validation": {"status": "PASS" if passed else "FAIL", "checks": report["checks"],
                       "glb_roundtrip_triangles": exported["roundtrip_triangles"]},
        "source": {"generator": "tool/blender_lenses/generate_lenses.py"},
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def main():
    original_scene = bpy.context.window.scene if bpy.context.window else bpy.context.scene
    existing_scene = bpy.data.scenes.get("SCN_AR_Lens_Variants")
    if existing_scene:
        for candidate in list(existing_scene.objects):
            bpy.data.objects.remove(candidate, do_unlink=True)
        bpy.data.scenes.remove(existing_scene)
    generated_object_prefixes = (
        "SM_AR_Glasses_AviatorGold", "SM_AR_Glasses_VisorCyan",
        "CAM_ar_glasses_", "LGT_ar_glasses_",
    )
    for candidate in list(bpy.data.objects):
        if candidate.name.startswith(generated_object_prefixes):
            bpy.data.objects.remove(candidate, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0 and mesh.name.startswith(("SM_AR_Glasses_AviatorGold", "SM_AR_Glasses_VisorCyan")):
            bpy.data.meshes.remove(mesh)
    for collection in list(bpy.data.collections):
        if collection.users == 0 and (
            collection.name.startswith("COL_AR_Lens_Variants")
            or collection.name.startswith("COL_ar_glasses_")
        ):
            bpy.data.collections.remove(collection)
    for material in list(bpy.data.materials):
        if material.users == 0 and material.name.startswith((
            "MAT_Frame_Gold", "MAT_Lens_AmberSmoke", "MAT_Frame_Titanium", "MAT_Lens_CyanSmoke"
        )):
            bpy.data.materials.remove(material)
    build_scene = bpy.data.scenes.new("SCN_AR_Lens_Variants")
    if bpy.context.window:
        bpy.context.window.scene = build_scene
    root = bpy.data.collections.new("COL_AR_Lens_Variants")
    build_scene.collection.children.link(root)
    results = {}
    for variant in VARIANTS:
        collection = bpy.data.collections.new(f"COL_{variant.asset_id}")
        root.children.link(collection)
        obj = create_object(variant, build_aviator() if variant.slug == "glasses_aviator_gold" else build_visor(), collection)
        report = validate(obj)
        if not report["passed"]:
            failed = [name for name, passed in report["checks"].items() if not passed]
            raise RuntimeError(f"{variant.asset_id} validation failed: {', '.join(failed)}")
        output = OUTPUT_ROOT / variant.slug
        output.mkdir(parents=True, exist_ok=True)
        exported = export_glb(obj, output / f"{variant.slug}.glb")
        if exported["roundtrip_triangles"] != report["triangles"]:
            raise RuntimeError(f"{variant.asset_id} GLB triangle mismatch")
        write_runtime(variant, obj, output / "runtime_mesh.json")
        write_manifest(variant, report, exported, output)
        preview = render_preview(build_scene, variant)
        obj.hide_render = True
        results[variant.asset_id] = {"report": report, "export": exported, "preview": str(preview), "output": str(output)}
    if bpy.context.window:
        bpy.context.window.scene = original_scene
    return {"status": "PASS", "blender": bpy.app.version_string, "assets": results}


if __name__ == "__main__":
    result = main()
