# Panel which is added to UI and used to trigger callbacks to update road points
tool
extends VBoxContainer

signal on_lane_change_pressed(selection, direction, change_type)
signal on_add_connected_rp(selection, point_init_type)

# EditorInterface, don't use as type:
# https://github.com/godotengine/godot/issues/85079
var _edi setget set_edi
var sel_road_point: RoadPoint
onready var top_label = $SectionLabel
onready var btn_add_lane_fwd = $HBoxLanes/HBoxSubLanes/fwd_add
onready var btn_add_lane_rev = $HBoxLanes/HBoxSubLanes/rev_add
onready var btn_rem_lane_fwd = $HBoxLanes/HBoxSubLanes/fwd_minus
onready var btn_rem_lane_rev = $HBoxLanes/HBoxSubLanes/rev_minus
onready var btn_sel_rp_next = $HBoxSelNextRP/sel_rp_front
onready var btn_sel_rp_prior = $HBoxSelPriorRP/sel_rp_back
onready var btn_add_rp_next = $HBoxAddNextRP/add_rp_front
onready var btn_add_rp_prior = $HBoxAddPriorRP/add_rp_back
onready var hbox_add_rp_next = $HBoxAddNextRP
onready var hbox_add_rp_prior = $HBoxAddPriorRP
onready var hbox_sel_rp_next = $HBoxSelNextRP
onready var hbox_sel_rp_prior = $HBoxSelPriorRP


func _ready():
	btn_add_lane_fwd.connect("pressed", self, "add_lane_fwd_pressed")
	btn_add_lane_rev.connect("pressed", self, "add_lane_rev_pressed")
	btn_rem_lane_fwd.connect("pressed", self, "rem_lane_fwd_pressed")
	btn_rem_lane_rev.connect("pressed", self, "rem_lane_rev_pressed")
	btn_sel_rp_next.connect("pressed", self, "sel_rp_next_pressed")
	btn_sel_rp_prior.connect("pressed", self, "sel_rp_prior_pressed")
	btn_add_rp_next.connect("pressed", self, "add_rp_next_pressed")
	btn_add_rp_prior.connect("pressed", self, "add_rp_prior_pressed")
	update_labels(Input.is_key_pressed(KEY_SHIFT))

func _unhandled_key_input(event: InputEventKey) -> void:
	if not event.scancode == KEY_SHIFT:
		return
	update_labels(event.pressed)


func update_labels(shift_pressed: bool) -> void:
	# Without setting the right min width toggling shift will
	# actually make the inspector shrink/grow a few pixels,
	# offsetting the entire 3D view to the left (huge pain!)
	# TODO: validate this works consistently across OS's and monitor scals/densities,
	# could also use: # OS.get_screen_max_scale()
	var fac: float = OS.get_screen_scale()
	btn_sel_rp_next.rect_min_size.x = 150 * fac
	btn_add_rp_next.rect_min_size.x = 150 * fac

	if shift_pressed:
		top_label.text = "Edit Container's RoadPoints"
		btn_sel_rp_next.text = "Select Last RoadPoint"
		btn_sel_rp_prior.text = "Select First RoadPoint"
	else:
		top_label.text = "Edit RoadPoint"
		btn_sel_rp_next.text = "Select Next RoadPoint"
		btn_sel_rp_prior.text = "Select Prior RoadPoint"


func update_road_point_panel():
	var fwd_lane_count = sel_road_point.get_fwd_lane_count()
	var rev_lane_count = sel_road_point.get_rev_lane_count()
	var lane_count = fwd_lane_count + rev_lane_count

	if lane_count > 1 and fwd_lane_count > 0:
		btn_rem_lane_fwd.disabled = false
	else:
		btn_rem_lane_fwd.disabled = true

	if lane_count > 1 and rev_lane_count > 0:
		btn_rem_lane_rev.disabled = false
	else:
		btn_rem_lane_rev.disabled = true

	if sel_road_point.next_pt_init:
		hbox_add_rp_next.visible = false
		hbox_sel_rp_next.visible = true
	else:
		hbox_add_rp_next.visible = true
		hbox_sel_rp_next.visible = false

	if sel_road_point.prior_pt_init:
		hbox_add_rp_prior.visible = false
		hbox_sel_rp_prior.visible = true
	else:
		hbox_add_rp_prior.visible = true
		hbox_sel_rp_prior.visible = false

	property_list_changed_notify()


func add_lane_fwd_pressed():
	#gd4
	# Here and below, change to:
	#on_lane_change_pressed.emit(sel_road_point, RoadPoint.TrafficUpdate.ADD_FORWARD)
	var bulk:bool = Input.is_key_pressed(KEY_SHIFT)
	emit_signal("on_lane_change_pressed", sel_road_point, RoadPoint.TrafficUpdate.ADD_FORWARD, bulk)
	update_road_point_panel()


func add_lane_rev_pressed():
	var bulk:bool = Input.is_key_pressed(KEY_SHIFT)
	emit_signal("on_lane_change_pressed", sel_road_point, RoadPoint.TrafficUpdate.ADD_REVERSE, bulk)
	update_road_point_panel()


func rem_lane_fwd_pressed():
	var bulk:bool = Input.is_key_pressed(KEY_SHIFT)
	emit_signal("on_lane_change_pressed", sel_road_point, RoadPoint.TrafficUpdate.REM_FORWARD, bulk)
	update_road_point_panel()


func rem_lane_rev_pressed():
	var bulk:bool = Input.is_key_pressed(KEY_SHIFT)
	emit_signal("on_lane_change_pressed", sel_road_point, RoadPoint.TrafficUpdate.REM_REVERSE, bulk)
	update_road_point_panel()


func sel_rp_next_pressed():
	#gd4
	# not is empty
	if not sel_road_point.next_pt_init:
		return

	var next_pt = sel_road_point.get_node(sel_road_point.next_pt_init)
	if Input.is_key_pressed(KEY_SHIFT):
		# Jump to to the "end" roadpoint in this direction (if it loops around, returns the same)
		next_pt = next_pt.get_last_rp(RoadPoint.PointInit.NEXT)
	_edi.get_selection().call_deferred("remove_node", sel_road_point)
	_edi.get_selection().call_deferred("add_node", next_pt)


func sel_rp_prior_pressed():
	#gd4
	# not is empty
	if not sel_road_point.prior_pt_init:
		return

	var prior_pt = sel_road_point.get_node(sel_road_point.prior_pt_init)
	if Input.is_key_pressed(KEY_SHIFT):
		# Jump to to the "end" roadpoint in this direction (if it loops around, returns the same)
		prior_pt = prior_pt.get_last_rp(RoadPoint.PointInit.PRIOR)
	_edi.get_selection().call_deferred("remove_node", sel_road_point)
	_edi.get_selection().call_deferred("add_node", prior_pt)


func add_rp_next_pressed():
	emit_signal("on_add_connected_rp", sel_road_point, RoadPoint.PointInit.NEXT)


func add_rp_prior_pressed():
	emit_signal("on_add_connected_rp", sel_road_point, RoadPoint.PointInit.PRIOR)


## Adds a numeric sequence to the end of a RoadPoint name
func increment_name(old_name) -> String:
	var new_name = old_name
	if not old_name[-1].is_valid_integer():
		new_name += "001"
	return new_name


func update_selected_road_point(object):
	sel_road_point = object
	update_road_point_panel()


func set_edi(value):
	_edi = value
