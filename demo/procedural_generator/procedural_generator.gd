extends Spatial

const RoadActor:PackedScene = preload("res://demo/procedural_generator/RoadActor.tscn")

## How far ahead of the camera will we let a new RoadPoint be added
export var max_rp_distance: int = 200
## How much buffer around this max dist to avoid adding new RPs
## (this will also define spacing between RoadPoints)
export var buffer_distance: int = 50

## Node used to calcualte distances
export var target_node: NodePath

onready var container: RoadContainer = get_node("RoadManager/Road_001")
onready var vehicles:Node = get_node("RoadManager/vehicles")
onready var target: Node = get_node_or_null(target_node)
onready var popup: AcceptDialog = get_node("Control/AcceptDialog")


func _ready() -> void:
	pass
	# popup.popup_centered(Vector2(200, 70))


func _process(_delta: float) -> void:
	update_road()


func xz_target_distance_to(_target: Spatial) -> float:
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
		if dist > max_rp_distance + buffer_distance * 1.5:
			# Manually clear prior/next points to ensure it gets fully disconnected
			despawn_cars(edge_rp)
			edge_rp.prior_pt_init = ""
			edge_rp.next_pt_init = ""
			edge_rp.queue_free()
		elif dist < max_rp_distance and rp_count < 30:
			var which_edge = edge_dirs[_idx]
			add_next_rp(edge_rp, which_edge)


## Add a new roadpoint in a given direction
func add_next_rp(rp: RoadPoint, dir: int) -> void:
	var mag = 1 if dir == RoadPoint.PointInit.NEXT else -1
	var flip_dir: int = RoadPoint.PointInit.NEXT if dir == RoadPoint.PointInit.PRIOR else RoadPoint.PointInit.PRIOR

	var new_rp := RoadPoint.new()
	container.add_child(new_rp)

	# Copy initial things like lane counts and orientation
	new_rp.copy_settings_from(rp, true)

	# Placement of a new roadpoint with interval no larger than buffer,
	# to avoid flicker removal/adding with the culling system

	# Randomly rotate the offset vector slightly
	randomize()
	var _transform := new_rp.transform
	var angle_range := 30 # Random angle rotation range
	var random_angle: float = rand_range(-angle_range / 2.0, angle_range / 2.0) # Generate a random angle within the range
	var rotation_axis := Vector3(0, 1, 0)
	_transform = _transform.rotated(rotation_axis, deg2rad(random_angle))

	var offset_pos:Vector3 = _transform.basis.z * buffer_distance * mag

	new_rp.transform.origin += offset_pos

	# Finally, connect them together
	var res = rp.connect_roadpoint(dir, new_rp, flip_dir)
	if res != true:
		print("Failed to connect RoadPoint")
		return

	# Now spawn vehicles
	var new_seg = rp.next_seg if dir == RoadPoint.PointInit.NEXT else rp.prior_seg
	if not is_instance_valid(new_seg):
		print("Invalid new segment")
		return
	var new_lanes = new_seg.get_lanes()
	for _lane in new_lanes:
		# TODO: get random poing along this lane and spawn,
		# for now just placing at the start point
		var new_instance = RoadActor.instance()
		vehicles.add_child(new_instance)
		var rand_pos = _lane.to_global(_lane.curve.get_point_position(0))
		new_instance.global_transform.origin = rand_pos
		_lane.register_vehicle(new_instance)


## Remvoe all vehicles registered to lanes of this RoadPoint
func despawn_cars(road_point:RoadPoint) -> void:
	var lanes:Array = []
	var any_valid := false
	if is_instance_valid(road_point.prior_seg) and road_point.prior_seg.get_parent() == road_point:
		lanes.append_array(road_point.prior_seg.get_lanes())
		any_valid = true
	if is_instance_valid(road_point.next_seg) and road_point.next_seg.get_parent() == road_point:
		lanes.append_array(road_point.next_seg.get_lanes())
		any_valid = true
	if not any_valid:
		print("No segments valid for car despawning")

	for _lane in lanes:
		var this_lane:RoadLane = _lane
		var lane_vehicles = this_lane.get_vehicles()
		for _vehicle in lane_vehicles:
			print("Freeing vehicle ", _vehicle)
			_vehicle.queue_free()

