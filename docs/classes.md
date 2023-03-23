# Addon classes

## Overview

This page is meant to give you a high level understanding of the components of the Road Generator addon, and how they work together. These primary components include:

- RoadNetwork (Spatial)
- RoadPoint (Spatial)
- RoadSegment (Geometry, hidden)
- LaneSegment (Curve, for AI)

## RoadNetwork

This is the parent and controller of the road generation. When added to the scene, two nodes (segments and points) are added as children to contain the RoadPoints places by a user, and the RoadSegments generated by the addon.

## RoadPoint

Think of this like a slice through a roadway. It defines the characteristics of the road at this point, including: the number of lanes, the direction of each lane, the texture UVs assigned to these lanes, lane width, and more.

See the `roadpoint.md` file for more details about all functionality and settings.

## RoadSegment

This is the actual mesh geometry that is generated between two RoadPoints. It is responsible for interpolating any differences in settings between RoadPoints, such as going from wider to narrower lane widths. Under the hood, a curve object is created to define the way the geometry is added.

## LaneSegment

A Road can contain one or more lanes. For convenience of AI path following, LaneSegments are optionally generated after a road has been created, an extension of the 3D Path node type.

LaneSegments are not created by default, and are not required (be aware, they are also not working fully, see: https://github.com/TheDuckCow/godot-road-generator/issues/46 and https://github.com/TheDuckCow/godot-road-generator/issues/45). See the `roadnetwork.md` page for details.