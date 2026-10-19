extends "res://addons/gut/test.gd"

const MOVE_DISTANCE := 2.0
const FLOAT_TOLERANCE := 0.001
const TOLERANCE_VEC := Vector3(FLOAT_TOLERANCE, FLOAT_TOLERANCE, FLOAT_TOLERANCE)


func _build_agent_fixture() -> Dictionary:
	var world: RoadManager = add_child_autofree(RoadManager.new())

	var lane_a: RoadLane = autoqfree(RoadLane.new())
	lane_a.name = "lane_a"
	lane_a.curve = Curve3D.new()
	lane_a.curve.up_vector_enabled = true
	lane_a.curve.add_point(Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Vector3.ZERO)
	lane_a.curve.add_point(Vector3(0.0, 0.0, 10.0), Vector3.ZERO, Vector3.ZERO)
	lane_a.curve.set_point_tilt(0, 0.0)
	lane_a.curve.set_point_tilt(1, 0.6)
	world.add_child(lane_a)

	var lane_b: RoadLane = autoqfree(RoadLane.new())
	lane_b.name = "lane_b"
	lane_b.curve = Curve3D.new()
	lane_b.curve.up_vector_enabled = true
	lane_b.curve.add_point(Vector3(0.0, 0.0, 10.0), Vector3.ZERO, Vector3.ZERO)
	lane_b.curve.add_point(Vector3(0.0, 0.0, 20.0), Vector3.ZERO, Vector3.ZERO)
	lane_b.curve.set_point_tilt(0, 0.6)
	lane_b.curve.set_point_tilt(1, 0.6)
	world.add_child(lane_b)

	lane_a.lane_next = lane_a.get_path_to(lane_b)
	lane_b.lane_prior = lane_b.get_path_to(lane_a)

	var actor: Node3D = autoqfree(Node3D.new())
	actor.name = "actor"
	world.add_child(actor)
	actor.global_position = Vector3(0.0, 0.0, 9.5)

	var agent: RoadLaneAgent = autoqfree(RoadLaneAgent.new())
	agent.auto_register = false
	actor.add_child(agent)
	agent.actor = actor
	agent.current_lane = lane_a

	return {
		"lane_a": lane_a,
		"lane_b": lane_b,
		"agent": agent,
	}


func _assert_basis_almost_eq(a: Basis, b: Basis, message: String) -> void:
	assert_almost_eq(a.x, b.x, TOLERANCE_VEC, "%s x" % message)
	assert_almost_eq(a.y, b.y, TOLERANCE_VEC, "%s y" % message)
	assert_almost_eq(a.z, b.z, TOLERANCE_VEC, "%s z" % message)


# ------------------------------------------------------------------------------


func test_move_with_rotation():
	var actor_move := _build_agent_fixture()
	var moved_transform: Transform3D = actor_move.agent.move_along_lane_with_rotation(MOVE_DISTANCE)

	assert_eq(
		actor_move.agent.current_lane,
		actor_move.lane_b,
		"move_along_lane_with_rotation should assign next lane")
	assert_true(
		moved_transform.basis.y.distance_to(Vector3.UP) > FLOAT_TOLERANCE,
		"Transform should include lane tilt")

	var actor_test := _build_agent_fixture()
	var tested_transform: Transform3D = actor_test.agent.test_move_along_lane_with_rotation(MOVE_DISTANCE)

	assert_eq(
		actor_test.agent.current_lane,
		actor_test.lane_a,
		"test_move_along_lane_with_rotation should not assign a new lane")
	assert_almost_eq(
		moved_transform.origin, tested_transform.origin, TOLERANCE_VEC, "Transform origins should match")
	_assert_basis_almost_eq(moved_transform.basis, tested_transform.basis, "Transform bases should match")


func test_move_along_lane():
	var actor_move := _build_agent_fixture()
	var moved_position: Vector3 = actor_move.agent.move_along_lane(MOVE_DISTANCE)

	assert_eq(actor_move.agent.current_lane, actor_move.lane_b, "move_along_lane should assign next lane")

	var actor_test := _build_agent_fixture()
	var tested_position: Vector3 = actor_test.agent.test_move_along_lane(MOVE_DISTANCE)

	assert_eq(
		actor_test.agent.current_lane,
		actor_test.lane_a,
		"test_move_along_lane should not assign a new lane")
	assert_almost_eq(moved_position, tested_position, TOLERANCE_VEC, "Positions should match")
