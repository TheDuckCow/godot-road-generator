extends Camera3D


@export var range_source: Node3D

var acc: float = 4.0
var velocity: float = 0.0
var max_vel: float = 10.0

var min_x: float
var max_x: float

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if range_source:
		min_x = range_source.global_position.x
		max_x = range_source.global_position.x
		for _ch in range_source.get_children():
			min_x = min(min_x, _ch.global_position.x)
			max_x = max(max_x, _ch.global_position.x)
	print("Camera x range: ", min_x, " - ", max_x)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var dir:int = 0
	if Input.is_action_pressed("ui_right") and global_position.x < max_x:
		dir += 1
	if Input.is_action_pressed("ui_left") and global_position.x > min_x:
		dir -= 1

	if dir == 0:
		velocity = lerp(velocity, 0.0, delta*acc*2)
	else:
		velocity += dir * delta*acc
	velocity = clamp(velocity, -max_vel, max_vel)
	
	var new_x = global_transform.origin.x
	new_x += velocity
	if global_position.x > max_x and dir <= 0:
		new_x = lerp(new_x, max_x, delta*4)
	elif new_x < min_x and dir >= 0:
		new_x = lerp(new_x, min_x, delta*10)
	global_transform.origin.x = new_x
