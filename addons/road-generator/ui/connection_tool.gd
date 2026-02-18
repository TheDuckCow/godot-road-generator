extends Object

# ------------------------------------------------------------------------------
#region Signals, Enums, constants, vars, and initializer
# ------------------------------------------------------------------------------

## When event handling detects a need to adjust the mode, propogate upwards to reflect in the toolbar
##
## Value should be of type plg._road_toolbar.InputMode
signal assign_mode(mode: int)

## State of the connection tool to be drawn
enum HintState {
	NONE, ## No interactions active
	CONNECT, ## Connect from source node to target node
	BRIDGE, ## Create new road container and bridge the gap betweem
	SNAP, ## Snap the source to the target, action should keep track of initial transforms
	UNSNAP, ## User is pulling 2+ elements apart, shoudl keep track of initial transforms
	CREATE_RP, ## Add a new node such as a RoadPoint
	CREATE_INTERSECTION, ## Construct an intersection
	DISCONNECT, ## Disconnect source node from target node
	DELETE, ## Only source nodes defined, not target
	DISSOLVE ## Only source nodes defined, not target
}

## State of the snapping tool
enum SnapState {
	IDLE,  ## No action in progress
	MOVING,  ## A node is being dragged around
	HINTING,  ## An action is being hinted at, reflected in hintstate
}

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

## Forwards the InputEvent to other EditorPlugins.
const INPUT_PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
## Prevents the InputEvent from reaching other Editor classes.
const INPUT_STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const margin := 3 ## Overlay margin for drawing white outlines
const white_col = Color(1, 1, 1, 0.9) ## Outline color
const rad_size := 10.0 ## Connector dot radius

var plg:EditorPlugin
var snap_threshold := 25.0 ## Threshold for snapping distance of nodes in the scene
var snapping: int = SnapState.IDLE ## Current state of snapping
var pre_snap_trans: Array[Transform3D] = []

## Used to define drawing overlays, should be updated in tandem with above assignments
var hinting: int = HintState.NONE
## Last cursor position, in case most recent event was not cursor-based (e.g. mod key)
var cursor := Vector2(-1, -1)

## Array of source nodes to keep track of interaction states
var hint_source_nodes: Array[Node3D] = []
## Array of target nodes to kep track of interaction states
var hint_target_nodes: Array[Node3D] = []
## Array of projected screen positions to draw for the corresponding source node
var hint_source_points: Array[Vector2] = []
## Array of projected screen positions to draw for the corresponding target node
var hint_target_points: Array[Vector2] = []

## Array of edges to highlight for this tool mode, may have a different number to above arrays
var hint_edges_r: Array[Vector2] = []
## Array of edges to highlight for this tool mode, may have a different number to above arrays
var hint_edges_f: Array[Vector2] = []

var _last_sel_inter: RoadIntersection ## Helper during hotkey navigation of roads
var _last_rp_before_inter: RoadPoint ## Helper during hotkey navigation of roads
var _overlay_ref: Control
var _hover_graphnode: RoadGraphNode ## Can only be queried in phyics states, so it's cached there

# Flag to trigger updated raycasts on next physics frame after relevant input
# TODO: Technically this means the outcome of the input handling is delayed one frame. Could improve
# by moving current input handling into physics process, at risk of events being swallowed.
var _physics_post_input: bool = false
# Context sharing from the physics process function to next input handling functions
var _intersect_dict: Dictionary = {}
var _intersect_mouse_src: Vector3 = Vector3.ZERO
var _intersect_mouse_nrm: Vector3 = Vector3.UP

var tempset_toolmode: bool = false

func _init(plugin: EditorPlugin) -> void:
	plg = plugin


# ------------------------------------------------------------------------------
#endregion
#region Plugin override pass-throughs
# ------------------------------------------------------------------------------


## This must be called by a parent process with an actual _physics_process hook
func _physics_process(_delta) -> void:
	# TODO: Technically safer to wrap in a mutex lock, but unsetting is one-sided anyways.
	if not _physics_post_input:
		return
	_physics_post_input = false
	# Perform raycast for both updating hinting as well as performing actions
	# Unforutnately, this means raycasting is essentially always being done
	# (if a road node is selected).
	if not plg.is_road_node(plg.get_selected_node()):
		return
	var view := EditorInterface.get_editor_viewport_3d(0)
	var camera := view.get_camera_3d()
	
	# Perform the main raycast
	_intersect_mouse_src = camera.project_ray_origin(cursor)
	_intersect_mouse_nrm = camera.project_ray_normal(cursor)
	var dist := camera.far

	var space_state := plg.get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		_intersect_mouse_src,
		_intersect_mouse_src + _intersect_mouse_nrm * dist)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	_intersect_dict = space_state.intersect_ray(query)

	# Now update hover node based one this state:
	_hover_graphnode = nearest_graphnode_from_raycast(_intersect_dict)
	# Be aware: _intersect_dict is also used in _perform_action.


## Called by the engine when the 3D editor's viewport is updated.
func forward_3d_draw_over_viewport(overlay: Control):
	# Overlay refresh 
	if not Rect2(Vector2(), overlay.size).has_point(overlay.get_local_mouse_position()):
		return # Outside the 3D viweport area, such as due to a hotkey press
	if not overlay.mouse_exited.is_connected(_on_mouse_exited):
		_overlay_ref = overlay
		_overlay_ref.mouse_exited.connect(_on_mouse_exited)
	# State handling
	if hinting == HintState.NONE:
		return
	match hinting:
		HintState.CONNECT:
			draw_hint_connect(overlay)
		HintState.BRIDGE:
			draw_hint_bridge(overlay)
		HintState.SNAP:
			draw_hint_snap(overlay)
		HintState.UNSNAP:
			draw_hint_disconnect(overlay, "Unsnap")
		HintState.CREATE_RP:
			draw_hint_create_rp(overlay)
		HintState.CREATE_INTERSECTION:
			draw_hint_create_intersection(overlay)
		HintState.DISCONNECT:
			draw_hint_disconnect(overlay, "Disconnect")
		HintState.DELETE:
			draw_hint_delete(overlay)
		HintState.DISSOLVE:
			draw_hint_dissolve(overlay)
		_:  # Including HintState.NONE
			return


## Handle or pass on event in the 3D editor
## If return true, consumes the event, otherwise forwards event
func forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	# Preprocess event to update toolbar if necessary
	handle_shortcuts(event, camera)
	
	# Handle inputs
	var ret := 0
	var selected:Node = plg.get_selected_node()
	var relevant:bool = plg.is_road_node(selected)

	if not relevant or plg.tool_mode == plg._road_toolbar.InputMode.SELECT:
		ret = _handle_select_mode_input(camera, event)
	elif plg.tool_mode == plg._road_toolbar.InputMode.ADD:
		ret = _handle_add_mode_input(camera, event)
	elif plg.tool_mode == plg._road_toolbar.InputMode.DELETE:
		ret = _handle_delete_mode_input(camera, event)
	return ret


# ------------------------------------------------------------------------------
#endregion
#region Interaction utilities
# ------------------------------------------------------------------------------


func handle_shortcuts(event: InputEvent, camera: Camera3D) -> void:
	traverse_nodes_shortcut(event)
	var _did_update := update_toolmode_shortcut(event)


## Implement handling of [] keys for moving between RPs in the 3d editor
##
## TODO: Turn into actual shortcut and make it configurable
## https://docs.godotengine.org/en/stable/classes/class_shortcut.html
func traverse_nodes_shortcut(event: InputEvent) -> void:
	var move_dir: int = -1
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_BRACKETRIGHT:
			move_dir = RoadPoint.PointInit.NEXT
		elif event.keycode == KEY_BRACKETLEFT:
			move_dir = RoadPoint.PointInit.PRIOR
		else:
			return
	else:
		return
	
	var to_end: bool = Input.is_key_pressed(KEY_SHIFT)
	var alt_pressed: bool = Input.is_key_pressed(KEY_ALT)
	var initial_sel = plg.get_selected_node()
	var new_sel: Node3D
	if initial_sel is RoadPoint and not alt_pressed:
		# Just pick the next/prior node
		var rp: RoadPoint = initial_sel
		if to_end:
			new_sel = rp.get_last_rp(move_dir)
		else:
			new_sel = rp.get_next_road_node() if move_dir == RoadPoint.PointInit.NEXT else rp.get_prior_road_node()
		if is_instance_valid(new_sel):
			if new_sel is RoadGraphNode and new_sel.container and new_sel.container.is_subscene():
				new_sel = new_sel.container
			elif new_sel is RoadIntersection:
				# avoids automatically going back to the same rp after entering an intersection
				_last_rp_before_inter = rp
	elif initial_sel is RoadPoint and alt_pressed:
		# Need to select the next/prior RP in the previously selected intersection
		if not is_instance_valid(_last_sel_inter):
			return
		new_sel = _get_nextprior_rp_from_inter(_last_sel_inter, initial_sel, move_dir)
		if not is_instance_valid(new_sel):
			return
		_last_rp_before_inter = initial_sel
	elif initial_sel is RoadIntersection:
		var inter: RoadIntersection = initial_sel
		new_sel = _get_nextprior_rp_from_inter(inter, _last_rp_before_inter, move_dir)
		if not is_instance_valid(new_sel):
			return
		_last_sel_inter = inter
		
	elif initial_sel is RoadContainer:
		# TODO: Select one of the roadpoints (or containers) of connected edges to this container
		pass
	else:
		return
	
	if is_instance_valid(new_sel) and is_instance_valid(initial_sel):
		plg._edi.get_selection().call_deferred("remove_node", initial_sel)
		plg._edi.get_selection().call_deferred("add_node", new_sel)


## Update the state of the toolbar mode
##
## Tightly bound to the toolbar code, not great design but necessary to have all
## inputs processed from here to avoid delay issues.
##
## Returns true if mode changed.
func update_toolmode_shortcut(event: InputEvent) -> bool:
	if event is InputEventKey and event.keycode == KEY_ALT:
		var was_tempset := tempset_toolmode
		tempset_toolmode = event.is_pressed()
		if was_tempset == tempset_toolmode:
			return false
		if plg._road_toolbar.mode == plg._road_toolbar.InputMode.SELECT:
			plg._road_toolbar._on_add_mode_pressed()
			return true
		elif plg._road_toolbar.mode == plg._road_toolbar.InputMode.ADD:
			plg._road_toolbar._on_select_mode_pressed()
			return true
				
	return false


## Utility for processing tab-navigation after leaving an intersection
static func _get_nextprior_rp_from_inter(inter: RoadIntersection, prior_rp: RoadPoint, move_dir: int) -> RoadPoint:
	var last_index = inter.edge_points.find(prior_rp)
	if last_index < 0:
		if inter.edge_points.size() > 0:
			last_index = 0
		else:
			return # nothing to select anyways

	var new_index: int = last_index+1 if move_dir == RoadPoint.PointInit.NEXT else last_index-1
	if new_index >= inter.edge_points.size():
		new_index = 0
	elif new_index < 0:
		new_index = inter.edge_points.size() -1
	return inter.edge_points[new_index]


## Gets nearest RoadPoint if user clicks a Segment. Returns RoadPoint or null.
##
## Takes in a previously already determined raycast intersection that must have
## been identified in a physics_process call (result can be empty).
func nearest_graphnode_from_raycast(intersect: Dictionary) -> RoadGraphNode:
	if intersect.is_empty():
		return null

	var collider = intersect["collider"]
	var position = intersect["position"]
	if collider.name.begins_with("road_mesh_col"):
		# Native RoadSegment - so there's just two RP's to choose between
		# Return the closest RoadPoint
		var road_segment: RoadSegment = collider.get_parent().get_parent()
		var start_point: RoadPoint = road_segment.start_point
		var end_point: RoadPoint = road_segment.end_point
		var nearest_point: RoadPoint
		var dist_to_start = start_point.global_position.distance_to(position)
		var dist_to_end = end_point.global_position.distance_to(position)
		if dist_to_start > dist_to_end:
			nearest_point = end_point
		else:
			nearest_point = start_point
		return nearest_point
	elif collider.name.begins_with("intersection_mesh_col"):
		var intersection: RoadIntersection = collider.get_parent().get_parent()
		return intersection
	else:
		# Might be a custom RoadContainer.
		# static body collider could be child or grandchild
		var check_par = collider.get_parent()
		if not check_par is RoadContainer:
			check_par = check_par.get_parent()
			if not check_par is RoadContainer:
				check_par = check_par.get_parent()
				if not check_par is RoadContainer:
					return null
		var par_rc:RoadContainer = check_par
		par_rc.update_edges()
		var nearest_point: RoadPoint
		var nearest_dist: float
		for idx in len(par_rc.edge_rp_locals):
			var edge: RoadPoint = par_rc.get_node_or_null(par_rc.edge_rp_locals[idx])
			if not is_instance_valid(edge):
				continue
			var edge_dist: float = edge.global_position.distance_to(position)
			if not is_instance_valid(nearest_point) or edge_dist < nearest_dist:
				nearest_point = edge
				nearest_dist = edge_dist
		if not is_instance_valid(nearest_point):
			return null
		return nearest_point


## Convert a given click to the nearest, best fitting 3d pos + normal for click.
##
## Includes selection node so that if there's no intersection made, we can still
## raycast onto the xz  or screen xy local plane of the object clicked on.
##
## Returns: [Position, Normal]
func get_click_point_with_context(intersect: Dictionary, mouse_src: Vector3, mouse_nrm: Vector3, camera: Camera3D, selection: Node) -> Array:
	# Unfortunately, must have collide with areas off. And this doesn't pick
	# up collisions with objects that don't have collisions already added, making
	# it not as convinient for viewport manipulation.

	if not intersect.is_empty():
		# If we hit a collider, offset the road upwards by half the gutter profile
		# (if negative) so that the road's edges can sink into the terrain to
		# avoid gaps.
		var half_gutter := 0.0
		if selection is RoadPoint:
			half_gutter = max(0.0, -0.5 * selection.gutter_profile.y)
		var nrm: Vector3 = intersect["normal"].normalized()
		var pos: Vector3 = intersect["position"] + nrm*half_gutter
		return [pos, nrm]

	# if we couldn't directly intersect with something, then place the next
	# point in the same plane as the initial selection which is also facing
	# the camera, or in the plane of that object's.

	var use_obj_plane = selection is RoadPoint or selection is RoadContainer

	# Points used to define offset used to construct a valid Plane
	var point_y_offset:Vector3
	var point_x_offset:Vector3

	if use_obj_plane:
		# Stick within the current selection's xy plane
		point_y_offset = selection.global_transform.basis.z
		point_x_offset = selection.global_transform.basis.x
	else:
		# Use the camera plane instead
		point_y_offset = camera.global_transform.basis.y
		point_x_offset = camera.global_transform.basis.x

	# the normal is the camera.global_transform.basis.z
	# the reference position is selection.global_transform.origin
	# which already defines the plane in quesiton.
	var plane_nrm = -camera.global_transform.basis.z
	var ref_pt = selection.global_transform.origin
	var plane = Plane(
		ref_pt,
		ref_pt + point_y_offset,
		ref_pt + point_x_offset)

	var hit_pt = plane.intersects_ray(mouse_src, mouse_nrm)
	var up = selection.global_transform.basis.y

	if hit_pt == null:
		point_y_offset = camera.global_transform.basis.y
		point_x_offset = camera.global_transform.basis.x
		plane = Plane(
			ref_pt,
			ref_pt + point_y_offset,
			ref_pt + point_x_offset)
		hit_pt = plane.intersects_ray(mouse_src, mouse_nrm)
		up = selection.global_transform.basis.y

	# TODO: Finally, detect if the point is behind or in front;
	# if behind, then skip action.

	return [hit_pt, up]


# ------------------------------------------------------------------------------
#endregion
#region GUI overlays
# ------------------------------------------------------------------------------


func draw_hint_connect(overlay: Control) -> void:
	var col: Color = Color.AQUA
	for idx in hint_source_points.size():
		var src := hint_source_points[idx]
		var trg := hint_target_points[idx]
		_draw_connector(overlay, src, trg, col)
	_draw_mouse_label(overlay, col, "Connect")
	_draw_edges(overlay, col, false)


func draw_hint_bridge(overlay: Control) -> void:
	var col: Color = Color.AQUA
	for idx in hint_source_points.size():
		var src := hint_source_points[idx]
		var trg := hint_target_points[idx]
		_draw_connector(overlay, src, trg, col)
	_draw_mouse_label(overlay, col, "Bridge")
	_draw_edges(overlay, col, false)


func draw_hint_snap(overlay: Control) -> void:
	var col: Color = Color.AQUA
	for idx in hint_source_points.size():
		var src := hint_source_points[idx]
		var trg := hint_target_points[idx]
		_draw_connector(overlay, src, trg, col)
	_draw_mouse_label(overlay, col, "Snap")
	_draw_edges(overlay, col, false)


func draw_hint_create_rp(overlay: Control) -> void:
	var col: Color = Color.AQUA
	if hint_source_nodes[0] is RoadPoint or hint_source_nodes[0] is RoadIntersection:
		_draw_connector(overlay, hint_source_points[0], cursor, col, true)
	_draw_mouse_label(overlay, col, "Add")


func draw_hint_create_intersection(overlay: Control) -> void:
	var col: Color = Color.AQUA
	for idx in hint_source_points.size():
		var src := hint_source_points[idx]
		var trg := hint_target_points[idx]
		var dashed: bool = idx > 0
		_draw_connector(overlay, src, trg, col, dashed)
		_draw_mouse_label(overlay, col, "Create Intersection")
	_draw_edges(overlay, col, false)


func draw_hint_disconnect(overlay: Control, label: String) -> void:
	var col: Color = Color.CORAL
	for idx in hint_source_points.size():
		var src := hint_source_points[idx]
		var trg := hint_target_points[idx]
		_draw_connector(overlay, src, trg, col)
	_draw_mouse_label(overlay, col, label)
	_draw_edges(overlay, col, false)


func draw_hint_delete(overlay: Control) -> void:
	var col: Color = Color.CORAL
	for pos in hint_source_points:
		_draw_x(overlay, pos, col)
		_draw_mouse_label(overlay, col, "Delete")
	_draw_edges(overlay, col, false)


func draw_hint_dissolve(overlay: Control) -> void:
	var col: Color = Color.CORAL
	for pos in hint_source_points:
		_draw_x(overlay, pos, col)
	_draw_mouse_label(overlay, col, "Dissolve")
	_draw_edges(overlay, col, true)


func _draw_edges(overlay: Control, col, dashed) -> void:
	for idx in hint_edges_r.size():
		var rev:Vector2 = hint_edges_r[idx]
		var fwd:Vector2 = hint_edges_f[idx]
		_draw_edge(overlay, col, dashed, [rev, fwd])


## Draws a white-outlined line with circles caps between two screen positions
func _draw_connector(overlay: Control, start_pos: Vector2, end_pos: Vector2, col: Color, dashed: bool = false) -> void:
	# White background margin
	overlay.draw_circle(start_pos, rad_size + margin, white_col)
	overlay.draw_circle(end_pos, rad_size + margin, white_col)
	
	const dash_dist := 8
	if dashed:
		overlay.draw_dashed_line(start_pos, end_pos, white_col, 2+margin*2, dash_dist, true)
	else:
		overlay.draw_line(start_pos, end_pos, white_col, 2+margin*2, true)
	
	# Colored part
	overlay.draw_circle(start_pos, rad_size, col)
	overlay.draw_circle(end_pos, rad_size, col)
	if dashed:
		overlay.draw_dashed_line(start_pos, end_pos, col, 2, dash_dist, true)
	else:
		overlay.draw_line(start_pos, end_pos, col, 2, true)


func _draw_x(overlay: Control, pos: Vector2, col: Color) -> void:
	var radius := 24.0  # Radius of the rounded ends
	var hf := radius / 2.0
	# white bg
	overlay.draw_line(
		pos + Vector2(-hf-margin, -hf-margin),
		pos + Vector2(hf+margin, hf+margin),
		white_col, 6 + margin)
	overlay.draw_line(
		pos + Vector2(-hf-margin, hf+margin),
		pos + Vector2(hf+margin, -hf-margin),
		white_col, 6 + margin)
	# Red part on top
	overlay.draw_line(
		pos + Vector2(-hf, -hf),
		pos + Vector2(hf, hf),
		col, 6)
	overlay.draw_line(
		pos + Vector2(-hf, + hf),
		pos + Vector2(hf, -hf),
		col, 6)


func _draw_edge(overlay: Control, col: Color, dashed: bool, pts: Array[Vector2]) -> void:
	var left_pt: Vector2 = pts[0]
	var right_pt: Vector2 = pts[1]
	const width := 4
	if dashed:
		# from: Vector2, to: Vector2, color: Color, width: float = -1.0, dash: float = 2.0, aligned: bool = true, antialiased: bool = false
		const dash_dist := 8
		overlay.draw_dashed_line(left_pt, right_pt, col, width, dash_dist)
	else:
		overlay.draw_line(left_pt, right_pt, col, width)


func _draw_mouse_label(overlay: Control, col: Color, text: String) -> void:
	var pos := cursor + Vector2(30, 35)
	var font = overlay.get_theme_default_font()
	const outline_size := 4
	overlay.draw_multiline_string_outline(font, pos, text, 0, -1, 24, -1, outline_size, Color.WHITE)
	overlay.draw_multiline_string(font, pos, text, 0, -1, 24, -1, col)


# ------------------------------------------------------------------------------
#endregion
#region Handle input hinting
# ------------------------------------------------------------------------------


func _handle_select_mode_input(camera: Camera3D, event: InputEvent) -> int:
	# Check relevant necessary to ensure last cursor pos is always updated
	var relevant := _relevant_input_event(event)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Drag started
			var selection:Node = plg.get_selected_node()
			if not plg.is_road_node(selection):
				snapping = SnapState.IDLE
				_clear_targets()
				return INPUT_PASS
			_clear_targets()
			if selection is RoadContainer:
				pre_snap_trans = [selection.global_transform]
				# TODO: Add each cross-connected RP that is not part of subscene.
			snapping = SnapState.MOVING # May get upgraded to HINTING after any mouse movements
			plg.update_overlays()
			return INPUT_PASS
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# Drag potentially ended
			if snapping == SnapState.HINTING:
				var res = _perform_action(camera)
				snapping = SnapState.IDLE
				_clear_targets()
				plg.update_overlays()
				return res
			snapping = SnapState.IDLE
			_clear_targets()
			plg.update_overlays()
			return INPUT_PASS
		else:
			pass # handle cancellation
	elif event is InputEventMouseMotion and snapping in [SnapState.MOVING, SnapState.HINTING]:
		# Update drag state to show connection/disconnection, no actions performed
		# if selection = cotnianer, check nearest poitns and so forth.
		# _physics_post_input = true needed?
		_clear_targets() # do NOT clear snapping here
		var selection:Node = plg.get_selected_node()

		if selection is RoadPoint:
			var rp: RoadPoint = selection
			pass # Not implemented yet (connect to other RPs/container edges)
		elif selection is RoadIntersection:
			pass # Not implemented yet (drag road_edges along with self)
		elif selection is RoadContainer:
			# Identify if snapping or unsnapping
			if snapping == SnapState.IDLE or pre_snap_trans[0].origin == selection.global_transform.origin:
					return INPUT_PASS
			var container: RoadContainer = selection
			var cont_connections: Array = container.get_connected_edges()
			if cont_connections.size() > 0:
				# TODO: support using alt to toggle this superstate
				hinting = HintState.UNSNAP
				snapping = SnapState.HINTING
				# Disconnection mode for each edge
				for _egdeset in cont_connections:
					var rp_local: RoadPoint = _egdeset[0]
					var rp_connected: RoadPoint = _egdeset[1]
					hint_source_nodes.append(rp_connected) # or rp_local?
					hint_source_points.append(camera.unproject_position(rp_connected.global_transform.origin))
					hint_target_nodes.append(rp_local) # what is considered for the action
					hint_target_points.append(camera.unproject_position(rp_local.global_transform.origin))
					_insert_edge_hint(rp_local, camera)
			else:
				var snappable_pts: Array = [] # anything that we could connect to
				var closest_pt: RoadPoint
				var cloest_dist: float = -1
				var local_edge: RoadPoint
				for _edge in container.get_open_edges():
					var _snap_point := _get_nearest_edge_roadpoint(_edge, true, true)
					if not is_instance_valid(_snap_point):
						continue
					var this_dist:float = (_edge.global_position - _snap_point.global_position).length()
					if not is_instance_valid(closest_pt) or this_dist < cloest_dist:
						closest_pt = _snap_point
						cloest_dist = this_dist
						local_edge = _edge
				# Now display snapping option
				if is_instance_valid(closest_pt) and closest_pt.container != selection:
					hinting = HintState.SNAP
					snapping = SnapState.HINTING
					hint_source_nodes.append(local_edge) # but need to actuall pass along the local_edge for the tool action....
					hint_source_points.append(camera.unproject_position(local_edge.global_transform.origin))
					hint_target_nodes.append(closest_pt)
					hint_target_points.append(camera.unproject_position(closest_pt.global_transform.origin))
					_insert_edge_hint(closest_pt, camera)
				else:
					hinting = HintState.NONE
					snapping = SnapState.MOVING
		plg.update_overlays()
		return INPUT_PASS
	
	_clear_targets()
	plg.update_overlays()
	return INPUT_PASS


## Handle adding new RoadPoints, connecting, and disconnecting RoadPoints
func _handle_add_mode_input(camera: Camera3D, event: InputEvent) -> int:
	snapping = SnapState.IDLE
	if _relevant_input_event(event):
		_clear_targets()
		#print("_handle_add_mode_input relevanat")
	
		# Set up context variables which help determine the relevant current input
		var hover_roadnode:RoadGraphNode = _hover_graphnode
		var selection:Node = plg.get_selected_node()
		
		var active_container: RoadContainer
		if selection is RoadGraphNode:
			active_container = selection.container
		elif selection is RoadContainer:
			active_container = selection
		
		if selection is RoadManager:
			hint_source_nodes.append(selection)
			hinting = HintState.CREATE_RP
		elif selection is RoadContainer:
			#if selection.is_subscene():
			if hover_roadnode is RoadPoint:
				var rp_hover:RoadPoint = hover_roadnode
				var rp_hover_filled:bool = rp_hover.is_prior_connected() and rp_hover.is_next_connected()
				var rp_hover_pos: Vector2 = camera.unproject_position(rp_hover.global_transform.origin)
				
				var closest_rp:RoadPoint = plg.get_nearest_edge_road_point(selection, camera, cursor)
				var closest_filled:bool = closest_rp.is_prior_connected() and closest_rp.is_next_connected()
				var closest_pos: Vector2 = camera.unproject_position(closest_rp.global_transform.origin)
				
				if closest_rp == rp_hover:
					pass
				elif closest_filled:
					var hover_prior = rp_hover.get_prior_road_node()
					var hover_next = rp_hover.get_next_road_node()
					var prior_same = is_instance_valid(hover_prior) and hover_prior.container == selection
					var next_same = is_instance_valid(hover_next) and hover_next.container == selection
					if closest_rp.container == rp_hover.container and closest_rp.container.is_subscene():
						pass
					elif (prior_same or next_same):
						hint_source_nodes.append(closest_rp)
						hint_source_points.append(closest_pos)
						hint_target_nodes.append(rp_hover)
						hint_target_points.append(rp_hover_pos)
						_insert_edge_hint(closest_rp, camera)
						_insert_edge_hint(rp_hover, camera)
						hinting = HintState.DISCONNECT
				elif not rp_hover_filled and not closest_filled:
					if closest_rp.container == rp_hover.container and selection.is_subscene():
						pass # can't can't modify internals of subscene container
					elif selection.is_subscene():
						if rp_hover.container.is_subscene():
							# Add a new container with two roadpoints + a connection
							hint_source_nodes.append(rp_hover)
							hint_source_points.append(rp_hover_pos)
							hint_target_nodes.append(closest_rp)
							hint_target_points.append(closest_pos)
							_insert_edge_hint(closest_rp, camera)
							_insert_edge_hint(rp_hover, camera)
							hinting = HintState.BRIDGE
						else:
							# Add child of other same-scene container
							hint_source_nodes.append(rp_hover)
							hint_source_points.append(rp_hover_pos)
							hint_target_nodes.append(closest_rp)
							hint_target_points.append(closest_pos)
							_insert_edge_hint(closest_rp, camera)
							_insert_edge_hint(rp_hover, camera)
							hinting = HintState.CONNECT
					else:
						# Add node as child of this container
						hint_source_nodes.append(closest_rp)
						hint_source_points.append(closest_pos)
						hint_target_nodes.append(rp_hover)
						hint_target_points.append(rp_hover_pos)
						_insert_edge_hint(closest_rp, camera)
						_insert_edge_hint(rp_hover, camera)
						hinting = HintState.CONNECT
			elif selection.is_subscene():
				# TODO: In future, could also suggest connecting to closest edge
				hint_source_nodes.append(selection.get_manager())
				hint_source_points.append(camera.unproject_position(selection.global_transform.origin))
				hinting = HintState.CREATE_RP
			else:
				hint_source_nodes.append(selection)
				hint_source_points.append(camera.unproject_position(selection.global_transform.origin))
				hinting = HintState.CREATE_RP
		elif selection is RoadPoint and not is_instance_valid(hover_roadnode):
			var rp_sel_filled:bool = selection.is_prior_connected() and selection.is_next_connected()
			if rp_sel_filled:
				pass
			else:
				hint_source_nodes.append(selection)
				hint_source_points.append(camera.unproject_position(selection.global_transform.origin))
				hinting = HintState.CREATE_RP
		elif selection is RoadIntersection and not is_instance_valid(hover_roadnode):
			hint_source_nodes.append(selection)
			hint_source_points.append(camera.unproject_position(selection.global_transform.origin))
			hinting = HintState.CREATE_RP
		elif hover_roadnode is RoadPoint and selection is RoadPoint:
			# TODO - extract into func handle_add_rp2rp?
			# Connection context, but need to check if same container and if 
			var rp_sel: RoadPoint = selection
			var rp_hover:RoadPoint = hover_roadnode

			var rp_sel_filled:bool = rp_sel.is_prior_connected() and rp_sel.is_next_connected()
			var rp_sel_pos: Vector2 = camera.unproject_position(rp_sel.global_transform.origin)
			
			var rp_hover_filled:bool = rp_hover.is_prior_connected() and rp_hover.is_next_connected()
			var rp_hover_pos: Vector2 = camera.unproject_position(rp_hover.global_transform.origin)
			
			var sel_hover_connected = rp_hover.get_next_road_node() == rp_sel or rp_hover.get_prior_road_node() == rp_sel
			
			# TODO: check if either are on an edge which is cross-container connected.
			if rp_sel == rp_hover:
				pass
			elif sel_hover_connected:
				hint_source_nodes.append(rp_sel)
				hint_source_points.append(rp_sel_pos)
				hint_target_nodes.append(rp_hover)
				hint_target_points.append(rp_hover_pos)
				_insert_edge_hint(rp_sel, camera)
				_insert_edge_hint(rp_hover, camera)
				hinting = HintState.DISCONNECT
			elif not rp_hover_filled and not rp_sel_filled:
				hint_source_nodes.append(rp_sel)
				hint_source_points.append(rp_sel_pos)
				hint_target_nodes.append(rp_hover)
				hint_target_points.append(rp_hover_pos)
				_insert_edge_hint(rp_sel, camera)
				_insert_edge_hint(rp_hover, camera)
				hinting = HintState.CONNECT
			elif rp_hover_filled and not rp_sel_filled:
				_hint_intersection_creation(rp_hover, rp_sel, camera)
			elif not rp_hover_filled and rp_sel_filled:
				_hint_intersection_creation(rp_sel, rp_hover, camera)
		elif hover_roadnode is RoadIntersection and selection is RoadPoint:
			var inter: RoadIntersection = hover_roadnode
			var rp: RoadPoint = selection
			if inter.container == rp.container:
				hint_source_nodes.append(rp)
				hint_source_points.append(camera.unproject_position(rp.global_transform.origin))
				hint_target_nodes.append(inter)
				hint_target_points.append(camera.unproject_position(inter.global_transform.origin))
				_insert_edge_hint(rp, camera)
				if rp in inter.edge_points:
					hinting = HintState.DISCONNECT
				else:
					hinting = HintState.CONNECT
		elif hover_roadnode is RoadPoint and selection is RoadIntersection:
			var inter: RoadIntersection = selection
			var rp: RoadPoint = hover_roadnode
			if inter.container == rp.container:
				hint_source_nodes.append(rp)
				hint_source_points.append(camera.unproject_position(rp.global_transform.origin))
				hint_target_nodes.append(inter)
				hint_target_points.append(camera.unproject_position(inter.global_transform.origin))
				_insert_edge_hint(rp, camera)
				if rp in inter.edge_points:
					hinting = HintState.DISCONNECT
				else:
					hinting = HintState.CONNECT
		
		plg.update_overlays()
	elif not event is InputEventMouseButton:
		return INPUT_PASS
	elif not event.button_index == MOUSE_BUTTON_LEFT:
		return INPUT_PASS
	elif event.pressed:
		var res = _perform_action(camera)
		_clear_targets()
		snapping = SnapState.IDLE
		plg.update_overlays()
		return res

	return INPUT_PASS


## Handle deleting roadpoints, intersections, and containers (saved subscenes)
func _handle_delete_mode_input(camera: Camera3D, event: InputEvent) -> int:
	var alt_pressed := Input.is_key_pressed(KEY_ALT)
	if alt_pressed:
		return _input_delete_dissolve(camera, event, HintState.DISSOLVE)
	else:
		return _input_delete_dissolve(camera, event, HintState.DELETE)


## Handle dissolving roadpoints, intersections, and containers (saved subscenes)
##
## Similar to delete, but aims to reconnect adjacent road nodes if possible after
func _handle_dissolve_mode_input(camera: Camera3D, event: InputEvent) -> int:
	return _input_delete_dissolve(camera, event, HintState.DISSOLVE)


## Common utility for both deleting and dissolving, which are otherwise quite similar
func _input_delete_dissolve(camera: Camera3D, event: InputEvent, apply_hint: int) -> int:
	snapping = SnapState.IDLE
	if _relevant_input_event(event):
		_clear_targets()
		var point: RoadGraphNode = _hover_graphnode
		var selection:Node = plg.get_selected_node() # TODO: switch to selected *nodes*?
		var hover_pos := camera.unproject_position(selection.global_transform.origin)
		var mouse_dist = cursor.distance_to(hover_pos)
		if point and point.container.is_subscene():
			hint_source_nodes.append(point.container)
			var pt := camera.unproject_position(point.container.global_transform.origin)
			hint_source_points.append(pt)
			hinting = apply_hint
			for idx in point.container.edge_rp_locals.size():
				if not point.container.edge_containers[idx]:
					# if a given edge isn't cross container connected, don't hint
					# at it being disconnected
					continue
				var edge_path = point.container.edge_rp_locals[idx]
				var edge_pt = point.container.get_node_or_null(edge_path)
				if is_instance_valid(edge_pt):
					_insert_edge_hint(edge_pt, camera)
		elif point:
			hint_source_nodes.append(point)
			var pt := camera.unproject_position(point.global_transform.origin)
			hint_source_points.append(pt)
			if point is RoadPoint:
				_insert_edge_hint(point, camera)
			elif point is RoadIntersection:
				for _edge in point.edge_points:
					_insert_edge_hint(_edge, camera)
			hinting = apply_hint
		elif selection is RoadPoint and not selection.prior_pt_init and not selection.next_pt_init and mouse_dist < snap_threshold:
			hint_source_nodes.append(selection)
			hint_source_points.append(hover_pos)
			_insert_edge_hint(selection, camera)
			hinting = apply_hint
		elif selection is RoadIntersection and selection.edge_points.size() == 0:
			hint_source_nodes.append(selection)
			hint_source_points.append(hover_pos)
			hinting = apply_hint
			for _edge in selection.edge_points:
				_insert_edge_hint(_edge, camera)
		else:
			pass # TODO: identify rp's in screenspace nearby to delete, may be not connected to anything
		plg.update_overlays()
		return INPUT_PASS
	elif not event is InputEventMouseButton:
		return INPUT_PASS
	elif not event.button_index == MOUSE_BUTTON_LEFT:
		return INPUT_PASS
	elif event.pressed:
		var res = _perform_action(camera)
		_clear_targets()
		snapping = SnapState.IDLE
		plg.update_overlays()
		return res

	return INPUT_PASS


# ------------------------------------------------------------------------------
#endregion
#region Perform action
# ------------------------------------------------------------------------------


func _perform_action(camera: Camera3D) -> int:
	match hinting:
		HintState.CONNECT:
			for idx in hint_source_nodes.size():
				if hint_target_nodes[idx] is RoadIntersection:
					# add branch
					plg.connect_rp_to_intersection(hint_target_nodes[idx], hint_source_nodes[idx])
				else:
					plg._connect_rp_on_click(hint_source_nodes[idx], hint_target_nodes[idx])
			return INPUT_STOP
		HintState.BRIDGE:
			plg.bridge_rps_with_new_container(hint_source_nodes[0], hint_target_nodes[0])
			return INPUT_STOP
		HintState.SNAP:
			if hint_target_nodes[0] is RoadPoint: # really is a snapping of a RoadContainer
				# Source will
				# must rely on connected signals, due to translation completing on its own
				var other_rp: RoadPoint = hint_target_nodes[0]
				var tgt_rp: RoadPoint = hint_source_nodes[0]
				plg.snap_container_to_road_point(tgt_rp, other_rp, pre_snap_trans) # init transform?
			elif hint_target_nodes[0] is RoadIntersection:
				pass  # would only be for overwriting translation intention of siblings
			return INPUT_STOP
		HintState.UNSNAP:
			var selection: Node = plg.get_selected_node()
			if selection is RoadContainer:
				print("Unsnapping container")
				var container: RoadContainer = selection
				plg.unsnap_container(container, pre_snap_trans)
			return INPUT_STOP
		HintState.CREATE_RP:
			if hint_source_nodes[0] is RoadPoint or hint_source_nodes[0] is RoadContainer:
				var selection = hint_source_nodes[0]
				var res: Array = get_click_point_with_context(
					_intersect_dict, _intersect_mouse_src, _intersect_mouse_nrm, camera, selection)
				var pos:Vector3 = res[0]
				var nrm:Vector3 = res[1]
				plg._add_next_rp_on_click(pos, nrm, hint_source_nodes[0], null)
			elif hint_source_nodes[0] is RoadIntersection:
				var inter = hint_source_nodes[0]
				var res: Array = get_click_point_with_context(
					_intersect_dict, _intersect_mouse_src, _intersect_mouse_nrm, camera, inter)
				var pos:Vector3 = res[0]
				var nrm:Vector3 = res[1]
				plg.add_and_connect_rp_to_intersection(inter, pos, nrm)
			elif hint_source_nodes[0] is RoadManager:
				var mgr: RoadManager = hint_source_nodes[0]
				var res: Array = get_click_point_with_context(
					_intersect_dict, _intersect_mouse_src, _intersect_mouse_nrm, camera, mgr)
				var pos:Vector3 = res[0]
				var nrm:Vector3 = res[1]
				plg.add_roadcontainer_and_roadpoint(mgr, pos, nrm)
			return INPUT_STOP
		HintState.CREATE_INTERSECTION:
			if hint_source_nodes[0] is RoadPoint and hint_target_nodes[0] is RoadPoint:
				plg.convert_to_intersection_with_new_branch(hint_target_nodes[0], hint_source_nodes[0])
			else:
				print("Not implemented")
			return INPUT_STOP
		HintState.DISCONNECT:
			if hint_target_nodes[0] is RoadIntersection:
				plg.disconnect_rp_from_intersection(hint_target_nodes[0], hint_source_nodes[0])
			elif hint_target_nodes[0] is RoadContainer:
				pass # Workflow not implemented
			else:
				plg._disconnect_rp_on_click(hint_source_nodes[0], hint_target_nodes[0])
			return INPUT_STOP
		HintState.DELETE:
			for del_node in hint_source_nodes:
				if del_node is RoadPoint:
					plg.delete_roadpoint(del_node)
				elif del_node is RoadIntersection:
					plg.delete_intersection(del_node)
				elif del_node is RoadContainer:
					plg.delete_roadcontainer(del_node)
				return INPUT_STOP
		HintState.DISSOLVE:
			# Dissolve where possibe, but failing that act like delete
			for del_node in hint_source_nodes:
				if del_node is RoadPoint:
					plg.dissolve_roadpoint(del_node)
				elif del_node is RoadIntersection:
					plg.dissolve_intersection(del_node)
				elif del_node is RoadContainer:
					# Can't dissolve a whole container (or should this be a "merge" operation?)
					plg.delete_roadcontainer(del_node)
				return INPUT_STOP
	return INPUT_PASS


# ------------------------------------------------------------------------------
#endregion
#region Input handling utilities
# ------------------------------------------------------------------------------


func _clear_targets() -> void:
	hint_source_nodes = []
	hint_target_nodes = []
	hint_source_points = []
	hint_target_points = []
	hint_edges_r = []
	hint_edges_f = []
	hinting = HintState.NONE
	# Do NOT clear snapping


func _insert_edge_hint(rp: RoadPoint, camera: Camera3D) -> void:
	var origin = rp.global_position
	
	var rev_width: float = rp.get_width_without_shoulders() / 2.0
	var fwd_width: float = rp.get_width_without_shoulders() / 2.0
	var align_offset: float = 0.0
	if rp.alignment == rp.Alignment.DIVIDER:
		align_offset = rp.lane_width * rp.get_fwd_lane_count() / 2.0 - rp.lane_width * rp.get_rev_lane_count() / 2.0
	
	var rev_pos3d: Vector3 = origin - rp.global_basis.x * (rev_width - align_offset + rp.shoulder_width_l)
	var fwd_pos3d: Vector3 = origin + rp.global_basis.x * (fwd_width + align_offset + rp.shoulder_width_r)
	
	var rev_pos2d: Vector2 = camera.unproject_position(rev_pos3d)
	var fwd_pos2d: Vector2 = camera.unproject_position(fwd_pos3d)
	hint_edges_r.append(rev_pos2d)
	hint_edges_f.append(fwd_pos2d)


func _relevant_input_event(event: InputEvent) -> bool:
	var relevant: bool = false
	if event is InputEventKey and event.keycode == KEY_ALT:
		relevant = true
	var mouse_events:bool = event is InputEventMouseMotion or event is InputEventPanGesture or event is InputEventMagnifyGesture
	if mouse_events:
		cursor = event.position
		relevant = true
	if relevant:
		# Ensure next physics frame attempts to update its raycast targets
		_physics_post_input = true
	return relevant


func _on_mouse_exited():
	if is_instance_valid(_overlay_ref) and _overlay_ref.mouse_exited.is_connected(_on_mouse_exited):
		_overlay_ref.mouse_exited.disconnect(_on_mouse_exited)
		plg.update_overlays()


func _hint_intersection_creation(rp_hover: RoadPoint, rp_sel: RoadPoint, camera: Camera3D) -> void:
	var prior_hover_node := rp_hover.get_prior_road_node()
	var next_hover_node := rp_hover.get_next_road_node()
	var rp_sel_pos: Vector2 = camera.unproject_position(rp_sel.global_transform.origin)
	var rp_hover_pos: Vector2 = camera.unproject_position(rp_hover.global_transform.origin)
	if prior_hover_node is RoadIntersection or next_hover_node is RoadIntersection:
		# Can't directly connect two intersections
		pass
	elif is_instance_valid(prior_hover_node) and prior_hover_node.container != rp_hover.container:
		pass  # cross-container connected
	elif is_instance_valid(next_hover_node) and next_hover_node.container != rp_hover.container:
		pass  # cross container connected
	elif rp_sel.container != rp_hover.container:
		pass  # Both must be part of the same container to become connected
	else:
		# Create intersection
		hint_source_nodes.append(rp_sel)
		hint_source_points.append(rp_sel_pos)
		hint_target_nodes.append(rp_hover)
		hint_target_points.append(rp_hover_pos)
		_insert_edge_hint(rp_sel, camera)
		# visualize some edge or border for new intersection? based on initial connections
		if is_instance_valid(prior_hover_node):
			_insert_edge_hint(prior_hover_node, camera)
			hint_source_nodes.append(prior_hover_node)
			hint_source_points.append(camera.unproject_position(prior_hover_node.global_transform.origin))
			hint_target_nodes.append(rp_hover)
			hint_target_points.append(rp_hover_pos)
		if is_instance_valid(next_hover_node):
			_insert_edge_hint(next_hover_node, camera)
			hint_source_nodes.append(next_hover_node)
			hint_source_points.append(camera.unproject_position(next_hover_node.global_transform.origin))
			hint_target_nodes.append(rp_hover)
			hint_target_points.append(rp_hover_pos)
		hinting = HintState.CREATE_INTERSECTION


## Returns a RoadPoint that is the closest to the input one within the manager.
##
## source_rp: The reference point to search near
## ignore_same_cont: If true, don't include RoadPoints from the same container
## only_edges: Only consider open edge RoadPoints, not interior/connected ones
func _get_nearest_edge_roadpoint(source_rp: RoadPoint, ignore_same_cont: bool, only_edges: bool) -> RoadPoint:
	var cont: RoadContainer = source_rp.container
	var containers: Array[RoadContainer]
	var mng := cont.get_manager()
	if is_instance_valid(mng):
		containers = cont.get_all_road_containers(mng)
	else:
		if ignore_same_cont:
			# If ignoring the same container and others can't be identified, nothing to do
			return null
		containers = [cont]
	
	var min_dist: float
	var nearest_rp: RoadPoint
	for _cont in containers:
		if ignore_same_cont and _cont == cont:
			continue
		var tgt_edge: RoadPoint
		# TODO: could short circuit based on aabb/distance on any axis
		if only_edges:
			tgt_edge = _cont.get_closest_edge_road_point(source_rp.global_position, source_rp)
		else:
			tgt_edge = _cont.get_closest_graphnode(source_rp.global_position, source_rp)
		if not is_instance_valid(tgt_edge):
			continue
		var dist = (source_rp.global_position - tgt_edge.global_position).length()
		if dist > snap_threshold:
			continue
		if min_dist and dist > min_dist:
			continue
		min_dist = dist
		nearest_rp = tgt_edge
	return nearest_rp


#endregion
# ------------------------------------------------------------------------------
