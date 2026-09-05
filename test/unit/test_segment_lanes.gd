extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")

var road_util: RoadUtils


func before_each():
	road_util = RoadUtils.new()
	road_util.gut = gut


func ensure_roadlanes_exist(container:RoadContainer, segs: int = 3):
	var lanes = []
	for _ch in container.get_roadpoints():
		var rp: RoadPoint = _ch as RoadPoint
		for ln in rp.get_children():
			if not ln is RoadLane:
				continue
			lanes.append(ln)
	var expected: int = 4*segs
	assert_eq(lanes.size(), expected, "Should create exactly %s lanes" % expected)


## Function for flipping a RoadPoint 180 and reversing connections
##
## Unforutnately, we can't directly use the high level addon flip operator due
## to current structure, when that is abstracted in the future, use that instead:
## plugin.subaction_flip_roadpoint
func simple_flip_roadpoint(rp: RoadPoint) -> void:
	var flipped_transform = rp.transform
	flipped_transform = flipped_transform.rotated_local(Vector3.UP, PI)
	rp.set_internal_updating(true)
	var tmpinit = rp.prior_pt_init
	rp.prior_pt_init = rp.next_pt_init
	rp.next_pt_init = tmpinit
	#rp.traffic_dir = _new_traffic_dirs # they are mirrored anyways
	var tmpmag = rp.prior_mag
	rp.prior_mag = rp.next_mag
	rp.next_mag = tmpmag
	rp.transform = flipped_transform
	rp.set_internal_updating(false)


# ------------------------------------------------------------------------------


## Checkes that two RoadPoints pointing in the same direction produces good lanes
func test_lanes_next_to_prior():
	var container:RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 4, true, true)
	# No flipping, already in a next-to-prior config
	
	container.generate_ai_lanes = true
	container.draw_lanes_editor = true
	ensure_roadlanes_exist(container)
	road_util.save_testscene_to_file(container)# "test_lanes_next_to_prior")


## Checkes that two RoadPoints pointing away from each other produces good lanes
func test_lanes_prior_to_prior():
	var container:RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 4, true, true)
	# Flip first two roadpoints
	for idx in [0, 1]:
		var rp:RoadPoint = points[idx]
		simple_flip_roadpoint(rp)

	container.generate_ai_lanes = true
	container.draw_lanes_editor = true
	container.rebuild_segments(true)
	ensure_roadlanes_exist(container)
	road_util.save_testscene_to_file(container)# "test_lanes_prior_to_prior")
	

## Checkes that two RoadPoints pointing towards each other produces good lanes
func test_lanes_next_to_next():
	var container:RoadContainer = add_child_autofree(RoadContainer.new())
	var points: Array[RoadPoint] = road_util.create_rp_line(container, 4, true, true)
	for idx in [2, 3]:
		var rp:RoadPoint = points[idx]
		simple_flip_roadpoint(rp)

	container.generate_ai_lanes = true
	container.draw_lanes_editor = true
	container.rebuild_segments(true)
	ensure_roadlanes_exist(container)
	road_util.save_testscene_to_file(container)
