# Panel which is added to UI and used to trigger callbacks to update road points
tool
extends VBoxContainer

var selected_road_point :RoadPoint


func _ready():
	$HBoxContainer/Button.connect("pressed", self, "_button_pressed")


func _button_pressed():
	print_debug("Selected road point is %s" % selected_road_point.name)


func update_selected_road_point(object):
	selected_road_point = object
