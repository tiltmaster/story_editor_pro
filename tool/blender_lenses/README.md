# Mobile AR lens generator

This tool procedurally authors the additional eyewear assets. It does not
download or incorporate external geometry, textures, or paid assets.

- One Blender unit is one meter.
- The origin is the tracked midpoint between the eyes.
- `+X` is subject-right, `+Y` is up, and `-Z` faces the camera.
- Object transforms are identity; pose rotation belongs to the native tracker.
- Runtime meshes are normalized to a nominal 0.064 m interpupillary distance.
- Each asset has two materials and at most 1,200 triangles.

Run `generate_lenses.py` inside the Blender MCP session on localhost port 9876.
It writes `assets/ar/glasses_aviator_gold` and
`assets/ar/glasses_visor_cyan`. QA renders are temporary and are not shipped.
