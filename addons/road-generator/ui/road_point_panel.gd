# Panel which is added to UI and used to trigger callbacks to update road points
tool
extends VBoxContainer


var selected_road_point :RoadPoint
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
	var fwd_lane_count = selected_road_point.get_fwd_lane_count()
	var rev_lane_count = selected_road_point.get_rev_lane_count()
	var lane_count = fwd_lane_count + rev_lane_count
	
	if lane_count > 1 and fwd_lane_count > 0:
		btn_rem_lane_fwd.disabled = false
	else:
		btn_rem_lane_fwd.disabled = true
	
	if lane_count > 1 and rev_lane_count > 0:
		btn_rem_lane_rev.disabled = false
	else:
		btn_rem_lane_rev.disabled = true
	
	property_list_changed_notify()


func add_lane_fwd_pressed():
	selected_road_point.update_traffic_dir(RoadPoint.TrafficUpdate.ADD_FORWARD)
	update_road_point_panel()

func add_lane_rev_pressed():
	selected_road_point.update_traffic_dir(RoadPoint.TrafficUpdate.ADD_REVERSE)
	update_road_point_panel()

func rem_lane_fwd_pressed():
	selected_road_point.update_traffic_dir(RoadPoint.TrafficUpdate.REM_FORWARD)
	update_road_point_panel()

func rem_lane_rev_pressed():
	selected_road_point.update_traffic_dir(RoadPoint.TrafficUpdate.REM_REVERSE)
	update_road_point_panel()

func move_div_left_pressed():
	print("move_div_left_pressed")
	#update_traffic_direction(RoadPoint.TrafficUpdate.MOVE_DIVIDER_LEFT)

func move_div_right_pressed():
	print("move_div_right_pressed")
	#update_traffic_direction(RoadPoint.TrafficUpdate.MOVE_DIVIDER_RIGHT)


func sel_rp_next_pressed():
	print("sel_rp_next_pressed")

func sel_rp_prior_pressed():
	print("sel_rp_prior_pressed")

func add_rp_next_pressed():
	print("add_rp_next_pressed")

func add_rp_prior_pressed():
	print("add_rp_prior_pressed")


func update_selected_road_point(object):
	selected_road_point = object
	update_road_point_panel()
