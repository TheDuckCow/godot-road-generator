extends Spatial

## How far ahead of the camera will we let a new RoadPoint be added
export var max_rp_distance: int = 200
## How much buffer around this max dist to avoid adding new RPs
## (this will also define spacing between RoadPoints)
export var buffer_distance: int = 50

## Node used to calcualte distances
export var target_node: NodePath

onready var container: RoadContainer = get_node("RoadManager/Road_001")
onready var lane_agent: Spatial = get_node("LaneAgent")
onready var target: Node = get_node_or_null(target_node)
onready var popup: AcceptDialog = get_node("Control/AcceptDialog")


func _ready() -> void:
	lane_agent.container = container
	popup.popup_centered(Vector2(200, 70))


func _process(_delta: float) -> void:
	update_road()


func xz_target_distance_to(_target: Spatial) -> float:
	var pos_a := Vector3(target.global_transform.origin.x, 0, target.global_transform.origin.z)
	var pos_b := Vector3(_target.global_transform.origin.x, 0, _target.global_transform.origin.z)
	return pos_a.distance_to(pos_b)


## Parent function responsible for processing this road.
func update_road() -> void:

	# Make sure the edges of the Road are all open.
	container.update_edges()

	if not container.edge_rp_locals:
		print("No edges to add")
		return

	# Iterate over all the RoadPoints with open connections.
	var rp_count:int = container.get_child_count()
	print("RP count:", rp_count)

	# Cache the initial edges, to avoid referencing export vars on container
	# that get updated as we add new RoadPoints
	var edge_list: Array = container.edge_rp_locals
	var edge_dirs: Array = container.edge_rp_local_dirs

	for _idx in range(len(edge_list)):
		var edge_rp:RoadPoint = container.get_node(edge_list[_idx])
		var dist := xz_target_distance_to(edge_rp)
		# print("Process loop %s with RoadPoint %s with dist %s" % [_idx, edge_rp, dist])

		if dist > max_rp_distance + buffer_distance * 1.5:
			print("Removing rp %s %s m from target" % [edge_rp, dist])
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
	var offset_pos:Vector3 = new_rp.transform.basis.z * buffer_distance * mag
	new_rp.transform.origin += offset_pos

	# Finally, connect them together
	rp.connect_roadpoint(dir, new_rp, flip_dir)
	# print("Added rp %s" % new_rp)
