# Custom resource notes

See this wiki page for more details:
https://github.com/TheDuckCow/godot-road-generator/wiki/User-guide:-Custom-road-meshes


## Special notes:

- For each prefab type, there's one `_src` and one `_exp` collection
  - src: the orignal export directly from Godot
  - exp: the one we are exporting out, flattend to a single mesh
- To properly export normals into the gLTF format, it's necessary to have the
  Blender modifier for normal weights, otherwise the gutter edges of the road
  get split and won't smoothly line up with the procedurally generated segments
