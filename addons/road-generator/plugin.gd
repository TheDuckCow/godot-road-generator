## Road and Highway generator addon.
tool
extends EditorPlugin

const RoadPointGizmo = preload("res://addons/road-generator/road_point_gizmo.gd")
const RoadPointEdit = preload("res://addons/road-generator/ui/road_point_edit.gd")

const RoadSegment = preload("res://addons/road-generator/road_segment.gd")

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
	#add_custom_type("RoadContainer", "Spatial", preload("road_network.gd"), preload("road_segment.png"))
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


## Render the editor indicators for RoadPoints and RoadLanes if selected.
func _on_selection_changed() -> void:
	var selected_node = get_selected_node(_eds.get_selected_nodes())

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
		selected_node.on_transform()
	elif selected_node is RoadLane:
		_last_lane = selected_node
		_last_lane.show_fins(true)

	var eligible = selected_node is RoadPoint or selected_node is RoadContainer
	# Show the panel even if selection is scene root, but not if selection is a
	# scene instance itself (non editable).
	var non_instance = (not selected_node.filename) or selected_node == get_tree().edited_scene_root
	if eligible and non_instance:
		_show_road_toolbar()
	else:
		_hide_road_toolbar()



func _on_scene_changed(scene_root: Node) -> void:
	var selected = get_selected_node(_eds.get_selected_nodes())
	if selected and (selected is RoadContainer or selected is RoadPoint):
		_show_road_toolbar()
	else:
		_hide_road_toolbar()


func _on_scene_closed(_value) -> void:
	_hide_road_toolbar()


func refresh() -> void:
	get_editor_interface().get_inspector().refresh()


func _show_road_toolbar() -> void:
	if not _road_toolbar.get_parent():
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _road_toolbar)
		_road_toolbar.create_menu.connect(
			"regenerate_pressed", self, "_on_regenerate_pressed")
		_road_toolbar.create_menu.connect(
			"select_network_pressed", self, "_on_select_network_pressed")
		_road_toolbar.create_menu.connect(
			"create_2x2_road", self, "_create_2x2_road_pressed")


func _hide_road_toolbar() -> void:
	if _road_toolbar.get_parent():
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _road_toolbar)
		_road_toolbar.create_menu.disconnect(
			"regenerate_pressed", self, "_on_regenerate_pressed")
		_road_toolbar.create_menu.disconnect(
			"select_network_pressed", self, "_on_select_network_pressed")
		_road_toolbar.create_menu.disconnect(
			"create_2x2_road", self, "_create_2x2_road_pressed")



func get_network_from_selection():
	var selected_node = get_selected_node(_eds.get_selected_nodes())
	var t_network = null

	if not is_instance_valid(selected_node):
		push_error("Invalid selection to add road segment")
		return
	if selected_node is RoadContainer:
		return selected_node
	elif selected_node is RoadPoint:
		if is_instance_valid(selected_node.network):
			return selected_node.network
		else:
			push_error("Invalid network for roadpoint")
			return
	else:
		push_error("Invalid selection for adding new road segments")
		return


func _on_regenerate_pressed():
	var t_network = get_network_from_selection()
	t_network.rebuild_segments(true)


func _on_select_network_pressed():
	var t_network = get_network_from_selection()
	_edi.get_selection().clear()
	_edi.get_selection().add_node(t_network)


## Adds a 2x2 RoadSegment to the Scene
func _create_2x2_road_pressed():
	var undo_redo = get_undo_redo()
	var t_network = get_network_from_selection()

	if t_network == null:
		push_error("Could not get RoadContainer object")
		return
	if not is_instance_valid(t_network):
		push_error("Connected RoadContainer is not valid")
		return

	undo_redo.create_action("Create 2x2 road (limited undo/redo)")
	undo_redo.add_do_method(self, "_create_2x2_road_do", t_network)
	undo_redo.add_undo_method(self, "_create_2x2_road_undo", t_network)
	undo_redo.commit_action()


func _create_2x2_road_do(t_network: RoadContainer):
	var default_name = "RP_001"

	if not is_instance_valid(t_network) or not t_network is RoadContainer:
		push_error("Invalid RoadContainer")
		return

	# Add new Segment at default location (World Origin)
	t_network.setup_road_network()
	var first_road_point = RoadPoint.new()
	t_network.add_child(first_road_point, true)
	first_road_point.name = first_road_point.increment_name(default_name)
	first_road_point.traffic_dir = [
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.FORWARD,
		RoadPoint.LaneDir.FORWARD
	]
	first_road_point.auto_lanes = true
	first_road_point.set_owner(t_network.owner)
	var second_road_point = RoadPoint.new()
	second_road_point.name = second_road_point.increment_name(default_name)
	first_road_point.add_road_point(second_road_point, RoadPoint.PointInit.NEXT)


func _create_2x2_road_undo(selected_node: RoadContainer) -> void:
	# Make a likely bad assumption that the last two children are the ones to
	# be undone, but this is likely quite flakey.
	# TODO: Perform proper undo/redo support, ideally getting add_do_reference
	# to work property (failed when attempted so far).
	var initial_children = selected_node.get_children()
	if len(initial_children) < 2:
		return

	# Each RoadPoint handles their own cleanup of connected RoadSegments.
	if initial_children[-1] is RoadPoint:
		initial_children[-1].queue_free()
	if initial_children[-2] is RoadPoint:
		initial_children[-2].queue_free()


## Returns the primary selection or null if nothing is selected
func get_selected_node(selected_nodes: Array) -> Node:
	# TTD: Update this algorithm to figure out which node is really the
	# primary selection rather than always assuming index 0 is the selection.
	if not selected_nodes.empty():
		return selected_nodes[0]
	else:
		return null


func forward_spatial_gui_input(camera: Camera, event: InputEvent)->bool:
	if event is InputEventMouseButton:
		# Event triggers on both press and release. Ignore press and only act on
		# release. Also, ignore right-click and middle-click.
		if event.button_index == BUTTON_LEFT and not event.pressed:
			# Shoot a ray and see if it hits anything
			var point = get_nearest_road_point(camera, event.position)
			if point:
				new_selection = point
	return false


func select_road_point(point):
	_last_point = point
	_edi.get_selection().clear()
	_edi.edit_node(point)
	_edi.get_selection().add_node(point)
	point.on_transform()
	_show_road_toolbar()


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
