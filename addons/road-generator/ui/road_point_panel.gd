@tool
# Panel which is added to UI and used to trigger callbacks to update road points
extends VBoxContainer

signal on_lane_change_pressed(selection, direction, change_type)
signal on_add_connected_rp(selection, point_init_type)

var sel_road_point: RoadPoint
var _edi: EditorInterface: set = set_edi
@onready var btn_add_lane_fwd = $HBoxLanes/HBoxSubLanes/fwd_add
@onready var btn_add_lane_rev = $HBoxLanes/HBoxSubLanes/rev_add
@onready var btn_rem_lane_fwd = $HBoxLanes/HBoxSubLanes/fwd_minus
@onready var btn_rem_lane_rev = $HBoxLanes/HBoxSubLanes/rev_minus
@onready var btn_sel_rp_next = $HBoxSelNextRP/sel_rp_front
@onready var btn_sel_rp_prior = $HBoxSelPriorRP/sel_rp_back
@onready var btn_add_rp_next = $HBoxAddNextRP/add_rp_front
@onready var btn_add_rp_prior = $HBoxAddPriorRP/add_rp_back
@onready var hbox_add_rp_next = $HBoxAddNextRP
@onready var hbox_add_rp_prior = $HBoxAddPriorRP
@onready var hbox_sel_rp_next = $HBoxSelNextRP
@onready var hbox_sel_rp_prior = $HBoxSelPriorRP


func _ready():
	btn_add_lane_fwd.connect("pressed", Callable(self, "add_lane_fwd_pressed"))
	btn_add_lane_rev.connect("pressed", Callable(self, "add_lane_rev_pressed"))
	btn_rem_lane_fwd.connect("pressed", Callable(self, "rem_lane_fwd_pressed"))
	btn_rem_lane_rev.connect("pressed", Callable(self, "rem_lane_rev_pressed"))
	btn_sel_rp_next.connect("pressed", Callable(self, "sel_rp_next_pressed"))
	btn_sel_rp_prior.connect("pressed", Callable(self, "sel_rp_prior_pressed"))
	btn_add_rp_next.connect("pressed", Callable(self, "add_rp_next_pressed"))
	btn_add_rp_prior.connect("pressed", Callable(self, "add_rp_prior_pressed"))


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

	notify_property_list_changed()


func add_lane_fwd_pressed():
	emit_signal("on_lane_change_pressed", sel_road_point, RoadPoint.TrafficUpdate.ADD_FORWARD)
	update_road_point_panel()


func add_lane_rev_pressed():
	emit_signal("on_lane_change_pressed", sel_road_point, RoadPoint.TrafficUpdate.ADD_REVERSE)
	update_road_point_panel()


func rem_lane_fwd_pressed():
	emit_signal("on_lane_change_pressed", sel_road_point, RoadPoint.TrafficUpdate.REM_FORWARD)
	update_road_point_panel()


func rem_lane_rev_pressed():
	emit_signal("on_lane_change_pressed", sel_road_point, RoadPoint.TrafficUpdate.REM_REVERSE)
	update_road_point_panel()


func sel_rp_next_pressed():
	if sel_road_point.next_pt_init:
		var next_pt = sel_road_point.get_node(sel_road_point.next_pt_init)
		_edi.get_selection().call_deferred("remove_node", sel_road_point)
		_edi.get_selection().call_deferred("add_node", next_pt)


func sel_rp_prior_pressed():
	if sel_road_point.prior_pt_init:
		var prior_pt = sel_road_point.get_node(sel_road_point.prior_pt_init)
		_edi.get_selection().call_deferred("remove_node", sel_road_point)
		_edi.get_selection().call_deferred("add_node", prior_pt)


func add_rp_next_pressed():
	emit_signal("on_add_connected_rp", sel_road_point, RoadPoint.PointInit.NEXT)


func add_rp_prior_pressed():
	emit_signal("on_add_connected_rp", sel_road_point, RoadPoint.PointInit.PRIOR)


## Adds a numeric sequence to the end of a RoadPoint name
func increment_name(old_name) -> String:
	var new_name = old_name
	if not old_name[-1].is_valid_int():
		new_name += "001"
	return new_name


func update_selected_road_point(object):
	sel_road_point = object
	update_road_point_panel()


func set_edi(value):
	_edi = value
