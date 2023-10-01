extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")
const RoadMaterial = preload("res://addons/road-generator/resources/road_texture.material")
onready var road_util := RoadUtils.new()


func before_each():
	gut.p("ran setup", 2)

func after_each():
	gut.p("ran teardown", 2)

func before_all():
	gut.p("ran run setup", 2)

func after_all():
	gut.p("ran run teardown", 2)


# ------------------------------------------------------------------------------


## Utility to create a single segment container (2 points)
func create_oneseg_container(container):
	container.setup_road_container()

	assert_eq(container.get_child_count(), 0, "No initial point children")

	var p1 = autoqfree(RoadPoint.new())
	var p2 = autoqfree(RoadPoint.new())

	container.add_child(p1)
	container.add_child(p2)
	assert_eq(container.get_child_count(), 2, "Both RPs added")

	p1.next_pt_init = p1.get_path_to(p2)
	p2.prior_pt_init = p2.get_path_to(p1)


# ------------------------------------------------------------------------------


func test_road_container_create():
	var container = autoqfree(RoadContainer.new())
	# Check the children are set up.

	watch_signals(container)
	assert_signal_emit_count(container, "on_road_updated", 0, "Don't signal create")

	# Trigger the auto setup which happens deferred in _ready
	container.setup_road_container()

	assert_eq(container.material_resource, RoadMaterial)

	# Since only setup, still should not have triggered on update.
	assert_signal_emit_count(container, "on_road_updated", 0, "Don't signal setup")
	container.rebuild_segments()
	# Now it's updated
	assert_signal_emit_count(container, "on_road_updated", 1, "Signal after rebuild")


func test_on_road_updated_single_segment():
	var container = add_child_autofree(RoadContainer.new())
	container.auto_refresh = false

	create_oneseg_container(container)

	# Now trigger the update, to see that a single segment was made
	watch_signals(container)
	container.rebuild_segments()
	var res = get_signal_parameters(container, 'on_road_updated')
	var segments_updated = res[0]
	assert_eq(len(segments_updated), 1, "Single segment created")
	assert_signal_emit_count(container, "on_road_updated", 1, "One signal call")


## Ensure that users can manually assign two points to connect with auto_refresh
func test_RoadContainer_validations_with_autorefresh():
	var container = add_child_autofree(RoadContainer.new())
	container.auto_refresh = true  # Will kick in validation

	create_oneseg_container(container)

	# Now trigger the update, to see that a single segment was made
	watch_signals(container)
	container.rebuild_segments()
	var res = get_signal_parameters(container, 'on_road_updated')
	var segments_updated = res[0]
	assert_eq(len(segments_updated), 1, "Single segment created")
	assert_signal_emit_count(container, "on_road_updated", 1, "One signal call")
