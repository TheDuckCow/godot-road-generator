## Create and hold the geometry of a segment of road, including its curve.
##
## Assume lazy evaluation, only adding nodes when explicitly requested, so that
## the structure stays light only until needed.
extends Spatial
class_name RoadSegment

export(NodePath) var start_init setget _init_start_set, _init_start_get
export(NodePath) var end_init setget _init_end_set, _init_end_get

var start_point:RoadPoint
var end_point:RoadPoint

var path:Path
var road_mesh:MeshInstance

# Likely will need reference of a curve.. do later.
# var curve 


var is_dirty := true


func _ready():
	check_refresh()


## Unique identifier for a segment based on what its connected to.
func get_id():
	# TODO: consider changing so that the smaller resource id is first,
	# so that we avoid bidirectional issues.
	if start_point and end_point:
		return "%s-%s" % [start_point.get_instance_id(), start_point.get_instance_id()]
	elif start_point:
		return "%s-x" % start_point.get_instance_id()
	elif end_point:
		"x-%s" % end_point.get_instance_id()
	else:
		return "x-x"
	

# ------------------------------------------------------------------------------
# Export callbacks
# ------------------------------------------------------------------------------

func _init_start_set(value):
	start_init = value
	is_dirty = true
	check_refresh()


func _init_start_get():
	return start_init


func _init_end_set(value):
	end_init = value
	is_dirty = true
	check_refresh()


func _init_end_get():
	return end_init


func check_refresh():
	if start_init:
		start_point = get_node(start_init)
	if end_init:
		end_point = get_node(end_init)
	if not start_point or not is_instance_valid(start_point):
		is_dirty = false
	if not end_point or not is_instance_valid(end_point):
		is_dirty = false
	if is_dirty:
		_rebuild()
		is_dirty = false

# ------------------------------------------------------------------------------
# Geometry construction
# ------------------------------------------------------------------------------

## Construct the geometry of this road segment.
func _rebuild():
	if not road_mesh:
		road_mesh = MeshInstance.new()
		add_child(road_mesh)
		road_mesh.name = "road_mesh"
	if not path:
		path = Path.new()
		add_child(path)
		path.name = "seg_path"
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	#st.add_smooth_group(true)
	print("(re)building segment")
	
	# Reposition this node to be physically located between both RoadPoints.
	global_transform.origin = (
		start_point.global_transform.origin + start_point.global_transform.origin) / 2.0
	
	# First, find out the number of lanes that match between the two road points,
	# if they are off by more than 2, then error out (that assumes triangles
	# on both sides).
	if abs(len(start_point.lanes) - len(end_point.lanes)) > 2:
		push_error("Invalid change in lane counts from %s to %s on %s" % [
			len(start_point.lanes), len(end_point.lanes), self.name
		])
		return
	elif len(start_point.lanes) == len(end_point.lanes):
		var start_loop = to_local(start_point.global_transform.origin)
		var end_loop = to_local(end_point.global_transform.origin)
		for i in range(len(start_point.lanes)):
			# Prepare attributes for add_vertex.
			# Long edge towards origin, p1
			#st.add_normal(Vector3(0, 1, 0))
			st.add_uv(Vector2(0, 0))
			st.add_vertex(start_loop) # Call last for each vertex, adds the above attributes.
			# p1
			#st.add_normal(Vector3(0, 1, 0))
			st.add_uv(Vector2(0, 1))
			st.add_vertex(start_loop + start_point.global_transform.basis.x * start_point.lane_width)
			# p3
			#st.add_normal(Vector3(0, 1, 0))
			st.add_uv(Vector2(1, 1))
			st.add_vertex(end_loop)
			
			# Reverse face, p1
			#st.add_normal(Vector3(0, 1, 0))
			st.add_uv(Vector2(0, 0))
			st.add_vertex(start_loop + start_point.global_transform.basis.x * start_point.lane_width)
			# p1
			#st.add_normal(Vector3(0, 1, 0))
			st.add_uv(Vector2(0, 1))
			st.add_vertex(end_loop + end_point.global_transform.basis.x * end_point.lane_width)
			# p3
			#st.add_normal(Vector3(0, 1, 0))
			st.add_uv(Vector2(1, 1))
			st.add_vertex(end_loop)
			break
			
	else:
		push_warning("Non-same number of lanes not implemented yet")
	st.index()
	st.generate_normals()
	road_mesh.mesh = st.commit()
	road_mesh.create_trimesh_collision() # Call deferred?
	road_mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	
