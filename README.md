<p align="center">
  <img src="icon.png" />
</p>

<h1 align="center">Godot Road Generator</h1>

<p align="center">A Godot plugin for creating flexible 3D highways and streets with traffic support</p>

<p align="center">
	<a href="https://discord.com/invite/gttJWznb4a">
	  <img src="https://img.shields.io/discord/802981313203798017.svg?label=&logo=discord&logoColor=ffffff&color=7389D8&labelColor=6A7EC2" alt="Join our discord"/>
	</a>
	<a href="https://www.patreon.com/WheelStealGame">
	  <img src="https://img.shields.io/badge/Patreon-Support%20Us!-orange.svg" alt="Patreon"/>
	</a>
	<a href="https://github.com/TheDuckCow/godot-road-generator/blob/main/LICENSE">
	  <img src="https://img.shields.io/github/license/theduckcow/godot-road-generator" alt="GitHub License"/>
	</a>
	<a href="https://github.com/TheDuckCow/godot-road-generator/releases">
	  <img alt="Latest Release" src="https://img.shields.io/github/v/release/theduckcow/godot-road-generator">
	</a>
	<a href="https://github.com/TheDuckCow/godot-road-generator/compare/main...dev">
	  <img alt="GitHub commits since latest release (dev)" src="https://img.shields.io/github/commits-since/theduckcow/godot-road-generator/latest/dev">
	</a>
</p>



## Godot 4.x and 3.x support

> :warning: **This project is not feature complete yet**!

See [upcoming milestones](https://github.com/TheDuckCow/godot-road-generator/milestones).

| [Dev](https://github.com/TheDuckCow/godot-road-generator/tree/dev) | [Main](https://github.com/TheDuckCow/godot-road-generator/tree/main) | [godot3](https://github.com/TheDuckCow/godot-road-generator/tree/godot3) |
| --- | ---- | ------ |
| Latest, Godot 4.3+ | Released, Godot 4.x | Godot 3.x (deprecated) |


Currently, all new development occurs in the dev branch targeting Godot 4.3+. When a release is ready, the dev branch is merged into main (which is why main may look inactive).

## What problems this addon solves

Without this plugin, Godot users can create road ways in one of three ways:

1. Use a CSGPolygon following a path
	- While this is simple to set up and requires no plugins, it has many limitations
	- You need a custom material for every combination of lane sequences (1 way street, 2 lane road, multi lane highway).
	- There's no way to transition from one lane count to another without highly custom workarounds.
	- No easy way to create intersections without fiddly geometry placement.
	- Largely impossible to avoid geometry gaps between different segments of road
2. Make custom model roads in a 3D modelling software
	- This adds an extra barrier to entry, and not being dynamic, greatly limits the way you can create roads layouts in Godot.
3. Write own code to create road meshes
	- It should go without saying, this is extra work! And this is exactly what this plugin aims to provide.

In addition to each point above, each scenario requires you to make your own custom code to handle AI traffic that can follow lanes. Furthermore, even when comparing to road generators for other game engines, they lack features to create fine tuned lane shapes such as dynamic lane changes and per-roadpoint settings. They also tend to focus on editor creation and lack the optimization for in-game procedural use cases.

## High level Features

| Feature | Demo |
| ------- | -----|
| RoadPoints, the primary road building block. They have their own lane-control gizmo, hold shift to affect all RoadPoints in this RoadContainer. | ![roadpoint widget](./demo/gifs/roadpoint_widget.gif) |
| Click-to draw, full spatial controls to fine tune placement after. Will snap to colliders on click if any. | ![click to draw](./demo/gifs/click_to_draw.gif) |
| RoadPoint inspector panel to define lane width, shoulder, and more. Hold shift to affect all RoadPoints within same container. | ![inspector panel](./demo/gifs/inspector_panel.gif) |
| RoadContainers to organize roads and snap roads together. Save a RoadContainer out to a scene for reuse! | ![Containers](./demo/gifs/containers.gif) |
| Changeable materials per RoadContainer. Source trim-sheet vector is provided to guide creating your own customized materials. | ![Material swap](./demo/gifs/material_swap.gif) |
| Prefab intersection RoadContainers. Snap together built-in four way, three way, and highway on/off ramps with ease. | ![Prefab containers](./demo/gifs/prefab_roadcontainers.gif) |
| Optional auto-generated AI path lanes. You can also manually define AI paths to link up roads. A provided RoadLaneAgent makes for easy navigation. | ![AI path demo](./demo/gifs/ai_lanes.gif) |
| Runtime-available functions for procedural use cases, operations apply on single RoadSegments at a time to be performant. | ![Procedural demo](./demo/gifs/procedural_demo.gif) |
| Quick export your road meshes. Output gltf/glb for sections of your road network to edit further in a 3D software, without exporting your whole scene. | ![Export road mesh](./demo/gifs/export_geo.png) |
| Support for custom-made meshes. Turn off "Create Geo", then drop in your own meshes + colliders. AI paths remain connected. | ![Custom road meshes demo](./demo/gifs/custom_geo.gif) |
| GDScript-only (for now), no extra compiling or dependencies to worry about. | ![GDScript only](./demo/gifs/gdscript-only.png) |
| ***[Planned](https://github.com/TheDuckCow/godot-road-generator/issues/121), not implemented:*** Procedural intersections. Can currently create using pre-saved scenes with custom geometry per above. | ![Planned intersections](./demo/gifs/intersection.gif) |


## Credits

This addon is developed by Moo-Ack! Productions as a part of the "Wheel Steal" game project. We poured a lot of effort, time, and money into making this an intuitive, highly functional addon - and we chose to give it away for free to the Godot community.

You can share you appreciation by:

1. Following or sharing the game project on [Bluesky](https://bsky.app/profile/wheelstealgame.bsky.social) or [Instagram](https://www.instagram.com/wheelstealgame/)
1. Joining the [Wheel Steal discord](https://discord.gg/gttJWznb4a)
1. Becoming a [Patron of the project](https://www.patreon.com/WheelStealGame) (see special Roadside Support tier for hands on support)

Further contributions by [antonkurkin](https://github.com/antonkurkin), [NoJoseJose](https://github.com/NoJoseJose), and [more here](https://github.com/theduckcow/godot-road-generator/graphs/contributors).

Logo designed by [Kenney](https://www.kenney.nl/assets).

## How to install and use

Follow the [Getting Started tutorial here](https://github.com/TheDuckCow/godot-road-generator/wiki/A-getting-started-tutorial).


Then, check out the [wiki pages](https://github.com/TheDuckCow/godot-road-generator/wiki) for more detailed usage.


## Games made with the Road Generator

*Want to include yours? [Create an issue](https://github.com/TheDuckCow/godot-road-generator/issues/new)!*

- [Wheel Steal Game](https://wheelstealgame.com/) - procedural use case
- [Wheelie Big and Small](https://theduckcow.itch.io/wheelie-big-and-small) - procedural use case
- [Makin'Paper / Racin'Paper](https://theduckcow.com/2024/paper-games-win-hearts-gdko-2024/) - editor created tracks


## Future plans

All development ideas are added as [enhancement issues here](https://github.com/TheDuckCow/godot-road-generator/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement). All *prioritized* issues are part of milestones [defined here](https://github.com/TheDuckCow/godot-road-generator/milestones)


## Contribution

Contributions are welcomed! See the [contributing guide](https://github.com/TheDuckCow/godot-road-generator/blob/main/CONTRIBUTING.md) for all the details on getting started.
