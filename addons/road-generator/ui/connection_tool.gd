extends Object

# ------------------------------------------------------------------------------
#region Enums, constants, vars, and initializer
# ------------------------------------------------------------------------------


enum SnapState {
	IDLE,
	SNAPPING,
	UNSNAPPING,
	MOVING,
	CANCELING,
}

# Forwards the InputEvent to other EditorPlugins.
const INPUT_PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
# Prevents the InputEvent from reaching other Editor classes.
const INPUT_STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const ROADPOINT_SNAP_THRESHOLD := 25.0


var plg:EditorPlugin

var rad_size := 10.0

# White margin background
var margin := 3
var white_col = Color(1, 1, 1, 0.9)

var _overlay_rp_selected: Node # Matching active selection or according RP child
var _overlay_rp_hovering: Node # Matching what the mouse is hovering over
var _overlay_hovering_pos := Vector2(-1, -1)
var _overlay_hovering_from := Vector2(-1, -1)
var _overlay_hint_disconnect := false
var _overlay_hint_connection := false
var _overlay_hint_delete := false
var _snapping = SnapState.IDLE
var _nearest_edges: Array # [Selected RP, Target RP]
var _edge_positions: Array # [edge_from_pos, edge_to_pos]
var _press_init_pos: Vector2


func _init(plugin: EditorPlugin) -> void:
	plg = plugin


# ------------------------------------------------------------------------------
#endregion
#region Plugin override pass-throughs
# ------------------------------------------------------------------------------


## Called by the engine when the 3D editor's viewport is updated.
func forward_3d_draw_over_viewport(overlay: Control):
	var selected:Node3D = _overlay_rp_selected

	if plg.tool_mode == plg._road_toolbar.InputMode.SELECT and _snapping == SnapState.IDLE:
		return
	elif plg.tool_mode == plg._road_toolbar.InputMode.SELECT:
		draw_select_mode(overlay, selected)
	elif plg.tool_mode == plg._road_toolbar.InputMode.DELETE:
		draw_delete_mode(overlay, selected)
	else:
		draw_add_mode(overlay, selected)


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


# ------------------------------------------------------------------------------
#endregion
#region GUI overlays
# ------------------------------------------------------------------------------

func draw_select_mode(overlay: Control, selected: Node3D) -> void:
	var col: Color
	if _overlay_hint_disconnect:
		col = Color.CORAL
	else:
		col = Color.AQUA

	# Treat Snapping and Unsnapping differently. When Snapping, show a line
	# between the two closest points. When Unsnapping, show lines between
	# all connected points that will be Unsnapped.
	if _snapping == SnapState.SNAPPING:
		if _overlay_rp_hovering == null or not is_instance_valid(_overlay_rp_hovering): # or is not RoadPoint?
			return # Nothing to draw

		if not selected is RoadPoint:
			return

		# White margin background
		overlay.draw_circle(_overlay_hovering_pos, rad_size + margin, white_col)
		overlay.draw_circle(_overlay_hovering_from, rad_size + margin, white_col)
		overlay.draw_line(
			_overlay_hovering_from,
			_overlay_hovering_pos,
			white_col,
			2+margin*2,
			true)

		# Now color based on operation
		overlay.draw_circle(_overlay_hovering_pos, rad_size, col)
		overlay.draw_circle(_overlay_hovering_from, rad_size, col)
		overlay.draw_line(
			_overlay_hovering_from,
			_overlay_hovering_pos,
			col,
			2,
			true)
#			return
	else: # Unsnapping
		# Iterate _all_edges and draw line for each
		for edge_pair in _edge_positions:
			_overlay_hovering_from = edge_pair[0]
			_overlay_hovering_pos = edge_pair[1]

			# White margin background
			overlay.draw_circle(_overlay_hovering_pos, rad_size + margin, white_col)
			overlay.draw_circle(_overlay_hovering_from, rad_size + margin, white_col)
			overlay.draw_line(
				_overlay_hovering_from,
				_overlay_hovering_pos,
				white_col,
				2+margin*2,
				true)

			# Now color based on operation
			overlay.draw_circle(_overlay_hovering_pos, rad_size, col)
			overlay.draw_circle(_overlay_hovering_from, rad_size, col)
			overlay.draw_line(
				_overlay_hovering_from,
				_overlay_hovering_pos,
				col,
				2,
				true)


func draw_add_mode(overlay: Control, selected: Node3D) -> void:
	var col: Color
	if _overlay_rp_hovering == null or not is_instance_valid(_overlay_rp_hovering): # or is not RoadPoint?
		return # Nothing to draw
	var hovering:RoadPoint = _overlay_rp_hovering
	if _overlay_hint_disconnect:
		# Hovering node is directly connected to this node already, offer to disconnect
		col = Color.CORAL
	elif hovering.is_next_connected() and hovering.is_prior_connected():
		# Where we're coming from is already fully connected.
		# Eventually though, this could be an intersection.
		return
	elif selected == null:
		# Should mean the source is a RoadContainer, meaning we want to create
		# a RoadPoint at the edge of an existing RoadContainer.
		col = Color.CHARTREUSE
		overlay.draw_circle(_overlay_hovering_pos, rad_size + margin, white_col)
		overlay.draw_circle(_overlay_hovering_pos, rad_size, col)
		# TODO: Consider drawing a horizontal line along the edge itself, to
		# clarify this is connection-affecting.
		return
	elif selected.is_next_connected() and selected.is_prior_connected():
		# Fully connected, though eventually this could be an intersection.
		return
	elif selected.container != hovering.container:
		col = Color.CADET_BLUE
	else:
		# Connection mode intra RoadContainer
		col = Color.AQUA
	# TODO: make color slight transparent, but requires merging draw positions
	# as one call instead of multiple shapes.

	if not selected is RoadPoint:
		return

	# White margin background
	overlay.draw_circle(_overlay_hovering_pos, rad_size + margin, white_col)
	overlay.draw_circle(_overlay_hovering_from, rad_size + margin, white_col)
	overlay.draw_line(
		_overlay_hovering_from,
		_overlay_hovering_pos,
		white_col,
		2+margin*2,
		true)

	# Now color based on opration
	overlay.draw_circle(_overlay_hovering_pos, rad_size, col)
	overlay.draw_circle(_overlay_hovering_from, rad_size, col)
	overlay.draw_line(
		_overlay_hovering_from,
		_overlay_hovering_pos,
		col,
		2,
		true)


func draw_delete_mode(overlay: Control, selected: Node3D) -> void:
	var col: Color
	if _overlay_hint_delete:
		col = Color.CORAL

		var radius := 24.0  # Radius of the rounded ends
		var hf := radius / 2.0
		# white bg
		overlay.draw_line(
			_overlay_hovering_pos + Vector2(-hf-margin, -hf-margin),
			_overlay_hovering_pos + Vector2(hf+margin, hf+margin),
			white_col, 6 + margin)
		overlay.draw_line(
			_overlay_hovering_pos + Vector2(-hf-margin, hf+margin),
			_overlay_hovering_pos + Vector2(hf+margin, -hf-margin),
			white_col, 6 + margin)
		# Red part on top
		overlay.draw_line(
			_overlay_hovering_pos + Vector2(-hf, -hf),
			_overlay_hovering_pos + Vector2(hf, hf),
			col, 6)
		overlay.draw_line(
			_overlay_hovering_pos + Vector2(-hf, + hf),
			_overlay_hovering_pos + Vector2(hf, -hf),
			col, 6)


# ------------------------------------------------------------------------------
#endregion
#region Input handling
# ------------------------------------------------------------------------------


func _handle_select_mode_input(camera: Camera3D, event: InputEvent) -> int:
	# Event triggers on both press and release. Ignore press and only act on
	# release. Also, ignore right-click and middle-click.
#	if (not event is InputEventMouseButton) and (not event is InputEventMouseMotion):
#		return INPUT_PASS 
	var selected:Node = plg.get_selected_node()
	var lmb_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var ctrl_pressed := Input.is_key_pressed(KEY_CTRL)
	var shift_pressed := Input.is_key_pressed(KEY_SHIFT)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and _snapping:
		# If user clicks RMB while snapping, then cancel snapping
		_snapping = SnapState.IDLE
		return INPUT_PASS
	elif event is InputEventKey and event.keycode == KEY_ESCAPE and _snapping:
		# If user presses escape while snapping, then cancel snapping
		_snapping = SnapState.IDLE
		return INPUT_PASS
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Nothing done until click up, but detect initial position
			# to differentiate between drags and direct clicks.
			_press_init_pos = event.position
			return INPUT_PASS
		elif _press_init_pos != event.position and not _snapping == SnapState.IDLE:
			# TODO: possibly add min distance before treated as a drag
			# (does built in godot have a tolerance before counted as a drag?)
			var sel_rp: RoadPoint = _nearest_edges[0]
			var tgt_rp: RoadPoint = _nearest_edges[1]
			if _snapping in [SnapState.SNAPPING, SnapState.CANCELING]:
				plg._snap_to_road_point_future(selected, sel_rp, tgt_rp, _snapping==SnapState.CANCELING)
			elif _snapping == SnapState.UNSNAPPING:
				# Disconnect Edge RoadPoints
				plg._unsnap_container_future(selected)
			# Clear overlays and snapping/unsnapping condition
			_snapping = SnapState.IDLE
			_overlay_hint_disconnect = false
			_overlay_hint_connection = false
			plg.update_overlays()
			return INPUT_PASS  # Is a drag event

		elif _press_init_pos != event.position:
			return INPUT_PASS  # Is a drag even

		# Shoot a ray and see if it hits anything
		var point:RoadGraphNode = plg.get_nearest_graph_node(camera, event.position)
		if point and not event.pressed:
			# Using this method creates a conflcit with builtin drag n drop & 3d gizmo usage
			#set_selection(point)
			#_on_selection_changed()

			if point.container.is_subscene():
				plg._new_selection = point.container
			else:
				plg._new_selection = point
			return INPUT_PASS
	elif event is InputEventMouseMotion and lmb_pressed and selected is RoadContainer:
		# If container already has Edge connections then unsnap/disconnect them.
		var sel_rp_connections: Array = selected.get_connected_edges()
#		_all_edges = selected.get_connected_edges()

		# Get the closest edges
		if len(sel_rp_connections) > 0:
#			print("%s %s connected edges" % [Time.get_ticks_msec(), len(sel_rp_connections)])
			var dist: float = 0
			_edge_positions = []
			for edge_group in sel_rp_connections:
				var edge = edge_group[0]
				var tgt_edge = edge_group[1]

				# Save edge positions for drawing in the viewport
				var edge_from_pos = camera.unproject_position(edge.global_transform.origin)
				var edge_to_pos = camera.unproject_position(tgt_edge.global_transform.origin)
				_edge_positions.append([edge_from_pos, edge_to_pos])

				# Save closest edges
				var group_dist = abs((edge.global_position - tgt_edge.global_position).length())
				if (not dist) or group_dist < dist:
					dist = group_dist
					_nearest_edges = edge_group

#			_nearest_edges = _all_edges[0]
#			var edge = _nearest_edges[0]
#			var tgt_edge = _nearest_edges[1]
#			dist = (edge.global_translation - tgt_edge.global_translation).length()
#			_overlay_hovering_from = camera.unproject_position(_nearest_edges[0].global_transform.origin)
#			_overlay_rp_hovering = _nearest_edges[0]
#			_overlay_hovering_pos = camera.unproject_position(_nearest_edges[1].global_transform.origin)
#			_overlay_rp_selected = _nearest_edges[1] # could be the selection, or child of selected container
			if false: # dist < ROADPOINT_SNAP_THRESHOLD:
				_snapping = SnapState.CANCELING
				# Use blue line color
				_overlay_hint_disconnect = false
				_overlay_hint_connection = true
			else:
				_snapping = SnapState.UNSNAPPING
				# Use red line color
				_overlay_hint_disconnect = true
				_overlay_hint_connection = false
#			selected.move_connected_road_points()
			plg.update_overlays()
			return INPUT_PASS

		# If container doesn't have Edge connections then snap/connect an Edge.
		# Get all usable Edge RoadPoints in selected container
		var sel_rp_edges: Array = selected.get_open_edges()
		if not len(sel_rp_edges) > 0:
			return INPUT_PASS

		# Iterate remaining RoadContainers in scene and find RoadPoint
		# closest to the RoadPoints in the selected container.
		var containers: Array = selected.get_all_road_containers(plg._edi.get_edited_scene_root())
		var min_dist: float
		_nearest_edges = []
		for cont in containers:
			if cont == selected:
				# Skip the selected container. We already have its Edge RoadPoints
				continue
			for edge in sel_rp_edges:
				if not is_instance_valid(edge):
					#push_warning("Container has invalid edges: " + selected.name)
					continue
				var tgt_edge = cont.get_closest_edge_road_point(edge.global_position)
				if not is_instance_valid(tgt_edge):
					#push_warning("Container has invalid edges: " + cont.name)
					continue
				var dist = (edge.global_position - tgt_edge.global_position).length()
				if dist < ROADPOINT_SNAP_THRESHOLD and ((not min_dist) or dist < min_dist):
					min_dist = dist
					_nearest_edges = [edge, tgt_edge]
		if _nearest_edges:
			_snapping = SnapState.SNAPPING
			_overlay_hovering_from = camera.unproject_position(_nearest_edges[0].global_transform.origin)
			_overlay_rp_hovering = _nearest_edges[0]
			_overlay_hovering_pos = camera.unproject_position(_nearest_edges[1].global_transform.origin)
			_overlay_rp_selected = _nearest_edges[1] # could be the selection, or child of selected container
			_overlay_hint_disconnect = false
			_overlay_hint_connection = true
			plg.update_overlays()
		else:
			_snapping = SnapState.IDLE

		return INPUT_PASS
	return INPUT_PASS


## Handle adding new RoadPoints, connecting, and disconnecting RoadPoints
func _handle_add_mode_input(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventMouseMotion or event is InputEventPanGesture or event is InputEventMagnifyGesture:
		# Handle updating UI overlays to indicate what would happen on click.
		## TODO: if pressed state, then use this to update the in/out mag handles
		# Pressed state not available here, need to track state separately.
		# Handle visualizing which connections are free to make
		# trigger overlay updates to draw/update indicators
		var point:RoadGraphNode = plg.get_nearest_graph_node(camera, event.position)
		var hover_point := point # logical workaround to duplicate
		var selection:Node = plg.get_selected_node()
		var src_is_contianer := false
		var target:RoadGraphNode

		if selection is RoadContainer:
			src_is_contianer = true
			var closest_rp = plg.get_nearest_edge_road_point(selection, camera, event.position)
			if closest_rp:
				target = closest_rp
			else:
				hover_point = point
				point = null # nothing to point from, so skip below on what we're pointing to
		elif selection is RoadManager:
			point = null
			target = null
		elif selection is RoadPoint:
			target = selection
		elif selection is RoadIntersection:
			# TODO: Update to act the same as target selection once functional
			point = null
			target = null
		else:
			point = null
			target = null
		
		if is_instance_valid(hover_point) and not is_instance_valid(target):
			var hover_cnct:bool = hover_point.is_prior_connected() and hover_point.is_next_connected()
			if not hover_cnct and src_is_contianer and not selection.is_subscene():
				# If the current selection is a same-scene container, and the user
				# hovers over another container with open connections, offer to
				# create a new RoadPoint in the *selected* container that attaches
				# to the *hovering* container. Confusing, but intuitive in practice
				# as it allows you to create roads easily *between* prefab scenes.
				_overlay_rp_hovering = hover_point # the selected non saved-scene container.
				_overlay_rp_selected = null  # Selection is an RC, not an RP. RP to be created
				_overlay_hovering_pos = camera.unproject_position(hover_point.global_transform.origin)
				_overlay_hint_disconnect = false
				_overlay_hint_connection = true
			else:
				_overlay_rp_selected = null
				_overlay_rp_hovering = null
				_overlay_hovering_pos = event.position
				_overlay_hint_disconnect = false
				_overlay_hint_connection = false
		elif is_instance_valid(point) and is_instance_valid(target):
			_overlay_hovering_from = camera.unproject_position(target.global_transform.origin)
			_overlay_rp_hovering = point
			_overlay_hovering_pos = camera.unproject_position(point.global_transform.origin)
			var target_prior_cnct:bool = target.is_prior_connected()
			var target_next_cnct:bool = target.is_next_connected()
			var hover_cnct:bool = point.is_prior_connected() and point.is_next_connected()

			if target == point:
				_overlay_rp_selected = null
				_overlay_rp_hovering = null
				_overlay_hint_disconnect = false
				_overlay_hint_connection = false
			elif src_is_contianer and point and point.container == selection:
				# If a container is selected, don't (dis)connect internal rp's to itself.
				_overlay_rp_selected = null
				_overlay_rp_hovering = null
				_overlay_hint_disconnect = false
				_overlay_hint_connection = false
			elif target.get_prior_road_node() == point:
				# If this pt is directly connected to the target, offer quick dis-connect tool
				_overlay_rp_selected = target
				_overlay_hint_disconnect = true
				_overlay_hint_connection = false
			elif target.get_next_road_node() == point:
				# If this pt is directly connected to the selection, offer quick dis-connect tool
				_overlay_rp_selected = target
				_overlay_hint_disconnect = true
				_overlay_hint_connection = false
			elif not hover_cnct and src_is_contianer and not selection.is_subscene():
				# If the current selection is a same-scene container, and the user
				# hovers over another container with open connections, offer to
				# create a new RoadPoint in the *selected* container that attaches
				# to the *hovering* container. Confusing, but intuitive in practice
				# as it allows you to create roads easily *between* prefab scenes.
				_overlay_rp_hovering = point # the closest hovering non subscene container RP.
				_overlay_rp_selected = null  # Selection is an RC, not an RP. RP to be created
				_overlay_hint_disconnect = false
				_overlay_hint_connection = true
			elif target_prior_cnct and target_next_cnct:
				# Fully connected roadpoint, nothing to do.
				# In the future, this could be a mode to convert into an intersection
				_overlay_rp_selected = null
				_overlay_rp_hovering = null
				_overlay_hint_disconnect = false
				_overlay_hint_connection = false
			else:
				# Open connection scenario
				_overlay_rp_selected = target # could be the selection, or child of selected container
				_overlay_hint_disconnect = false
				_overlay_hint_connection = true
		else:
			_overlay_rp_selected = null
			_overlay_rp_hovering = null
			_overlay_hovering_pos = event.position
			_overlay_hint_disconnect = false
			_overlay_hint_connection = false
		plg.update_overlays()
		# Consume the event no matter what.
		return INPUT_PASS

	elif not event is InputEventMouseButton:
		return INPUT_PASS
	elif not event.button_index == MOUSE_BUTTON_LEFT:
		return INPUT_PASS
	elif not event.pressed:
		return INPUT_STOP
	# Should consume all left click operation hereafter.

	var selection = plg.get_selected_node()

	if _overlay_hint_disconnect:
		plg._disconnect_rp_on_click(selection, _overlay_rp_hovering)
	elif _overlay_hint_connection and selection is RoadContainer:
		# Case of hovering over another container, so we want to add a new RoadPoint
		# and connect it
		plg._add_and_connect_rp(selection, _overlay_rp_hovering)
	elif _overlay_hint_connection:
		#print("Connect: %s to %s" % [selection.name, _overlay_rp_hovering.name])
		plg._connect_rp_on_click(_overlay_rp_selected, _overlay_rp_hovering)
	else:
		var res:Array = plg.get_click_point_with_context(camera, event.position, selection)
		var pos:Vector3 = res[0]
		var nrm:Vector3 = res[1]

		if selection is RoadContainer and selection.is_subscene():
			plg._add_next_rp_on_click(pos, nrm, selection.get_manager())
		elif selection is RoadPoint and selection.is_next_connected() and selection.is_prior_connected():
			plg._add_next_rp_on_click(pos, nrm, selection.container)
		else:
			plg._add_next_rp_on_click(pos, nrm, selection)
	return INPUT_STOP


func _handle_delete_mode_input(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventMouseMotion or event is InputEventPanGesture:
		var point: RoadGraphNode = plg.get_nearest_graph_node(camera, event.position)
		var selection:Node = plg.get_selected_node()
		_overlay_hovering_from = camera.unproject_position(selection.global_transform.origin)
		var mouse_dist = event.position.distance_to(_overlay_hovering_from)
		var max_dist:= 50.0 # ie only auto suggest deleting RP if it's within this dist to mouse.
		if point and point.container.is_subscene():
			# Don't offer changing saved scenes in any way.
			_overlay_rp_hovering = null
			_overlay_hovering_pos = Vector2(-1, -1)
			_overlay_hint_delete = false
		elif point:
			_overlay_rp_hovering = point
			_overlay_hovering_pos = camera.unproject_position(point.global_transform.origin)
			_overlay_hint_delete = true
		elif selection is RoadPoint and not selection.prior_pt_init and not selection.next_pt_init and mouse_dist < max_dist:
			_overlay_rp_hovering = selection
			_overlay_hovering_pos = _overlay_hovering_from
			_overlay_hint_delete = true
		else:
			_overlay_rp_hovering = null
			_overlay_hovering_pos = Vector2(-1, -1)
			_overlay_hint_delete = false
		plg.update_overlays()
		return INPUT_PASS
	elif not event is InputEventMouseButton:
		return INPUT_PASS
	elif not event.button_index == MOUSE_BUTTON_LEFT:
		return INPUT_PASS
	elif event.pressed and _overlay_rp_hovering != null:
		# Always match what the UI is showing
		plg._delete_rp_on_click(_overlay_rp_hovering)
	return INPUT_STOP


#endregion
# ------------------------------------------------------------------------------
