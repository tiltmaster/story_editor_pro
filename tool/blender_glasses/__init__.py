"""Blender add-on entry point for the Niero mobile AR glasses builder."""

import bpy
from bpy.props import BoolProperty, StringProperty

from .glasses_generator import build_asset

bl_info = {
    "name": "Niero AR Glasses Builder",
    "author": "Niero Engineering",
    "version": (1, 0, 0),
    "blender": (4, 3, 0),
    "location": "3D View > Sidebar > AR Pipeline",
    "description": "Build and validate mobile face-anchored glasses with two LODs",
    "category": "Object",
}


class NIERO_OT_build_ar_glasses(bpy.types.Operator):
    bl_idname = "niero.build_ar_glasses"
    bl_label = "Build AR Glasses"
    bl_description = "Create, validate, export, and render the procedural AR glasses asset"
    bl_options = {"REGISTER"}

    output_dir: StringProperty(name="Output Directory", subtype="DIR_PATH", default="//assets/ar/glasses")
    replace_existing: BoolProperty(
        name="Replace Existing Generated Asset",
        description="Replace only COL_AR_Glasses after explicit confirmation",
        default=False,
    )

    def invoke(self, context, event):
        return context.window_manager.invoke_props_dialog(self, width=460)

    def draw(self, context):
        self.layout.prop(self, "output_dir")
        self.layout.prop(self, "replace_existing")
        if self.replace_existing:
            self.layout.label(text="Only COL_AR_Glasses will be replaced.", icon="ERROR")

    def execute(self, context):
        try:
            report = build_asset(bpy.path.abspath(self.output_dir), self.replace_existing)
        except Exception as error:
            self.report({"ERROR"}, f"AR glasses build failed: {error}")
            return {"CANCELLED"}
        self.report({"INFO"}, f"PASS: LOD0 {report['lods']['LOD0']['triangles']} tris; LOD1 {report['lods']['LOD1']['triangles']} tris")
        return {"FINISHED"}


class NIERO_PT_ar_glasses(bpy.types.Panel):
    bl_label = "Niero AR Glasses"
    bl_idname = "NIERO_PT_ar_glasses"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "AR Pipeline"

    def draw(self, context):
        self.layout.label(text="Anchor: eye midpoint")
        self.layout.label(text="Axes: +X right, +Y up, -Z forward")
        self.layout.operator("niero.build_ar_glasses", icon="OUTLINER_OB_MESH")


CLASSES = (NIERO_OT_build_ar_glasses, NIERO_PT_ar_glasses)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)


def unregister():
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)

