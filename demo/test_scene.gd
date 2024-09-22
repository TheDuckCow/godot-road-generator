extends Node3D


@onready var container = $RoadManager/RoadContainer
@onready var a_point = $RoadManager/RoadContainer/first_point
@onready var tween = $Tween


func _ready():
	#return # Shortcut.
	var _auto_close_timer = get_tree().create_timer(1.5)
	var res = _auto_close_timer.connect("timeout", Callable(self, "_on_timeout"))
	assert(res == OK)


func _on_timeout():
	print("Timeout occurred, pretween y:", a_point.global_transform.origin.y)
	var init = a_point.transform.origin
	var speed = 1.5
	tween.interpolate_property(
		a_point, "position",
		init, init + Vector3(0, 2, 0),
		speed,
		Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.start()
	var res = tween.connect("tween_completed", Callable(self, "_on_tween_complete"))
	assert(res == OK)


func _on_tween_complete(_object, _key):
	print("Tween finished, new y: ", a_point.global_transform.origin.y)
	a_point.emit_transform()
