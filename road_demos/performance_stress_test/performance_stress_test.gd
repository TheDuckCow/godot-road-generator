extends Node3D

@onready var label := %results
@onready var manager:RoadManager = $RoadManager
@onready var edges_btn := %edges
@onready var lanes_btn := %lanes
@onready var geo_btn := %geo
@onready var underside_btn := %underside
@onready var update_btn := %update
@onready var sample_input := %sample_input

var rebuild_count := 0
var samples := []


func _ready() -> void:
	run_rebuild()


func update_settings() -> void:
	var containers := manager.get_containers()
	var seg_counts := 0
	for _node in containers:
		var rc := _node as RoadContainer
		rc.generate_ai_lanes = lanes_btn.button_pressed
		rc.create_edge_curves = edges_btn.button_pressed
		rc.create_geo = geo_btn.button_pressed
		rc.underside_thickness = 2 if underside_btn.button_pressed else -1
		
		rc.use_lowpoly_preview = false


func run_rebuild() -> void:
	print("Running rebuild")
	update_settings()
	var containers := manager.get_containers()
	var seg_counts := 0
	rebuild_count = 0
	for _node in containers:
		var _cont: RoadContainer = _node
		if not _cont.on_road_updated.is_connected(_roads_updated):
			var res = _cont.on_road_updated.connect(_roads_updated)
			assert(res == OK)
		seg_counts += len(_cont.get_segments())

	var _time_start := Time.get_ticks_msec()
	manager.rebuild_all_containers(true)
	var _time_postgen := Time.get_ticks_msec()
	
	var sample_time := _time_postgen - _time_start
	samples.append(sample_time)
	var total_sample_time := 0
	for _sample in samples:
		total_sample_time += _sample
	
	var settings_txt := "%s, %s, %s, %s" % [
		"AI lanes" if lanes_btn.button_pressed else "no AI lanes",
		"edge curves" if edges_btn.button_pressed else "no edge curves",
		"geo" if geo_btn.button_pressed else "no geo",
		"underside" if underside_btn.button_pressed else "no underside",
		
	]
	var line1 := "Averge time to generate containers: %s ms over %s samples" % [
		total_sample_time / samples.size(), samples.size()]
	var line2 := "%sx segment rebuilds with %s" % [rebuild_count, settings_txt]
	print(line1)
	print(line2)
	label.text = "%s\n%s" % [line1, line2]
	assert(rebuild_count == seg_counts)


func _roads_updated(segments: Array) -> void:
	rebuild_count += len(segments)


func _on_update_pressed() -> void:
	samples = []


func _physics_process(delta: float) -> void:
	if samples.size() < sample_input.value:
		run_rebuild()
		if samples.size() == sample_input.value:
			print("Completed samples")
