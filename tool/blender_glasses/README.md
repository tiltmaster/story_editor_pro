# Niero AR Glasses Builder

Procedurally creates a mobile, face-anchored glasses asset without external models, textures, or paid APIs.

- Scale: 1 Blender unit = 1 meter.
- Origin: midpoint between tracked eyes.
- Axes: `+X` subject-right, `+Y` up, `-Z` subject-forward/camera-facing.
- Calibration: 0.064 m nominal IPD and approximately 0.14 m frame width.
- Budgets: LOD0 3,000–6,000 triangles; LOD1 1,500–3,000; Canvas LOD2 700–1,200; two materials maximum.
- Safety: rebuilding never replaces `COL_AR_Glasses` unless explicitly confirmed.

Headless build:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup --python .\tool\blender_glasses\build_glasses.py -- --output .\assets\ar\glasses
```

Live MCP build with the official Blender add-on on `localhost:9876`:

```powershell
python .\tool\blender_glasses\socket_client.py .\tool\blender_glasses\mcp_build.py
```

Contract test:

```powershell
python .\tool\blender_glasses\test_manifest.py .\assets\ar\glasses
```

`runtime_mesh.json` uses Canvas-specific LOD2 and is normalized to eye centers at X -0.5/+0.5. Scale by tracked IPD. `validation.json` records topology, transforms, materials, dimensions, budgets, and GLB round-trip results.
