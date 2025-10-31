extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")
const RoadMaterial = preload("res://addons/road-generator/assets/road_texture.material")

var road_util: RoadUtils


func before_each():
	gut.p("ran setup", 2)
	road_util = RoadUtils.new()
	road_util.gut = gut

func after_each():
	gut.p("ran teardown", 2)

func before_all():
	gut.p("ran run setup", 2)

func after_all():
	gut.p("ran run teardown", 2)


# ------------------------------------------------------------------------------


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


func has_a2b_connection(cont_a, cont_b) -> bool:
	var any_connected = false
	for connections in cont_a.edge_containers:
		if connections and cont_a.get_node(connections) == cont_b:
			any_connected = true
	return any_connected

# ------------------------------------------------------------------------------


func test_road_container_creation_does_not_emit_signals():
	var container = autoqfree(RoadContainer.new())

	# Add to scene so signals can be emitted
	add_child(container)

	# Start watching emitted signals
	watch_signals(container)

	# No signals should be emitted on creation
	assert_signal_emit_count(container, "on_road_updated", 0, "Creating the container should not emit any signals")

	# Simulate _ready() setup
	container.setup_road_container()

	# Default material should be assigned
	assert_eq(container.material_resource, RoadMaterial, "Default road material should be assigned after setup")

	# Setup should not emit any signals
	assert_signal_emit_count(container, "on_road_updated", 0, "Calling setup should not emit any signals")

	# Rebuilding with no road points should not emit signals
	container.rebuild_segments()
	assert_signal_emit_count(container, "on_road_updated", 0, "Rebuilding with no segments should not emit a signal")
	assert_eq(container.get_child_count(), 0, "New container should have no children")


func test_road_container_emits_signal_when_road_points_connected():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()

	var rp1 = RoadPoint.new()
	container.add_child(rp1)

	# Reset signal tracking
	watch_signals(container)

	# Add second road point but do not connect it yet
	var rp2 = RoadPoint.new()
	rp2.transform.origin += Vector3.FORWARD
	container.add_child(rp2)

	# No signal should be emitted if points are not connected
	assert_signal_emit_count(container, "on_road_updated", 0, "Adding unconnected RoadPoints should not emit a signal")

	# Connect the two road points
	rp1.connect_roadpoint(RoadPoint.PointInit.NEXT, rp2, RoadPoint.PointInit.NEXT)

	# Watch signals after the connection
	watch_signals(container)

	# Connecting points should emit one update signal
	assert_signal_emit_count(container, "on_road_updated", 1, "Connecting RoadPoints should emit a road update signal")


func test_on_road_updated_single_segment():
	var container = add_child_autofree(RoadContainer.new())
	container._auto_refresh = false

	road_util.create_oneseg_container(container)

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

	road_util.create_oneseg_container(container)

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
	var spatial = autoqfree(Node3D.new())
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
	road_util.create_oneseg_container(container)
	assert_eq(len(container.edge_rp_locals), 2, "Should have two edges")
	validate_edges_equal_size(container)

	# Third case: 2 edges over 3 points
	var p2 = container.get_roadpoints()[1]
	var p3 = autoqfree(RoadPoint.new())
	p2.next_pt_init = p2.get_path_to(p3)
	p3.prior_pt_init = p3.get_path_to(p2)
	assert_eq(len(container.edge_rp_locals), 2, "Should have two edges still")
	validate_edges_equal_size(container)

	# Fourth case: 3 edges over 4 points (one point entirely disconnected)
	# In this case, the disconencted point should count as 2 open edges.
	var p4 = autoqfree(RoadPoint.new())
	container.add_child(p4)  # unconnected
	assert_eq(len(container.edge_rp_locals), 4, "Should have 2+2 edges now")
	validate_edges_equal_size(container)

	# Fifth case: 3 edges over 4 points, one edge conencted to Container itself.
	p3.next_pt_init = p3.get_path_to(container)
	assert_eq(len(container.edge_rp_locals), 4, "Should still have 2+2 edges now")
	validate_edges_equal_size(container)

	# Sixth case: One edge marked as terminated, no longer an "edge" and thus
	# both directions no longer counted
	p4.terminated = true
	assert_eq(len(container.edge_rp_locals), 2, "Back down to 2")
	validate_edges_equal_size(container)


func test_container_connection():
	var cont_a = add_child_autofree(RoadContainer.new())
	var cont_b = add_child_autofree(RoadContainer.new())
	cont_a._auto_refresh = false
	cont_b._auto_refresh = false

	road_util.create_two_containers(cont_a, cont_b)
	var pt1 = cont_a.get_roadpoints()[0]
	var pt2 = cont_b.get_roadpoints()[1]

	var init_edge_rp_locals = cont_a.edge_rp_locals
	var init_edge_rp_local_dirs = cont_a.edge_rp_local_dirs

	# Should have initial edges open
	assert_eq(len(cont_a.edge_rp_locals), 2, "cont_a should have initial edges open")
	assert_eq(len(cont_b.edge_rp_locals), 2, "cont_b should have initial edges open")

	var err = pt1.connect_container(RoadPoint.PointInit.NEXT, pt2, RoadPoint.PointInit.PRIOR)
	assert_false(err, "Connection should not be a successful when using the already connected directions")

	# Making assumption that first open dir is Next, and second is Prio.
	var res = pt1.connect_container(RoadPoint.PointInit.PRIOR, pt2, RoadPoint.PointInit.NEXT)
	assert_true(res, "Connection should be a success")

	# One of the connections made should be the other container
	assert_true(has_a2b_connection(cont_a, cont_b), "cont_a should connect to cont_b")
	assert_true(has_a2b_connection(cont_b, cont_a), "cont_b should connect to cont_a")

	# TODO: Validate the right changes made; though may be overkill to test.
	#cont_a.edge_containers = []
	#cont_a.edge_rp_targets = []
	#cont_a.edge_rp_target_dirs = []

	# Should NOT have changed
	assert_eq(cont_a.edge_rp_locals, init_edge_rp_locals)
	assert_eq(cont_a.edge_rp_local_dirs, init_edge_rp_local_dirs)
	# TODO: also verify no prior and next of points have not changed,
	# since this operation should work the same even for saved scenes.


func test_container_disconnection():
	# -----
	# First make the CONNECTED RoadContainers,
	# mostly a repeat of the above test.
	var cont_a = add_child_autofree(RoadContainer.new())
	var cont_b = add_child_autofree(RoadContainer.new())
	cont_a._auto_refresh = false
	cont_b._auto_refresh = false

	road_util.create_two_containers(cont_a, cont_b)
	var pt1 = cont_a.get_roadpoints()[0]
	var pt2 = cont_b.get_roadpoints()[1]

	# Should have initial edges open
	assert_eq(len(cont_a.edge_rp_locals), 2, "cont_a should have initial edges open")
	assert_eq(len(cont_b.edge_rp_locals), 2, "cont_b should have initial edges open")

	var err = pt1.connect_container(RoadPoint.PointInit.NEXT, pt2, RoadPoint.PointInit.PRIOR)
	assert_false(err, "Connection should not be a successful when using the already connected directions")

	# Making assumption that first open dir is Next, and second is Prio.
	var res = pt1.connect_container(RoadPoint.PointInit.PRIOR, pt2, RoadPoint.PointInit.NEXT)
	assert_true(res, "Connection should be a success")

	# end setup of connected containers
	# -----

	# NOW test the disconnection.
	res = pt1.disconnect_container(RoadPoint.PointInit.PRIOR, RoadPoint.PointInit.NEXT)
	assert_true(res, "Disconnection should be a success")

	# There should be no connections
	assert_false(has_a2b_connection(cont_a, cont_b), "cont_a should not connect to cont_b")
	assert_false(has_a2b_connection(cont_b, cont_a), "cont_b should not connect to cont_a")

	# Now try connecting/disconnected in flipped order (next to next)
	pt1 = cont_a.get_roadpoints()[0]
	pt2 = cont_b.get_roadpoints()[0] # the change from above, using first rp.

	res = pt1.connect_container(RoadPoint.PointInit.PRIOR, pt2, RoadPoint.PointInit.PRIOR)
	assert_true(res, "Connection should be a success for same-dir")
	assert_true(has_a2b_connection(cont_a, cont_b), "cont_a should be connect to cont_b")

	# Working test disconnection
	res = pt1.disconnect_container(RoadPoint.PointInit.PRIOR, RoadPoint.PointInit.PRIOR)
	assert_true(res, "Disonnection should be a success for same-dir")
	assert_false(has_a2b_connection(cont_a, cont_b), "cont_a should be connect to cont_b")

	# A couple tests which should intentionally fail.
	res = pt1.disconnect_container(RoadPoint.PointInit.PRIOR, RoadPoint.PointInit.PRIOR)
	assert_false(res, "Disconnection should fail since not connected in that direction")
	res = pt1.disconnect_container(RoadPoint.PointInit.NEXT, RoadPoint.PointInit.NEXT)
	assert_false(res, "Disconnection should fail with invalid edge directions")


func test_container_snap_unsnap():
	var cont_a:RoadContainer = add_child_autofree(RoadContainer.new())
	var cont_b:RoadContainer = add_child_autofree(RoadContainer.new())
	cont_a._auto_refresh = false
	cont_b._auto_refresh = false

	road_util.create_two_containers(cont_a, cont_b)
	var pt1:RoadPoint = cont_a.get_roadpoints()[0]
	var pt2:RoadPoint = cont_b.get_roadpoints()[1]

	cont_a.snap_to_road_point(pt1, pt2)
	assert_true(pt1.cross_container_connected())
	assert_true(pt2.cross_container_connected())


func test_collider_assignmens():
	var container = add_child_autofree(RoadContainer.new())
	container.collider_group_name = "test_collider_group"
	container.collider_meta_name = "test_meta_name"
	road_util.create_oneseg_container(container)

	var _members = get_tree().get_nodes_in_group(container.collider_group_name)
	assert_true(len(_members)>0, "Should have 1+ segmetns in test group name")
	for _collider in _members:
		assert_true(_collider.has_meta(container.collider_meta_name), "Meta name should be assigned")
