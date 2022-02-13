extends Spatial


onready var network = $RoadNetwork
onready var a_point = $RoadNetwork/points/first_point
onready var tween = $Tween


func _ready():
	pass # Replace with function body.
	var _auto_close_timer = get_tree().create_timer(1.5)
	var res = _auto_close_timer.connect("timeout", self, "_on_timeout")
	assert(res == OK)


func _on_timeout():
	print("Timeout occurred, pretween y:", a_point.global_transform.origin.y)
	var init = a_point.transform.origin
	var speed = 1.5
	tween.interpolate_property(
		a_point, "translation",
		init, init + Vector3(0, 2, 0),
		speed,
		Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.start()
	var res = tween.connect("tween_completed", self, "_on_tween_complete")
	assert(res == OK)


func _on_tween_complete(_object, _key):
	print("Tween finished, new y: ", a_point.global_transform.origin.y)
	a_point.on_transform()
