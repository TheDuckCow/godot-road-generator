extends "res://addons/gut/test.gd"

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


func create_two_containers(container_a, container_b):
	create_oneseg_container(container_a)
	create_oneseg_container(container_b)

	assert_eq(len(container_a.edge_containers), 2, "Cont A should have 2 empty edge container slots")
	assert_eq(len(container_b.edge_containers), 2, "Cont B should have 2 empty edge container slots")
	#container_a.update_edges() # should be auto-called
	#container_b.update_edges() # should be auto-called


func create_intersection_two_branch(container):
	container.setup_road_container()
	
	assert_eq(container.get_child_count(), 0, "No initial point children")

	var i1 = autoqfree(RoadIntersection.new())
	var p1 = autoqfree(RoadPoint.new())
	var p2 = autoqfree(RoadPoint.new())

	container.add_child(i1)
	container.add_child(p1)
	container.add_child(p2)
	assert_eq(container.get_child_count(), 3, "All graph nodes added")
	
	var edges: Array[RoadPoint] = [p1, p2]
	i1.edge_points = edges
	
	p1.next_pt_init = p1.get_path_to(i1)
	p2.prior_pt_init = p2.get_path_to(i1)
	
