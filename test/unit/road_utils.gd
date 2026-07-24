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
	p1.name = "p1"
	p2.name = "p2"

	container.add_child(i1)
	container.add_child(p1)
	container.add_child(p2)
	p1.position.z -= 10
	
	p2.position.z += 10
	assert_eq(container.get_child_count(), 3, "All graph nodes added")

	var edges: Array[RoadPoint] = [p1, p2]
	i1.edge_points = edges

	p1.next_pt_init = p1.get_path_to(i1) # will trigger a rebuild on inter'
	p2.prior_pt_init = p2.get_path_to(i1) # will trigger a rebuild on inter'

	# Due to manual assignment, must call this manually
	container.update_edges()


## Creates a four-branch intersection with each edge facing the center, so all
## edges feed forward lanes into the intersection.
func create_intersection_four_branch(container):
	container.setup_road_container()

	assert_eq(container.get_child_count(), 0, "No initial point children")

	var i1 = autoqfree(RoadIntersection.new())
	var pn = autoqfree(RoadPoint.new())
	var ps = autoqfree(RoadPoint.new())
	var pe = autoqfree(RoadPoint.new())
	var pw = autoqfree(RoadPoint.new())
	pn.name = "pn"
	ps.name = "ps"
	pe.name = "pe"
	pw.name = "pw"

	container.add_child(i1)
	container.add_child(pn)
	container.add_child(ps)
	container.add_child(pe)
	container.add_child(pw)

	pn.position = Vector3(0, 0, -10)
	ps.position = Vector3(0, 0, 10)
	pe.position = Vector3(10, 0, 0)
	pw.position = Vector3(-10, 0, 0)
	# Rotate each edge so its forward axis points at the center.
	ps.rotation_degrees.y = 180
	pe.rotation_degrees.y = -90
	pw.rotation_degrees.y = 90

	var edges: Array[RoadPoint] = [pn, ps, pe, pw]
	i1.edge_points = edges

	pn.next_pt_init = pn.get_path_to(i1)
	ps.next_pt_init = ps.get_path_to(i1)
	pe.next_pt_init = pe.get_path_to(i1)
	pw.next_pt_init = pw.get_path_to(i1)

	container.update_edges()


## Creates a three-branch T: pw and pe form a straight bar across the
## intersection, and ps is the stem with no edge opposite it.
## dist spaces the branches from the center; the default keeps branch
## footprints overlapping (historic), pass ~30 for non-overlapping geometry.
func create_intersection_three_branch(container, dist: float = 10.0):
	container.setup_road_container()

	assert_eq(container.get_child_count(), 0, "No initial point children")

	var i1 = autoqfree(RoadIntersection.new())
	var pw = autoqfree(RoadPoint.new())
	var pe = autoqfree(RoadPoint.new())
	var ps = autoqfree(RoadPoint.new())
	pw.name = "pw"
	pe.name = "pe"
	ps.name = "ps"

	container.add_child(i1)
	container.add_child(pw)
	container.add_child(pe)
	container.add_child(ps)

	pw.position = Vector3(-dist, 0, 0)
	pe.position = Vector3(dist, 0, 0)
	ps.position = Vector3(0, 0, dist)
	# Rotate each edge so its forward axis points at the center.
	pw.rotation_degrees.y = 90
	pe.rotation_degrees.y = -90
	ps.rotation_degrees.y = 180

	var edges: Array[RoadPoint] = [pw, pe, ps]
	i1.edge_points = edges

	pw.next_pt_init = pw.get_path_to(i1)
	pe.next_pt_init = pe.get_path_to(i1)
	ps.next_pt_init = ps.get_path_to(i1)

	container.update_edges()


## Creates an intersection that distinguishes facing-aware pairing from a
## position-only one. The source ps aims south; pb sits nearly dead-opposite but
## faces sideways, while pg sits off to the side yet faces ps head-on. A position
## metric prefers pb; an orientation-aware one prefers pg.
func create_intersection_facing_split(container):
	container.setup_road_container()

	assert_eq(container.get_child_count(), 0, "No initial point children")

	var i1 = autoqfree(RoadIntersection.new())
	var ps = autoqfree(RoadPoint.new())
	var pg = autoqfree(RoadPoint.new())
	var pb = autoqfree(RoadPoint.new())
	ps.name = "ps"
	pg.name = "pg"
	pb.name = "pb"

	container.add_child(i1)
	container.add_child(ps)
	container.add_child(pg)
	container.add_child(pb)

	ps.position = Vector3(0, 0, -10)
	pg.position = Vector3(8, 0, 12)
	pb.position = Vector3(1, 0, 12)
	# ps aims south (+Z); pg faces back head-on (-Z); pb faces sideways (+X).
	ps.rotation_degrees.y = 0
	pg.rotation_degrees.y = 180
	pb.rotation_degrees.y = 90

	var edges: Array[RoadPoint] = [ps, pg, pb]
	i1.edge_points = edges

	ps.next_pt_init = ps.get_path_to(i1)
	pg.next_pt_init = pg.get_path_to(i1)
	pb.next_pt_init = pb.get_path_to(i1)

	container.update_edges()
