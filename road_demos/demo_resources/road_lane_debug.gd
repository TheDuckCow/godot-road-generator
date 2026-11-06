extends Panel

@export var actor: Node3D

@onready var lbl_next:Label = %next
@onready var lbl_left:Label = %left
@onready var lbl_right:Label = %right
@onready var lbl_prior:Label = %prior
@onready var lbl_no_agent:Label = %no_agent
@onready var lbl_agent_info:Label = %agent_info

var agent: RoadLaneAgent

func _ready() -> void:
	if not is_instance_valid(actor):
		return

	for _ch in actor.get_children():
		if not _ch is RoadLaneAgent:
			continue
		agent = _ch
		break

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(agent):
		return
	var clane:RoadLane = agent.current_lane
	if not is_instance_valid(clane):
		return

	lbl_left.text = "Left" if clane.lane_left else "-"
	lbl_right.text = "Right" if clane.lane_right else "-"
	var next_count := clane.get_next_lanes().size()
	lbl_next.text = "Next (%d)" % next_count if next_count > 0 else "-"
	var prior_count := clane.get_prior_lanes().size()
	lbl_prior.text = "Prior (%d)" % prior_count if prior_count > 0 else "-"

	var agents := clane.get_agents()
	lbl_agent_info.text = "%.1f / %.1f m\nagent %d of %d in lane" % [
		agent.current_lane_offset, clane.curve.get_baked_length(),
		agents.find(agent) + 1, agents.size()]
