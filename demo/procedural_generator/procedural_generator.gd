extends Node3D

const RoadActorScene: PackedScene = preload("res://demo/procedural_generator/RoadActor.tscn")

## How far ahead of the camera will we let a new RoadPoint be added
@export var max_rp_distance: int = 200
## How much buffer around this max dist to avoid adding new RPs
## (this will also define spacing between RoadPoints)
@export var buffer_distance: int = 50
## How much RPs are allowed
@export var max_rp: int = 20

## Node used to calcualte distances
@export var target_node: NodePath

@onready var container: RoadContainer = get_node("RoadManager/Road_001")
@onready var vehicles: Node = get_node("RoadManager/vehicles")
@onready var target: Node = get_node_or_null(target_node)
@onready var car_label: Label = get_node("%car_count")


func _init() -> void:
	randomize()
	var rseed = randi()
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

	# Iterate over all the RoadPoints with open connections.
	var rp_count:int = container.get_child_count()

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
		elif rp_count > max_rp:
			pass


## Manually clear prior/next points to ensure it gets fully disconnected
func remove_rp(edge_rp: RoadPoint, dir: int) -> void:
	var next_edge_rp: RoadPoint = edge_rp.get_next_rp() if dir == RoadPoint.PointInit.PRIOR else edge_rp.get_prior_rp()
	var flip_dir: int = RoadPoint.PointInit.NEXT if dir == RoadPoint.PointInit.PRIOR else RoadPoint.PointInit.PRIOR
	var spawner = edge_rp.get_node("ActorSpawner")
	assert(spawner)
	edge_rp.remove_child(spawner)
	edge_rp.disconnect_roadpoint(flip_dir, dir)
	next_edge_rp.add_child(spawner)
	# No need to manually remove cars, as we use the default: RoadLane.auto_free_vehicles=true
	#despawn_cars(edge_rp)
	edge_rp.prior_pt_init = ""
	edge_rp.next_pt_init = ""
	# Defer to allow time to free cars first, if using despawn_cars above
	edge_rp.call_deferred("queue_free")


## Add a new roadpoint in a given direction
func add_next_rp(rp: RoadPoint, dir: int) -> void:
	var mag = 1 if dir == RoadPoint.PointInit.NEXT else -1
	var flip_dir: int = RoadPoint.PointInit.NEXT if dir == RoadPoint.PointInit.PRIOR else RoadPoint.PointInit.PRIOR

	var new_rp := RoadPoint.new()
	container.add_child(new_rp)

	# Copy initial things like lane counts and orientation
	new_rp.copy_settings_from(rp, true)

	new_rp.traffic_dir=[]
	new_rp.lanes=[]

	for i in range(randi_range(1, 4)):
		new_rp.traffic_dir.append(RoadPoint.LaneDir.REVERSE)
		new_rp.lanes.append(RoadPoint.LaneType.SLOW)
	for i in range(randi_range(0, 2)):
		new_rp.traffic_dir.append(RoadPoint.LaneDir.REVERSE)
		new_rp.lanes.append(RoadPoint.LaneType.FAST)
	for i in range(randi_range(0, 2)):
		new_rp.traffic_dir.append(RoadPoint.LaneDir.FORWARD)
		new_rp.lanes.append(RoadPoint.LaneType.FAST)
	for i in range(randi_range(1, 4)):
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
	var res = rp.connect_roadpoint(dir, new_rp, flip_dir)
	if res != true:
		print("Failed to connect RoadPoint")
		return
	new_rp.add_child(spawner)
	spawn_vehicles_on_lane(rp, dir)


func spawn_vehicles_on_lane(rp: RoadPoint, dir: int) -> void:
	# Now spawn vehicles
	var new_seg = rp.next_seg if dir == RoadPoint.PointInit.NEXT else rp.prior_seg
	if not is_instance_valid(new_seg):
		print("Invalid new segment")
		return
	var new_lanes = new_seg.get_lanes()
	for _lane in new_lanes:
		var new_instance = RoadActorScene.instantiate()
		vehicles.add_child(new_instance)

		var rand_offset = randf() * _lane.curve.get_baked_length()
		var rand_pos = _lane.curve.sample_baked(rand_offset)
		new_instance.global_transform.origin = _lane.to_global(rand_pos)

		# We could let the agent auto-find the nearest road lane, but to save
		# on some performance we can directly assign BEFORE entering the tree
		# so that it skips the recusive find funciton.
		# Must run after its ready function, but before its physics_process call
		new_instance.agent.assign_lane(_lane)
		print("new_instance %s " % new_instance)


## Manual way to remove all vehicles registered to lanes of this RoadPoint,
## if we didn't use RoadLane.auto_free_vehicles = true
func despawn_cars(road_point:RoadPoint) -> void:
	var lanes:Array = []
	for seg in [road_point.prior_seg, road_point.next_seg]:
		if not is_instance_valid(seg):
			continue
		# Any connected segment is about to be destroyed since this RP is going
		# away, so all adjacent vehicles should all be removed
		lanes.append_array(seg.get_lanes())
	if lanes.is_empty():
		print("No lanes valid for car despawning")

	for _lane in lanes:
		var this_lane:RoadLane = _lane
		var lane_vehicles = this_lane._vehicles_in_lane #this_lane.get_vehicles()
		for _vehicle in lane_vehicles:
			print("Freeing vehicle ", _vehicle)
			_vehicle.queue_free()


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
				_ln_cars += len(lane._vehicles_in_lane)

	var car_count: int = len(get_tree().get_nodes_in_group("cars"))
	var rp_count: int = len(container.get_roadpoints())
	var _origin = target.global_transform.origin
	var player_pos: String = "(%s, %s, %s)" % [
		round(_origin.x), round(_origin.y), round(_origin.z)
	]
	car_label.text = "Roadpoints:%s\nCars: %s (lane-registered %s)\nfps: %s\nPlayer at: %s" % [
		rp_count,
		car_count,
		_ln_cars,
		Engine.get_frames_per_second(),
		player_pos]
