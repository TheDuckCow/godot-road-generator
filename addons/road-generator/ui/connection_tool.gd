extends Object

# ------------------------------------------------------------------------------
#region Enums, constants, vars, and initializer
# ------------------------------------------------------------------------------

## State of the connection tool to be drawn
enum HintState {
	NONE, ## No interactions active
	CONNECT, ## Connect from source node to target node
	DISCONNECT, ## Disconnect source node from target node
	DELETE, ## Only source nodes defined, not target
	DISSOLVE ## Only source nodes defined, not target
}

## State of the snapping tool
enum SnapState {
	IDLE,
	SNAPPING,
	UNSNAPPING,
	MOVING,
	CANCELING,
}

## Forwards the InputEvent to other EditorPlugins.
const INPUT_PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
## Prevents the InputEvent from reaching other Editor classes.
const INPUT_STOP := EditorPlugin.AFTER_GUI_INPUT_STOP

## Overlay margin for drawing white outlines
const margin := 3
## Outline color
const white_col = Color(1, 1, 1, 0.9)
## Connector dot radius
const rad_size := 10.0

## Threshold for snapping distance of nodes in the scene
var snap_threshold := 25.0
var plg:EditorPlugin

## Current state of snapping
var snapping: int = SnapState.IDLE

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


func _init(plugin: EditorPlugin) -> void:
	plg = plugin


# ------------------------------------------------------------------------------
#endregion
#region Plugin override pass-throughs
# ------------------------------------------------------------------------------


## Called by the engine when the 3D editor's viewport is updated.
func forward_3d_draw_over_viewport(overlay: Control):
	if hinting == HintState.NONE:
		return
	match hinting:
		HintState.CONNECT:
			draw_hint_connect(overlay)
		HintState.DISCONNECT:
			draw_hint_disconnect(overlay)
		HintState.DELETE:
			draw_hint_delete(overlay)
		HintState.DISSOLVE:
			draw_hint_dissolve(overlay)
		_:  # Including HintState.NONE
			return


## Handle or pass on event in the 3D editor
## If return true, consumes the event, otherwise forwards event
func forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	var ret := 0

	var selected:Node = plg.get_selected_node()
	var relevant:bool = plg.is_road_node(selected)

	# TODO: Modifier key like control or option to toggle between select & add.

	if not relevant or plg.tool_mode == plg._road_toolbar.InputMode.SELECT:
		ret = _handle_select_mode_input(camera, event)
	elif plg.tool_mode == plg._road_toolbar.InputMode.ADD:
		ret = _handle_add_mode_input(camera, event)
	elif plg.tool_mode == plg._road_toolbar.InputMode.DELETE:
		ret = _handle_delete_mode_input(camera, event)
	return ret


## Implement handling of [] keys for moving between RPs in the 3d editor
##
## TODO: Turn into actual shortcut and make it configurable
## https://docs.godotengine.org/en/stable/classes/class_shortcut.html
func unhandled_input(event: InputEvent) -> void:
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
		# TODO: need some way of calling plg.get_tree().set_input_as_handled()


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


func draw_hint_disconnect(overlay: Control) -> void:
	var col: Color = Color.CORAL
	for idx in hint_source_points.size():
		var src := hint_source_points[idx]
		var trg := hint_target_points[idx]
		_draw_connector(overlay, src, trg, col)
		_draw_mouse_label(overlay, col, "Disconnect")
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
func _draw_connector(overlay: Control, start_pos: Vector2, end_pos: Vector2, col: Color) -> void:
	# White background margin
	overlay.draw_circle(start_pos, rad_size + margin, white_col)
	overlay.draw_circle(end_pos, rad_size + margin, white_col)
	overlay.draw_line(
		start_pos,
		end_pos,
		white_col,
		2+margin*2,
		true)
	
	# Colored part
	overlay.draw_circle(start_pos, rad_size, col)
	overlay.draw_circle(end_pos, rad_size, col)
	overlay.draw_line(
		start_pos,
		end_pos,
		col,
		2,
		true)


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
#region Input handling
# ------------------------------------------------------------------------------


func _handle_select_mode_input(camera: Camera3D, event: InputEvent) -> int:
	# TODO: Re-implement thi
	return INPUT_PASS


## Handle adding new RoadPoints, connecting, and disconnecting RoadPoints
func _handle_add_mode_input(camera: Camera3D, event: InputEvent) -> int:
	# TODO: Re-implement thi
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
	if _relevant_input_event(event):
		_clear_targets()
		var point: RoadGraphNode = plg.get_nearest_graph_node(camera, cursor) # TODO: revert to cursor
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
		var res = _perform_action()
		_clear_targets()
		plg.update_overlays()
		return res

	return INPUT_PASS


func _perform_action() -> int:
	match hinting:
		HintState.CONNECT:
			return INPUT_STOP
		HintState.DISCONNECT:
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
	if event is InputEventKey and event.keycode == KEY_ALT:
		return true
	var mouse_events:bool = event is InputEventMouseMotion or event is InputEventPanGesture or event is InputEventMagnifyGesture
	if mouse_events:
		cursor = event.position
		return true
	return false


#endregion
# ------------------------------------------------------------------------------
