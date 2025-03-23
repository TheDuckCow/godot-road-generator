@tool
@icon("res://addons/road-generator/resources/road_branch.png") #TODO: add real icon
## Road Branch Lane Pair is a node in a road network. 
## The Lane Pair is used to map lanes between two Road Paths that are connected via Road Branch
## Many Lane Pairs can exist per entry/exit path pair (e.g. 3 lanes going straight, 2 lanes turning left)

class_name RoadBranchLanePair
extends Node3D

@export var entry_lane : RoadLane
@export var exit_lane : RoadLane

@export var entry_lane_branch_tag : String
@export var exit_lane_branch_tag : String


func _ready():
	pass


# Workaround for cyclic typing
func is_road_branch_lane_pair() -> bool:
	return true
