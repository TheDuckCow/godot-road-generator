extends Panel

@export var actor: Node3D

@onready var lbl_next:Label = %next
@onready var lbl_left:Label = %left
@onready var lbl_right:Label = %right
@onready var lbl_prior:Label = %prior
@onready var lbl_no_agent:Label = %no_agent

var agent: RoadLaneAgent

func _ready() -> void:
	if not is_instance_valid(actor):
		return

	for _ch in actor.get_children():
		if not _ch is RoadLaneAgent:
			continue
		agent = _ch
		break

func _physics_process(delta: float) -> void:
	if not is_instance_valid(agent):
		return
	var clane:RoadLane = agent.lane_position.lane
	if not is_instance_valid(clane):
		return

	lbl_left.text = "Left" if clane.lane_left else "-"
	lbl_right.text = "Right" if clane.lane_right else "-"
	lbl_next.text = "Next" if clane.lane_next else "-"
	lbl_prior.text = "Prior" if clane.lane_prior else "-"
