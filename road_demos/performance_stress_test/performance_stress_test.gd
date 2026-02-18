extends Node3D

@export var label: Label

@onready var manager:RoadManager = $RoadManager

var rebuild_count := 0

func _ready() -> void:
	var containers := manager.get_containers()
	var seg_counts := 0
	for _node in containers:
		var _cont: RoadContainer = _node
		var res = _cont.on_road_updated.connect(_roads_updated)
		assert(res == OK)
		seg_counts += len(_cont.get_segments())

	var _time_start := Time.get_ticks_msec()
	manager.rebuild_all_containers(true)
	var _time_postgen = Time.get_ticks_msec()
	var line1 = "Time to generate containers: %s ms" % (_time_postgen - _time_start)
	var line2 = "%sx segment rebuilds compared to %s actual segments" % [rebuild_count, seg_counts]
	print(line1)
	print(line1)
	label.text = "%s\n%s" % [line1, line2]
	assert(rebuild_count == seg_counts)


func _roads_updated(segments: Array) -> void:
	rebuild_count += len(segments)
