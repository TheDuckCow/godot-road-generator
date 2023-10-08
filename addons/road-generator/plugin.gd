## Road and Highway generator addon.
tool
extends EditorPlugin

const RoadPointGizmo = preload("res://addons/road-generator/ui/road_point_gizmo.gd")
const RoadPointEdit = preload("res://addons/road-generator/ui/road_point_edit.gd")

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")

var road_point_gizmo = RoadPointGizmo.new(self)
var road_point_editor = RoadPointEdit.new(self)
var _road_toolbar = preload("res://addons/road-generator/ui/road_toolbar.tscn").instance()
var _edi = get_editor_interface()
var _eds = get_editor_interface().get_selection()
var _last_point: Node
var _last_lane: Node
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
func forward_spatial_draw_over_viewport(overlay):
	# Draw overlays using 2D elements on the node: overlay, e.g. draw_circle
	pass


## Handle or pass on event in the 3D editor
## If return true, consumes the event, otherwise forwards event
func forward_spatial_gui_input(camera: Camera, event: InputEvent)->bool:
	if event is InputEventMouseButton:
		# Event triggers on both press and release. Ignore press and only act on
		# release. Also, ignore right-click and middle-click.
		if event.button_index == BUTTON_LEFT and not event.pressed:
			# Shoot a ray and see if it hits anything
			var point = get_nearest_road_point(camera, event.position)
			if point:
				new_selection = point
	return false # Return false to not consume th event


# ------------------------------------------------------------------------------
# Utilities
# ------------------------------------------------------------------------------


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
	var eligible = (
		selected_node is RoadPoint
		or selected_node is RoadContainer
		or selected_node is RoadManager)
	var non_instance = (not selected_node.filename) or selected_node == get_tree().edited_scene_root
	if eligible and non_instance:
		_show_road_toolbar()
	else:
		_hide_road_toolbar()


func _on_scene_changed(scene_root: Node) -> void:
	var selected = get_selected_node()
	if selected and (selected is RoadContainer or selected is RoadPoint):
		_show_road_toolbar()
	else:
		_hide_road_toolbar()


func _on_scene_closed(_value) -> void:
	_hide_road_toolbar()


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


func handles(object: Object):
	# Must return "true" in order to use "forward_spatial_gui_input".
	return true


# ------------------------------------------------------------------------------
# Create menu handling
# ------------------------------------------------------------------------------


func _show_road_toolbar() -> void:
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
	if _road_toolbar.get_parent():
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
	if get_tree().get_edited_scene_root() == t_container:
		first_road_point.set_owner(t_container)
	else:
		first_road_point.set_owner(t_container.owner)
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

