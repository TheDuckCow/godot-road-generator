extends Node3D


@export var fps_label: Label
@export var anim_node: Node3D
@export var loop_duration: float = 2.0
@export var show_decorations: bool = true:
	set(value):
		show_decorations = value
		updat_decorations()

@onready var init_trans := anim_node.global_transform
@onready var manager: RoadManager = %RoadManager

var do_anim: bool = false
var counter: float = 0.0


func _physics_process(delta: float) -> void:
	fps_label.text = "%s fps" % Engine.get_frames_per_second()
	if not do_anim:
		return
	
	counter += delta
	if counter > loop_duration:
		counter = -loop_duration # neg value to be a flipper animation
	
	var fac: float = abs(counter / loop_duration)
	fac = ease(fac, -1.5)
	var ang: float = lerp(0.0, PI/6.0, fac)
	anim_node.global_transform = init_trans.rotated(Vector3.UP, ang)


func _on_anim_toggled(toggled_on: bool) -> void:
	do_anim = toggled_on


func _on_deco_toggled(toggled_on: bool) -> void:
	show_decorations = toggled_on


func updat_decorations() -> void:
	var conts := manager.get_containers()
	for _cont in conts:
		_cont = _cont as RoadContainer 
		for _rp in _cont.get_roadpoints():
			_rp = _rp as RoadPoint
			for deco in _rp.decorations:
				deco = deco as RoadDecoration
				deco.enabled = show_decorations
