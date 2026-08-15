extends Node

## synchroinization entity for multiple traffic lights
## using group field of TrafficLightSingle
## switches between groups on timer
## between each switch turns yellow light

const TrafficLightSingle = preload("res://road_demos/demo_resources/traffic_light/traffic_light_single.gd")
const LightState := TrafficLightSingle.LightState

const DEFAULT_GROUP_TIME := 5.0
@export var time_per_group : Array[float] #in seconds
@export var yellow_time := 2.0 #in seconds
@export var current_group := 0
@export var current_yellow := true

## only extended automatically on registering, never shrinks automatically. empty groups are still cycled
var light_groups : Array[Array] #TODO nested types

var _timer: Timer

func _ready() -> void:
	var lights = get_children()
	for light_node in lights:
		self.register_light(light_node)
	self._timer = Timer.new()
	self._timer.one_shot = true
	self._timer.timeout.connect(_on_timeout.bind())
	add_child(self._timer)
	child_entered_tree.connect(_on_child_entered_tree)
	if self.current_yellow:
		self.current_yellow = false #switched at the beginning of next_phase, switching here once to set to the initial state
		next_phase()
	else:
		#already set all registered to red or green
		self._timer.wait_time = self.time_per_group[self.current_group]
		self._timer.start()


func _on_child_entered_tree(light_node) -> void:
	register_light(light_node)


func register_light(light_node) -> void:
	if light_node is not TrafficLightSingle:
			push_error("children of TrafficLightSynchronizer should be TrafficLightSingle")
			return
	var light :TrafficLightSingle = light_node
	if light_groups.size() <= light.group:
		light_groups.resize(light.group+1)
		while time_per_group.size() != light_groups.size():
			time_per_group.append(DEFAULT_GROUP_TIME)
	if light in light_groups[light.group]:
		push_warning("trying to register the traffic light twice")
		return
	light_groups[light.group].append(light)
	light.tree_exited.connect(func(): self.unregister_light(light))
	light.set_state(LightState.RED if light.group != self.current_group else LightState.GREEN)


func unregister_light(light :TrafficLightSingle) -> void:
	if light_groups.size() <= light.group || light not in light_groups[light.group]:
		push_error("the traffic light is not in group ", light.group, " when unregistered")
		return
	light_groups[light.group].erase(light)


func _on_timeout() -> void:
	next_phase()


func next_group() -> int:
	assert(self.time_per_group.size() >= self.light_groups.size())
	return (self.current_group + 1) % self.light_groups.size()


func next_phase() -> void:
	var new_wait :float
	self.current_yellow = !self.current_yellow
	if self.current_yellow:
		new_wait = self.yellow_time
		self.set_lights(self.current_group, LightState.YELLOW)
		self.set_lights(self.next_group(), LightState.YELLOW)
	else:
		new_wait = self.time_per_group[self.current_group]
		self.set_lights(self.current_group, LightState.RED)
		self.set_lights(self.next_group(), LightState.GREEN)
		self.current_group = self.next_group()
	self._timer.wait_time = new_wait
	self._timer.start()


func set_lights(group :int, new_state :LightState) -> void:
	for light:TrafficLightSingle in light_groups[group]:
		light.set_state(new_state)
