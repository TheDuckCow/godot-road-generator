extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")

var road_util: RoadUtils

func before_each():
	gut.p("ran setup", 2)
	road_util = RoadUtils.new()
	road_util.gut = gut


func test_create_road_manager():
	var _pt = autoqfree(RoadManager.new())
	pass_test('nothing tested, passing')


func test_manager_signals():
	var manager:RoadManager = add_child_autofree(RoadManager.new())
	manager.auto_refresh = false
	watch_signals(manager)
	assert_signal_emit_count(manager, "on_road_updated", 0, "Calling setup should not emit any signals")
	
	var container = RoadContainer.new()
	manager.add_child(container)
	container._auto_refresh = false
	road_util.create_oneseg_container(container) # won't be built yet
	
	# Should have zero calls still, since not built yet
	assert_signal_emit_count(manager, "on_road_updated", 0, "With refresh off should not have signalled yet")
	assert_eq(container.get_segments().size(), 0, "Shouldn't have segments yet")
	container.rebuild_segments()
	assert_signal_emit_count(manager, "on_road_updated", 1, "Calling setup should emit a single update signal")
	assert_eq(container.get_segments().size(), 1, "Should have a single segment")


## Ensures that if auto refresh is off, segments aren't automatically created
func test_auto_refresh():
	var manager:RoadManager = add_child_autofree(RoadManager.new())
	var container = RoadContainer.new()
	manager.add_child(container)
	manager.auto_refresh = false
	watch_signals(manager)
	watch_signals(container)
	
	road_util.create_oneseg_container(container)
	
	assert_signal_emit_count(manager, "on_road_updated", 0, "Should have no segment updates")
	assert_signal_emit_count(container, "on_road_updated", 0, "Should have no segment updates")
	
	manager.density = 20.0
	
	assert_signal_emit_count(manager, "on_road_updated", 0, "Should have no segment updates")
	assert_signal_emit_count(container, "on_road_updated", 0, "Should have no segment updates")
	
	# This will call updates in a deferred way, so we must make our own deferred call to run after.
	manager.auto_refresh = true
	
	assert_signal_emit_count(manager, "on_road_updated", 1, "Should have no segment updates")
	assert_signal_emit_count(container, "on_road_updated", 1, "Should have no segment updates")


func test_set_density():
	var manager:RoadManager = add_child_autofree(RoadManager.new())
	manager.auto_refresh = true  # Simulating default editor, no explicit calls to rebuild
	
	var container = RoadContainer.new()
	manager.add_child(container)
	container.setup_road_container()
	road_util.create_oneseg_container(container)
	
	# Check initial setup
	var segs := container.get_segments()
	assert_eq(segs.size(), 1)
	var segment = segs[0]
	assert_gt(manager.density, 0.0)
	assert_eq(container.density, -1.0)
	assert_eq(segment.density, manager.density)
	
	# Update the setting
	watch_signals(container)
	manager.density = 1.23 # should auto trigger rebuilds
	assert_signal_emit_count(container, "on_road_updated", 1, "Should have updated segments")
	
	segs = container.get_segments()
	assert_eq(segs.size(), 1, "Should still only havea  single segment")
	segment = segs[0]
	assert_eq(manager.density, 1.23)
	assert_eq(container.density, -1.0)
	assert_eq(segment.density, manager.density)
