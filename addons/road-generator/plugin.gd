## Road and Highway generator addon.
tool
extends EditorPlugin

const RoadPointGizmo = preload("res://addons/road-generator/ui/road_point_gizmo.gd")
const RoadPointEdit = preload("res://addons/road-generator/ui/road_point_edit.gd")
const RoadToolbar = preload("res://addons/road-generator/ui/road_toolbar.tscn")

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

var tool_mode # Will be a value of: RoadToolbar.InputMode.SELECT

var road_point_gizmo = RoadPointGizmo.new(self)
var road_point_editor = RoadPointEdit.new(self)
var _road_toolbar
var _edi = get_editor_interface()
var _eds = get_editor_interface().get_selection()
var _last_point: Node
var _last_lane: Node
var _overlay_rp_hovering: Node
var _overlay_hovering_pos := Vector2(-1, -1)
var _overlay_hovering_from := Vector2(-1, -1)
var _overlay_hint_disconnect := false
var _overlay_hint_connection := false
var _overlay_hint_delete := false

var _press_init_pos: Vector2

var new_selection: RoadPoint # Reference for passing selected node


func _enter_tree():
	add_spatial_gizmo_plugin(road_point_gizmo)
	add_inspector_plugin(road_point_editor)
	road_point_editor.call("set_edi", _edi)
	_eds.connect("selection_changed", self, "_on_selection_changed")
	_eds.connect("selection_changed", road_point_gizmo, "on_selection_changed")
	connect("scene_changed", self, "_on_scene_changed")
	connect("scene_closed", self, "_on_scene_closed")

	# Don't add the following, as they would result in repeast in the UI.
	#add_custom_type("RoadPoint", "Spatial", preload("road_point.gd"), preload("road_point.png"))
	#add_custom_type("RoadContainer", "Spatial", preload("road_container.gd"), preload("road_segment.png"))
	#add_custom_type("RoadLane", "Curve3d", preload("lane_segment.gd"), preload("road_segment.png"))

	var gui = get_editor_interface().get_base_control()
	_road_toolbar = RoadToolbar.instance()
	_road_toolbar.gui = gui
	_road_toolbar.update_icons()

	# Update toolbar connections
	_road_toolbar.connect("mode_changed", self, "_on_mode_change")

	# Initial mode
	tool_mode = _road_toolbar.InputMode.SELECT


func _exit_tree():
	_eds.disconnect("selection_changed", self, "_on_selection_changed")
	_eds.disconnect("selection_changed", road_point_gizmo, "on_selection_changed")
	disconnect("scene_changed", self, "_on_scene_changed")
	disconnect("scene_closed", self, "_on_scene_closed")
	_road_toolbar.queue_free()
	remove_spatial_gizmo_plugin(road_point_gizmo)
	remove_inspector_plugin(road_point_editor)

	# Don't add the following, as they would result in repeast in the UI.
	#remove_custom_type("RoadPoint")
	#remove_custom_type("RoadContainer")
	#remove_custom_type("RoadLane")


# ------------------------------------------------------------------------------
# EditorPlugin overriden methods
# ------------------------------------------------------------------------------


## Called by the engine when the 3D editor's viewport is updated.
func forward_spatial_draw_over_viewport(overlay: Control):
	var selected = get_selected_node()

	if tool_mode == _road_toolbar.InputMode.SELECT:
		return
	elif tool_mode == _road_toolbar.InputMode.DELETE:
		if _overlay_hint_delete:
			var col = Color.rosybrown

			var radius := 24.0  # Radius of the rounded ends
			var hf := radius / 2.0
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
	var rad_size := 10.0
	var col:Color
	if _overlay_rp_hovering == null or not is_instance_valid(_overlay_rp_hovering):
		return # Nothing to draw
	elif _overlay_hint_disconnect:
		# Hovering node is directly connected to this node already, offer to disconnect
		col = Color.rosybrown
	elif selected is RoadPoint and selected.next_pt_init and selected.prior_pt_init:
		# Where we're coming from is already fully connected.
		# Eventually though, this could be an intersection.
		return
	else:
		# Connect mode
		var pt:RoadPoint = _overlay_rp_hovering
		if pt.next_pt_init and pt.prior_pt_init:
			# Fully connected, though eventually this could be an intersection.
			return
		else:
			col = Color.aqua

	overlay.draw_circle(_overlay_hovering_pos, rad_size, col)
	if selected is RoadPoint:
		overlay.draw_circle(_overlay_hovering_from, rad_size, col)
		overlay.draw_line(
			_overlay_hovering_from,
			_overlay_hovering_pos,
			col,
			2,
			true)


## Handle or pass on event in the 3D editor
## If return true, consumes the event, otherwise forwards event
func forward_spatial_gui_input(camera: Camera, event: InputEvent) -> bool:
	var ret := false

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


func _handle_gui_select_mode(camera: Camera, event: InputEvent) -> bool:
	# Event triggers on both press and release. Ignore press and only act on
	# release. Also, ignore right-click and middle-click.
	if not event is InputEventMouseButton:
		return false
	if event.button_index == BUTTON_LEFT:

		if event.pressed:
			# Nothing done until click up, but detect initial position
			# to differentiate between drags and direct clicks.
			_press_init_pos = event.position
			return false
		elif _press_init_pos != event.position:
			# TODO: possibly add min distance before treated as a drag
			# (does built in godot have a tolerance before counted as a drag?)
			return false  # Is a drag event

		# Shoot a ray and see if it hits anything
		var point = get_nearest_road_point(camera, event.position)
		if point and not event.pressed:
			# Using this method creates a conflcit with buultin drag n drop & 3d gizmo usage
			#set_selection(point)
			#_on_selection_changed()
			new_selection = point
			return false
	return false


## Handle adding new RoadPoints, connecting, and disconnecting RoadPoints
func _handle_gui_add_mode(camera: Camera, event: InputEvent) -> bool:
	if event is InputEventMouseMotion or event is InputEventPanGesture:
		# Handle updating UI overlays to indicate what would happen on click.

		## TODO: if pressed state, then use this to update the in/out mag handles
		# Pressed state not available here, need to track state separately.
		# Handle visualizing which connections are free to make
		# trigger overlay updates to draw/update indicators
		var point = get_nearest_road_point(camera, event.position)
		var selection = get_selected_node()
		_overlay_hovering_from = camera.unproject_position(selection.global_transform.origin)
		if point:
			_overlay_rp_hovering = point
			_overlay_hovering_pos = camera.unproject_position(point.global_transform.origin)

			if selection == point:
				_overlay_rp_hovering = null
				_overlay_hint_disconnect = false
				_overlay_hint_connection = false
			elif selection.prior_pt_init and selection.get_node(selection.prior_pt_init) == point:
				_overlay_hint_disconnect = true
				_overlay_hint_connection = false
			elif selection.next_pt_init and selection.get_node(selection.next_pt_init) == point:
				_overlay_hint_disconnect = true
				_overlay_hint_connection = false
			elif selection.prior_pt_init and selection.next_pt_init:
				# _overlay_rp_hovering = null
				# In the future, this could be a mode to convert into an intersection
				_overlay_hint_disconnect = false
				_overlay_hint_connection = false
			else:
				# Open connection scenario
				_overlay_hint_disconnect = false
				_overlay_hint_connection = true
		else:
			_overlay_rp_hovering = null
			_overlay_hovering_pos = event.position
			_overlay_hint_disconnect = false
			_overlay_hint_connection = false
		update_overlays()

		# Consume the event no matter what.
		return false
	if not event is InputEventMouseButton:
		return false
	if not event.button_index == BUTTON_LEFT:
		return false
	if not event.pressed:
		# Should consume all left click operations
		return true

	var selection = get_selected_node()
	if _overlay_hint_disconnect:
		_disconnect_rp_on_click(selection, _overlay_rp_hovering)
	elif _overlay_hint_connection:
		_connect_rp_on_click(selection, _overlay_rp_hovering)
	else:
		var res := get_click_point_with_context(camera, event.position, selection)
		var pos:Vector3 = res[0]
		var nrm:Vector3 = res[1]
		_add_next_rp_on_click(pos, nrm, selection)
	return true


func _handle_gui_delete_mode(camera: Camera, event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var point = get_nearest_road_point(camera, event.position)
		var selection = get_selected_node()
		_overlay_hovering_from = camera.unproject_position(selection.global_transform.origin)
		if point:
			_overlay_rp_hovering = point
			_overlay_hovering_pos = camera.unproject_position(point.global_transform.origin)
			_overlay_hint_delete = true
		else:
			_overlay_rp_hovering = null
			_overlay_hovering_pos = Vector2(-1, -1)
			_overlay_hint_delete = false
		update_overlays()
		return true
	if not event is InputEventMouseButton:
		return false
	if not event.button_index == BUTTON_LEFT:
		return false
	if event.pressed:
		# Do an immediate delete
		var point = get_nearest_road_point(camera, event.position)
		_delete_rp_on_click(point)
	return true


## Render the editor indicators for RoadPoints and RoadLanes if selected.
func _on_selection_changed() -> void:
	var selected_node = get_selected_node()

	if new_selection:
		select_road_point(new_selection)
		selected_node = new_selection
		new_selection = null
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
	var non_instance = (not selected_node.filename) or selected_node == get_tree().edited_scene_root
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
	if not selected_nodes.empty():
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
	# _edi.edit_node(node) # Necessary?
	_edi.get_selection().add_node(node)


## Gets nearest RoadPoint if user clicks a Segment. Returns RoadPoint or null.
func get_nearest_road_point(camera: Camera, mouse_pos: Vector2)->RoadPoint:
	var src = camera.project_ray_origin(mouse_pos)
	var nrm = camera.project_ray_normal(mouse_pos)
	var dist = camera.far

	var space_state =  get_viewport().world.direct_space_state
	var intersect = space_state.intersect_ray(src, src + nrm * dist, [], 1)

	if intersect.empty():
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
			var dist_to_start = start_point.global_translation.distance_to(position)
			var dist_to_end = end_point.global_translation.distance_to(position)
			if dist_to_start > dist_to_end:
				nearest_point = end_point
			else:
				nearest_point = start_point

			return nearest_point


## Convert a given click to the nearest, best fitting 3d pos + normal for click.
##
## Includes selection node so that if there's no intersection made, we can still
## raycast onto the xz  or screen xy local plane of the object clicked on.
##
## Returns: [Position, Normal]
func get_click_point_with_context(camera: Camera, mouse_pos: Vector2, selection: Node) -> Array:
	var src = camera.project_ray_origin(mouse_pos)
	var nrm = camera.project_ray_normal(mouse_pos)
	var dist = camera.far

	var space_state =  get_viewport().world.direct_space_state
	# intersect_ray(from, to, exclude, collision_mask, collide_with_bodies, collide_with_areas)
	# Unfortunately, must have collide with areas off. And this doesn't pick
	# up collisions with objects that don't have collisions already added, making
	# it not as convinient for viewport manipulation.
	var intersect = space_state.intersect_ray(
		src, src + nrm * dist, [], 1, true, false)

	if not intersect.empty():
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


func handles(object: Object):
	# Must return "true" in order to use "forward_spatial_gui_input".
	return true


# ------------------------------------------------------------------------------
# Create menu handling
# ------------------------------------------------------------------------------


func _show_road_toolbar() -> void:
	_road_toolbar.mode = tool_mode

	if not _road_toolbar.get_parent():
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _road_toolbar)
		_road_toolbar.selected_nodes = _eds.get_selected_nodes()

		# Utilities
		_road_toolbar.create_menu.connect(
			"regenerate_pressed", self, "_on_regenerate_pressed")
		_road_toolbar.create_menu.connect(
			"select_container_pressed", self, "_on_select_container_pressed")

		# Native nodes
		_road_toolbar.create_menu.connect(
			"create_container", self, "_create_container_pressed")
		_road_toolbar.create_menu.connect(
			"create_roadpoint", self, "_create_roadpoint_pressed")
		_road_toolbar.create_menu.connect(
			"create_lane", self, "_create_lane_pressed")

		# Specials / prefabs
		_road_toolbar.create_menu.connect(
			"create_2x2_road", self, "_create_2x2_road_pressed")


func _hide_road_toolbar() -> void:
	if _road_toolbar and _road_toolbar.get_parent():
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _road_toolbar)

		# Utilities
		_road_toolbar.create_menu.disconnect(
			"regenerate_pressed", self, "_on_regenerate_pressed")
		_road_toolbar.create_menu.disconnect(
			"select_container_pressed", self, "_on_select_container_pressed")

		# Native nodes
		_road_toolbar.create_menu.disconnect(
			"create_container", self, "_create_container_pressed")
		_road_toolbar.create_menu.disconnect(
			"create_roadpoint", self, "_create_roadpoint_pressed")
		_road_toolbar.create_menu.disconnect(
			"create_lane", self, "_create_lane_pressed")

		# Specials / prefabs
		_road_toolbar.create_menu.disconnect(
			"create_2x2_road", self, "_create_2x2_road_pressed")

func _on_regenerate_pressed():
	var t_container = get_container_from_selection()
	t_container.rebuild_segments(true)


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
	if selection is RoadPoint:
		parent = selection.get_parent()
		if selection.next_pt_init and selection.prior_pt_init:
			print("Fully connected already")
			# already fully connected, so for now add as just a standalone pt
			# TODO: In the future, this should create an intersection.
			_sel = parent
		else:
			_sel = selection
	elif selection is RoadContainer:
		parent = selection
		_sel = selection
	# elif selection is RoadManager:
	# add_container = true, but would need to somehow pass through reference
	else: # RoadManager or RoadLane.
		push_error("Invalid selection context, need RoadContainer parent")
		return


	undo_redo.create_action("Add next RoadPoint")
	undo_redo.add_do_method(self, "_add_next_rp_on_click_do", pos, nrm, _sel, parent)
	undo_redo.add_undo_method(self, "_add_next_rp_on_click_undo", pos, _sel, parent)
	undo_redo.commit_action()


func _add_next_rp_on_click_do(pos: Vector3, nrm: Vector3, selection: Node, parent: Node) -> void:

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

		# Update rotation along the initially picked axis.
	elif selection is RoadContainer:
		parent.add_child(next_rp)
		next_rp.set_owner(get_tree().get_edited_scene_root())
		next_rp.name = "RP_001"  # TODO: define this in some central area.
		next_rp.traffic_dir = [
			RoadPoint.LaneDir.REVERSE,
			RoadPoint.LaneDir.REVERSE,
			RoadPoint.LaneDir.FORWARD,
			RoadPoint.LaneDir.FORWARD
		]
		next_rp.auto_lanes = true

	# Make the road visible halfway above the ground by the gutter height amount.
	var half_gutter: float = -0.5 * next_rp.gutter_profile.y
	next_rp.global_transform.origin = pos + nrm * half_gutter

	# Rotate this rp towards the initial selected node
	if selection is RoadPoint:
		var look_pos = selection.global_transform.origin
		if not adding_to_next:
			# Essentially flip the look 180 so it's not twisted around.
			print("Flipping dir")
			look_pos += 2 * dirvec
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
	if not rp_a is RoadPoint or not rp_b is RoadPoint:
		push_error("Cannot connect non-roadpoints")
		return

	# TOOD: must handle if they belong to different RoadContainers

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

	# not the poitn we'll connect to.
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

	undo_redo.create_action("Connect RoadPoints")
	undo_redo.add_do_method(rp_a, "connect_roadpoint", from_dir, rp_b, target_dir)
	undo_redo.add_undo_method(rp_a, "disconnect_roadpoint", from_dir, target_dir)
	undo_redo.commit_action()


func _disconnect_rp_on_click(rp_a, rp_b):
	var undo_redo = get_undo_redo()
	if not rp_a is RoadPoint or not rp_b is RoadPoint:
		push_error("Cannot connect non-roadpoints")
		return

	# TOOD: must handle if they belong to different RoadContainers

	var from_dir
	var target_dir
	if rp_a.prior_pt_init and rp_a.get_node(rp_a.prior_pt_init) == rp_b:
		from_dir = RoadPoint.PointInit.PRIOR
	elif rp_a.next_pt_init and rp_a.get_node(rp_a.next_pt_init) == rp_b:
		from_dir = RoadPoint.PointInit.NEXT
	else:
		push_error("Not initially connected")
		return
	if rp_b.prior_pt_init and rp_b.get_node(rp_b.prior_pt_init) == rp_a:
		target_dir = RoadPoint.PointInit.PRIOR
	elif rp_b.next_pt_init and rp_b.get_node(rp_b.next_pt_init) == rp_a:
		target_dir = RoadPoint.PointInit.NEXT
	else:
		push_error("Not initially connected")
		return

	undo_redo.create_action("Disconnect RoadPoints")
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
	if prior_rp != null and next_rp != null:
		dissolve = true

	# "Do" steps

	undo_redo.create_action("Dissolve RoadPoint")
	undo_redo.add_do_property(rp, "prior_pt_init", "")
	undo_redo.add_do_property(rp, "next_pt_init", "")
	if dissolve:
		print("Setting up for dissolve")
		if prior_samedir:
			undo_redo.add_do_property(prior_rp, "next_pt_init", "")
			undo_redo.add_do_property(prior_rp, "next_pt_init", prior_rp.get_path_to(next_rp))
		else:
			undo_redo.add_do_property(prior_rp, "prior_pt_init", "")
			undo_redo.add_do_property(prior_rp, "prior_pt_init", prior_rp.get_path_to(next_rp))
		if next_samedir:
			undo_redo.add_do_property(next_rp, "prior_pt_init", "")
			undo_redo.add_do_property(next_rp, "prior_pt_init", next_rp.get_path_to(prior_rp))
		else:
			undo_redo.add_do_property(next_rp, "next_pt_init", "")
			undo_redo.add_do_property(next_rp, "next_pt_init", next_rp.get_path_to(prior_rp))
	if prior_rp:
		undo_redo.add_do_method(self, "set_selection", prior_rp)
	elif next_rp:
		undo_redo.add_do_method(self, "set_selection", next_rp)
	else:
		undo_redo.add_do_method(self, "set_selection", rp.container)
	undo_redo.add_do_method(rp.get_parent(), "remove_child", rp)  # Queuefree borqs with undoredo
	# might need to do:
	# container.remove_segment(seg)
	if dissolve:
		undo_redo.add_do_method(prior_rp, "on_transform")
		undo_redo.add_do_method(next_rp, "on_transform") # Technicall only one should be needed

	# ""Undo" steps

	undo_redo.add_undo_reference(rp)
	undo_redo.add_undo_method(rp.get_parent(), "add_child", rp, true) # TODO, improve positioning
	# undo_redo.add_undo_method(rp.get_parent(), "move_child", rp, orig_pos), or use add_child_below_node instead
	undo_redo.add_undo_method(rp, "set_owner", get_tree().get_edited_scene_root())
	undo_redo.add_undo_property(rp, "prior_pt_init", rp.prior_pt_init)
	undo_redo.add_undo_property(rp, "next_pt_init", rp.next_pt_init)
	if dissolve:
		if prior_samedir:
			undo_redo.add_do_property(prior_rp, "next_pt_init", "")
			undo_redo.add_do_property(prior_rp, "next_pt_init", prior_rp.next_pt_init)
		else:
			undo_redo.add_do_property(prior_rp, "prior_pt_init", "")
			undo_redo.add_do_property(prior_rp, "prior_pt_init", prior_rp.prior_pt_init)
		if next_samedir:
			undo_redo.add_do_property(next_rp, "prior_pt_init", "")
			undo_redo.add_do_property(next_rp, "prior_pt_init", next_rp.prior_pt_init)
		else:
			undo_redo.add_do_property(next_rp, "next_pt_init", "")
			undo_redo.add_do_property(next_rp, "next_pt_init", next_rp.next_pt_init)
		#undo_redo.add_undo_property(prior_rp, "prior_pt_init", prior_rp.prior_pt_init)
		#undo_redo.add_undo_property(prior_rp, "next_pt_init", prior_rp.next_pt_init)
		#undo_redo.add_undo_property(next_rp, "prior_pt_init", next_rp.prior_pt_init)
		#undo_redo.add_undo_property(next_rp, "next_pt_init", next_rp.next_pt_init)
	undo_redo.add_undo_method(self, "set_selection", rp)
	undo_redo.add_undo_method(rp, "on_transform")
	if dissolve:
		undo_redo.add_undo_method(prior_rp, "on_transform")
		undo_redo.add_undo_method(next_rp, "on_transform")

	undo_redo.commit_action()


## Adds a single RoadPoint to the scene
func _create_roadpoint_pressed() -> void:
	var undo_redo = get_undo_redo()
	var t_container = get_container_from_selection()
	if not is_instance_valid(t_container):
		push_error("Invalid selection context")
		return

	undo_redo.create_action("Add RoadPoint")
	undo_redo.add_do_method(self, "_create_2x2_road_do", t_container, true)
	undo_redo.add_undo_method(self, "_create_2x2_road_undo", t_container, true)
	undo_redo.commit_action()


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
	first_road_point.traffic_dir = [
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.FORWARD,
		RoadPoint.LaneDir.FORWARD
	]
	first_road_point.auto_lanes = true
	first_road_point.set_owner(get_tree().get_edited_scene_root())

	var second_road_point = RoadPoint.new()
	second_road_point.name = second_road_point.increment_name(default_name)
	if single_point == false:
		first_road_point.add_road_point(second_road_point, RoadPoint.PointInit.NEXT)
		set_selection(second_road_point)
	else:
		set_selection(first_road_point)

	t_container.update_edges() # Since we updated a roadpoint name after adding.


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

