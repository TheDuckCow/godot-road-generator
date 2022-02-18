# Godot Road Generator

This plugin for the Godot Engine with quickly and procedurally generating roads such as streets and highways.

> :warning: **This project is not feature complete yet**!

## What problems this solves

Without this addon, Godot users can create road ways in one of three ways:

1. Use a CSGPolygon following a path
	- While this works well and requires no plugins, it has many limitations:
	- You have to have a custom material for every combination of lane sequences (1 way street, 2 lane road, multi lane highway). Additioanlly, there's no way to transition from one lane count to another without highly custom workarounds.
	- Editing road points using native curve point handles is awkward and not precise, which is not great for trying to finely tune road placements.
	- There's not clear way how to create intersections
2. Custom model roads in a 3D modelling software
	- This adds an extra barrier to entry, and not being dynamic, greatly limits the way you can create roads layouts in Godot.
3. Write their own code to create road meshes
	- It should go without saying, this is extra work! And this is exactly what this plugin aims to provide.

In addition to the specific points to each method above, in all cases you would need to write extensive custom code in order to create AI traffic that can follow lanes. Furthermore, even when comparing to road generators for other game engines, they lack features to create fine tuned lane shapes (like a road with 2 lanes one way, and only 1 in another). They also tend to not be well suited for dynamically adding new roadways during runtime as all roads are updated siultaneously and assumed to be defined in the editor.

## Included Features

This section will be filled out with more visuals as the plugin is updated. In a nutshell, these features *already* exist:

* Classes for RoadPoints and RoadSegments
	* RoadPoint: Think of this like a slice through a roadway. It defines the characteristics of the road at this point, including: the number of lanes, the direction of each lane, the texture UVs assigned to these lanes, lane width, and more.
	* RoadSegment: This is the actual mesh geometry that is generated between two RoadPoints. It is repsonsible for interpolating any differences in settings between RoadPoints, such as going from wider to narrower lane widths. Under the hood, a curve object is created to define the way the geometry is added.
* Seamless end to end roads. A core feature and improvement of this system over others is that two different road segmetns are perfectly joined together with no gaps, even if they are from different road networks.
* Visual widget to showcase orientation of the selected RoadPoint.
* Network manager to control refreshing of roads in game and in the editor.
* Fast performance - transforming RoadPoints in the editor will switch to a low poly mode until transforming has completed.
* Flexible road layouts - use the auto assignment for intelligent road texturing, or manually specific on a per RoadPoint basis the order and sequence of lanes and lane directions.
* Lightway as much as possible. The system is designed to be used in a procedural, endless world, so it should scale effectively. Curves are used without creating node paths where possible, and the number of nodes per road segment/point is aimed to be as minimal as possible. Furthermore, there is room to defer generation until it's needed, so roadways can be placed even without generating the geometry and further details all right away (some interfaaces need to be added for this still)

## How to use

This will be updated in the future. At the moment, there is no custom UI around the creation of roads. One must manually create the following node tree structure using the classes this plugin defines:

```
- RoadNetwork (Node, road_network.gd)
  - points (Node, no script)
  	- Children nodes (Spatials, road_point.gd)
  - segments (Node, no script)
  	- Runtime-generated nodes (Spatials, road_segment.gd)
```

The first step is to add the RoadNetwork as a node in your scene. It can be a simple Node type, or a Spatial if you want to be able to easily show/hide the entire network. Thereunder, you need to add two children nodes. These nodes will contain both the auto-generated road segments, as well as the user (or runtime) defined road points.

Add a RoadPoint (type: Spatial), and set the number of lanes via the traffic direciton array. For ease of use, consider starting off using auto_lane which will auto assign the lanes array (which defines the UV assignments).

Duplicate this RoadPoint. Then, make the RoadPoint.prior_pt_init point to the path of the second road point and vice verse. In the future, this will be automatically assigned.

That's basically it! You can chain more road points together this way.

## Demos

See the [first preview](https://twitter.com/TheDuckCow/status/1492909016800010248) and [auto lane texturing](https://twitter.com/TheDuckCow/status/1494475011532414978) demos from the early days of this project.


## Future plans

To be populated in repo Issues. The repo has *not* reached its MVP yet, which will require including:

* Automatic shoulder generation
* An interface to ease the creation of roads by pointing and clicking
* Creating transitions from RoadPoints with different lane counts/layouts.
* Intersections
* Generating additional road features, such as barriers, lamposts, or custom resources.
* Generating lanes curves tailored for AI drivers
* Further road texture detailing, such as cross walk segments and more.

## Contribution

Contributions are welcomed!

This repository uses the Godot Unit Testing (GUT) system for running tests. Install the [latest release of GUT](https://github.com/bitwes/Gut/releases) into the addons folder.
