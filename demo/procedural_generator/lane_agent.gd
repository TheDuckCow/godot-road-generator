extends Spatial


export var acceleration := 50 # in meters per sec squared
export var max_speed := 200  # in meters per sec
export var visualize_lane := false

var speed:float = 0.0
var current_lane: RoadLane
var container

var flipfac:int = 1  # assign as neg 1 each time dir changes


func _physics_process(delta: float) -> void:
	if not is_instance_valid(container):
		return

	update_lane(delta)
	move_agent(delta)


func update_lane(delta: float) -> void:
	var any_input := false
	if Input.is_action_pressed("ui_up"):
		speed += acceleration*delta
		any_input = true
	if Input.is_action_pressed("ui_down"):
		speed -= acceleration*delta
		any_input = true
	speed = clamp(speed, -max_speed, max_speed)
	if not any_input:
		speed = lerp(speed, 0, delta)

	if not is_instance_valid(current_lane):
		current_lane = find_nearest_lane()
		if is_instance_valid(current_lane):
			current_lane.draw_in_game = visualize_lane
			current_lane.rebuild_geom()
		else:
			print("Could not find closest lane")

	if Input.is_action_just_pressed("ui_left"):
		var left_lane = current_lane.get_node_or_null(current_lane.lane_left)
		if is_instance_valid(left_lane):
			current_lane.draw_in_game = false
			current_lane = left_lane
			current_lane.draw_in_game = visualize_lane
	if Input.is_action_just_pressed("ui_right"):
		var right_lane = current_lane.get_node_or_null(current_lane.lane_right)
		if is_instance_valid(right_lane):
			current_lane.draw_in_game = false
			current_lane = right_lane
			current_lane.draw_in_game = visualize_lane


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
	# var cur_pos_along_lane: float = 0.5

	# TODO: this needs to be made either neg or positive, base don whether
	# our movement is inthe same direction as the lane itself;
	# right now it's ping-ponging
	var move_distance:float = -speed * delta * flipfac

	# Move along the current curve until it move_distance is cleared, or we've
	# run out of space and we need to get to the next curve.
	var ref_point:Vector3 = global_transform.origin
	var itr = 0
	while true:
		itr += 1
		if itr > 1:
			print("Crossed a lane with %s iteration(s) " % itr)
		if not is_instance_valid(current_lane):
			print("No current lane")
			return
		# Then, calculate + speed*delta distance along this lane,
		# carrying over to the next one if necessary.
		# TODO: Flip offset direction if reversed == true
		# Offset is the distance in m along the curve of current position
		var init_offset:float = current_lane.curve.get_closest_offset(current_lane.to_local(ref_point))
		var lane_length = current_lane.curve.get_baked_length()

		# Need to know if flipping the direction of move_distance, depends on which direction
		# the roads are 'facing'
		var check_next_offset:float = init_offset + move_distance
		if check_next_offset > lane_length: # lane_length:
			# Need to find the point along the next curve
			var ref_local = current_lane.curve.interpolate_baked(lane_length) # likely could optimize
			ref_point = current_lane.to_global(ref_local)
			var _update_lane = current_lane.get_node_or_null(current_lane.lane_next)
			if not is_instance_valid(_update_lane):
				break
			current_lane.draw_in_game = false
			current_lane = _update_lane
			current_lane.draw_in_game = visualize_lane
			move_distance -= lane_length - init_offset
			var next_offset = current_lane.curve.get_closest_offset(current_lane.to_local(ref_point))

			# flipped scenarios, so now add/sub to move_dist should reverse
			if next_offset > 0 and move_distance > 0:
				flipfac *= -1
			elif next_offset == 0 and move_distance < 0:
				flipfac *= -1
		elif check_next_offset < 0:
			# Need to find the point along the prior curve
			var ref_local = current_lane.curve.interpolate_baked(0) # likely could optimize
			ref_point = current_lane.to_global(ref_local)
			var _update_lane = current_lane.get_node_or_null(current_lane.lane_prior)
			if not is_instance_valid(_update_lane):
				break
			current_lane.draw_in_game = false
			current_lane = _update_lane
			current_lane.draw_in_game = visualize_lane
			move_distance += init_offset # TODO, this is not in dinstance, this is index;..
			var next_offset = current_lane.curve.get_closest_offset(current_lane.to_local(ref_point))

			# flipped scenarios, so now add/sub to move_dist should reverse
			if next_offset > 0 and move_distance > 0:
				flipfac *= -1
			elif next_offset == 0 and move_distance < 0:
				flipfac *= -1
		else:
			# Next offset is within the length of this lane
			var ref_local = current_lane.curve.interpolate_baked(check_next_offset)
			ref_point = current_lane.to_global(ref_local)
			print("Was same lane ", current_lane)
			break

	global_transform.origin = ref_point # TODO: lerp basis x, but exact basis z


func align_new_move_dir(ref_point):

	return
