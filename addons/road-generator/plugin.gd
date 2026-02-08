@tool
extends EditorPlugin
## Road and Highway generator addon.

# ------------------------------------------------------------------------------
#region Signals/Enums/Const/Vars
# ------------------------------------------------------------------------------

const RoadPointGizmo = preload("res://addons/road-generator/ui/road_point_gizmo.gd")
const RoadIntersectionGizmo = preload("res://addons/road-generator/ui/road_intersection_gizmo.gd")
const RoadPointEdit = preload("res://addons/road-generator/ui/road_point_edit.gd")
const RoadContainerEdit = preload("res://addons/road-generator/ui/road_container_edit.gd")
const RoadToolbar = preload("res://addons/road-generator/ui/road_toolbar.tscn")
const RoadToolbarClass = preload("res://addons/road-generator/ui/road_toolbar.gd")
const ConnectionTool = preload("res://addons/road-generator/ui/connection_tool.gd")

const RoadSegment = preload("res://addons/road-generator/nodes/road_segment.gd")


var tool_mode # Will be a value of: RoadToolbar.InputMode.SELECT

var road_point_gizmo = RoadPointGizmo.new(self)
var road_intersection_gizmo = RoadIntersectionGizmo.new(self)
var road_point_editor = RoadPointEdit.new(self)
var road_container_editor = RoadContainerEdit.new(self)
var connection_tool = ConnectionTool.new(self)

var plugin_version: String

var _road_toolbar: RoadToolbarClass
var _edi = get_editor_interface()
var _eds = get_editor_interface().get_selection()
var _last_point: Node
var _last_lane: Node
var _export_file_dialog: FileDialog
var _last_selection_roadnode: bool = false

var _lock_x_rotation := false
var _lock_y_rotation := false
var _lock_z_rotation := false

var _edi_debug := false

# For use by road_point_edit and panel, keys are props on RoadPoint
var copy_attributes:Dictionary = {}


# ------------------------------------------------------------------------------
#endregion
#region Setup and builtin overrides
# ------------------------------------------------------------------------------


func _enter_tree():
	add_node_3d_gizmo_plugin(road_point_gizmo)
	add_node_3d_gizmo_plugin(road_intersection_gizmo)
	add_inspector_plugin(road_point_editor)
	road_point_editor.call("set_edi", _edi)
	add_inspector_plugin(road_container_editor)
	road_container_editor.call("set_edi", _edi)
	_eds.connect("selection_changed", self._on_selection_changed)
	
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
	_road_toolbar.rotation_lock_toggled.connect(_on_rotation_lock_toggled)
	_road_toolbar.snap_distance_updated.connect(_on_snap_distance_updated)
	_road_toolbar.select_terrain_3d_pressed.connect(_on_select_terrain_3d_pressed)

	# Initial mode
	tool_mode = _road_toolbar.InputMode.SELECT
	
	# Load the plugin version, for UI and form-opening purposes
	plugin_version = get_plugin_version()


func _exit_tree():
	_eds.disconnect("selection_changed", self._on_selection_changed)
	disconnect("scene_changed", self._on_scene_changed)
	disconnect("scene_closed", self._on_scene_closed)
	_road_toolbar.queue_free()
	remove_node_3d_gizmo_plugin(road_point_gizmo)
	remove_node_3d_gizmo_plugin(road_intersection_gizmo)
	remove_inspector_plugin(road_container_editor)
	remove_inspector_plugin(road_point_editor)

	# Don't add the following, as they would result in repeast in the UI.
	#remove_custom_type("RoadPoint")
	#remove_custom_type("RoadContainer")
	#remove_custom_type("RoadLane")


func _physics_process(delta: float) -> void:
	connection_tool._physics_process(delta)

# ------------------------------------------------------------------------------
#endregion
#region EditorPlugin overriden methods
# ------------------------------------------------------------------------------


## Called by the engine when the 3D editor's viewport is updated.
func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	connection_tool.forward_3d_draw_over_viewport(overlay)


## Handle or pass on event in the 3D editor
## If return true, consumes the event, otherwise forwards event
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	return connection_tool.forward_3d_gui_input(camera, event)


# ------------------------------------------------------------------------------
#endregion
#region GUI utilities
# ------------------------------------------------------------------------------


## Identifies roads relevant for built in toolbar operations.
func is_road_node(node: Node) -> bool:
	# Not counting RoadLane, since they are just native curves with extra draws
	return (node is RoadPoint
		or node is RoadIntersection
		or node is RoadContainer
		or node is RoadManager)


## Render the editor indicators for RoadPoints and RoadLanes if selected.
func _on_selection_changed() -> void:
	var nodes = _eds.get_selected_nodes()
	
	var selected_node := get_selected_node()

	if not selected_node:
		if not _last_selection_roadnode:
			return
		road_point_gizmo.set_hidden()
		road_intersection_gizmo.set_hidden()
		connection_tool._clear_targets()
		update_overlays()
		_hide_road_toolbar() # hiding too soon
		_last_selection_roadnode = false
		return

	if _last_lane and is_instance_valid(_last_lane):
		_last_lane.show_fins(false)

	# TOOD: Change show/hide to occur on button-release, for consistency with internal panels.
	var eligible = is_road_node(selected_node)
	if eligible:
		_show_road_toolbar()
		connection_tool._clear_targets()
		update_overlays() # In case connection tool active and user used a shorcut key
		_last_selection_roadnode = true
	elif _last_selection_roadnode:
		road_point_gizmo.set_hidden()
		road_intersection_gizmo.set_hidden()
		connection_tool._clear_targets()
		update_overlays()
		_hide_road_toolbar()
		_last_selection_roadnode = false
		return

	if selected_node is RoadPoint:
		_last_point = selected_node
		road_point_gizmo.set_visible()
		road_intersection_gizmo.set_hidden()
	elif selected_node is RoadIntersection:
		road_point_gizmo.set_hidden()
		road_intersection_gizmo.set_visible()
	elif selected_node is RoadLane:
		road_point_gizmo.set_hidden()
		_last_lane = selected_node
		_last_lane.show_fins(true)
		
		road_point_gizmo.set_hidden()
		road_intersection_gizmo.set_hidden()
	else:
		road_point_gizmo.set_hidden()
		road_intersection_gizmo.set_hidden()


func _on_scene_changed(scene_root: Node) -> void:
	var selected := get_selected_node()
	var eligible := is_road_node(selected)
	# We do not need ot reshow/hide the toolbar, this is handled via node
	# deselection/selection on scene change by the editor itself


func _on_scene_closed(_value) -> void:
	_hide_road_toolbar()


func _on_mode_change(_mode: int) -> void:
	tool_mode = _mode  # Instance of RoadToolbar.InputMode
	update_overlays()


func refresh() -> void:
	get_editor_interface().get_inspector().refresh()


func get_plugin_version() -> String:
	var addon_path:String = get_script().resource_path
	addon_path = addon_path.get_base_dir() + "/plugin.cfg"
	print("Path: ", addon_path)
	var config := ConfigFile.new()
	if config.load(addon_path) == OK:
		return config.get_value("plugin", "version", "")
	return ""

# ------------------------------------------------------------------------------
#endregion
#region Editor setting callabls
# ------------------------------------------------------------------------------

## Finds and returns the most relevant connector if any in this scene
func get_connector() -> Node:
	var scene_root := EditorInterface.get_edited_scene_root()
	var connector: Node = _find_nodetype_recursive(scene_root, "RoadTerrain3DConnector")
	return connector


## Depth-first search for connector nodes
func _find_nodetype_recursive(node, target_type) -> Node:
	for ch in node.get_children():
		var nd: Node = ch
		var script = nd.get_script()
		if script and script.get_global_name() == target_type:
			return nd
		elif nd.get_class() == target_type:
			return nd
		else:
			var res = _find_nodetype_recursive(nd, target_type)
			if res != null:
				return res
	return null

## Returns the snapping threshold from the connection tool
func get_snapping_distance() -> float:
	return connection_tool.snap_threshold


func set_snapping_distance(value: float) -> void:
	connection_tool.snap_threshold = value


# ------------------------------------------------------------------------------
#endregion
#region Selection utilities
# ------------------------------------------------------------------------------


## Returns the primary selection or null if nothing is selected
func get_selected_node() -> Node:
	# TODO: Update this algorithm to figure out which node is really the
	# primary selection rather than always assuming index 0 is the selection.
	var selected_nodes := _eds.get_selected_nodes()
	if not selected_nodes.is_empty():
		return selected_nodes[0]
	else:
		return null


## Returns the next highest level RoadManager from current primary selection.
func get_manager_from_selection() -> RoadManager:
	var selected_node := get_selected_node()

	if not is_instance_valid(selected_node):
		push_error("Invalid selection to add road segment")
		return
	elif selected_node is RoadManager:
		return selected_node
	elif selected_node is RoadContainer:
		return selected_node.get_manager()
	elif selected_node is RoadGraphNode:
		if is_instance_valid(selected_node.container):
			return selected_node.container.get_manager()
		else:
			push_error("Invalid RoadContainer instance for RoadPoint's parent")
			return
	push_warning("No relevant Road* node selected")
	return


## Gets the RoadContainer from selection of either roadcontainer or roadpoint.
func get_container_from_selection(): # -> Optional[RoadContainer]
	var selected_node := get_selected_node()
	var t_container = null

	if not is_instance_valid(selected_node):
		push_error("Invalid selection to add road segment")
		return
	if selected_node is RoadContainer:
		return selected_node
	elif selected_node is RoadGraphNode:
		if is_instance_valid(selected_node.container):
			return selected_node.container
		else:
			push_error("Invalid container for roadpoint")
			return
	else:
		push_warning("Invalid selection for adding new road segments")
		return


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


func _handles(object: Object):
	# Must return "true" in order to use "forward_spatial_gui_input".
	return object is Node3D


# ------------------------------------------------------------------------------
#endregion
#region Create menu handling
# ------------------------------------------------------------------------------


func _show_road_toolbar() -> void:
	_road_toolbar.mode = tool_mode
	_road_toolbar.on_show(
		_eds.get_selected_nodes(),
		connection_tool.snap_threshold,
		get_connector, # Passes in the callable directly, to defer search to submenu open
		_lock_x_rotation,
		_lock_y_rotation,
		_lock_z_rotation)

	if not _road_toolbar.get_parent():
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _road_toolbar)

		# Utilities
		_road_toolbar.create_menu.regenerate_pressed.connect(_on_regenerate_pressed)
		_road_toolbar.create_menu.select_container_pressed.connect(_on_select_container_pressed)
		_road_toolbar.create_menu.pressed_add_custom_roadcontainer.connect(_instance_custom_roadcontainer)

		# Native nodes
		_road_toolbar.create_menu.create_container.connect(_create_container_pressed)
		_road_toolbar.create_menu.create_roadpoint.connect(_create_roadpoint_pressed)
		_road_toolbar.create_menu.create_lane.connect(_create_lane_pressed)
		_road_toolbar.create_menu.create_lane_agent.connect(_create_lane_agent_pressed)

		# Specials / prefabs
		_road_toolbar.create_menu.create_2x2_road.connect(_create_2x2_road_pressed)

		# Aditional tools
		_road_toolbar.create_menu.export_mesh.connect(_export_mesh_modal)
		_road_toolbar.create_menu.feedback_pressed.connect(_on_feedback_pressed)
		_road_toolbar.create_menu.report_issue_pressed.connect(_on_report_issue_pressed)
		_road_toolbar.create_menu.create_terrain3d_connector.connect(add_and_configure_terrain3d_connector)


func _hide_road_toolbar() -> void:
	if _road_toolbar and _road_toolbar.get_parent():
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _road_toolbar)

		# Utilities
		_road_toolbar.create_menu.regenerate_pressed.disconnect(_on_regenerate_pressed)
		_road_toolbar.create_menu.select_container_pressed.disconnect(_on_select_container_pressed)
		_road_toolbar.create_menu.pressed_add_custom_roadcontainer.disconnect(_instance_custom_roadcontainer)

		# Native nodes
		_road_toolbar.create_menu.create_container.disconnect(_create_container_pressed)
		_road_toolbar.create_menu.create_roadpoint.disconnect(_create_roadpoint_pressed)
		_road_toolbar.create_menu.create_lane.disconnect(_create_lane_pressed)
		_road_toolbar.create_menu.create_lane_agent.disconnect(_create_lane_agent_pressed)

		# Specials / prefabs
		_road_toolbar.create_menu.create_2x2_road.disconnect(_create_2x2_road_pressed)
		
		# Aditional tools
		_road_toolbar.create_menu.export_mesh.disconnect(_export_mesh_modal)
		_road_toolbar.create_menu.feedback_pressed.disconnect(_on_feedback_pressed)
		_road_toolbar.create_menu.report_issue_pressed.disconnect(_on_report_issue_pressed)
		_road_toolbar.create_menu.create_terrain3d_connector.disconnect(add_and_configure_terrain3d_connector)


func _on_rotation_lock_toggled(axis_id: int, state: bool) -> void:
	match axis_id:
		0:
			_lock_x_rotation = state
		1:
			_lock_y_rotation = state
		2:
			_lock_z_rotation = state


func _on_snap_distance_updated(value: float) -> void:
	connection_tool.snap_threshold = value


func _on_select_terrain_3d_pressed() -> void:
	var connector := get_connector()
	if is_instance_valid(connector):
		set_selection(connector)


func _on_regenerate_pressed() -> void:
	var nd := get_selected_node()
	if nd is RoadManager:
		for ch_container in nd.get_containers():
			ch_container.rebuild_segments(true)
		return
	var t_container = get_container_from_selection()
	if t_container:
		t_container.rebuild_segments(true)
		return


# ------------------------------------------------------------------------------
#endregion
#region Operations
# ------------------------------------------------------------------------------


func _instance_custom_roadcontainer(path: String) -> void:
	var undo_redo = get_undo_redo()
	var init_sel := get_selected_node()

	# Determine where to place it, for now - origin of the RoadManager
	var t_manager = get_manager_from_selection()
	if not is_instance_valid(t_manager):
		push_error("Invalid selection context, could not find RoadManager")
		# TODO: could allow it to be placed at center of the scene instead,
		# as child of scene root
		return
	var parent:Node3D = t_manager

	var scene:PackedScene = load(path)
	if not is_instance_valid(scene):
		push_error("Invalid scene path, could not load %s" % path)
		return

	var new_rc = scene.instantiate()
	var scene_name:String = path.get_file().get_basename()
	new_rc.name = scene_name

	undo_redo.create_action("Add RoadScene (%s)" % scene_name)

	undo_redo.add_do_reference(new_rc)
	undo_redo.add_do_method(parent, "add_child", new_rc, true)
	undo_redo.add_do_method(new_rc, "set_owner", get_tree().get_edited_scene_root())
	undo_redo.add_do_method(self, "set_selection", new_rc)
	undo_redo.add_do_method(self, "_call_update_edges", new_rc)

	undo_redo.add_undo_method(parent, "remove_child", new_rc)
	undo_redo.add_undo_method(self, "set_selection", init_sel)

	undo_redo.commit_action()


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

	var init_sel := get_selected_node()
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


func _add_next_rp_on_click(pos: Vector3, nrm: Vector3, selection: Node, auto_connect_rp=null) -> void:
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
			push_warning("Fully connected already")
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
	else: # RoadManager or RoadLane.
		push_error("Invalid selection context, need RoadContainer parent")
		return

	undo_redo.create_action("Add next RoadPoint")
	if handle_mag > 0:
		if not selection.next_pt_init:
			undo_redo.add_do_property(_sel, "next_mag", handle_mag)
			undo_redo.add_undo_property(_sel, "next_mag", _sel.next_mag)
		elif not selection.prior_pt_init:
			undo_redo.add_do_property(_sel, "prior_mag", handle_mag)
			undo_redo.add_undo_property(_sel, "prior_mag", _sel.prior_mag)
	if selection is RoadPoint and not selection.is_next_connected() and not selection.is_prior_connected():
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


# Adds a new RP as a child of rp_rc which should be a "dynamic" container,
# aligned to the position of and connected to the connect_rp of another RP
func _add_and_connect_rp(rp_rc: RoadContainer, connect_rp: RoadPoint) -> void:
	if connect_rp.container == rp_rc:
		push_error("Containers should be different to connect")
		return

	var target_dir: int
	if not connect_rp.is_next_connected():
		target_dir = RoadPoint.PointInit.NEXT
	elif not connect_rp.is_prior_connected():
		target_dir = RoadPoint.PointInit.PRIOR
	else:
		push_error("Connection rp is already connected")
		return
	var this_dir: int = RoadPoint.PointInit.PRIOR if target_dir == RoadPoint.PointInit.NEXT else RoadPoint.PointInit.NEXT

	var undo_redo = get_undo_redo()
	var init_sel := get_selected_node()

	var pos: Vector3 = connect_rp.global_transform.origin
	var nrm: Vector3 = connect_rp.global_rotation
	var new_rp := RoadPoint.new()

	undo_redo.create_action("Add and connect RoadPoint")

	undo_redo.add_do_reference(new_rp)
	undo_redo.add_do_method(rp_rc, "add_child", new_rp, true)
	undo_redo.add_do_method(new_rp, "set_owner", get_tree().get_edited_scene_root())
	undo_redo.add_do_method(new_rp, "copy_settings_from", connect_rp)
	undo_redo.add_do_property(new_rp, "global_transform", connect_rp.global_transform)
	undo_redo.add_do_method(new_rp, "connect_container", this_dir, connect_rp, target_dir)
	undo_redo.add_do_method(self, "set_selection", new_rp)

	#undo_redo.add_undo_method(new_rp, "disconnect_container", this_dir, target_dir)
	undo_redo.add_undo_method(rp_rc, "remove_child", new_rp)
	undo_redo.add_undo_method(self, "set_selection", init_sel)

	undo_redo.commit_action()


func _call_update_edges(container: RoadContainer) -> void:
	container.update_edges()


func _add_next_rp_on_click_do(pos: Vector3, nrm: Vector3, selection: Node, parent: Node, handle_mag: float) -> void:

	var next_rp = RoadPoint.new()
	next_rp._is_internal_updating = true
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
		next_rp.name = next_rp.increment_name("RP_001")

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

			if _lock_x_rotation:
				next_rp.global_rotation.x = 0.0
			if _lock_y_rotation:
				next_rp.global_rotation.y = 0.0
			if _lock_z_rotation:
				next_rp.global_rotation.z = 0.0

	next_rp._is_internal_updating = false
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
	var init_sel := get_selected_node()
	if not rp_a is RoadPoint or not rp_b is RoadPoint:
		push_error("Cannot connect non-roadpoints")
		return

	var from_dir
	var target_dir
	# Starting point is current selection.
	if rp_a.prior_pt_init and rp_a.next_pt_init:
		push_warning("Cannot connect, fully connected")
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
		push_warning("Cannot connect, fully connected")
		return true
	elif rp_b.prior_pt_init:
		target_dir = RoadPoint.PointInit.NEXT # only next open
	elif rp_b.next_pt_init:
		target_dir = RoadPoint.PointInit.PRIOR # only prior open
	else:
		var rel_vec = rp_a.global_transform.origin - rp_b.global_transform.origin
		if rp_b.global_transform.basis.z.dot(rel_vec) > 0:
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


## Action to disconnect a RoadPoint
##
## init_trans provides the undo position to assign to the rp_b if relevant, such
## as when disconnected a RoadContainer via unsnapping.
func _disconnect_rp_on_click(rp_a, rp_b, init_trans: Array[Transform3D] = []):
	var undo_redo = get_undo_redo()
	if not rp_a is RoadPoint or not rp_b is RoadPoint:
		push_error("Cannot connect non-roadpoints")
		return

	# TOOD: must handle if they belong to different RoadContainers

	var from_dir
	var target_dir
	if rp_a.get_prior_road_node() == rp_b:
		from_dir = RoadPoint.PointInit.PRIOR
	elif rp_a.get_next_road_node() == rp_b:
		from_dir = RoadPoint.PointInit.NEXT
	else:
		push_error("Not initially connected")
		return
	if rp_b.get_prior_road_node() == rp_a:
		target_dir = RoadPoint.PointInit.PRIOR
	elif rp_b.get_next_road_node() == rp_a:
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


# ------------------------------------------------------------------------------
#endregion
#region Top-level actions with undoredo
# ------------------------------------------------------------------------------


func add_roadcontainer_and_roadpoint(manager: RoadManager, pos: Vector3, nrm: Vector3) -> void:
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Create RoadContainer and RoadPoint")
	var container := RoadContainer.new()
	var rp := RoadPoint.new()
	
	container.name = "Road_001"
	undo_redo.add_do_method(manager, "add_child", container, true)
	undo_redo.add_do_method(container, "set_owner", manager.owner)
	var target_transform: Transform3D = manager.global_transform
	target_transform.basis = Basis.IDENTITY
	target_transform.origin = pos
	undo_redo.add_do_property(container, "global_transform", target_transform)
	
	rp.name = rp.increment_name("RP_001")
	undo_redo.add_do_method(container, "add_child", rp, true)
	undo_redo.add_do_method(rp, "set_owner", manager.owner)
	# TODO: do the RP raycast placement approach, including normal
	if nrm == Vector3.ZERO:
		pass
	else:
		var half_gutter: float = -0.5 * rp.gutter_profile.y
		var new_transform = target_transform
		new_transform.origin = pos + nrm * half_gutter
		undo_redo.add_do_property(rp, "global_transform", new_transform)
	
	undo_redo.add_do_reference(container)
	undo_redo.add_do_reference(rp)
	
	undo_redo.add_undo_method(container, "remove_child", rp)
	undo_redo.add_undo_method(rp, "set_owner", null)
	undo_redo.add_undo_method(manager, "remove_child", container)
	undo_redo.add_undo_method(container, "set_owner", null)
	
	var editor_selected:Array = _edi.get_selection().get_selected_nodes()
	undo_redo.add_do_method(self, "set_selection", rp)
	undo_redo.add_undo_method(self, "set_selection_list", editor_selected)
	
	undo_redo.commit_action()


## Converts the first RoadPoint into an intersection then adds the next one as a branch
func convert_to_intersection_with_new_branch(rp_init: RoadPoint, rp_branch: RoadPoint) -> void:
	var undo_redo = get_undo_redo()
	if rp_init.container != rp_branch.container:
		push_error("Source RoadPoints don't belong to the same RoadContainer")
		return
	
	undo_redo.create_action("Create intersection", 0, null, false) # if last arg=true -> backwards undo
	var inter = subaction_create_intersection(rp_init, rp_branch, undo_redo)
	undo_redo.add_do_method(rp_init.container, "rebuild_segments", false)
	undo_redo.add_undo_method(rp_init.container, "rebuild_segments", false)
	
	var editor_selected:Array = _edi.get_selection().get_selected_nodes()
	undo_redo.add_do_method(self, "set_selection", inter)
	undo_redo.add_undo_method(self, "set_selection_list", editor_selected)
	
	undo_redo.commit_action()


func add_and_connect_rp_to_intersection(inter: RoadIntersection, pos: Vector3, nrm: Vector3) -> void:
	var undo_redo = get_undo_redo()
	if not is_instance_valid(inter):
		push_error("Invalid RoadIntersection, cannot add and connect")
		return
	
	var rp := RoadPoint.new()
	
	undo_redo.create_action("Branch new RoadPoint from RoadIntersection")
	
	rp.name = rp.increment_name("RP_001")
	undo_redo.add_do_method(inter.container, "add_child", rp, true)
	undo_redo.add_do_method(rp, "set_owner", inter.owner)
	if nrm == Vector3.ZERO:
		nrm = Vector3.UP	 # workaround? should this ever be null?
		print("nrm was null for create branch from road container")

	var half_gutter: float = -0.5 * rp.gutter_profile.y
	var new_transform = inter.global_transform # weird to do this, use direct method to assign global?
	new_transform.origin = pos + nrm * half_gutter
	new_transform.basis.y = nrm # legal????
	undo_redo.add_do_property(rp, "global_transform", new_transform)
	undo_redo.add_do_method(rp, "look_at", inter.global_transform.origin, new_transform.basis.y)
	undo_redo.add_do_method(inter, "add_branch", rp)
	
	undo_redo.add_do_reference(rp)
	
	undo_redo.add_undo_method(inter, "remove_branch", rp)
	undo_redo.add_undo_method(inter.container, "remove_child", rp)
	undo_redo.add_undo_method(rp, "set_owner", null)
	
	undo_redo.add_do_method(self, "_call_update_edges", inter.container)
	undo_redo.add_undo_method(self, "_call_update_edges", inter.container)
	
	var editor_selected:Array = _edi.get_selection().get_selected_nodes()
	undo_redo.add_do_method(self, "set_selection", rp) # selection not retained???
	undo_redo.add_undo_method(self, "set_selection_list", editor_selected)
	undo_redo.commit_action()


func connect_rp_to_intersection(inter: RoadIntersection, rp: RoadPoint) -> void:
	var undo_redo = get_undo_redo()
	if inter.container != rp.container:
		push_error("RoadIntersection and RoadPoint don't belong to the same RoadContainer")
		return
	
	undo_redo.create_action("Connect RoadPoint to RoadIntersection")
	subaction_add_branch(inter, rp, undo_redo)
	undo_redo.add_do_method(self, "_call_update_edges", inter.container)
	undo_redo.add_undo_method(self, "_call_update_edges", inter.container)
	
	undo_redo.commit_action()


## Snap this selected sel_rp's container onto the tgt_rp of another container
##
## Only results in translating the whole RoadContainer, not RPs.
##
## Assumes the initial_trans is a single entry consiging of sel_rp's container.
func snap_container_to_road_point(sel_rp:RoadPoint, tgt_rp:RoadPoint, initial_trans: Array[Transform3D]) -> void:
	var undo_redo = get_undo_redo()
	if sel_rp.container == tgt_rp.container:
		push_error("Cannot snap a RoadContainer to itself")
		return

	# Precalculate the snapt-to locaiton
	var container: RoadContainer = sel_rp.container
	var res:Array = container.get_transform_for_snap_rp(sel_rp, tgt_rp)
	var tgt_transform: Transform3D = res[0]
	var sel_dir:int = res[1]
	var tgt_dir:int = res[2]

	undo_redo.create_action("Snap RoadContainer to RoadPoint")

	undo_redo.add_do_property(container, "global_transform", tgt_transform)
	undo_redo.add_do_method(sel_rp, "connect_container", sel_dir, tgt_rp, tgt_dir)

	undo_redo.add_undo_method(sel_rp, "disconnect_container", sel_dir, tgt_dir)
	undo_redo.add_undo_property(container, "global_transform", initial_trans[0])

	undo_redo.commit_action()


## Dragging a RoadContainer away from its connected points
func unsnap_container(container: RoadContainer, initial_trans: Array[Transform3D]) -> void:
	var undo_redo = get_undo_redo()
	var current_transform := container.global_transform
	container.update_edges() # Force current, to workaround some bad states seen
	
	undo_redo.create_action("Unsnap RoadContainer connections")
	
	for idx in container.edge_rp_locals.size():
		var local_rp: RoadPoint = container.get_node_or_null(container.edge_rp_locals[idx])
		var local_dir: int = container.edge_rp_local_dirs[idx]
		var other_cont: RoadContainer = container.get_node_or_null(container.edge_containers[idx])
		if not is_instance_valid(other_cont):
			continue # Empty slot
		var other_rp: RoadPoint = other_cont.get_node_or_null(container.edge_rp_targets[idx])
		var other_dir: int = container.edge_rp_target_dirs[idx]
		if not is_instance_valid(other_rp):
			continue
		undo_redo.add_do_method(local_rp, "disconnect_container", local_dir, other_dir)
	undo_redo.add_do_property(container, "global_transform", current_transform)

	# --  undo steps
	undo_redo.add_undo_property(container, "global_transform", initial_trans[0])
	for idx in container.edge_rp_locals.size():
		var local_rp: RoadPoint = container.get_node_or_null(container.edge_rp_locals[idx])
		var local_dir: int = container.edge_rp_local_dirs[idx]
		var other_rp: RoadPoint = container.get_node_or_null(container.edge_rp_targets[idx])
		var other_dir: int = container.edge_rp_target_dirs[idx]
		if not is_instance_valid(other_rp):
			continue
		undo_redo.add_undo_method(local_rp, "connect_container", local_dir, other_rp, other_dir)

	undo_redo.commit_action()


func disconnect_rp_from_intersection(inter: RoadIntersection, rp: RoadPoint) -> void:
	var undo_redo = get_undo_redo()
	if inter.container != rp.container:
		push_error("Intersection and RoadPoint don't belong to the same RoadContainer")
		return
	if not rp in inter.edge_points:
		push_error("RoadPoint not already connected to RoadIntersection")
		return
	
	undo_redo.create_action("Connect RoadPoint to RoadIntersection")
	undo_redo.add_do_method(inter, "remove_branch", rp)
	undo_redo.add_undo_method(inter, "add_branch", rp)
	undo_redo.add_do_method(self, "_call_update_edges", inter.container)
	undo_redo.add_undo_method(self, "_call_update_edges", inter.container)
	
	undo_redo.commit_action()


func delete_roadpoint(rp: RoadPoint) -> void:
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Delete RoadPoint")
	subaction_delete_roadpoint(rp, false, undo_redo)
	undo_redo.add_do_method(rp.container, "rebuild_segments", false)
	undo_redo.add_undo_method(rp.container, "rebuild_segments", false)
	
	# Update do/undo selections
	var editor_selected:Array = _edi.get_selection().get_selected_nodes()
	if editor_selected == [rp]:
		var next_rp = rp.get_next_road_node(true) # true = don't try to select another container's RP
		var prior_rp = rp.get_next_road_node(true)
		if is_instance_valid(next_rp):
			undo_redo.add_do_method(self, "set_selection", next_rp)
		elif is_instance_valid(prior_rp):
			undo_redo.add_do_method(self, "set_selection", prior_rp)
		else:
			undo_redo.add_do_method(self, "set_selection", rp.container)
	undo_redo.add_undo_method(self, "set_selection_list", editor_selected)
	undo_redo.commit_action()


func dissolve_roadpoint(rp: RoadPoint) -> void:
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Dissolve RoadPoint")
	subaction_delete_roadpoint(rp, true, undo_redo)
	undo_redo.add_do_method(rp.container, "rebuild_segments", false)
	undo_redo.add_undo_method(rp.container, "rebuild_segments", false)
	
	# Update do/undo selections
	var editor_selected:Array = _edi.get_selection().get_selected_nodes()
	if editor_selected == [rp]:
		var next_rp = rp.get_next_road_node()
		var prior_rp = rp.get_next_road_node()
		if is_instance_valid(next_rp):
			undo_redo.add_do_method(self, "set_selection", next_rp)
		elif is_instance_valid(prior_rp):
			undo_redo.add_do_method(self, "set_selection", prior_rp)
		else:
			undo_redo.add_do_method(self, "set_selection", rp.container)
	undo_redo.add_undo_method(self, "set_selection_list", editor_selected)
	undo_redo.commit_action()


func delete_intersection(inter: RoadIntersection) -> void:
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Delete RoadIntersection")
	subaction_delete_intersection(inter, undo_redo)
	var editor_selected:Array = _edi.get_selection().get_selected_nodes()
	if editor_selected == [inter]:
		var container := inter.container
		if is_instance_valid(container):
			undo_redo.add_do_method(self, "set_selection", container)
	undo_redo.add_undo_method(self, "set_selection_list", editor_selected)
	undo_redo.commit_action()


func dissolve_intersection(inter: RoadIntersection) -> void:
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Dissolve RoadIntersection")
	subaction_dissolve_intersection(inter, undo_redo)
	var editor_selected:Array = _edi.get_selection().get_selected_nodes()
	if editor_selected == [inter]:
		var container := inter.container
		if is_instance_valid(container):
			undo_redo.add_do_method(self, "set_selection", container)
	undo_redo.add_undo_method(self, "set_selection_list", editor_selected)
	undo_redo.commit_action()


func delete_roadcontainer(container: RoadContainer) -> void:
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Delete RoadContainer")
	subaction_delete_roadcontainer(container, undo_redo)
	var editor_selected:Array = _edi.get_selection().get_selected_nodes()
	if editor_selected == [container]:
		var mgr := container.get_manager()
		if is_instance_valid(mgr):
			undo_redo.add_do_method(self, "set_selection", mgr)
	undo_redo.add_undo_method(self, "set_selection_list", editor_selected)
	undo_redo.commit_action()


func add_and_configure_terrain3d_connector() -> void:
	var undo_redo = get_undo_redo()
	var connector := RoadTerrain3DConnector.new()
	connector.name = "RoadTerrain3DConnector"
	var editor_selected:Array = _edi.get_selection().get_selected_nodes()

	# First, find manager and determine node parent
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	var target_parent: Node = scene_root
	var init_node: Node = get_selected_node()
	var manager := get_manager_from_selection()
	if not is_instance_valid(manager):
		manager = _find_nodetype_recursive(scene_root, "RoadManager")

	if is_instance_valid(manager):
		connector.road_manager = manager
		target_parent = manager
	else:
		manager = null
		target_parent = EditorInterface.get_edited_scene_root()

	# Now find and assign Terrain3D if found
	var terrain_node: Node = _find_nodetype_recursive(scene_root, "Terrain3D")
	if is_instance_valid(terrain_node):
		connector.terrain = terrain_node

	undo_redo.create_action("Add RoadTerrain3DConnector")
	undo_redo.add_do_method(target_parent, "add_child", connector, true)
	if is_instance_valid(manager):
		undo_redo.add_do_method(target_parent, "move_child", connector, 0)
	undo_redo.add_do_method(connector, "set_owner", get_tree().get_edited_scene_root())
	undo_redo.add_do_method(self, "set_selection", connector)
	undo_redo.add_undo_method(target_parent, "remove_child", connector)
	undo_redo.add_undo_method(connector, "set_owner", null)
	undo_redo.add_undo_method(self, "set_selection_list", editor_selected)
	undo_redo.add_do_reference(connector)
	undo_redo.commit_action()


# ------------------------------------------------------------------------------
#endregion
#region Subactions for undoredo
# ------------------------------------------------------------------------------


func subaction_create_intersection(source_rp: RoadPoint, rp_branch: RoadPoint, undo_redo:EditorUndoRedoManager) -> RoadIntersection:
	var inter = RoadIntersection.new()
	var initial_branches = [source_rp.get_prior_road_node(true), source_rp.get_next_road_node(true), rp_branch]
	
	inter.name = "Intersection"
	undo_redo.add_do_method(source_rp.get_parent(), "add_child", inter, true)
	undo_redo.add_do_method(inter, "set_owner", source_rp.owner)
	var target_transform: Transform3D = source_rp.global_transform
	target_transform.basis = Basis.IDENTITY # Necesary as any rotation meses up generated mesh
	undo_redo.add_do_property(inter, "global_transform", target_transform)
	
	var prior_graph: RoadGraphNode
	var prior_rp: RoadPoint
	var prior_samedir: bool = true
	
	var next_graph: RoadGraphNode
	var next_rp: RoadPoint
	var next_samedir: bool = true
	if source_rp.prior_pt_init:
		prior_graph = source_rp.get_node(source_rp.prior_pt_init)
		if prior_graph.next_pt_init == prior_graph.get_path_to(source_rp):
			prior_rp = prior_graph
			prior_samedir = true
			undo_redo.add_do_method(source_rp, "disconnect_roadpoint", RoadPoint.PointInit.PRIOR, RoadPoint.PointInit.NEXT) # one should be flipped?
		elif prior_graph.prior_pt_init == prior_graph.get_path_to(source_rp):
			prior_rp = prior_graph
			prior_samedir = false
			undo_redo.add_do_method(source_rp, "disconnect_roadpoint", RoadPoint.PointInit.PRIOR, RoadPoint.PointInit.PRIOR) # one should be flipped?
		else:
			push_warning("Should be prior connected %s" % prior_graph.name)
			pass # not actually mutually connected?
	
	if source_rp.next_pt_init:
		next_graph = source_rp.get_node(source_rp.next_pt_init)
		if next_graph.prior_pt_init == next_graph.get_path_to(source_rp):
			next_rp = next_graph
			next_samedir = true
			undo_redo.add_do_method(source_rp, "disconnect_roadpoint", RoadPoint.PointInit.NEXT, RoadPoint.PointInit.PRIOR) # one should be flipped?
		elif next_graph.next_pt_init == next_graph.get_path_to(source_rp):
			next_rp = prior_graph
			next_samedir = false
			undo_redo.add_do_method(source_rp, "disconnect_roadpoint", RoadPoint.PointInit.NEXT, RoadPoint.PointInit.NEXT) # one should be flipped?
		else:
			push_warning("Should be prior connected %s" % next_graph.name)
			pass # not actually mutually connected?
	
	# Core removal
	undo_redo.add_do_method(source_rp.get_parent(), "remove_child", source_rp)
	undo_redo.add_undo_method(source_rp.get_parent(), "add_child", source_rp)
	undo_redo.add_undo_method(source_rp, "set_owner", get_tree().get_edited_scene_root())
	undo_redo.add_undo_reference(source_rp)
	
	for _branch in initial_branches:
		if not is_instance_valid(_branch) or not _branch is RoadPoint:
			continue
		#subaction_add_branch(inter, _branch, undo_redo)
		undo_redo.add_do_method(inter, "add_branch", _branch)
	undo_redo.add_do_reference(inter)
	
	# Undo steps
	for _branch in initial_branches:
		if not is_instance_valid(_branch) or not _branch is RoadPoint:
			continue
		undo_redo.add_undo_method(inter, "remove_branch", _branch)
	
	undo_redo.add_undo_method(source_rp.get_parent(), "remove_child", inter)
	undo_redo.add_undo_method(inter, "set_owner", null)
	
	for _rp in initial_branches:
		undo_redo.add_undo_property(_rp, "_is_internal_updating", true)
		undo_redo.add_undo_property(_rp, "prior_pt_init", _rp.prior_pt_init)
		undo_redo.add_undo_property(_rp, "next_pt_init", _rp.next_pt_init)
		undo_redo.add_undo_property(_rp, "_is_internal_updating", false)
	# And finally, restore the one which was deleted in favor of the intersection
	undo_redo.add_undo_property(source_rp, "_is_internal_updating", true)
	undo_redo.add_undo_property(source_rp, "prior_pt_init", source_rp.prior_pt_init)
	undo_redo.add_undo_property(source_rp, "next_pt_init", source_rp.next_pt_init)
	undo_redo.add_undo_property(source_rp, "_is_internal_updating", false)
	return inter


func subaction_add_branch(inter: RoadIntersection, rp: RoadPoint, undo_redo:EditorUndoRedoManager) -> void:
	undo_redo.add_do_method(inter, "add_branch", rp)
	undo_redo.add_undo_method(inter, "remove_branch", rp)


func subaction_delete_roadpoint(rp: RoadPoint, dissolve: bool, undo_redo:EditorUndoRedoManager) -> void:
	var prior_graph: RoadGraphNode
	var prior_rp: RoadPoint
	var prior_samedir: bool = true
	var prior_inter: RoadIntersection
	
	var next_graph: RoadGraphNode
	var next_rp: RoadPoint
	var next_samedir: bool = true
	var next_inter: RoadIntersection
	
	if rp.prior_pt_init:
		prior_graph = rp.get_node(rp.prior_pt_init)
		if prior_graph is RoadIntersection:
			prior_inter = prior_graph
			undo_redo.add_do_method(prior_inter, "remove_branch", rp)
		elif prior_graph.next_pt_init == prior_graph.get_path_to(rp):
			prior_rp = prior_graph
			prior_samedir = true
			undo_redo.add_do_method(rp, "disconnect_roadpoint", RoadPoint.PointInit.PRIOR, RoadPoint.PointInit.NEXT) # one should be flipped?
		elif prior_graph.prior_pt_init == prior_graph.get_path_to(rp):
			prior_rp = prior_graph
			prior_samedir = false
			undo_redo.add_do_method(rp, "disconnect_roadpoint", RoadPoint.PointInit.PRIOR, RoadPoint.PointInit.PRIOR) # one should be flipped?
		else:
			push_warning("Should be prior connected %s" % prior_graph.name)
			pass # not actually mutually connected?
	else:
		pass # TODO: check if cross-container selected, if so need to sever the edge
	
	if rp.next_pt_init:
		next_graph = rp.get_node(rp.next_pt_init)
		if next_graph is RoadIntersection:
			next_inter = next_graph
			undo_redo.add_do_method(next_inter, "remove_branch", rp)
		elif next_graph.prior_pt_init == next_graph.get_path_to(rp):
			next_rp = next_graph
			next_samedir = true
			undo_redo.add_do_method(rp, "disconnect_roadpoint", RoadPoint.PointInit.NEXT, RoadPoint.PointInit.PRIOR) # one should be flipped?
		elif next_graph.next_pt_init == next_graph.get_path_to(rp):
			next_rp = prior_graph
			next_samedir = false
			undo_redo.add_do_method(rp, "disconnect_roadpoint", RoadPoint.PointInit.NEXT, RoadPoint.PointInit.NEXT) # one should be flipped?
		else:
			push_warning("Should be prior connected %s" % next_graph.name)
			pass # not actually mutually connected?
	else:
		pass # TODO: check if cross-container selected, if so need to sever the edge
	
	
	# Core removal
	undo_redo.add_do_method(rp.get_parent(), "remove_child", rp)
	
	# Begin undo steps
	undo_redo.add_undo_method(rp.get_parent(), "add_child", rp)
	undo_redo.add_undo_method(rp, "set_owner", get_tree().get_edited_scene_root())
	undo_redo.add_undo_reference(rp)

	# dissolve steps (overlapping do/undo to same some if/else space
	if dissolve:
		if is_instance_valid(prior_rp) and is_instance_valid(next_rp):
			undo_redo.add_do_method(
				prior_rp,
				"connect_roadpoint",
				RoadPoint.PointInit.NEXT if prior_samedir else RoadPoint.PointInit.PRIOR,
				next_rp,
				RoadPoint.PointInit.PRIOR if next_samedir else RoadPoint.PointInit.NEXT,
			)
			undo_redo.add_undo_method(
				prior_rp,
				"disconnect_roadpoint",
				RoadPoint.PointInit.NEXT if prior_samedir else RoadPoint.PointInit.PRIOR,
				RoadPoint.PointInit.PRIOR if next_samedir else RoadPoint.PointInit.NEXT,
			)
		elif is_instance_valid(prior_rp) and is_instance_valid(next_inter):
			undo_redo.add_do_method(next_inter, "add_branch", prior_rp)
			undo_redo.add_undo_method(next_inter, "remove_branch", prior_rp)
		elif is_instance_valid(prior_inter) and is_instance_valid(next_rp):
			undo_redo.add_do_method(prior_inter, "add_branch", next_rp)
			undo_redo.add_undo_method(prior_inter, "remove_branch", next_rp)
	
	for _rp in [prior_rp, next_rp, rp]:
		if not is_instance_valid(_rp):
			continue
		undo_redo.add_undo_property(_rp, "_is_internal_updating", true)
		undo_redo.add_undo_property(_rp, "prior_pt_init", _rp.prior_pt_init)
		undo_redo.add_undo_property(_rp, "next_pt_init", _rp.next_pt_init)
		undo_redo.add_undo_property(_rp, "_is_internal_updating", false)
	for _inter in [prior_inter, next_inter]:
		if not is_instance_valid(_inter):
			continue
		var this_inter: RoadIntersection = _inter
		undo_redo.add_undo_property(_inter, "_is_internal_updating", true)
		undo_redo.add_undo_property(_inter, "edge_points", _inter.edge_points.duplicate())
		undo_redo.add_undo_property(_inter, "_is_internal_updating", false)
		#undo_redo.add_undo_method(_inter, "add_branch", rp)


func subaction_delete_intersection(inter: RoadIntersection, undo_redo:EditorUndoRedoManager) -> void:
	print("Doing subaction_delete_intersection")
	var edges := inter.edge_points.duplicate()
	
	for _rp in edges:
		if _rp.get_next_road_node() == inter:
			print("DID next_pt_init")
			undo_redo.add_do_property(_rp, "next_pt_init", "")
		if _rp.get_prior_road_node() == inter:
			print("DID prior_pt_init")
			undo_redo.add_do_property(_rp, "prior_pt_init", "")
	
	# Core removal
	undo_redo.add_do_method(inter.get_parent(), "remove_child", inter)
	undo_redo.add_undo_method(inter.get_parent(), "add_child", inter)
	undo_redo.add_undo_method(inter, "set_owner", get_tree().get_edited_scene_root())
	
	undo_redo.add_undo_reference(inter)
	
	for _rp in edges:
		if _rp.get_next_road_node() == inter:
			undo_redo.add_undo_property(_rp, "_is_internal_updating", true)
			undo_redo.add_undo_property(_rp, "next_pt_init", _rp.next_pt_init)
			undo_redo.add_undo_property(_rp, "_is_internal_updating", false)
		if _rp.get_prior_road_node() == inter:
			undo_redo.add_undo_property(_rp, "_is_internal_updating", true)
			undo_redo.add_undo_property(_rp, "prior_pt_init", _rp.prior_pt_init)
			undo_redo.add_undo_property(_rp, "_is_internal_updating", false)


## Dissolves an intersection, keeping the two largest roads lane-wise connected
func subaction_dissolve_intersection(inter: RoadIntersection, undo_redo:EditorUndoRedoManager) -> void:
	print("Doing subaction_dissolve_intersection")
	if inter.edge_points.size() < 2:
		# Will be the same as a simple delete in this scenario
		subaction_delete_intersection(inter, undo_redo)
		return
	
	# See if there's a better choice for rpa / rpb. Idea:
	# For RPA: pick the RoadPoint with the largest number of lanes
	var edges := inter.edge_points.duplicate()
	var rpa: RoadPoint
	var rpa_lanes: int = -1
	var rpa_next := false
	var rpb: RoadPoint
	var rpb_lanes: int = -1
	var rpb_next := false
	for _rp in edges:
		if rpa_lanes == -1:
			rpa_lanes = _rp.lanes.size()
			rpa = _rp
		elif _rp.lanes.size() > rpa_lanes:
			rpb_lanes = rpa_lanes
			rpb = rpa
			rpa_lanes = _rp.lanes.size()
			rpa = _rp
		elif rpb_lanes == -1:
			rpb_lanes = _rp.lanes.size()
			rpb = _rp
		elif _rp.lanes.size() > rpb_lanes:
			rpb_lanes = _rp.lanes.size()
			rpb = _rp
	
	undo_redo.add_do_property(inter, "_is_internal_updating", true)
	
	if rpa.get_next_road_node() == inter:
		print("DID next_pt_init")
		undo_redo.add_do_method(inter, "remove_branch", rpa)
		rpa_next = true
	elif rpa.get_prior_road_node() == inter:
		print("DID prior_pt_init")
		undo_redo.add_do_method(inter, "remove_branch", rpa)
		rpa_next = false
	
	if rpb.get_next_road_node() == inter:
		print("DID next_pt_init")
		undo_redo.add_do_method(inter, "remove_branch", rpb)
		rpb_next = true
	elif rpb.get_prior_road_node() == inter:
		print("DID prior_pt_init")
		undo_redo.add_do_method(inter, "remove_branch", rpb)
		rpb_next = false
	
	# TODO: disconenct other branches
	for _rp in edges:
		if _rp == rpa or _rp == rpb:
			continue
		undo_redo.add_do_method(inter, "remove_branch", _rp)

	# Now connect the other two 
	undo_redo.add_do_method(
		rpa,
		"connect_roadpoint",
		RoadPoint.PointInit.NEXT if rpa_next else RoadPoint.PointInit.PRIOR,
		rpb,
		RoadPoint.PointInit.NEXT if rpb_next else RoadPoint.PointInit.PRIOR,
	)
	
	# Do the dissolve connection
	undo_redo.add_do_method(inter.get_parent(), "remove_child", inter)
	undo_redo.add_undo_method(inter.get_parent(), "add_child", inter)
	undo_redo.add_undo_method(inter, "set_owner", get_tree().get_edited_scene_root())
	
	# Redo steps, in reverse order
	undo_redo.add_undo_reference(inter)
	undo_redo.add_undo_method(
		rpa,
		"disconnect_roadpoint",
		RoadPoint.PointInit.NEXT if rpa_next else RoadPoint.PointInit.PRIOR,
		RoadPoint.PointInit.NEXT if rpb_next else RoadPoint.PointInit.PRIOR,
	)
	
	# Save initial state before dissolve
	for _rp in edges:
		undo_redo.add_undo_method(inter, "add_branch", _rp)
	undo_redo.add_undo_property(inter, "_is_internal_updating", false)
	undo_redo.add_do_method(self, "_call_update_edges", inter.container)
	undo_redo.add_undo_method(self, "_call_update_edges", inter.container)


func subaction_delete_roadcontainer(container: RoadContainer, undo_redo:EditorUndoRedoManager) -> void:
	
	# We need to identify the container-level connection edges to clear
	var connected_conts: Array[RoadContainer] = []
	for idx in container.edge_containers.size():
		var _cont: RoadContainer = container.get_node_or_null(container.edge_containers[idx])
		if not is_instance_valid(_cont):
			continue
		connected_conts.append(_cont)
		
		# Need to find which indexs of this connected container point back to the original
		var cp_edge_containers := _cont.edge_containers.duplicate()
		var cp_edge_rp_targets := _cont.edge_rp_targets.duplicate()
		var cp_edge_rp_target_dirs := _cont.edge_rp_target_dirs.duplicate()
		for jdx in _cont.edge_containers.size():
			var _cont_back: RoadContainer = _cont.get_node_or_null(_cont.edge_containers[jdx])
			if _cont_back != container:
				continue
			cp_edge_containers[jdx] = ^""
			cp_edge_rp_targets[jdx] = ^""
			cp_edge_rp_target_dirs[jdx] = -1
		undo_redo.add_do_property(_cont, "edge_containers", cp_edge_containers)
		undo_redo.add_do_property(_cont, "edge_rp_targets", cp_edge_rp_targets)
		undo_redo.add_do_property(_cont, "edge_rp_target_dirs", cp_edge_rp_target_dirs)
	
	undo_redo.add_do_method(container.get_parent(), "remove_child", container)
	undo_redo.add_undo_method(container.get_parent(), "add_child", container)
	undo_redo.add_undo_method(container, "set_owner", get_tree().get_edited_scene_root())
	
	undo_redo.add_undo_reference(container)
	for _cont in connected_conts:
		undo_redo.add_undo_property(_cont, "edge_containers", _cont.edge_containers)
		undo_redo.add_undo_property(_cont, "edge_rp_targets", _cont.edge_rp_targets)
		undo_redo.add_undo_property(_cont, "edge_rp_target_dirs", _cont.edge_rp_target_dirs)


## Utility to call within an undo/redo transaction to flip around a RoadPoint
## including handling of connections
func subaction_flip_roadpoint(rp: RoadPoint, undo_redo:EditorUndoRedoManager) -> void:
	# TODO: see if we can reuse?
	#var undo_redo = get_undo_redo()
	var flipped_transform = rp.transform
	flipped_transform = flipped_transform.rotated_local(Vector3.UP, PI)
	
	# Flip all assymetric roadpoint properties
	undo_redo.add_do_method(rp, "set_internal_updating", true)
	undo_redo.add_undo_method(rp, "set_internal_updating", true)
	
	undo_redo.add_do_property(rp, "prior_pt_init", rp.next_pt_init)
	undo_redo.add_undo_property(rp, "prior_pt_init", rp.prior_pt_init)
	undo_redo.add_do_property(rp, "next_pt_init", rp.prior_pt_init)
	undo_redo.add_undo_property(rp, "next_pt_init", rp.next_pt_init)
	
	undo_redo.add_do_property(rp, "shoulder_width_l", rp.shoulder_width_r)
	undo_redo.add_undo_property(rp, "shoulder_width_l", rp.shoulder_width_l)
	undo_redo.add_do_property(rp, "shoulder_width_r", rp.shoulder_width_l)
	undo_redo.add_undo_property(rp, "shoulder_width_r", rp.shoulder_width_r)
	
	# Flip lanes around. e.g. we want to go from [-1, 1, 1] to [-1, -1, 1]
	var _tmp_dirs:Array[RoadPoint.LaneDir] = rp.traffic_dir.duplicate(true)
	_tmp_dirs.reverse()
	var _new_traffic_dirs:Array[RoadPoint.LaneDir] = []
	var _initial_dirs:Array[RoadPoint.LaneDir] = rp.traffic_dir.duplicate(true)
	for _dir in _tmp_dirs:
		match _dir:
			RoadPoint.LaneDir.FORWARD:
				_new_traffic_dirs.append(RoadPoint.LaneDir.REVERSE)
			RoadPoint.LaneDir.REVERSE:
				_new_traffic_dirs.append(RoadPoint.LaneDir.FORWARD)
			RoadPoint.LaneDir.BOTH:
				_new_traffic_dirs.append(RoadPoint.LaneDir.BOTH)
			RoadPoint.LaneDir.NONE:
				_new_traffic_dirs.append(RoadPoint.LaneDir.NONE)

	undo_redo.add_do_property(rp, "traffic_dir", _new_traffic_dirs)
	undo_redo.add_undo_property(rp, "traffic_dir", _initial_dirs)
	
	undo_redo.add_do_property(rp, "prior_mag", rp.next_mag)
	undo_redo.add_undo_property(rp, "prior_mag", rp.prior_mag)
	undo_redo.add_do_property(rp, "next_mag", rp.prior_mag)
	undo_redo.add_undo_property(rp, "next_mag", rp.next_mag)
	
	undo_redo.add_do_property(rp, "transform", flipped_transform)
	undo_redo.add_undo_property(rp, "transform", rp.transform)
	
	# Update direction references within this and connected RoadContainers
	if rp.is_on_edge() and is_instance_valid(rp.container):
		var edge_rp_local_dirs_old:Array[int] = rp.container.edge_rp_local_dirs.duplicate(true)
		var edge_rp_local_dirs_new:Array[int] = edge_rp_local_dirs_old.duplicate(true)
		for _idx in range(len(rp.container.edge_rp_locals)):
			if rp.container.get_node(rp.container.edge_rp_locals[_idx]) == rp:
				edge_rp_local_dirs_new[_idx] = 0 if edge_rp_local_dirs_new[_idx] == 1 else 1
		undo_redo.add_do_property(rp.container, "edge_rp_local_dirs", edge_rp_local_dirs_new)
		undo_redo.add_undo_property(rp.container, "edge_rp_local_dirs", edge_rp_local_dirs_old)
		
		# Check if cross-container connected at this RP and grab container if so
		var _pr = rp.get_prior_road_node()
		var _nt = rp.get_next_road_node()
		var other_cont:RoadContainer
		if is_instance_valid(_pr) and _pr.container != rp.container:
			other_cont = _pr.container
		elif is_instance_valid(_nt) and _nt.container != rp.container:
			other_cont = _nt.container
		
		# Now update the other direction too
		if is_instance_valid(other_cont):
			var edge_rp_target_dirs_old:Array[int] = other_cont.edge_rp_target_dirs.duplicate(true)
			var edge_rp_target_dirs_new:Array[int] = edge_rp_target_dirs_old.duplicate(true)
			for _idx in range(len(other_cont.edge_rp_target_dirs)):
				if other_cont.get_node(other_cont.edge_containers[_idx]) != rp.container:
					continue
				if rp.container.get_node(other_cont.edge_rp_targets[_idx]) == rp:
					edge_rp_target_dirs_new[_idx] = 0 if edge_rp_target_dirs_new[_idx] == 1 else 1
			undo_redo.add_do_property(other_cont, "edge_rp_target_dirs", edge_rp_target_dirs_new)
			undo_redo.add_undo_property(other_cont, "edge_rp_target_dirs", edge_rp_target_dirs_old)
	
	undo_redo.add_do_method(rp, "set_internal_updating", false)
	undo_redo.add_undo_method(rp, "set_internal_updating", false)
	
	undo_redo.add_do_method(rp.container, "rebuild_segments", true)
	undo_redo.add_undo_method(rp.container, "rebuild_segments", true)


## Adds a single RoadPoint to the scene
func _create_roadpoint_pressed() -> void:
	var undo_redo = get_undo_redo()
	var t_container = get_container_from_selection()
	if not is_instance_valid(t_container):
		push_error("Invalid selection context")
		return
	
	var selected_node := get_selected_node()

	undo_redo.create_action("Add RoadPoint")
	if selected_node is RoadContainer:
		var editor_selected:Array = _edi.get_selection().get_selected_nodes()
		var rp := RoadPoint.new()
		rp.name = rp.increment_name("RP_001")
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
	var selected_node := get_selected_node()
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


func _export_mesh_modal() -> void:
	var selected := get_selected_node()
	if not selected is RoadContainer:
		push_error("Must have RoadContainer selected to export to gLTF")
		return
	
	var basepath: String
	if selected.get_owner() and selected.get_owner().scene_file_path:
		var subpath := selected.get_owner().scene_file_path
		basepath = subpath.get_basename() + "_"
	else:
		basepath = "res://"

	var path := "%s%s_geo.glb" % [basepath, selected.name]
	var abspath := ProjectSettings.globalize_path(path)

	var editorViewport = Engine.get_singleton(&"EditorInterface").get_editor_viewport_3d()
	_export_file_dialog = FileDialog.new()
	
	_export_file_dialog.file_selected.connect(_export_gltf)
	_export_file_dialog.current_dir = abspath.get_base_dir()
	_export_file_dialog.current_path = abspath
	_export_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_file_dialog.title = "Export RoadContainer to gLTF"
	
	_export_file_dialog.set_option_count(1)
	_export_file_dialog.set_option_name(0, "Instance after export")
	_export_file_dialog.set_option_values(0, ["Yes", "No"])
	_export_file_dialog.set_option_default(0, 1)
	
	editorViewport.add_child(_export_file_dialog, true)
	_export_file_dialog.popup_centered_ratio()


func _export_gltf(path: String) -> void:
	var container:RoadContainer = get_selected_node()
	
	if not path.get_extension() in ["glb", "gltf"]:
		path = "%s.%s" % [path, "glb"]
		print("Resolved path to: ", path)
	
	# Identify options selected
	var _option_values := _export_file_dialog.get_selected_options()
	var option_index:int = _option_values[_export_file_dialog.get_option_name(0)]
	var instance_after_export:bool = option_index == 0
	
	var meshes: Array[Mesh] = []
	var unset_owners:Array[Array] = []
	for _seg in container.get_segments():
		var seg := _seg as RoadSegment 
		unset_owners.append([_seg, _seg.owner])
		_seg.owner = container.get_owner()
		if is_instance_valid(seg.road_mesh):
			meshes.append(seg.road_mesh.mesh)
			unset_owners.append([seg.road_mesh, seg.road_mesh.owner])
			seg.road_mesh.owner = container.get_owner()
	for _intersec in container.get_intersections():
		var intersec := _intersec as RoadIntersection
		unset_owners.append([intersec, intersec.owner])
		intersec.owner = container.get_owner()
		if is_instance_valid(intersec._mesh):
			meshes.append(intersec._mesh.mesh)
			unset_owners.append([intersec._mesh, intersec._mesh.owner])
			intersec._mesh.owner = container.get_owner()
		
	
	var gltf_document_save := GLTFDocument.new()
	var gltf_state_save := GLTFState.new()

	# This works, but export *everything* contained, not just the road segment
	# meshes. Potential improvement or execution option: temporarily instance
	# another branch of the node tree with just the meshes placed as needed.
	gltf_document_save.append_from_scene(container, gltf_state_save)
	gltf_document_save.write_to_filesystem(gltf_state_save, path)
	
	# Undo the owner overrides
	for unsetter in unset_owners:
		unsetter[0].owner = unsetter[1]

	if instance_after_export:
		_instance_gltf_post_export(container, path)
	else:
		Engine.get_singleton(&"EditorInterface").get_resource_filesystem().scan_sources()

	_export_file_dialog.queue_free()


func _instance_gltf_post_export(container:RoadContainer, export_file: String) -> void:
	var local_path := ProjectSettings.localize_path(export_file)
	if export_file == local_path and not export_file.begins_with("res://"):
		push_error("Failed to localize the path, ensure gltf was saved within project folder to instance after")
		return
	
	Engine.get_singleton(&"EditorInterface").get_resource_filesystem().update_file(local_path)
	Engine.get_singleton(&"EditorInterface").get_resource_filesystem().reimport_files([local_path])
	
	var glb_scene:PackedScene = load(export_file)
	if not glb_scene:
		push_error("Failed load gltf/glb export, check output path and try again")
		return
	
	var glb_model:Node3D = glb_scene.instantiate()
	glb_model.name = export_file.get_file().get_basename()
	
	# Undo/redoable part of action
	# TODO: Revisit this, the "do" action works, but undo is unstable/can crash godot.
	#var undo_redo = get_undo_redo()
	#undo_redo.create_action("Replace road geo with instance")
	#undo_redo.add_do_method(container, "add_child", glb_model, true)
	#undo_redo.add_do_method(glb_model, "set_owner", get_tree().get_edited_scene_root())
	#undo_redo.add_do_property(container, "create_geo", false)
	#undo_redo.add_do_reference(glb_model)
	#undo_redo.add_undo_property(container, "create_geo", container.create_geo)
	#undo_redo.add_undo_method(container, "remove_child", glb_model)
	#undo_redo.commit_action()
	
	container.add_child(glb_model)
	glb_model.owner = container.get_owner()
	container.create_geo = false


## Open up the addon feedback form
func _on_feedback_pressed() -> void:
	const FORM_BASE_URL := "https://docs.google.com/forms/d/e/1FAIpQLSdNbtXvw0FYQGEKpnqhpJZyujxFsabTk4i3SHPXYA6UGRdG9w/viewform"
	const GODOT_FIELD_ID := "entry.600361287"
	const ADDON_FIELD_ID := "entry.474237825"
	
	var version_info := Engine.get_version_info()
	var godot_version := "%d.%d" % [version_info["major"], version_info["minor"]]
	if version_info["status"] != "stable":
		godot_version += "-%s" % version_info["status"]

	var url = "%s?%s=%s&%s=%s" % [
		FORM_BASE_URL,
		GODOT_FIELD_ID,
		godot_version,
		ADDON_FIELD_ID,
		plugin_version
	]
	OS.shell_open(url)


func _on_report_issue_pressed() -> void:
	OS.shell_open("https://github.com/TheDuckCow/godot-road-generator/issues")


## Adds a single RoadLane to the scene.
func _create_lane_pressed() -> void:
	var undo_redo = get_undo_redo()
	var target_parent := get_selected_node()

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
	var target_parent := get_selected_node()

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

#endregion
# ------------------------------------------------------------------------------
