extends Node3D

const RoadActorManager = preload("road_actor_manager.gd")
const RoadActorSpawner = preload("road_actor_spawner.gd")
const RoadActor = preload("road_actor.gd")

## How far ahead of the camera will we let a new RoadPoint be added
@export var max_rp_distance: int = 200
## How much buffer around this max dist to avoid adding new RPs
## (this will also define spacing between RoadPoints)
@export var buffer_distance: int = 50

## Node used to calcualte distances
@export var target_node: NodePath

@onready var container: RoadContainer = get_node("RoadManager/Road_001")
@onready var vehicles: RoadActorManager = get_node("RoadManager/vehicles")
@onready var target: Node = get_node_or_null(target_node)
@onready var info_label: Label = get_node("%info_label")


func _init() -> void:
	randomize()
	var rseed = 1152532487#randi()
	seed(rseed)
	print("Seed number: ", rseed)


func _physics_process(_delta: float) -> void:
	update_road()
	update_stats()


func xz_target_distance_to(_target: Node3D) -> float:
	var pos_a := Vector2(target.global_transform.origin.x, target.global_transform.origin.z)
	var pos_b := Vector2(_target.global_transform.origin.x, _target.global_transform.origin.z)
	return pos_a.distance_to(pos_b)


## Parent function responsible for processing this road.
func update_road() -> void:

	# Make sure the edges of the Road are all open.
	container.update_edges()
	# TODO: This is overkill as it refreshes all points, in the future we should
	# have the container connection tool handle the responsibility of updating
	# prior/next lane assignments of edge roadPoints so it happens automatically
	container.update_lane_seg_connections()

	if not container.edge_rp_locals:
		print("No edges to add")
		return

	# Cache the initial edges, to avoid referencing export vars on container
	# that get updated as we add new RoadPoints
	var edge_list: Array = container.edge_rp_locals
	var edge_dirs: Array = container.edge_rp_local_dirs

	for _idx in range(len(edge_list)):
		var edge_rp:RoadPoint = container.get_node(edge_list[_idx])
		var dist := xz_target_distance_to(edge_rp)
		# print("Process loop %s with RoadPoint %s with dist %s" % [_idx, edge_rp, dist])
		var which_edge = edge_dirs[_idx]
		if dist > max_rp_distance + buffer_distance * 1.5:
			# buffer * factor is to ensure buffer range is wider than the distance between rps,
			# to avoid flicker spawning
			remove_rp(edge_rp, which_edge)
		elif dist < max_rp_distance:
			add_next_rp(edge_rp, which_edge)


## Manually clear prior/next points to ensure it gets fully disconnected
func remove_rp(edge_rp: RoadPoint, dir: int) -> void:
	var next_edge_rp: RoadPoint = edge_rp.get_next_road_node() if dir == RoadPoint.PointInit.PRIOR else edge_rp.get_prior_road_node()
	var flip_dir: int = RoadPoint.PointInit.NEXT if dir == RoadPoint.PointInit.PRIOR else RoadPoint.PointInit.PRIOR
	var spawner: RoadActorSpawner = edge_rp.get_node("ActorSpawner")
	assert(spawner)
	despawn_cars(edge_rp) # reusing despawned actors with RoadActorManager, so auto_free_vehicles == false
	edge_rp.remove_child(spawner)
	edge_rp.disconnect_roadpoint(back_dir, dir)
	next_edge_rp.add_child(spawner)
	edge_rp.prior_pt_init = ""
	edge_rp.next_pt_init = ""
	# Defer to allow time to free cars first, if using despawn_cars above
	edge_rp.call_deferred("queue_free")


## Add a new roadpoint in a given direction
func add_next_rp(rp: RoadPoint, dir: int) -> void:
	var mag = 1 if dir == RoadPoint.PointInit.NEXT else -1
	var back_dir: int = RoadPoint.PointInit.NEXT if dir == RoadPoint.PointInit.PRIOR else RoadPoint.PointInit.PRIOR

	var new_rp := RoadPoint.new()
	container.add_child(new_rp)

	# Copy initial things like lane counts and orientation
	new_rp.copy_settings_from(rp, true)

	new_rp.traffic_dir=[]
	new_rp.lanes=[]

	for idx in range(randi_range(1, 4)):
		new_rp.traffic_dir.append(RoadPoint.LaneDir.REVERSE)
		new_rp.lanes.append(RoadPoint.LaneType.SLOW)
	for idx in range(randi_range(0, 2)):
		new_rp.traffic_dir.append(RoadPoint.LaneDir.REVERSE)
		new_rp.lanes.append(RoadPoint.LaneType.FAST)
	for idx in range(randi_range(0, 2)):
		new_rp.traffic_dir.append(RoadPoint.LaneDir.FORWARD)
		new_rp.lanes.append(RoadPoint.LaneType.FAST)
	for idx in range(randi_range(1, 4)):
		new_rp.traffic_dir.append(RoadPoint.LaneDir.FORWARD)
		new_rp.lanes.append(RoadPoint.LaneType.SLOW)

	# Placement of a new roadpoint with interval no larger than buffer,
	# to avoid flicker removal/adding with the culling system

	# Randomly rotate the offset vector slightly
	var _transform := new_rp.transform
	var angle_range := 30 # Random angle rotation range
	var random_angle: float = randf_range(-angle_range / 2.0, angle_range / 2.0) # Generate a random angle within the range
	var rotation_axis := Vector3.UP
	_transform = _transform.rotated(rotation_axis, deg_to_rad(random_angle))

	var rand_y_offset:float = randf_range(-7.5, 7.5)
	var offset_pos:Vector3 = _transform.basis.z * buffer_distance * mag + Vector3.UP * rand_y_offset

	new_rp.transform.origin += offset_pos

	var spawner = rp.get_node("ActorSpawner")
	assert(spawner)
	rp.remove_child(spawner)

	# Finally, connect them together
	var res = rp.connect_roadpoint(dir, new_rp, back_dir)
	if res != true:
		print("Failed to connect RoadPoint")
		return
	new_rp.add_child(spawner)
	spawn_vehicles_on_lane(rp, dir)


func spawn_vehicles_on_lane(rp: RoadPoint, dir: int) -> void:
	const after_start := 4.0
	# Now spawn vehicles
	var new_seg = rp.next_seg if dir == RoadPoint.PointInit.NEXT else rp.prior_seg
	if not is_instance_valid(new_seg):
		print("Invalid new segment")
		return
	var new_lanes = new_seg.get_lanes()
	for _lane: RoadLane in new_lanes:
		var length = _lane.curve.get_baked_length()
		var start = after_start if _lane.flags != RoadLane.LaneFlags.DIVERGING else length / 2.0
		var end = length if _lane.flags != RoadLane.LaneFlags.MERGING else length / 2.0
		var rand_offset = randf_range(start, end)
		var rand_pos = _lane.curve.sample_baked(rand_offset)
		vehicles.add_actor(_lane.to_global(rand_pos), _lane)


## Manual way to remove all vehicles registered to lanes of this RoadPoint,
## if we didn't use RoadLane.auto_free_vehicles = true
func despawn_cars(road_point:RoadPoint) -> void:
	var no_lane := true
	for seg in [road_point.prior_seg, road_point.next_seg]:
		if not is_instance_valid(seg):
			continue
		# Any connected segment is about to be destroyed since this RP is going
		# away, so all adjacent vehicles should all be removed
		for _lane: RoadLane in seg.get_lanes():
			for dir in RoadLane.MoveDir.values():
				var shared_part = _lane.shared_parts[dir]
				if shared_part:
					shared_part.clear_blocks()
			no_lane = false
			while ! _lane.obstacles.is_empty():
				vehicles.remove_actor(_lane.obstacles[0].node)
	if no_lane:
		print("No lanes valid for car despawning")



func update_stats() -> void:
	# For debugging purpses, brute force count the number of cars registered
	# across all RoadLanes; number should match overall car count.
	var _ln_cars = 0
	for _rp in container.get_roadpoints():
		var rp:RoadPoint = _rp
		for seg in [rp.prior_seg, rp.next_seg]:
			if not is_instance_valid(seg):
				continue
			if not seg in rp.get_children():
				continue # avoid double counting
			for lane in seg.get_lanes():
				_ln_cars += len(lane.obstacles)

	var car_count: int = vehicles.get_actor_count()
	var rp_count: int = len(container.get_roadpoints())
	var _origin = target.global_transform.origin
	var player_pos: String = "(%s, %s, %s)" % [
		round(_origin.x), round(_origin.y), round(_origin.z)
	]
	info_label.text = "Roadpoints:%s\nCars: %s (lane-registered %s)\nfps: %s\nPlayer at: %s" % [
		rp_count,
		car_count,
		_ln_cars,
		Engine.get_frames_per_second(),
		player_pos]
