extends Spatial


onready var manager:RoadManager = $RoadManager

var rebuild_count := 0

func _ready() -> void:
	var containers := manager.get_containers()
	var seg_counts := 0
	for _node in containers:
		var _cont: RoadContainer = _node
		var res = _cont.connect("on_road_updated", self, "_roads_updated")
		assert(res == OK)
		seg_counts += len(_cont.get_segments())

	var _time_start := OS.get_ticks_msec()
	manager.rebuild_all_containers()
	var _time_postgen = OS.get_ticks_msec()
	print("Time to generate containers: %s ms" % (_time_postgen - _time_start))
	print("%sx segment rebuilds compared to %s actual segments" % [rebuild_count, seg_counts])
	assert(rebuild_count == seg_counts)


func _roads_updated(segments: Array) -> void:
	rebuild_count += len(segments)
