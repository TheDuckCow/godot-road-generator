# Custom RoadPoint gizmo shapes

The custom puzzle piece shapes are created in Blender. There are three piece types:

- Full puzzle piece
- End cap with an outwards facing tab
- End cap with an outwards facing space

To refresh these meshes:

1. Open the blend file in Blender 5.2+
2. Make your edits in one of the export-marked collections (bools are used)
3. Go to file > Export All Collections, to export 1 collection called rp_gizmos
4. In your filesystem (not godot), move the generated rp_gizmos.glb file from next to the blend file to one folder up, since the base one is .gdignore'd
5. Then open it in a temporary inherited scene, mark each mesh resource as unique, then save each to disk as a .tres
6. Finally, delete the glb file - should not be committed (but the .tres should be)
