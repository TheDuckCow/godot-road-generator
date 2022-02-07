## Road and Highway generator addon.
tool
extends EditorPlugin


const RoadPointGizmo = preload("res://addons/road-generator/road_point_gizmo.gd")

var road_point_gizmo = RoadPointGizmo.new()


func _enter_tree():
	add_spatial_gizmo_plugin(road_point_gizmo)


func _exit_tree():
	remove_spatial_gizmo_plugin(road_point_gizmo)
