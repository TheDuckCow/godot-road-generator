extends MeshInstance
class_name RoadSegment

export(NodePath) var start_init setget _init_start_set, _init_start_get
export(NodePath) var end_init setget _init_end_set, _init_end_get

var start_point:RoadPoint
var end_point:RoadPoint

# Likely will need reference of a curve.. do later.
# var curve 


var is_dirty := true


func _ready():
	check_refresh()


## Unique identifier cosntructed from the two connected ends.
func get_id():
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
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
		for i in range(len(start_point.lanes)):
			# Prepare attributes for add_vertex.
			st.add_normal(Vector3(0, 0, 1))
			st.add_uv(Vector2(0, 0))
			# Call last for each vertex, adds the above attributes.
			st.add_vertex(Vector3(-1, -1, 0))

			st.add_normal(Vector3(0, 0, 1))
			st.add_uv(Vector2(0, 1))
			st.add_vertex(Vector3(-1, 1, 0))

			st.add_normal(Vector3(0, 0, 1))
			st.add_uv(Vector2(1, 1))
			st.add_vertex(Vector3(1, 1, 0))
			break
			
	else:
		push_warning("Non-same number of lanes not implemented yet")
	st.index()
	st.generate_normals()
	mesh = st.commit()
	create_trimesh_collision()
	cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	
