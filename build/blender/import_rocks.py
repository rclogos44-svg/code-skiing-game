"""Turns downloaded Poly Haven rock scans (CC0, glTF) into small game meshes: joined, decimated to
~1500 triangles, centred on their bounding box and scaled so the widest horizontal half-extent is
1.25 (the size Vegetation's procedural rocks were, so rocks.bin scales still fit), base 0.45 below
the origin.  The game keeps its
own snowy triplanar rock shader, so only the shape is used (no UVs or textures).

usage: tools/blender/blender -b --factory-startup --python build/blender/import_rocks.py -- \
           OUT_DIR SCAN.gltf [SCAN.gltf ...]
writes OUT_DIR/rock_<i>.obj
"""
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out_dir, scans = args[0], args[1:]
os.makedirs(out_dir, exist_ok=True)
for i, path in enumerate(scans):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(path))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.view_layer.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # no UVs (the shader is triplanar): UV seams would also hold the decimation back
    while obj.data.uv_layers:
        obj.data.uv_layers.remove(obj.data.uv_layers[0])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.object.mode_set(mode="OBJECT")
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    dec = obj.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, 1500.0 / max(tris, 1))
    obj.modifiers.new("tri", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier="dec")
    bpy.ops.object.modifier_apply(modifier="tri")
    vs = [v.co for v in obj.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c = (lo + hi) * 0.5
    half = max(hi.x - lo.x, hi.y - lo.y) * 0.5          # Blender Z is up
    k = 1.25 / half
    # the game sinks every rock by 0.35 of its scale: put the base 0.45 under the origin, so only
    # its foot is buried and the boulder shows whole
    base = Vector((c.x, c.y, lo.z + 0.45 / k))
    for v in obj.data.vertices:
        v.co = (v.co - base) * k
    obj.data.update()
    for p in obj.data.polygons:
        p.use_smooth = True
    obj.data.materials.clear()
    dst = os.path.join(out_dir, "rock_%d.obj" % i)
    bpy.ops.wm.obj_export(filepath=dst, export_selected_objects=True, export_uv=False, export_materials=False,
                          export_normals=True, forward_axis="NEGATIVE_Z", up_axis="Y")
    print("rock %d: %s -> %s, %d -> %d triangles, height %.2f" % (i, os.path.basename(path), dst, tris,
          len(obj.data.polygons), (hi.z - lo.z) * k))
