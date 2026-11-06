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


# ------------------------------------------------------------------------------
# Sorted agents and cached offsets


func _offsets(lane: RoadLane) -> Array:
	var result: Array = []
	for agent in lane.get_agents():
		result.append(snappedf(agent.current_lane_offset, 0.01))
	return result


func _assert_indices(lane: RoadLane) -> void:
	var agents := lane.get_agents()
	for idx in range(agents.size()):
		assert_eq(agents[idx]._index_in_lane, idx, "Agent knows its index in the lane")


func test_agents_sorted_by_offset():
	var lane := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -30))
	for z in [-20.0, -5.0, -10.0]:
		_make_agent(Vector3(0, 0, z)).assign_lane(lane)

	assert_eq(_offsets(lane), [5.0, 10.0, 20.0], "Agents sorted rearmost first")
	_assert_indices(lane)


func test_passing_agent_resorts():
	var lane := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -30))
	var rear := _make_agent(Vector3(0, 0, -5))
	var front := _make_agent(Vector3(0, 0, -10))
	rear.assign_lane(lane)
	front.assign_lane(lane)

	rear.actor.global_position = rear.move_along_lane(10.0)

	assert_eq(lane.get_agents(), [front, rear] as Array[RoadLaneAgent], "Passing agent moves ahead")
	assert_almost_eq(rear.current_lane_offset, 15.0, 0.01)
	_assert_indices(lane)


func test_assign_same_lane_twice_keeps_one_entry():
	var lane := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -30))
	var agent := _make_agent(Vector3(0, 0, -5))

	agent.assign_lane(lane)
	agent.assign_lane(lane)

	assert_eq(lane.get_agents().size(), 1, "Agent listed once")


func test_moving_into_next_lane_moves_registration():
	var lanes := _make_fork()
	var agent := _make_agent(Vector3(0, 0, -8))
	agent.lane_next_chooser = func(_caller, options): return options[0]
	agent.assign_lane(lanes[0])

	agent.actor.global_position = agent.move_along_lane(4.0)

	assert_does_not_have(lanes[0].get_agents(), agent, "Left the old lane")
	assert_has(lanes[1].get_agents(), agent, "Joined the new lane")
	assert_almost_eq(agent.current_lane_offset, 2.0, 0.01, "Offset carried into the new lane")


func test_offset_cached_until_actor_moved_elsewhere():
	var lane := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -30))
	var agent := _make_agent(Vector3(0, 0, -5))
	agent.assign_lane(lane)
	agent.actor.global_position = agent.move_along_lane(2.0)
	assert_almost_eq(agent.current_lane_offset, 7.0, 0.01)

	agent.actor.global_position = Vector3(0.5, 0, -20)
	agent.actor.global_position = agent.move_along_lane(1.0)

	assert_almost_eq(agent.current_lane_offset, 21.0, 0.01, "Teleport forces a re-projection")


func test_test_move_keeps_offset_and_order():
	var lane := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -30))
	var rear := _make_agent(Vector3(0, 0, -5))
	var front := _make_agent(Vector3(0, 0, -10))
	rear.assign_lane(lane)
	front.assign_lane(lane)

	rear.test_move_along_lane(10.0)

	assert_almost_eq(rear.current_lane_offset, 5.0, 0.01, "Offset unchanged")
	assert_eq(lane.get_agents(), [rear, front] as Array[RoadLaneAgent], "Order unchanged")


func test_get_vehicles_maps_agents_to_actors():
	var lane := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -30))
	var agent := _make_agent(Vector3(0, 0, -5))
	var second := RoadLaneAgent.new()
	agent.actor.add_child(second)
	agent.assign_lane(lane)
	second.assign_lane(lane)
	var other := _make_agent(Vector3(0, 0, -10))
	other.assign_lane(lane)

	var vehicles := lane.get_vehicles()

	assert_eq(vehicles.size(), 2, "One entry per actor")
	assert_has(vehicles, agent.actor)
	assert_has(vehicles, other.actor)


func test_freed_agent_leaves_lane():
	var lane := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -30))
	var agent := _make_agent(Vector3(0, 0, -5))
	var other := _make_agent(Vector3(0, 0, -10))
	agent.assign_lane(lane)
	other.assign_lane(lane)

	agent.actor.free()

	assert_eq(lane.get_agents(), [other] as Array[RoadLaneAgent], "Freed agent removed")
	_assert_indices(lane)


func test_auto_free_only_auto_register_actors():
	var lane := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -30))
	var npc := _make_agent(Vector3(0, 0, -5))
	var player := _make_agent(Vector3(0, 0, -10))
	player.auto_register = false
	npc.assign_lane(lane)
	player.assign_lane(lane)
	var npc_actor := npc.actor
	var player_actor := player.actor

	manager.remove_child(lane)
	await wait_frames(2)

	assert_false(is_instance_valid(npc_actor), "NPC freed with its lane")
	assert_true(is_instance_valid(player_actor), "Player kept")
	lane.free()


func test_curve_change_resorts_agents():
	var lane := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -30))
	var near := _make_agent(Vector3(0, 0, -5))
	var far := _make_agent(Vector3(0, 0, -20))
	near.assign_lane(lane)
	far.assign_lane(lane)

	lane.on_reverse_lane()
	await wait_frames(1)

	assert_eq(lane.get_agents(), [far, near] as Array[RoadLaneAgent], "Order follows the new curve")
	assert_almost_eq(far.current_lane_offset, 10.0, 0.01)
	assert_almost_eq(near.current_lane_offset, 25.0, 0.01)
	_assert_indices(lane)


func test_get_agents_near():
	var lanes := _make_fork()
	var prior := _make_lane("P", Vector3(0, 0, 10), Vector3.ZERO)
	_link(prior, lanes[0])
	var a_near := _make_agent(Vector3(0, 0, -2))
	var a_far := _make_agent(Vector3(0, 0, -8))
	var p_end := _make_agent(Vector3(0, 0, 1))
	var p_start := _make_agent(Vector3(0, 0, 9))
	a_near.assign_lane(lanes[0])
	a_far.assign_lane(lanes[0])
	p_end.assign_lane(prior)
	p_start.assign_lane(prior)
	var b1_start := _make_agent(lanes[1].to_global(lanes[1].curve.sample_baked(1.0)))
	var b2_far := _make_agent(lanes[2].to_global(lanes[2].curve.sample_baked(6.0)))
	b1_start.assign_lane(lanes[1])
	b2_far.assign_lane(lanes[2])

	var ahead := lanes[0].get_agents_near(8.0, 3.5)
	assert_eq(ahead.size(), 2, "Same-lane agent plus the one just into a branch")
	assert_has(ahead, a_far)
	assert_has(ahead, b1_start)

	var behind := lanes[0].get_agents_near(1.0, 2.5)
	assert_eq(behind.size(), 2, "Same-lane agent plus the one at the end of the prior lane")
	assert_has(behind, a_near)
	assert_has(behind, p_end)


func test_get_agents_near_self_loop_terminates():
	var lane := _make_lane("A", Vector3.ZERO, Vector3(0, 0, -10))
	_link(lane, lane)
	var agent := _make_agent(Vector3(0, 0, -5))
	agent.assign_lane(lane)

	assert_eq(lane.get_agents_near(5.0, 100.0), [agent] as Array[RoadLaneAgent], "Each lane visited once")
