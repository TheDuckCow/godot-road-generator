# Panel which is added to UI and used to trigger callbacks to update road points
tool
extends VBoxContainer


enum PointInit {
	NEXT,
	PRIOR,
}


const seg_dist_mult: float = 4.0


var sel_road_point: RoadPoint
var _edi: EditorInterface setget set_edi
onready var btn_add_lane_fwd = $HBoxLanes/HBoxSubLanes/fwd_add
onready var btn_add_lane_rev = $HBoxLanes/HBoxSubLanes/rev_add
onready var btn_rem_lane_fwd = $HBoxLanes/HBoxSubLanes/fwd_minus
onready var btn_rem_lane_rev = $HBoxLanes/HBoxSubLanes/rev_minus
onready var btn_move_div_left = $HBoxLanes/HBoxSubLanes/move_left
onready var btn_move_div_right = $HBoxLanes/HBoxSubLanes/move_right
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
	btn_move_div_left.connect("pressed", self, "move_div_left_pressed")
	btn_move_div_right.connect("pressed", self, "move_div_right_pressed")
	btn_sel_rp_next.connect("pressed", self, "sel_rp_next_pressed")
	btn_sel_rp_prior.connect("pressed", self, "sel_rp_prior_pressed")
	btn_add_rp_next.connect("pressed", self, "add_rp_next_pressed")
	btn_add_rp_prior.connect("pressed", self, "add_rp_prior_pressed")


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
	sel_road_point.update_traffic_dir(RoadPoint.TrafficUpdate.ADD_FORWARD)
	update_road_point_panel()

func add_lane_rev_pressed():
	sel_road_point.update_traffic_dir(RoadPoint.TrafficUpdate.ADD_REVERSE)
	update_road_point_panel()

func rem_lane_fwd_pressed():
	sel_road_point.update_traffic_dir(RoadPoint.TrafficUpdate.REM_FORWARD)
	update_road_point_panel()

func rem_lane_rev_pressed():
	sel_road_point.update_traffic_dir(RoadPoint.TrafficUpdate.REM_REVERSE)
	update_road_point_panel()

func move_div_left_pressed():
	pass

func move_div_right_pressed():
	pass


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
	add_road_point(PointInit.NEXT)
	if sel_road_point.next_pt_init:
		var next_pt = sel_road_point.get_node(sel_road_point.next_pt_init)
		_edi.get_selection().call_deferred("remove_node", sel_road_point)
		_edi.get_selection().call_deferred("add_node", next_pt)

func add_rp_prior_pressed():
	add_road_point(PointInit.PRIOR)
	if sel_road_point.prior_pt_init:
		var prior_pt = sel_road_point.get_node(sel_road_point.prior_pt_init)
		_edi.get_selection().call_deferred("remove_node", sel_road_point)
		_edi.get_selection().call_deferred("add_node", prior_pt)


func add_road_point(pt_init):
	var points = sel_road_point.get_parent()
	var new_road_point = copy_road_point(sel_road_point)
	var lane_width: float = new_road_point.lane_width
	var basis_z = new_road_point.transform.basis.z	
	
	new_road_point.name = increment_name(sel_road_point.name)
	points.add_child(new_road_point, true)
	new_road_point.owner = points.owner
	
	match pt_init:
		PointInit.NEXT:
			new_road_point.transform.origin += seg_dist_mult * lane_width * basis_z
			new_road_point.prior_pt_init = new_road_point.get_path_to(sel_road_point)
			sel_road_point.next_pt_init = sel_road_point.get_path_to(new_road_point)
		PointInit.PRIOR:
			new_road_point.transform.origin -= seg_dist_mult * lane_width * basis_z
			new_road_point.next_pt_init = new_road_point.get_path_to(sel_road_point)
			sel_road_point.prior_pt_init = sel_road_point.get_path_to(new_road_point)


## Takes an existing RoadPoint and returns a new copy
func copy_road_point(old_road_point: RoadPoint) -> RoadPoint:
	var new_road_point = RoadPoint.new()
	new_road_point.auto_lanes = false
	new_road_point.lanes = old_road_point.lanes.duplicate(true)
	new_road_point.traffic_dir = old_road_point.traffic_dir.duplicate(true)
	new_road_point.auto_lanes = old_road_point.auto_lanes
	new_road_point.lane_width = old_road_point.lane_width
	new_road_point.shoulder_width_l = old_road_point.shoulder_width_l
	new_road_point.shoulder_width_r = old_road_point.shoulder_width_r
	new_road_point.gutter_profile.x = old_road_point.gutter_profile.x
	new_road_point.gutter_profile.y = old_road_point.gutter_profile.y
	new_road_point.prior_mag = old_road_point.prior_mag
	new_road_point.next_mag = old_road_point.next_mag
	new_road_point.global_transform = old_road_point.global_transform
	new_road_point._last_update_ms = old_road_point._last_update_ms
	return new_road_point


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
