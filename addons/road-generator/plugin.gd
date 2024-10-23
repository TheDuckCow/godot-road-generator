@tool
## Road and Highway generator addon.
extends EditorPlugin

enum SnapState {
	IDLE,
	SNAPPING,
	UNSNAPPING,
	MOVING,
	CANCELING,
}

const RoadPointGizmo = preload("res://addons/road-generator/ui/road_point_gizmo.gd")
const RoadPointEdit = preload("res://addons/road-generator/ui/road_point_edit.gd")
const RoadToolbar = preload("res://addons/road-generator/ui/road_toolbar.tscn")

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

# Forwards the InputEvent to other EditorPlugins.
const INPUT_PASS := EditorPlugin.AFTER_GUI_INPUT_PASS
# Prevents the InputEvent from reaching other Editor classes.
const INPUT_STOP := EditorPlugin.AFTER_GUI_INPUT_STOP
const ROADPOINT_SNAP_THRESHOLD := 25.0


var tool_mode # Will be a value of: RoadToolbar.InputMode.SELECT

var road_point_gizmo = RoadPointGizmo.new(self)
var road_point_editor = RoadPointEdit.new(self)
var _road_toolbar
var _edi = get_editor_interface()
var _eds = get_editor_interface().get_selection()
var _last_point: Node
var _last_lane: Node
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

var _new_selection: Node # RoadPoint or RoadContainer

var _edi_debug := false

# For use by road_point_edit and panel, keys are props on RoadPoint
var copy_attributes:Dictionary = {}


func _enter_tree():
	add_node_3d_gizmo_plugin(road_point_gizmo)
	add_inspector_plugin(road_point_editor)
	road_point_editor.call("set_edi", _edi)
	_eds.connect("selection_changed", Callable(self, "_on_selection_changed"))
	_eds.connect("selection_changed", Callable(road_point_gizmo, "on_selection_changed"))
	connect("scene_changed", Callable(self, "_on_scene_changed"))
	connect("scene_closed", Callable(self, "_on_scene_closed"))

	# Don't add the following, as they would result in repeast in the UI.
	#add_custom_type("RoadPoint", "Spatial", preload("road_point.gd"), preload("road_point.png"))
	#add_custom_type("RoadContainer", "Spatial", preload("road_container.gd"), preload("road_segment.png"))
	#add_custom_type("RoadLane", "Curve3d", preload("lane_segment.gd"), preload("road_segment.png"))

	var gui = get_editor_interface().get_base_control()
	_road_toolbar = RoadToolbar.instantiate()
	_road_toolbar.gui = gui
	_road_toolbar.update_icons()

	# Update toolbar connections
	_road_toolbar.mode_changed.connect(_on_mode_change)

	# Initial mode
	tool_mode = _road_toolbar.InputMode.SELECT


func _exit_tree():
	_eds.disconnect("selection_changed", Callable(self, "_on_selection_changed"))
	_eds.disconnect("selection_changed", Callable(road_point_gizmo, "on_selection_changed"))
	disconnect("scene_changed", Callable(self, "_on_scene_changed"))
	disconnect("scene_closed", Callable(self, "_on_scene_closed"))
	_road_toolbar.queue_free()
	remove_node_3d_gizmo_plugin(road_point_gizmo)
	remove_inspector_plugin(road_point_editor)

	# Don't add the following, as they would result in repeast in the UI.
	#remove_custom_type("RoadPoint")
	#remove_custom_type("RoadContainer")
	#remove_custom_type("RoadLane")


# ------------------------------------------------------------------------------
# EditorPlugin overriden methods
# ------------------------------------------------------------------------------


## Called by the engine when the 3D editor's viewport is updated.
func _forward_3d_draw_over_viewport(overlay: Control):

	var selected = _overlay_rp_selected
	var rad_size := 10.0
	var col:Color

	# White margin background
	var margin := 3
	var white_col = Color(1, 1, 1, 0.9)

	if tool_mode == _road_toolbar.InputMode.SELECT and _snapping == SnapState.IDLE:
		return
	elif tool_mode == _road_toolbar.InputMode.SELECT:
		# Set the drawing color
		if _overlay_hint_disconnect:
			col = Color.CORAL
		else:
			col = Color.AQUA

		# Treat Snapping and Unsnapping differently. When Snapping, show a line
		# between the two closest points. When Unsnapping, show lines between
		# all connected points that will be Unsnapped.
		if _snapping == SnapState.SNAPPING:
#			col = Color.cadetblue
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
#			return
	elif tool_mode == _road_toolbar.InputMode.DELETE:
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
		return

	# Add mode
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


## Handle or pass on event in the 3D editor
## If return true, consumes the event, otherwise forwards event
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	var ret := 0

	var selected = get_selected_node()
	var relevant = is_road_node(selected)

	# TODO: Modifier key like control or option to toggle between select & add.

	if not relevant or tool_mode == _road_toolbar.InputMode.SELECT:
		ret = _handle_gui_select_mode(camera, event)
	elif tool_mode == _road_toolbar.InputMode.ADD:
		ret = _handle_gui_add_mode(camera, event)
	elif tool_mode == _road_toolbar.InputMode.DELETE:
		ret = _handle_gui_delete_mode(camera, event)

	return ret


# ------------------------------------------------------------------------------
# Utilities
# ------------------------------------------------------------------------------


## Identifies roads relevant for built in toolbar operations.
func is_road_node(node: Node) -> bool:
	# Not counting RoadLane, since they are just native curves with extra draws
	return (node is RoadPoint
		or node is RoadContainer
		or node is RoadManager
		or node is RoadIntersection)


func _handle_gui_select_mode(camera: Camera3D, event: InputEvent) -> int:
	# Event triggers on both press and release. Ignore press and only act on
	# release. Also, ignore right-click and middle-click.
#	if (not event is InputEventMouseButton) and (not event is InputEventMouseMotion):
#		return INPUT_PASS
	var selected = get_selected_node()
	var lmb_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var ctrl_pressed = Input.is_key_pressed(KEY_CTRL)
	var shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and _snapping:
		# If user clicks RMB while snapping, then cancel snapping
		_snapping = SnapState.IDLE
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
				_snap_to_road_point_future(selected, sel_rp, tgt_rp, _snapping==SnapState.CANCELING)
			elif _snapping == SnapState.UNSNAPPING:
				# Disconnect Edge RoadPoints
				_unsnap_container_future(selected)
			# Clear overlays and snapping/unsnapping condition
			_snapping = SnapState.IDLE
			_overlay_hint_disconnect = false
			_overlay_hint_connection = false
			update_overlays()

			return INPUT_PASS  # Is a drag event

		elif _press_init_pos != event.position:
			return INPUT_PASS  # Is a drag even

		# Shoot a ray and see if it hits anything
		var point = get_nearest_road_point(camera, event.position)
		if point and not event.pressed:
			# Using this method creates a conflcit with builtin drag n drop & 3d gizmo usage
			#set_selection(point)
			#_on_selection_changed()

			if point.container.is_subscene():
				_new_selection = point.container
			else:
				_new_selection = point
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
			update_overlays()
			return INPUT_PASS

		# If container doesn't have Edge connections then snap/connect an Edge.
		# Get all usable Edge RoadPoints in selected container
		var sel_rp_edges: Array = selected.get_open_edges()
		if not len(sel_rp_edges) > 0:
			return INPUT_PASS

		# Iterate remaining RoadContainers in scene and find RoadPoint
		# closest to the RoadPoints in the selected container.
		var containers: Array = selected.get_all_road_containers(_edi.get_edited_scene_root())
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
			update_overlays()
		else:
			_snapping = SnapState.IDLE

		return INPUT_PASS
	return INPUT_PASS


## Handle adding new RoadPoints, connecting, and disconnecting RoadPoints
func _handle_gui_add_mode(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventMouseMotion or event is InputEventPanGesture:
		# Handle updating UI overlays to indicate what would happen on click.

		## TODO: if pressed state, then use this to update the in/out mag handles
		# Pressed state not available here, need to track state separately.
		# Handle visualizing which connections are free to make
		# trigger overlay updates to draw/update indicators
		var point = get_nearest_road_point(camera, event.position)
		var selection = get_selected_node()
		var src_is_contianer := false
		var target:RoadPoint

		if selection is RoadContainer:
			src_is_contianer = true
			var closest_rp = get_nearest_edge_road_point(selection, camera, event.position)
			if closest_rp:
				target = closest_rp
			else:
				point = null # nothing to point from, so skip below on what we're pointing to
		elif selection is RoadManager:
			point = null
			target = null
		elif selection is RoadPoint:
			target = selection
		else:
			point = null
			target = null

		if is_instance_valid(point) and is_instance_valid(target):
			_overlay_hovering_from = camera.unproject_position(target.global_transform.origin)
			_overlay_rp_hovering = point
			_overlay_hovering_pos = camera.unproject_position(point.global_transform.origin)

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
			elif target.get_prior_rp() == point:
				# If this pt is directly connected to the target, offer quick dis-connect tool
				_overlay_rp_selected = target
				_overlay_hint_disconnect = true
				_overlay_hint_connection = false
			elif target.get_next_rp() == point:
				# If this pt is directly connected to the selection, offer quick dis-connect tool
				_overlay_rp_selected = target
				_overlay_hint_disconnect = true
				_overlay_hint_connection = false
			elif target.is_prior_connected() and target.is_next_connected():
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
		update_overlays()
		# Consume the event no matter what.
		return INPUT_PASS

	if not event is InputEventMouseButton:
		return INPUT_PASS
	if not event.button_index == MOUSE_BUTTON_LEFT:
		return INPUT_PASS
	if not event.pressed:
		return INPUT_STOP
	# Should consume all left click operation hereafter.

	var selection = get_selected_node()

	if _overlay_hint_disconnect:
		_disconnect_rp_on_click(selection, _overlay_rp_hovering)
	elif _overlay_hint_connection:
		#print("Connect: %s to %s" % [selection.name, _overlay_rp_hovering.name])
		_connect_rp_on_click(_overlay_rp_selected, _overlay_rp_hovering)
	else:
		var res := get_click_point_with_context(camera, event.position, selection)
		var pos:Vector3 = res[0]
		var nrm:Vector3 = res[1]

		if selection is RoadContainer and selection.is_subscene():
			_add_next_rp_on_click(pos, nrm, selection.get_manager())
		else:
			_add_next_rp_on_click(pos, nrm, selection)
	return INPUT_STOP


func _handle_gui_delete_mode(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventMouseMotion or event is InputEventPanGesture:
		var point = get_nearest_road_point(camera, event.position)
		var selection = get_selected_node()
		_overlay_hovering_from = camera.unproject_position(selection.global_transform.origin)
		var mouse_dist = event.position.distance_to(_overlay_hovering_from)
		var max_dist = 50 # ie only auto suggest deleting RP if it's within this dist to mouse.
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
		update_overlays()
		return INPUT_PASS
	if not event is InputEventMouseButton:
		return INPUT_PASS
	if not event.button_index == MOUSE_BUTTON_LEFT:
		return INPUT_PASS
	if event.pressed and _overlay_rp_hovering != null:
		# Always match what the UI is showing
		_delete_rp_on_click(_overlay_rp_hovering)
	return INPUT_STOP


## Render the editor indicators for RoadPoints and RoadLanes if selected.
func _on_selection_changed() -> void:
	var selected_node = get_selected_node()

	if _new_selection:
		set_selection(_new_selection)
		selected_node = _new_selection
		_new_selection = null
	elif not selected_node:
		_hide_road_toolbar()
		return

	if _last_lane and is_instance_valid(_last_lane):
		_last_lane.show_fins(false)

	if selected_node is RoadPoint:
		_last_point = selected_node
		# selected_node.on_transform() # Creates duplicate rebuilds.
	elif selected_node is RoadLane:
		_last_lane = selected_node
		_last_lane.show_fins(true)

	# Show the panel even if selection is scene root, but not if selection is a
	# scene instance itself (non editable).
	# TOOD: Change show/hide to occur on button-release, for consistency with internal panels.
	var eligible = is_road_node(selected_node)
	var non_instance = true
	if eligible and non_instance:
		_show_road_toolbar()
	else:
		_hide_road_toolbar()


func _on_scene_changed(scene_root: Node) -> void:
	var selected = get_selected_node()
	var eligible = is_road_node(selected)
	if selected and eligible:
		_show_road_toolbar()
	else:
		_hide_road_toolbar()


func _on_scene_closed(_value) -> void:
	_hide_road_toolbar()


func _on_mode_change(_mode: int) -> void:
	tool_mode = _mode  # Instance of RoadToolbar.InputMode


func refresh() -> void:
	get_editor_interface().get_inspector().refresh()


# ------------------------------------------------------------------------------
# Selection utilities
# ------------------------------------------------------------------------------


## Returns the primary selection or null if nothing is selected
func get_selected_node() -> Node:
	# TODO: Update this algorithm to figure out which node is really the
	# primary selection rather than always assuming index 0 is the selection.
	var selected_nodes = _eds.get_selected_nodes()
	if not selected_nodes.is_empty():
		return selected_nodes[0]
	else:
		return null


## Returns the next highest level RoadManager from current primary selection.
func get_manager_from_selection(): # -> Optional[RoadManager]
	var selected_node = get_selected_node()

	if not is_instance_valid(selected_node):
		push_error("Invalid selection to add road segment")
		return
	elif selected_node is RoadManager:
		return selected_node
	elif selected_node is RoadContainer:
		return selected_node.get_manager()
	elif selected_node is RoadPoint:
		if is_instance_valid(selected_node.container):
			return selected_node.container.get_manager()
		else:
			push_error("Invalid RoadContainer instance for RoadPoint's parent")
			return
	push_warning("No relevant Road* node selected")
	return


## Gets the RoadContainer from selection of either roadcontainer or roadpoint.
func get_container_from_selection(): # -> Optional[RoadContainer]
	var selected_node = get_selected_node()
	var t_container = null

	if not is_instance_valid(selected_node):
		push_error("Invalid selection to add road segment")
		return
	if selected_node is RoadContainer:
		return selected_node
	elif selected_node is RoadPoint:
		if is_instance_valid(selected_node.container):
			return selected_node.container
		else:
			push_error("Invalid container for roadpoint")
			return
	else:
		push_warning("Invalid selection for adding new road segments")
		return


func select_road_point(point) -> void:
	_last_point = point
	_edi.get_selection().clear()
	_edi.edit_node(point)
	_edi.get_selection().add_node(point)
	point.on_transform()
	_show_road_toolbar()


## Utility for easily selecting a node in the editor.
func set_selection(node: Node) -> void:
	_edi.get_selection().clear()
	_edi.get_selection().add_node(node)
	_edi.edit_node(node) # Necessary?


func set_selection_list(nodes: Array) -> void:
	_edi.get_selection().clear()
	for _nd in nodes:
		_edi.get_selection().add_node(_nd)
		_edi.edit_node(_nd)


## Gets nearest RoadPoint if user clicks a Segment. Returns RoadPoint or null.
func get_nearest_road_point(camera: Camera3D, mouse_pos: Vector2) -> RoadPoint:
	var src = camera.project_ray_origin(mouse_pos)
	var nrm = camera.project_ray_normal(mouse_pos)
	var dist = camera.far

	var space_state = get_viewport().world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(src, src + nrm * dist)
	var intersect = space_state.intersect_ray(query)

	if intersect.is_empty():
		return null
	else:
		var collider = intersect["collider"]
		var position = intersect["position"]
		if not collider.name.begins_with("road_mesh_col"):
			return null
		else:
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


## Get the nearest edge RoadPoint for the given container
func get_nearest_edge_road_point(container: RoadContainer, camera: Camera3D, mouse_pos: Vector2):
	if _edi_debug:
		print_debug("get_nearest_edge_road_point")

	var closest_rp:RoadPoint
	var closest_dist: float
	for pth in container.edge_rp_locals:
		var rp = container.get_node(pth)
		#print("\tChecking dist to %s" % rp.name)
		if not is_instance_valid(rp):
			continue
		# TODO: check if this point is behind the camera, ignore
		var cam2rp = rp.global_transform.origin - camera.global_transform.origin
		if camera.global_transform.basis.z.dot(cam2rp) > 0: # fwd is -z
				continue
		var rp_screen_pos:Vector2 = camera.unproject_position(rp.global_transform.origin)
		var this_dist = mouse_pos.distance_squared_to(rp_screen_pos)
		#print("\trp_screen_pos: %s:%s - %s to mouse at %s" % [
		#	rp.name, rp_screen_pos, this_dist, mouse_pos])
		if not closest_dist or this_dist < closest_dist:
			closest_dist = this_dist
			closest_rp = rp
	return closest_rp


## Convert a given click to the nearest, best fitting 3d pos + normal for click.
##
## Includes selection node so that if there's no intersection made, we can still
## raycast onto the xz  or screen xy local plane of the object clicked on.
##
## Returns: [Position, Normal]
func get_click_point_with_context(camera: Camera3D, mouse_pos: Vector2, selection: Node) -> Array:
	var src = camera.project_ray_origin(mouse_pos)
	var nrm = camera.project_ray_normal(mouse_pos)
	var dist = camera.far

	var space_state = get_viewport().world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(src, src + nrm * dist)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var intersect = space_state.intersect_ray(query)
	# Unfortunately, must have collide with areas off. And this doesn't pick
	# up collisions with objects that don't have collisions already added, making
	# it not as convinient for viewport manipulation.

	if not intersect.is_empty():
		return [intersect["position"], intersect["normal"]]

	# if we couldn't directly intersect with something, then place the next
	# point in the same plane as the initial selection which is also facing
	# the camera, or in the plane of that object's

	var use_obj_plane = selection is RoadPoint

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

	var hit_pt = plane.intersects_ray(src, nrm)
	var up = selection.global_transform.basis.y

	if hit_pt == null:
		point_y_offset = camera.global_transform.basis.y
		point_x_offset = camera.global_transform.basis.x
		plane = Plane(
			ref_pt,
			ref_pt + point_y_offset,
			ref_pt + point_x_offset)
		hit_pt = plane.intersects_ray(src, nrm)
		up = selection.global_transform.basis.y

	# TODO: Finally, detect if the point is behind or in front;
	# if behind, then skip action.

	return [hit_pt, up]


func _handles(object: Object):
	# Must return "true" in order to use "forward_spatial_gui_input".
	return object is Node3D


# ------------------------------------------------------------------------------
# Create menu handling
# ------------------------------------------------------------------------------


func _show_road_toolbar() -> void:
	_road_toolbar.mode = tool_mode

	if not _road_toolbar.get_parent():
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _road_toolbar)
		_road_toolbar.on_show(_eds.get_selected_nodes())

		# Utilities
		_road_toolbar.create_menu.regenerate_pressed.connect(_on_regenerate_pressed)
		_road_toolbar.create_menu.select_container_pressed.connect(_on_select_container_pressed)

		# Native nodes
		_road_toolbar.create_menu.create_container.connect(_create_container_pressed)
		_road_toolbar.create_menu.create_roadpoint.connect(_create_roadpoint_pressed)
		_road_toolbar.create_menu.create_lane.connect(_create_lane_pressed)
		_road_toolbar.create_menu.create_lane_agent.connect(_create_lane_agent_pressed)

		# Specials / prefabs
		_road_toolbar.create_menu.create_2x2_road.connect(_create_2x2_road_pressed)


func _hide_road_toolbar() -> void:
	if _road_toolbar and _road_toolbar.get_parent():
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _road_toolbar)

		# Utilities
		_road_toolbar.create_menu.regenerate_pressed.disconnect(_on_regenerate_pressed)
		_road_toolbar.create_menu.select_container_pressed.disconnect(_on_select_container_pressed)

		# Native nodes
		_road_toolbar.create_menu.create_container.disconnect(_create_container_pressed)
		_road_toolbar.create_menu.create_roadpoint.disconnect(_create_roadpoint_pressed)
		_road_toolbar.create_menu.create_lane.disconnect(_create_lane_pressed)
		_road_toolbar.create_menu.create_lane_agent.disconnect(_create_lane_agent_pressed)

		# Specials / prefabs
		_road_toolbar.create_menu.create_2x2_road.disconnect(_create_2x2_road_pressed)


func _on_regenerate_pressed() -> void:
	var nd = get_selected_node()
	if nd is RoadManager:
		for ch_container in nd.get_containers():
			ch_container.rebuild_segments(true)
		return
	var t_container = get_container_from_selection()
	if t_container:
		t_container.rebuild_segments(true)
		return


func _on_select_container_pressed():
	var t_container = get_container_from_selection()
	set_selection(t_container)


## Adds a RoadContainer as a child, and if an existing road container or
## RoadPoint is selected, it is set as the 'next' RoadContainer.
func _create_container_pressed() -> void:
	var undo_redo = get_undo_redo()
	var t_manager = get_manager_from_selection()
	if not is_instance_valid(t_manager):
		push_error("Invalid selection context")
		return

	var init_sel = get_selected_node()
	# if init_sel is RoadPoint: and is an "edge" roadpoint,

	undo_redo.create_action("Add RoadContainer")
	undo_redo.add_do_method(self, "_create_road_container_do", t_manager, init_sel)
	undo_redo.add_undo_method(self, "_create_road_container_undo", t_manager, init_sel)
	undo_redo.commit_action()


func _create_road_container_do(t_manager: RoadManager, init_sel: Node) -> void:
	var default_name = "Road_001"

	if not is_instance_valid(t_manager) or not t_manager is RoadManager:
		push_error("Invalid context")
		return

	# TODO: Decide where to place contaier based on initial selection, e.g. if
	# another Road

	# Add new RoadContainer at default location (World Origin)
	var t_container = RoadContainer.new()
	t_manager.add_child(t_container)
	t_container.name = RoadPoint.increment_name(default_name)

	if get_tree().get_edited_scene_root() == t_manager:
		t_container.set_owner(t_manager)
	else:
		t_container.set_owner(t_manager.owner)
	t_container.setup_road_container()
	set_selection(t_container)


func _create_road_container_undo(selected_node: Node, init_sel: Node) -> void:
	# Make a likely bad assumption that the last child is the one to
	# be undone, but this is likely quite flakey.
	# TODO: Perform proper undo/redo support, ideally getting add_do_reference
	# to work property (failed when attempted so far).
	var initial_children = selected_node.get_children()
	if len(initial_children) == 0:
		return

	if initial_children[-1] is RoadContainer:
		initial_children[-1].queue_free()


func _add_next_rp_on_click(pos: Vector3, nrm: Vector3, selection: Node) -> void:
	var undo_redo = get_undo_redo()

	if not is_instance_valid(selection):
		push_error("Invalid selection selection, not valid node")
		return

	var parent: Node
	var _sel: Node
	var add_container = false
	var t_manager: Node = null
	var handle_mag:float = 0
	if selection is RoadPoint:
		parent = selection.get_parent()
		if selection.next_pt_init and selection.prior_pt_init:
			print("Fully connected already")
			# already fully connected, so for now add as just a standalone pt
			# TODO: In the future, this should create an intersection.
			_sel = parent
		else:
			_sel = selection

			var road_width = _sel.lane_width * len(_sel.lanes)
			var dist:float = pos.distance_to(_sel.global_transform.origin) / 2.0
			handle_mag = max(road_width, dist)
	elif selection is RoadContainer:
		parent = selection
		_sel = selection
	elif selection is RoadManager:
		add_container = true
		t_manager = selection
		_sel = selection
	else: # RoadManager or RoadLane.
		push_error("Invalid selection context, need RoadContainer parent")
		return

	if add_container:
		undo_redo.create_action("Add RoadContainer")
		undo_redo.add_do_method(self, "_create_road_container_do", t_manager, selection)
		undo_redo.add_undo_method(self, "_create_road_container_undo", t_manager, selection)
	else:
		undo_redo.create_action("Add next RoadPoint")
		if handle_mag > 0:
			if not selection.next_pt_init:
				undo_redo.add_do_property(_sel, "next_mag", handle_mag)
				undo_redo.add_undo_property(_sel, "next_mag", _sel.next_mag)
			elif not selection.prior_pt_init:
				undo_redo.add_do_property(_sel, "prior_mag", handle_mag)
				undo_redo.add_undo_property(_sel, "prior_mag", _sel.prior_mag)
		if selection is RoadPoint and not selection.next_pt_init and not selection.prior_pt_init:
			# Special case: the starting point is not connected to anything, then the user is
			# probably wanting it to be rotated towards the new point being placed anyways
			undo_redo.add_do_method(selection, "look_at", pos, selection.global_transform.basis.y)
			undo_redo.add_undo_property(selection, "global_transform", selection.global_transform)
		undo_redo.add_do_method(self, "_add_next_rp_on_click_do", pos, nrm, _sel, parent, handle_mag)
		if parent is RoadContainer:
			undo_redo.add_do_method(self, "_call_update_edges", parent)
			undo_redo.add_undo_method(self, "_call_update_edges", parent)
		undo_redo.add_undo_method(self, "_add_next_rp_on_click_undo", pos, _sel, parent)

	undo_redo.commit_action()


func _call_update_edges(container: RoadContainer) -> void:
	container.update_edges()


func _add_next_rp_on_click_do(pos: Vector3, nrm: Vector3, selection: Node, parent: Node, handle_mag: float) -> void:

	var next_rp = RoadPoint.new()
	var adding_to_next = true
	var dirvec: Vector3 = pos - selection.global_transform.origin

	if selection is RoadPoint:
		next_rp.name = selection.name # TODO: increment

		if selection.prior_pt_init and selection.next_pt_init:
			parent.add_child(next_rp)
			adding_to_next = true #??
			# Both populated (assume valid), so place this as disconnected.
			# TOOD in future: turn these all into an intersection?
			# or make it a sort of "add point in middle" situation? ie somehwere
			# along the curve of the existing road.
		elif selection.prior_pt_init:
			selection.add_road_point(next_rp, RoadPoint.PointInit.NEXT)
			adding_to_next = true
		elif selection.next_pt_init:
			selection.add_road_point(next_rp, RoadPoint.PointInit.PRIOR)
			adding_to_next = false
		else:
			# Neither connection exists, so pick next or prior based on basis.
			var dir = selection.global_transform.basis.z.dot(dirvec)
			var do_dir
			if dir > 0:
				do_dir = RoadPoint.PointInit.NEXT
				adding_to_next = true
			else:
				do_dir = RoadPoint.PointInit.PRIOR
				adding_to_next = false
			selection.add_road_point(next_rp, do_dir)

		if handle_mag > 0:
			next_rp.prior_mag = handle_mag
			next_rp.next_mag = handle_mag

		# Update rotation along the initially picked axis.
	elif selection is RoadContainer:
		next_rp.name = "RP_001"  # TODO: define this in some central area.
		var _lanes:Array[RoadPoint.LaneDir] = [
			RoadPoint.LaneDir.REVERSE,
			RoadPoint.LaneDir.REVERSE,
			RoadPoint.LaneDir.FORWARD,
			RoadPoint.LaneDir.FORWARD
		]
		next_rp.traffic_dir = _lanes
		next_rp.auto_lanes = true
		parent.add_child(next_rp)
		next_rp.set_owner(get_tree().get_edited_scene_root())

	# Make the road visible halfway above the ground by the gutter height amount.
	if nrm == Vector3.ZERO:
		pass
	else:
		var half_gutter: float = -0.5 * next_rp.gutter_profile.y
		next_rp.global_transform.origin = pos + nrm * half_gutter

		# Rotate this rp towards the initial selected node
		if selection is RoadPoint:
			var look_pos = selection.global_transform.origin
			if not adding_to_next:
				# Essentially flip the look 180 so it's not twisted around.
				look_pos += 2 * dirvec
			# Increase the angle a bit more based on the selected's magnitude,
			# to result in a more natural rotation to ensure the curve doesn't
			# look like it doubles back.
			if adding_to_next:
				look_pos += selection.global_transform.basis.z * selection.next_mag
			else:
				look_pos += selection.global_transform.basis.z * selection.prior_mag
			next_rp.look_at(look_pos, nrm)

	set_selection(next_rp)


## Assume, potentially badly, that last node is the one to delete
func _add_next_rp_on_click_undo(pos, selection, parent: Node) -> void:
	var initial_children = parent.get_children()
	if len(initial_children) < 1:
		return

	var prior_selection
	var was_next_pt: bool

	# Each RoadPoint handles their own cleanup of connected RoadSegments.
	if not initial_children[-1] is RoadPoint:
		return
	var added_node = initial_children[-1]
	if added_node.prior_pt_init:
		prior_selection = added_node.get_node(added_node.prior_pt_init)
		was_next_pt = true
	elif added_node.next_pt_init:
		prior_selection = added_node.get_node(added_node.next_pt_init)
		was_next_pt = false
	initial_children[-1].queue_free()

	if is_instance_valid(prior_selection):
		# Clean up the new old connection.
		if was_next_pt:
			prior_selection.next_pt_init = ""
		else:
			prior_selection.prior_pt_init = ""
		set_selection(prior_selection)


func _connect_rp_on_click(rp_a, rp_b):
	var undo_redo = get_undo_redo()
	var init_sel = get_selected_node()
	if not rp_a is RoadPoint or not rp_b is RoadPoint:
		push_error("Cannot connect non-roadpoints")
		return

	var from_dir
	var target_dir
	# Starting point is current selection.
	if rp_a.prior_pt_init and rp_a.next_pt_init:
		print("Cannot connect, fully connected")
		return true
	elif rp_a.prior_pt_init:
		from_dir = RoadPoint.PointInit.NEXT # only next open
	elif rp_a.next_pt_init:
		from_dir = RoadPoint.PointInit.PRIOR # only prior open
	else:
		var rel_vec = rp_b.global_transform.origin - rp_a.global_transform.origin
		if rp_a.global_transform.basis.z.dot(rel_vec) > 0:
			from_dir = RoadPoint.PointInit.NEXT
		else:
			from_dir = RoadPoint.PointInit.PRIOR

	if rp_b.prior_pt_init and rp_b.next_pt_init:
		print("Cannot connect, fully connected")
		return true
	elif rp_b.prior_pt_init:
		target_dir = RoadPoint.PointInit.NEXT # only next open
	elif rp_b.next_pt_init:
		target_dir = RoadPoint.PointInit.PRIOR # only prior open
	else:
		var rel_vec = rp_a.global_transform.origin - rp_b.global_transform.origin
		if rp_b.global_transform.basis.z.dor(rel_vec) > 0:
			target_dir = RoadPoint.PointInit.NEXT
		else:
			target_dir = RoadPoint.PointInit.PRIOR

	# Finally, determine if we are doing a intra- or inter-RoadContainer
	var inter_container: bool = rp_a.container != rp_b.container

	if inter_container:
		undo_redo.create_action("Connect RoadContainers")
		var add_point = false
		var new_rp = null # new one we might be adding
		var parent = null
		var from_rp = null # the one in the same container it'll connect to.
		var cross_rp = null # the one in another container
		var flip_inputs = false # condition where we needed to do some switching around, empirically.

		if rp_a.global_transform.origin == rp_b.global_transform.origin:
			# They are already in the same position, so we should not add a new RP anyways.
			# TODO: Could also check for rotation being aligned.
			pass
		elif rp_a.container.is_subscene() and rp_b.container.is_subscene():
			push_warning("Connected RoadContainer of saved scenes may not visually appaer connected")
			# TODO: Create a new container in the middle which connects these two,
			# or offer to snape one to the other.
		elif rp_a.container.is_subscene():
			# If THIS container (A) is a subscene, create new point in container B, at A's position
			add_point = true
			new_rp = RoadPoint.new()
			parent = rp_b.container
			from_rp = rp_b
			cross_rp = rp_a

			# Hack workaround, to get right combination below, since we're
			# effectively swapping to as though the user flipped which was
			# selected vs hovering
			# TOOD: Do this more gracefully than this if/else.
			flip_inputs = true
		else:
			# rp_b is a saved scene, or *neither* is a saved scene.
			# In both cases, make new child of container A (current selection)
			add_point = true
			new_rp = RoadPoint.new()
			parent = rp_a.container
			from_rp = rp_a
			cross_rp = rp_b

		# In all cases, make sure we do the connection
		if add_point:
			new_rp.name = from_rp.name
			undo_redo.add_do_reference(new_rp)
			undo_redo.add_do_method(parent, "add_child", new_rp, true)
			undo_redo.add_do_method(new_rp, "set_owner", get_tree().get_edited_scene_root())
			undo_redo.add_do_method(new_rp, "copy_settings_from", cross_rp)

			var flip_target_dir = RoadPoint.PointInit.NEXT if target_dir == RoadPoint.PointInit.PRIOR else RoadPoint.PointInit.PRIOR
			var flip_from_dir = RoadPoint.PointInit.NEXT if from_dir == RoadPoint.PointInit.PRIOR else RoadPoint.PointInit.PRIOR

			if flip_inputs:
				# Connect existing container rp to this newly created one
				undo_redo.add_do_method(from_rp, "connect_roadpoint", flip_from_dir, new_rp, flip_target_dir)
				# using target + flipped target, as the newly added point has orientation matching pt of other container
				undo_redo.add_do_method(new_rp, "connect_container", target_dir, cross_rp, flip_target_dir)
			else:
				# Connect existing container rp to this newly created one
				undo_redo.add_do_method(from_rp, "connect_roadpoint", from_dir, new_rp, target_dir)
				# using flipped target + target, as the newly added point has orientation matching pt of other container
				undo_redo.add_do_method(new_rp, "connect_container", flip_target_dir, cross_rp, target_dir)

			undo_redo.add_do_method(self, "set_selection", new_rp)

			if flip_inputs:
				undo_redo.add_undo_method(new_rp, "disconnect_container", target_dir, flip_target_dir)
				undo_redo.add_undo_method(from_rp, "disconnect_roadpoint", flip_from_dir, flip_target_dir)
			else:
				undo_redo.add_undo_method(new_rp, "disconnect_container", flip_target_dir, target_dir)
				undo_redo.add_undo_method(from_rp, "disconnect_roadpoint", from_dir, target_dir)

			undo_redo.add_undo_method(parent, "remove_child", new_rp)
			undo_redo.add_undo_method(self, "set_selection", init_sel)
		else:
			undo_redo.add_do_method(rp_a, "connect_container", from_dir, rp_b, target_dir)
			undo_redo.add_undo_method(rp_a, "disconnect_container", from_dir, target_dir)
	else:
		undo_redo.create_action("Connect RoadPoints")
		undo_redo.add_do_method(rp_a, "connect_roadpoint", from_dir, rp_b, target_dir)
		undo_redo.add_undo_method(rp_a, "disconnect_roadpoint", from_dir, target_dir)
	undo_redo.commit_action()


func _unsnap_container_future(selected:RoadContainer):
	# TODO: this poses a problem actually, as the unsnapp now happens cleanly after the transform
	# (UI drag) has completed. For snapping this is good, as snapping takes place at the end,
	# but here we actually want the snapping to happen immediately
	if not selected is RoadContainer:
		push_warning("_unsnap_container_future should have been called with RoadContainer")
		return
	var res = selected.connect("on_transform", Callable(self, "_call_disconnect_rp_on_click"))
	assert(res == OK)


func _call_disconnect_rp_on_click(selected:RoadContainer):
	selected.disconnect("on_transform", Callable(self, "_call_disconnect_rp_on_click"))
	selected._drag_source_rp = null
	selected._drag_target_rp = null
	# For simplicity, this will disconnect all parts of the RoadContainer
	for edge in selected.get_connected_edges():
		_disconnect_rp_on_click(edge[1], edge[0])


func _disconnect_rp_on_click(rp_a, rp_b):
	var undo_redo = get_undo_redo()
	if not rp_a is RoadPoint or not rp_b is RoadPoint:
		push_error("Cannot connect non-roadpoints")
		return

	# TOOD: must handle if they belong to different RoadContainers

	var from_dir
	var target_dir
	if rp_a.get_prior_rp() == rp_b:
		from_dir = RoadPoint.PointInit.PRIOR
	elif rp_a.get_next_rp() == rp_b:
		from_dir = RoadPoint.PointInit.NEXT
	else:
		push_error("Not initially connected")
		return
	if rp_b.get_prior_rp() == rp_a:
		target_dir = RoadPoint.PointInit.PRIOR
	elif rp_b.get_next_rp() == rp_a:
		target_dir = RoadPoint.PointInit.NEXT
	else:
		push_error("Not initially connected")
		return

	# Finally, determine if we are doing a intra- or inter-RoadContainer
	var inter_container: bool = rp_a.container != rp_b.container

	undo_redo.create_action("Disconnect RoadPoints")
	if inter_container:
		undo_redo.add_do_method(rp_a, "disconnect_container", from_dir, target_dir)
		undo_redo.add_undo_method(rp_a, "connect_container", from_dir, rp_b, target_dir)
	else:
		undo_redo.add_do_method(rp_a, "disconnect_roadpoint", from_dir, target_dir)
		undo_redo.add_undo_method(rp_a, "connect_roadpoint", from_dir, rp_b, target_dir)
	undo_redo.commit_action()


func _delete_rp_on_click(selection: Node):
	var undo_redo = get_undo_redo()

	if not selection is RoadPoint:
		push_error("Selection is not a RoadPoint")
		return
	elif not is_instance_valid(selection):
		push_error("Invalid selection selection, not valid node")
		return

	var rp:RoadPoint = selection
	var container:RoadContainer = rp.container
	var prior_rp = null
	var prior_samedir: bool = true
	var next_rp = null
	var next_samedir: bool = true
	var dissolve = false
	if rp.prior_pt_init:
		prior_rp = rp.get_node(rp.prior_pt_init)
		if prior_rp.next_pt_init == prior_rp.get_path_to(rp):
			prior_samedir = true
		elif prior_rp.prior_pt_init == prior_rp.get_path_to(rp):
			prior_samedir = false
		else:
			push_warning("Should be prior connected %s" % prior_rp.name)
			pass # not actually mutually connected?
	if rp.next_pt_init:
		next_rp = rp.get_node(rp.next_pt_init)
		if next_rp.prior_pt_init == next_rp.get_path_to(rp):
			next_samedir = true
		elif next_rp.prior_pt_init == next_rp.get_path_to(rp):
			next_samedir = false
		else:
			push_warning("Should be prior connected %s" % next_rp.name)
			pass # not actually mutually connected?
	if is_instance_valid(prior_rp) and is_instance_valid(next_rp):
		# only if fully connected will it combine both sides back together
		dissolve = true

	#print("Dissolve: %s, prior %s samedir %s , next %s smaedir %s" % [
	#	dissolve, prior_rp, prior_samedir, next_rp, next_samedir])

	# Define the current editor selection for redo'ing afer an undo,
	# which could be multi selection
	var editor_selected:Array = _edi.get_selection().get_selected_nodes()

	# Define the action
	if dissolve:
		undo_redo.create_action("Dissolve RoadPoint")
	else:
		undo_redo.create_action("Delete RoadPoint")

	# Disconnect the existing RoadPoints and set updated selection
	var prior_dir = RoadPoint.PointInit.NEXT if prior_samedir else RoadPoint.PointInit.PRIOR
	var next_dir = RoadPoint.PointInit.PRIOR if next_samedir else RoadPoint.PointInit.NEXT
	if is_instance_valid(prior_rp):
		undo_redo.add_do_method(rp, "disconnect_roadpoint", RoadPoint.PointInit.PRIOR, prior_dir)
	if is_instance_valid(next_rp):
		undo_redo.add_do_method(rp, "disconnect_roadpoint", RoadPoint.PointInit.NEXT, next_dir)

	# Remove the node
	undo_redo.add_do_method(rp.get_parent(), "remove_child", rp)
	undo_redo.add_undo_method(rp.get_parent(), "add_child", rp)
	undo_redo.add_undo_method(rp, "set_owner", get_tree().get_edited_scene_root())

	# Update do/undo selections
	if is_instance_valid(next_rp):
		undo_redo.add_do_method(self, "set_selection", next_rp)
	elif is_instance_valid(prior_rp):
		undo_redo.add_do_method(self, "set_selection", prior_rp)
	else:
		undo_redo.add_do_method(self, "set_selection", rp.container)
	undo_redo.add_undo_method(self, "set_selection_list", editor_selected)

	# If in dissolve mode, connect RPs in both directions to each other
	if dissolve:
		undo_redo.add_do_method(
			prior_rp,
			"connect_roadpoint",
			prior_dir,
			next_rp,
			next_dir
		)
		undo_redo.add_undo_method(
			prior_rp,
			"disconnect_roadpoint",
			prior_dir,
			next_dir
		)
		undo_redo.add_do_method(container, "rebuild_segments", false)

	# Have to do reconnection undo steps after re-adding and un-dissolve connections
	if is_instance_valid(prior_rp):
		undo_redo.add_undo_method(rp, "connect_roadpoint", RoadPoint.PointInit.PRIOR, prior_rp, prior_dir)
	if is_instance_valid(next_rp):
		undo_redo.add_undo_method(rp, "connect_roadpoint", RoadPoint.PointInit.NEXT, next_rp, next_dir)

	undo_redo.add_undo_method(container, "rebuild_segments", false)
	undo_redo.add_undo_reference(rp)
	undo_redo.commit_action()


## When the interface is running and we realize we are about to perform a snap,
## we can't perform the action right away as then it would happen before the
## internal move action completes (and thus, someone who does control-Z would see
## the container move back but not realize it hasn't undone the connection step
## yet). So, we want to wait until after transform has been fired, then
## in the container check if these meta props are assigned, and THEN we can
## call the function there via a signal callback back to plugin
func _snap_to_road_point_future(selected:RoadContainer, sel_rp:RoadPoint, tgt_rp:RoadPoint, is_cancelling:bool):
	if is_cancelling:
		# If canceling, no undo/redo stack to worry about, so just move
		# directly (is there a consequence for that?)
		_snap_to_road_point(selected, sel_rp, tgt_rp, is_cancelling)
		return

	# selected._drag_init_transform # already be assigned
	selected._drag_source_rp = sel_rp
	selected._drag_target_rp = tgt_rp

	# Signal will be called after the transform action has completed, then auto disconnect this
	var res = selected.connect("on_transform", Callable(self, "_on_transform_complete_do_snap"))
	assert(res == OK)


## Conditionally defined callback for RoadContainer's on_transform to complete drag-snap action
func _on_transform_complete_do_snap(selected:RoadContainer):
	selected.disconnect("on_transform", Callable(self, "_on_transform_complete_do_snap"))
	var _srcrp = selected._drag_source_rp
	var _tgtrp = selected._drag_target_rp
	selected._drag_source_rp = null
	selected._drag_target_rp = null
	_snap_to_road_point(selected, _srcrp, _tgtrp, false)


## Action committing function to do road point snapping
##
## This should be called only after any translation internal event has finished
## (ie this is called after its on_transform signal has been emitted already)
func _snap_to_road_point(selected:RoadContainer, sel_rp:RoadPoint, tgt_rp:RoadPoint, is_cancelling:bool) -> void:
	var undo_redo = get_undo_redo()

	# Precalculate the snapt-to locaiton
	var res:Array = selected.get_transform_for_snap_rp(sel_rp, tgt_rp)
	var tgt_transform: Transform3D = res[0]
	var sel_dir:int = res[1]
	var tgt_dir:int = res[2]

	# This just means we're cancelling the user's movement efforts, so put back without undo
	if is_cancelling:
		sel_rp.container = tgt_transform
		return

	undo_redo.create_action("Snap RoadContainer to RoadPoint")

	undo_redo.add_do_property(sel_rp.container, "global_transform", tgt_transform)
	undo_redo.add_undo_property(sel_rp.container, "global_transform", sel_rp.container.global_transform)

	# TODO: move any sibling RoadPoints if appropriate?

	undo_redo.add_do_method(sel_rp, "connect_container", sel_dir, tgt_rp, tgt_dir)
	undo_redo.add_undo_method(sel_rp, "disconnect_container", sel_dir, tgt_dir)
	undo_redo.commit_action()


## Adds a single RoadPoint to the scene
func _create_roadpoint_pressed() -> void:
	var undo_redo = get_undo_redo()
	var t_container = get_container_from_selection()
	if not is_instance_valid(t_container):
		push_error("Invalid selection context")
		return
	
	var selected_node = get_selected_node()

	undo_redo.create_action("Add RoadPoint")
	if selected_node is RoadContainer:
		var editor_selected:Array = _edi.get_selection().get_selected_nodes()
		var rp := RoadPoint.new()
		rp.name = "RP_001"
		undo_redo.add_do_method(selected_node, "add_child", rp, true)
		undo_redo.add_do_method(rp, "set_owner", get_tree().get_edited_scene_root())
		undo_redo.add_do_method(self, "set_selection", rp)
		undo_redo.add_undo_method(selected_node, "remove_child", rp)
		undo_redo.add_undo_method(rp, "set_owner", null)
		undo_redo.add_undo_method(self, "set_selection_list", editor_selected)
		undo_redo.add_do_reference(rp)
	else:
		undo_redo.add_do_method(self, "_create_roadpoint_do", t_container)
		undo_redo.add_undo_method(self, "_create_roadpoint_undo", t_container)
	undo_redo.add_do_method(self, "_call_update_edges", t_container)
	undo_redo.add_undo_method(self, "_call_update_edges", t_container)
	undo_redo.commit_action()


## Add a RoadPoint to an existing RoadPoint
func _create_roadpoint_do(t_container: RoadContainer):
	var default_name = "RP_001"

	if not is_instance_valid(t_container) or not t_container is RoadContainer:
		push_error("Invalid RoadContainer")
		return

	# Get selected RoadPoint.
	t_container.setup_road_container()
	var selected_node = get_selected_node()
	var first_road_point: RoadPoint
	var second_road_point: RoadPoint

	if not selected_node is RoadPoint:
		print_debug("Couldn't add RoadPoint. Try selecting a RoadPoint, first.")
		return

	first_road_point = selected_node
	second_road_point = RoadPoint.new()
	second_road_point.name = second_road_point.increment_name(default_name)
	first_road_point.add_road_point(second_road_point, RoadPoint.PointInit.NEXT)
	set_selection(second_road_point)


func _create_roadpoint_undo(t_container: RoadContainer):
	# Make a likely bad assumption that the last child of the RoadContainer is
	# the one to be undone, but this is likely quite flakey.
	# TODO: Perform proper undo/redo support, ideally getting add_do_reference
	# to work property (failed when attempted so far).
	var initial_children = t_container.get_children()

	# Each RoadPoint handles their own cleanup of connected RoadSegments.
	for i in range (len(initial_children)-1, 0, -1):
		if initial_children[i] is RoadPoint:
			initial_children[i].queue_free()
			break


## Adds a 2x2 RoadSegment to the Scene
func _create_2x2_road_pressed() -> void:
	var undo_redo = get_undo_redo()
	var t_container = get_container_from_selection()

	if t_container == null:
		push_error("Could not get RoadContainer object")
		return
	if not is_instance_valid(t_container):
		push_error("Connected RoadContainer is not valid")
		return

	undo_redo.create_action("Add 2x2 road segment")
	undo_redo.add_do_method(self, "_create_2x2_road_do", t_container, false)
	undo_redo.add_undo_method(self, "_create_2x2_road_undo", t_container, false)
	undo_redo.add_do_method(t_container, "update_edges")
	undo_redo.add_undo_method(t_container, "update_edges")
	undo_redo.commit_action()


func _create_2x2_road_do(t_container: RoadContainer, single_point: bool):
	var default_name = "RP_001"

	if not is_instance_valid(t_container) or not t_container is RoadContainer:
		push_error("Invalid RoadContainer")
		return

	# Add new Segment at default location (World Origin)
	t_container.setup_road_container()
	var first_road_point = RoadPoint.new()
	t_container.add_child(first_road_point, true)
	first_road_point.name = first_road_point.increment_name(default_name)
	var new_dirs: Array[RoadPoint.LaneDir] = [
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.FORWARD,
		RoadPoint.LaneDir.FORWARD
	]
	first_road_point.traffic_dir = new_dirs
	first_road_point.auto_lanes = true
	first_road_point.set_owner(get_tree().get_edited_scene_root())

	var second_road_point = RoadPoint.new()
	second_road_point.name = second_road_point.increment_name(default_name)
	if single_point == false:
		first_road_point.add_road_point(second_road_point, RoadPoint.PointInit.NEXT)
		set_selection(second_road_point)
	else:
		set_selection(first_road_point)


func _create_2x2_road_undo(selected_node: RoadContainer, single_point: bool) -> void:
	# Make a likely bad assumption that the last two children are the ones to
	# be undone, but this is likely quite flakey.
	# TODO: Perform proper undo/redo support, ideally getting add_do_reference
	# to work property (failed when attempted so far).
	var initial_children = selected_node.get_children()
	if len(initial_children) < 2 and single_point == false:
		return
	elif len(initial_children) < 1 and single_point == true:
		return

	# Each RoadPoint handles their own cleanup of connected RoadSegments.
	if initial_children[-1] is RoadPoint:
		initial_children[-1].queue_free()
		if single_point:
			return
	if initial_children[-2] is RoadPoint:
		initial_children[-2].queue_free()


## Adds a single RoadLane to the scene.
func _create_lane_pressed() -> void:
	var undo_redo = get_undo_redo()
	var target_parent = get_selected_node()

	if not is_instance_valid(target_parent):
		push_error("No valid parent node selected to add RoadLane to")
		return

	undo_redo.create_action("Add RoadLane")
	undo_redo.add_do_method(self, "_create_lane_do", target_parent)
	undo_redo.add_undo_method(self, "_create_lane_undo", target_parent)
	undo_redo.commit_action()


func _create_lane_do(parent: Node) -> void:
	# Add new RoadContainer at default location (World Origin)
	var default_name = "Lane 001"
	var n_lane = RoadLane.new()
	parent.add_child(n_lane)
	n_lane.name = RoadPoint.increment_name(default_name)

	if parent is RoadPoint:
		# Initialize this RoadLane with the same curve as the RP's 1st segment.
		for ch in parent.get_children():
			if not ch is RoadSegment:
				continue
			var seg:RoadSegment = ch
			n_lane.curve = seg.curve.duplicate()
			# Reset its transform to undo the rotation of the parent
			var tr = parent.transform
			n_lane.transform = tr.inverse()
			# But then must counter clear this part
			n_lane.transform.origin = Vector3(0, 0, 0)
			break
	else:
		pass # Don't do any curve init, better to match Godot default new curve

	if get_tree().get_edited_scene_root() == parent:
		n_lane.set_owner(parent)
	else:
		n_lane.set_owner(parent.owner)

	set_selection(n_lane)


func _create_lane_undo(parent: Node) -> void:
	# Make a likely bad assumption that the last child is the one to
	# be undone, but this is likely quite flakey.
	# TODO: Perform proper undo/redo support, ideally getting add_do_reference
	# to work property (failed when attempted so far).
	var initial_children = parent.get_children()
	if len(initial_children) == 0:
		return

	if initial_children[-1] is RoadLane:
		initial_children[-1].queue_free()


## Adds a single RoadLane to the scene.
func _create_lane_agent_pressed() -> void:
	var undo_redo = get_undo_redo()
	var target_parent = get_selected_node()

	if not is_instance_valid(target_parent):
		push_error("No valid parent node selected to add RoadLane to")
		return

	var agent := RoadLaneAgent.new()
	agent.name = "RoadLaneAgent"
	var editor_selected:Array = _edi.get_selection().get_selected_nodes()

	undo_redo.create_action("Add RoadLaneAgent")
	undo_redo.add_do_reference(agent)
	undo_redo.add_do_method(target_parent, "add_child", agent, true)
	undo_redo.add_do_method(agent, "set_owner", get_tree().get_edited_scene_root())
	undo_redo.add_do_method(self, "set_selection", agent)
	undo_redo.add_undo_method(target_parent, "remove_child", agent)
	undo_redo.add_undo_method(self, "set_selection_list", editor_selected)
	undo_redo.commit_action()
