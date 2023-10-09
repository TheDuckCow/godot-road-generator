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


func validate_edges_equal_size(container):
	var edges = len(container.edge_containers)
	assert_eq(len(container.edge_rp_targets), edges)
	assert_eq(len(container.edge_rp_target_dirs), edges)
	assert_eq(len(container.edge_rp_locals), edges)
	assert_eq(len(container.edge_rp_local_dirs), edges)

	# now also validate that all local children name match actual names in editor,
	# since we depend on node names for making connections.
	var ch_paths = []
	for ch in container.get_children():
		ch_paths.append(container.get_path_to(ch))
	for rp_path in container.edge_rp_locals:
		assert_has(ch_paths, rp_path, "edge_rp_local name not matching any child")


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
	container._auto_refresh = false

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
	container._auto_refresh = true  # Will kick in validation

	create_oneseg_container(container)

	# Now trigger the update, to see that a single segment was made
	watch_signals(container)
	container.rebuild_segments()
	var res = get_signal_parameters(container, 'on_road_updated')
	var segments_updated = res[0]
	assert_eq(len(segments_updated), 1, "Single segment created")
	assert_signal_emit_count(container, "on_road_updated", 1, "One signal call")


func test_get_manager_null():
	var container = add_child_autofree(RoadContainer.new())

	# No manager
	var res = container.get_manager()
	assert_eq(res, null)


func test_get_manager_parent():
	# Direct manager
	var manager = add_child_autofree(RoadManager.new())
	var container = autoqfree(RoadContainer.new())
	manager.add_child(container)

	var res = container.get_manager()
	assert_eq(res, manager)


func test_get_manager_grandparent():
	# Direct manager
	var manager = add_child_autofree(RoadManager.new())
	var spatial = autoqfree(Spatial.new())
	var container = autoqfree(RoadContainer.new())
	manager.add_child(spatial)
	spatial.add_child(container)

	var res = container.get_manager()
	assert_eq(res, manager)


## Verify update_edges works, called whenever updating RP prior/next rp init
func test_update_edges():
	var container = add_child_autofree(RoadContainer.new())
	container._auto_refresh = false
	# even with auto_refresh off, container.update_edges() gets called automatically
	# via the _autofix_noncyclic_references method.
	# TODO: could validate that "called" on update_edges?

	# First case: no edges
	assert_eq(len(container.edge_rp_locals), 0, "Should zero edges")
	validate_edges_equal_size(container)

	# Second case: 2 edges over 2 points
	create_oneseg_container(container)
	container.rebuild_segments()
	assert_eq(len(container.edge_rp_locals), 2, "Should have two edges")
	validate_edges_equal_size(container)

	# Third case: 2 edges over 3 points
	var p2 = container.get_roadpoints()[1]
	var p3 = autoqfree(RoadPoint.new())
	container.add_child(p3)
	p2.next_pt_init = p2.get_path_to(p3)
	p3.prior_pt_init = p3.get_path_to(p2)
	container.rebuild_segments()
	assert_eq(len(container.edge_rp_locals), 2, "Should have two edges still")
	validate_edges_equal_size(container)

	# Fourth case: 3 edges over 4 points (one point entirely disconnected)
	# In this case, the disconencted point should count as 2 open edges.
	var p4 = autoqfree(RoadPoint.new())
	container.add_child(p4)  # unconnected
	container.rebuild_segments()
	assert_eq(len(container.edge_rp_locals), 4, "Should have 3 edges now")
	validate_edges_equal_size(container)

	# Fifth case: 3 edges over 4 points, one edge conencted to Container itself.
	p3.next_pt_init = p3.get_path_to(container)
	container.rebuild_segments()
	assert_eq(len(container.edge_rp_locals), 4, "Should still have 3 edges now")
	validate_edges_equal_size(container)
