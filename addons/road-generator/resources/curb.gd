@tool
extends RoadDecoration
class_name RoadCurb

@export var offset_start: float = 0.0
@export var offset_end: float = -0.0

func setup(segment: RoadSegment) -> void:
	print("Setup curb for ", segment.start_point.name, " to ", segment.end_point.name)
	
	var reverse = segment.get_parent().get_node(segment.EDGE_R_NAME)
	var decomesh = MeshInstance3D.new()
	decomesh.name = "Deco"
	reverse.add_child(decomesh)
	decomesh.set_owner(segment.get_tree().get_edited_scene_root())