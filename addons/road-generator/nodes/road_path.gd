@tool
@icon("res://addons/road-generator/resources/road_path.png") #TODO: add real icon
## Create and hold the collection of road points that define a road path.
## Road paths are segments of road that connect two road branches.
## A Road path must contain road containers and associated road points.

class_name RoadPath
extends Node3D

@export var start_point : RoadPoint
@export var end_point : RoadPoint

var _entry_branch : RoadBranch
@export var entry_branch : RoadBranch :
	set(value):
		var branch : RoadBranch = value
		branch.add_exit_path(self)
		if _entry_branch:
			_entry_branch.remove_exit_path(self)
		_entry_branch = branch		
	get:
		return _entry_branch
		
var _exit_branch : RoadBranch
@export var exit_branch : RoadBranch:
	set(value):
		var branch : RoadBranch = value
		branch.add_entry_path(self)
		if _exit_branch:
			_exit_branch.remove_entry_path(self)
		_exit_branch = branch		
	get:
		return _exit_branch

func _ready():
	pass

# Workaround for cyclic typing
func is_road_path() -> bool:
	return true

func get_container() -> RoadContainer:
	var container_method = "is_road_container"
	
	for ch in get_children():
		if ch.has_method(container_method):
			return ch
			
	return null

#given a branch and tag, return the lane of that tag
#this is used to match lanes across branches
#from path to path
func get_lane_of_tag_on_branch(tag: String, branch: RoadBranch) -> RoadLane:
	return null
