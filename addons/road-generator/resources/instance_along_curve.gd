@tool
extends RoadDecoration
class_name InstanceAlongCurve

@export_file("*.tscn") var source_scene: String


func setup(segment: RoadSegment) -> void:
	print("Instancing as child")
	
	var reverse = segment.get_parent().get_node(segment.EDGE_R_NAME)
	var pack_scene = load(source_scene)
	var decomesh = pack_scene.instantiate()
	reverse.add_child(decomesh)
	decomesh.set_owner(segment.get_tree().get_edited_scene_root())
