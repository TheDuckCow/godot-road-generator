@tool
@icon("res://addons/road-generator/resources/road_branch.png") #TODO: add real icon
## Road Branch is a node in a road network. Road branches are connected via Road paths.
## A Road Branch may contain a Road Intersection which would dictate crossing behavior.

class_name RoadBranch
extends Node3D

var _entry_paths : Array[RoadPath] = []
@export var entry_paths : Array[RoadPath] :
	get:
		return _entry_paths
		
var _exit_paths : Array[RoadPath] = []
@export var exit_paths : Array[RoadPath] :
	get:
		return _exit_paths

func _ready():
	pass


# Workaround for cyclic typing
func is_road_branch() -> bool:
	return true

func add_exit_path(new_path: RoadPath):
	if new_path not in exit_paths:
		exit_paths.append(new_path)

func remove_exit_path(new_path: RoadPath):
	remove_path_element(new_path, exit_paths)

func add_entry_path(new_path: RoadPath):
	if new_path not in entry_paths:
		entry_paths.append(new_path)

func remove_entry_path(new_path: RoadPath):
	remove_path_element(new_path, entry_paths)
		
func remove_path_element(path: RoadPath, arr: Array[RoadPath]):
	var idx = arr.find(path)
	if idx >= 0:
		arr.remove_at(idx)
	
