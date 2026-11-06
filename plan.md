# Plan: sorted lane agents, lane branching, chosen_lane_next, path-aware agent_ahead

Replace the single `lane_next`/`lane_prior` links with plural `lanes_next`/`lanes_prior` (older scenes still load), connect intersection lanes, and let agents pick a `chosen_lane_next`. Keep agents sorted by offset in each lane, replacing `_vehicles_in_lane`. Give each agent a path-aware `agent_ahead` that only updates when something changes (no rescans every frame), so `distance_to_agent_ahead()` is O(1).

## Phase 1: Lane connections

1. [road_lane.gd](addons/road-generator/nodes/road_lane.gd):
   - Remove `lane_next` and `lane_prior`.
   - Add `@export var lanes_next: Array[NodePath]` and `lanes_prior`.
   - Add `get_next_lanes()` / `get_prior_lanes()`, which return the valid lanes.
   - Add `add_lane_next` / `add_lane_prior` (skip duplicates), `remove_lane_next` / `remove_lane_prior`, and `clear_lane_links`. Each queues a deferred refresh of the agents.
   - Update the `lane_next_tag` docs.
2. [road_container.gd](addons/road-generator/nodes/road_container.gd) `update_lane_seg_connections()`: clear the links, then add every tag match in both directions. This fixes splits, which currently keep only the last match. Keep the F/R direction flip.
   - Added (`F0a`) and removed (`F0r`) transition lanes also match `F0`, so lane-count changes become forks and merges. Transition lanes get no `lane_left`/`lane_right` links in [road_segment.gd](addons/road-generator/nodes/road_segment.gd).
3. New `RoadContainer.update_lane_intersection_connections()`, called right after `update_lane_seg_connections()` in the rebuild:
   - For each intersection edge RoadPoint, match the road lane's tag at the end touching that RoadPoint against the intersection lane tags. Those tags come from `_directional_lanes` in [intersection_ngon.gd](addons/road-generator/procgen/intersection_ngon.gd).
   - Decide which way each link goes from where the curves start and end.
   - A road lane entering the intersection lists all its straight and turn lanes as next lanes.
   - A road lane leaving the intersection lists every intersection lane that arrives in it as prior lanes.
4. Move these callers to the new lists:
   - `clear_lane_segments()` in [road_segment.gd](addons/road-generator/nodes/road_segment.gd)
   - `_clear_generated_lanes()` in [intersection_ngon.gd](addons/road-generator/procgen/intersection_ngon.gd)
   - `_move_along_lane`, `close_to_lane_end` and `find_continued_lane` in [road_lane_agent.gd](addons/road-generator/nodes/road_lane_agent.gd)
   - The despawn-lane linking in [road_actor_spawner.gd](road_demos/procedural_generator/road_actor_spawner.gd)
   - The Next/Prior labels in [road_lane_debug.gd](road_demos/demo_resources/road_lane_debug.gd)
5. Loading older scenes:
   - `RoadLane._set()` catches `lane_next` and `lane_prior`. A non-empty path is added to the matching list, and `_set()` returns true.
   - The old properties are never saved again, so a scene converts itself the next time it's saved.
   - No `.tscn` file in this repo uses them.
6. New `RoadContainer.update_lane_edge_connections()`, run after the intersection pass: links lanes across connected container edges by matching curve endpoints, including owned (prefab) lanes. Links into other containers are dropped first so disconnected edges don't keep stale links.
7. Prefab containers in [custom_containers](addons/road-generator/custom_containers/): branch lanes start at the prefab edge, so forks live on the neighboring container's lane via step 6. Side links that only stood in for branches (lanes sharing a start point) are removed, and `splitter_2x2` saves its internal `lanes_next`/`lanes_prior`.

## Phase 2: chosen_lane_next

1. Agent:
   - Add `chosen_lane_next`. Its setter re-runs `refresh_agent_ahead()`.
   - Add `lane_next_chooser: Callable`, taking `(agent, options)` and returning a `RoadLane`.
   - The choice is made in `assign_lane`: no options gives null, one gives that lane, more than one uses the callback if set, else `pick_random()`.
   - Check the choice before using it. If it's no longer in `get_next_lanes()`, pick again.
2. `_move_along_lane`:
   - Moving forward, the first lane change follows `chosen_lane_next`. Any extra lane changes in the same call pick through the callback or at random.
   - `test_move_along_lane` uses the chosen lane, then the first entry of `get_next_lanes()`, and changes nothing.
   - Moving backward uses the first entry of `get_prior_lanes()`.

## Phase 3: Sorted agents and cached offset

1. RoadLane:
   - Remove `_vehicles_in_lane`, `register_vehicle` and `unregister_vehicle`.
   - Add `_agents`, sorted by offset from low to high (index 0 is the rearmost), with `register_agent`, `unregister_agent`, `update_agent_order` and `get_agents`.
   - `get_vehicles()` maps the agents to their actors, without duplicates.
   - `_exit_tree` auto-free frees the actors of agents whose `auto_register` is true. Its doc changes to "may be auto-freed by its lane".
   - `cars_in_lane` keeps using `get_vehicles()`. It now also counts agents with `auto_register` off, such as the player.
2. RoadLane `get_agents_near(offset, distance) -> Array[RoadLaneAgent]`:
   - A binary search on `_agents` returns every agent between `offset - distance` and `offset + distance`.
   - If the range runs past the lane's end, continue from the start of every lane in `get_next_lanes()` with the leftover distance. If it runs before the start, continue back from the end of every lane in `get_prior_lanes()`.
   - It follows every branch, since a lane has no chosen path. A visited set prevents loops.
   - Cost: O(log n + k) per lane visited, where k is the number of agents returned from it.
   - Use case: checking for room before a lane change.
3. Agent:
   - Add `current_lane_offset`.
   - Add a public `sync_offset()`. If the actor is within about 0.01 m of the last point the agent returned, keep the stored offset; otherwise do one `get_closest_offset`.
4. `assign_lane(new_lane, offset := -1.0)`:
   - Set the lane, offset and chosen next lane, register in the new lane, then unregister from the old one.
   - The old lane is held in a local variable, so this still works if `register_agent` ends up calling `unassign_lane()` partway through (as the despawn lane does).
   - `unassign_lane()` clears `agent_ahead`.
   - A new `_exit_tree` calls `unassign_lane()`.
5. If an agent passes another in the same lane, call `update_agent_order`. `close_to_lane_end` uses the stored offset.
6. When a lane's curve changes: on a deferred call, recompute agent offsets, re-sort, refresh `agent_ahead`, and notify the agents behind.
7. [procedural_generator.gd](road_demos/procedural_generator/procedural_generator.gd) `despawn_cars` / `update_stats`: use `get_vehicles()`.

## Phase 4: agent_ahead

1. Add signal `agent_ahead_changed(old_agent)`. The setter only emits when the agent actually changes.
2. `_ahead_gap`: the total length of the empty lanes between the agent and its leader. It's set on each refresh and keeps cross-lane distance O(1).
3. Look-ahead limits:
   - `static var lookahead_max_distance` and `static var lookahead_max_hops` on `RoadLaneAgent`, shared by the forward search and the notify-behind walk.
   - **The notify-behind problem:** the walk back from a lane has to reach every follower that could see that lane. If each agent had its own limits, an agent that looks further than the walk back reaches would never hear about changes and would keep an outdated `agent_ahead`. That's why the limits are global.
4. `refresh_agent_ahead()`:
   - If there's an agent ahead in the same lane, use it.
   - Otherwise start at `chosen_lane_next`. The first lane that has agents gives its rearmost agent.
   - Only continue past a lane that has exactly one next lane.
   - Stop at a fork, a dead end, the limits, or an already-visited lane.
5. Notifying the agents behind (there's no `agent_behind`):
   - The agent directly behind in the same lane re-checks.
   - If the changed agent was the rearmost, the frontmost agent of each feeder lane re-checks. Empty feeder lanes are walked back through, within the limits and a visited set.
   - This runs on register, unregister, reorder, link changes, curve changes, and a lane's `_exit_tree`.
   - A re-checking agent only picks up the new agent if its own path reaches that lane. That's how cars on branches it didn't choose get ignored.
6. `distance_to_agent_ahead()`:
   - Returns `INF` if there's no agent ahead.
   - Same lane: the offset difference.
   - Otherwise: (lane length - offset) + `_ahead_gap` + the leader's offset.

## Phase 5: Demo

1. `DespawnRoadLane` overrides `register_agent` to call `remove_actor(agent.actor)` and never adds the agent to its list. Otherwise actors hidden for reuse would sit in the despawn lane and cars heading for the exit would brake for them.
2. [road_actor.gd](road_demos/demo_resources/actors/road_actor.gd) `_get_auto_input`:
   - Add exports `min_follow_gap` and `follow_time`.
   - Brake (forward input 0) when `distance_to_agent_ahead() < min_follow_gap + speed * follow_time`.
   - The gap already allows for car length, which belongs to the actor.
   - Player driving is unchanged.

## Tests

1. [test_intersection_lanes.gd](test/unit/test_intersection_lanes.gd): a 4-way intersection with an outer RoadPoint on each branch. Check:
   - Entering lanes list all their straight and turn lanes.
   - Every intersection lane has a prior and a next lane.
   - Leaving lanes list every arriving intersection lane.
   - Connected curve endpoints line up.
2. Splits keep both next lanes. Setting `lane.set("lane_next", path)` and `lane_prior` the same way fills the new lists.
3. New `test/unit/test_road_lane_agent.gd`, with a `RoadManager` at the root, hand-built lanes including a fork and a merge, and `Node3D` actors with agents. Test cases:
   - Insertion order.
   - Passing another agent re-sorts and fires the signal.
   - No flicker when a leader crosses into the next lane.
   - A leader turning onto a branch the follower didn't choose drops out of `agent_ahead`.
   - A car in the next lane on a single-link chain is seen.
   - A car past an unchosen fork isn't seen.
   - The chooser callback is used, and random choice only returns one of the options.
   - A second agent inserted in a neighbor lane fires `agent_ahead_changed` on the followers there, including the frontmost agents in feeder lanes.
   - Freeing an agent notifies the agents behind it.
   - The self-linked lane doesn't loop forever.
   - Distances are correct.
   - Teleporting an actor forces a re-projection.
   - `get_vehicles()` maps agents to their actors.
   - Auto-free only frees actors whose agent has `auto_register` on.
   - `get_agents_near`: within one lane, across next and prior lanes including a fork and a merge, the distance cutoff, and the self-linked lane.

## Not handled by this plan

- **Vehicle length:** distances are measured from agent origin to agent origin. Bumper gaps are for game code.
- **Lane changes:** the actor holds two agents. This plan adds no lane-change logic, and `change_lane()` stays as it is. It only guarantees that inserting the second agent immediately notifies the followers in that lane (who would naturally slow down as they feel too-close to their agent_ahead).
- **`agent_behind`:** not tracked.  any situation where logic might say, "if there's an agent behind..." would instead be on the vehicle behind eg ambulance tells people to get out of the way, vs people seeing ambulance behind.
- **Paths beyond the next choice:** past a fork after `chosen_lane_next`, `agent_ahead` is null. (at reasonable speeds, it's impossible to cross multiple branches in a single update)
- **Merging cars:** a car in a feeder lane only counts once it's on a lane in the agent's path.  proper merging is extremely complicated: involves driver timidness, vehicle acceleration properties, etc and is outside scope.
- **Connections between road containers:** must be made at simple road segments, never at intersections or junctures.
