extends "res://addons/gut/test.gd"

var manager: RoadManager


func before_each():
	manager = add_child_autofree(RoadManager.new())


func _make_lane(lane_name: String, from: Vector3, to: Vector3) -> RoadLane:
	var lane := RoadLane.new()
	lane.name = lane_name
	lane.curve.add_point(from)
	lane.curve.add_point(to)
	manager.add_child(lane)
	return lane


func _link(from: RoadLane, to: RoadLane) -> void:
	from.add_lane_next(to)
	to.add_lane_prior(from)


func _make_agent(pos: Vector3) -> RoadLaneAgent:
	var actor := Node3D.new()
	manager.add_child(actor)
	actor.global_position = pos
	var agent := RoadLaneAgent.new()
	actor.add_child(agent)
	return agent


## Lane A heads -Z for 10m, then forks into B1 (bearing -X) and B2 (bearing +X).
func _make_fork() -> Array[RoadLane]:
	var lane_a := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -10))
	var lane_b1 := _make_lane("B1", Vector3(0, 0, -10), Vector3(-5, 0, -20))
	var lane_b2 := _make_lane("B2", Vector3(0, 0, -10), Vector3(5, 0, -20))
	_link(lane_a, lane_b1)
	_link(lane_a, lane_b2)
	return [lane_a, lane_b1, lane_b2]


# ------------------------------------------------------------------------------


func test_single_next_lane_is_chosen():
	var lane_a := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -10))
	var lane_b := _make_lane("B", Vector3(0, 0, -10), Vector3(0, 0, -20))
	_link(lane_a, lane_b)
	var agent := _make_agent(Vector3.ZERO)

	agent.assign_lane(lane_a)

	assert_eq(agent.chosen_lane_next, lane_b, "Only next lane is chosen")


func test_no_next_lane_chooses_null():
	var lane_a := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -10))
	var agent := _make_agent(Vector3.ZERO)

	agent.assign_lane(lane_a)

	assert_null(agent.chosen_lane_next, "Dead end has no chosen lane")


func test_chooser_callback_picks_branch():
	var lanes := _make_fork()
	var agent := _make_agent(Vector3.ZERO)
	var calls: Array = []
	agent.lane_next_chooser = func(caller: RoadLaneAgent, options: Array[RoadLane]) -> RoadLane:
		calls.append([caller, options])
		return options[1]

	agent.assign_lane(lanes[0])

	assert_eq(agent.chosen_lane_next, lanes[2], "Callback choice is used")
	assert_eq(calls.size(), 1, "Callback called once")
	assert_eq(calls[0][0], agent, "Callback receives the agent")
	assert_eq(calls[0][1].size(), 2, "Callback receives both options")


func test_random_choice_is_an_option():
	var lanes := _make_fork()
	var agent := _make_agent(Vector3.ZERO)
	var seen := {}

	for i in range(30):
		agent.assign_lane(lanes[0])
		assert_true(agent.chosen_lane_next in [lanes[1], lanes[2]], "Random choice is a next lane")
		seen[agent.chosen_lane_next] = true

	assert_eq(seen.size(), 2, "Both branches get picked over many tries")


func test_move_follows_chosen_lane():
	var lanes := _make_fork()
	var agent := _make_agent(Vector3.ZERO)
	agent.lane_next_chooser = func(_caller, options): return options[1]
	agent.assign_lane(lanes[0])

	var pos := agent.move_along_lane(12.0)

	assert_eq(agent.current_lane, lanes[2], "Moved onto the chosen branch")
	assert_gt(pos.x, 0.0, "Position is on the chosen branch")


func test_test_move_keeps_choice_and_lane():
	var lanes := _make_fork()
	var agent := _make_agent(Vector3.ZERO)
	var calls := [0]
	agent.lane_next_chooser = func(_caller, options):
		calls[0] += 1
		return options[1]
	agent.assign_lane(lanes[0])

	var pos := agent.test_move_along_lane(12.0)

	assert_gt(pos.x, 0.0, "Test move follows the chosen branch")
	assert_eq(agent.current_lane, lanes[0], "Test move keeps the current lane")
	assert_eq(agent.chosen_lane_next, lanes[2], "Test move keeps the choice")
	assert_eq(calls[0], 1, "Test move does not pick again")


func test_stale_choice_is_repicked():
	var lanes := _make_fork()
	var agent := _make_agent(Vector3.ZERO)
	agent.lane_next_chooser = func(_caller, options): return options[1]
	agent.assign_lane(lanes[0])
	assert_eq(agent.chosen_lane_next, lanes[2])

	lanes[0].remove_lane_next(lanes[2])
	lanes[2].remove_lane_prior(lanes[0])
	agent.move_along_lane(12.0)

	assert_eq(agent.current_lane, lanes[1], "Re-picked the remaining branch")


func test_unassign_clears_choice():
	var lanes := _make_fork()
	var agent := _make_agent(Vector3.ZERO)
	agent.assign_lane(lanes[0])

	agent.unassign_lane()

	assert_null(agent.chosen_lane_next, "No choice without a lane")


func test_backward_move_uses_prior_lane():
	var lanes := _make_fork()
	var agent := _make_agent(Vector3(5, 0, -20))
	agent.assign_lane(lanes[2])

	agent.move_along_lane(-12.0)

	assert_eq(agent.current_lane, lanes[0], "Moved back onto the prior lane")
