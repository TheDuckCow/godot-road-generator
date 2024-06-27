extends Spatial


export var acceleration := 5.0 # in meters per sec squared
export var max_speed := 200  # in meters per sec

var velocity:float = 0.0
var current_lane: RoadLane
var container


func _physics_process(delta: float) -> void:
	if not is_instance_valid(container):
		return

	update_lane(delta)
	move_agent(delta)


func update_lane(delta: float) -> void:
	if Input.is_action_pressed("ui_up"):
		velocity += acceleration*delta
	if Input.is_action_pressed("ui_down"):
		velocity -= acceleration*delta

	if not is_instance_valid(current_lane):
		current_lane = find_nearest_lane()
		print("Assigned closest lane: ", current_lane)

	if Input.is_action_just_pressed("ui_left"):
		var left_lane = current_lane.get_node_or_null(current_lane.lane_left)
		if is_instance_valid(left_lane):
			current_lane = left_lane
	if Input.is_action_just_pressed("ui_right"):
		var right_lane = current_lane.get_node_or_null(current_lane.lane_right)
		if is_instance_valid(right_lane):
			current_lane = right_lane


## Get closest position on the follow path given a global position
func get_closest_path_point(path: Path, pos:Vector3) -> Vector3:
	var interp_point = path.curve.get_closest_point(path.to_local(pos))
	return path.to_global(interp_point)


func find_nearest_lane() -> RoadLane:
	var pos = global_transform.origin # + this_car.transform.basis.z*5
	var closest_lane = null
	var closest_dist = null
	var all_lanes = get_tree().get_nodes_in_group(container.ai_lane_group)

	for lane in all_lanes:
		if not lane is RoadLane:
			push_warning("Non RoadLane in group %s" % container.ai_lane_group)
			continue
		var this_lane_closest = get_closest_path_point(lane, pos)
		var this_lane_dist = pos.distance_to(this_lane_closest)
		if this_lane_dist > 50:
			continue
		elif closest_lane == null:
			closest_lane = lane
			closest_dist = this_lane_dist
		elif this_lane_dist < closest_dist:
			closest_lane = lane
			closest_dist = this_lane_dist
	return closest_lane


func move_agent(delta: float) -> void:
	if not is_instance_valid(current_lane):
		push_warning("No valid lane")
		return

	# TODO: update this, so that we are snaping camera to lane position
	var cur_pos_along_lane: float = 0.5
	# Then, calculate + velocity*delta distance along this lane,
	# carrying over to the next one if necessary.
	transform.origin.z -= velocity

	velocity = lerp(velocity, 0, delta)
