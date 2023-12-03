# Godot Road Generator

A godot plugin for creating 3D highways and streets.

![demo road gen](https://user-images.githubusercontent.com/2958461/227853559-1b6cbdfa-d1a8-463b-9acb-02f5f1563f63.gif)

> :warning: **This project is not feature complete yet**!

See [upcoming milestones](https://github.com/TheDuckCow/godot-road-generator/milestones).

## Godot version support

The alpha version of this addon is supporting godot 3.5, the public 1.0 release will target Godot 4.0+.

The Godot 3.5 builds shared before v1.0 will be provided as-is and without further maintenance after the 1.0 launch.

## Credits

This addon is developed by Moo-Ack! Productions as a part of the "Wheel Steal" game project. We poured a lot of effort, time, and money into making this an intuitive, highly functional addon - and we chose to give it away for free to the Godot community.

You can share you appreciation by:

1. Following or sharing the game project on [Twitter](https://twitter.com/WheelStealGame) or [Instagram](https://www.instagram.com/wheelstealgame/).
1. Joining the [Wheel Steal discord](https://discord.gg/gttJWznb4a).
1. Becoming a Patreon of the project (coming soon)

Logo specially designed by [Kenney](https://www.kenney.nl/assets) for this project.


## How to install

Follow the [Getting Started tutorial here](https://github.com/TheDuckCow/godot-road-generator/wiki/A-getting-started-tutorial).


## What problems this addon solves

Without this plugin, Godot users can create road ways in one of three ways:

1. Use a CSGPolygon following a path
	- While this works well and requires no plugins, it has many limitations
	- You need a custom material for every combination of lane sequences (1 way street, 2 lane road, multi lane highway). Additionally, there's no way to transition from one lane count to another without highly custom workarounds.
	- Editing road points using native curve point handles is awkward and not precise, which is not great for trying to finely tune road placements.
	- No easy way to create intersections without fiddly geometry placement.
2. Custom model roads in a 3D modelling software
	- This adds an extra barrier to entry, and not being dynamic, greatly limits the way you can create roads layouts in Godot.
3. Write their own code to create road meshes
	- It should go without saying, this is extra work! And this is exactly what this plugin aims to provide.

In addition to the specific points to each method above, in all cases you would need to write extensive custom code in order to create AI traffic that can follow lanes. Furthermore, even when comparing to road generators for other game engines, they lack features to create fine tuned lane shapes (like a road with 2 lanes one way, and only 1 in another). They also tend to not be well suited for dynamically adding new roadways during runtime as all roads are updated simultaneously and assumed to be defined in the editor.

## How to use

Check out the [wiki pages](https://github.com/TheDuckCow/godot-road-generator/wiki) on detailed usage.

## Demos

See the [first preview](https://twitter.com/TheDuckCow/status/1492909016800010248) and [auto lane texturing](https://twitter.com/TheDuckCow/status/1494475011532414978) demos from the early days of this project.


## Future plans

All development ideas are added as [enhancement issues here](https://github.com/TheDuckCow/godot-road-generator/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement). All *prioritized* issues are part of milestones [defined here](https://github.com/TheDuckCow/godot-road-generator/milestones)


## Contribution

Contributions are welcomed! See the [contributing guide](https://github.com/TheDuckCow/godot-road-generator/blob/main/CONTRIBUTING.md) for all the details on getting started.
