# Overview

Welcome to the Godot Road Generator wiki.

This wiki is currently made for the Godot 3.x version of the plugin, but the project will soon migrate to Godot 4. See details in the [README page](https://github.com/TheDuckCow/godot-road-generator/blob/main/README.md) for more.

## Get started using the page below:

TODO: Live link to the wiki getting-started.md page once ready.

## Live Demos

- [Dynamic lane count changing in 3D viewport](https://www.instagram.com/p/CpCZITztdqc/)
- [Editor panel buttons](https://www.instagram.com/p/Cn0SeAytCQf/)


## Included Features

The following features are currently available:

* Seamless end to end roads. A core feature and improvement of this system over others is that two different road segments are perfectly joined together with no gaps, even if they are from different road networks.
* Visual widget to showcase orientation of the selected RoadPoint.
* Network manager to control refreshing of roads in game and in the editor.
* Fast performance - transforming RoadPoints in the editor will switch to a low poly mode until transforming has completed.
* Flexible road layouts - use the auto assignment for intelligent road texturing, or manually specific on a per RoadPoint basis the order and sequence of lanes and lane directions.
* In-editor controls 
* Easy to get started
  * Add a RoadNetwork in any scene, and it will auto set up the default configuration of a material and children to get started
  * Then, use the "Create" node to add your first road segment. In the future, we'll have more types of pieces you can quickly add.
  * Select a RoadPoint (functionally a spatial), and move it around.
  * Use the custom inspector panel to edit RoadPoints quickly and easily
* Lightweight as much as possible. The system is designed to be used in a procedural, endless world, so it should scale effectively. Curves are used without creating node paths where possible, and the number of nodes per road segment/point is aimed to be as minimal as possible. Furthermore, there is room to defer generation until it's needed, so roadways can be placed even without generating the geometry and further details all right away (some interfaces need to be added for this still)

Planned features:

* Intersections
* Out of the box AI follower component
* Improved support for textured road materials
* Roadside elements, such as lampposts and side barriers

See the [enhancements-labeled issues](https://github.com/TheDuckCow/godot-road-generator/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement) for the most up to date (and immediate) plans.
