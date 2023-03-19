# RoadPoints

You will be spending most of your time most likely using RoadPoints, either from code or in the UI.

## Edit RoadPoints in the UI

There are two main ways to update RoadPoints:

### 3D view widgets

A subset of the most convinient controls for a RoadPoint are available directly in the 3D view, via widgets.

**Lane count slider**

The blue dot at the edge of the road can be slid in and out from the RoadPoint to change the number of lanes for that RoadPoint. 


### Inspector pannel

All controls of a RoadPoint are available in the inspector panel. It is currently split into two sections.

**Edit RoadPoint section**

- **Select [Next/Prior] RoadPoint**: On press, will update your editor selection to be the next or previous RoadPoint
- **+ [Next/Prior] RoadPoint**: If the [last/first] RoadPoint is selected, then this button is displayed instead as a quick way to add another RoadPoint with the same settings.
- **+ icon**: Add another lane to this side of the road.
- **- icon**: Remove another lane from this side of the road.
- **Yellow ||**: This is not a button, just a visual indiecator separating the controls affecting the "reverse" (left side) controls from the "forward" (right side).


**Script Variables section**

These are all export nodes directly from the RoadPoint script.

- **traffic_dir** (array of enums): The primary field which determines the number of lanes on the road. The panel buttons above as well as the 3D viewport widget simply hook in to edit this value to add or remove nodes of the according type.
    - Values must match the [Enum class LaneDir](https://github.com/TheDuckCow/godot-road-generator/blob/main/addons/road-generator/road_point.gd#L21).
    - Note: There is little or no functionality yet with the `BOTH` selection, and the `NONE` is functioanlly a no-op.
- **auto_lanes** (bool): Auto assign lane textures based on the sequence of traffic directions above. Most users will want to keep this setting on.
- **lanes** (array of enums): Do not edit if auto lanes is on, which is the recommended value. Can be used to manually override the texture used for a lane.
- **lane_width** (float): Change how wide (in meters) each lane of traffic is.
- **shoulder_width_l** (float): Define how wide the left ("reverse") shoulder is before the gutter bevel. If too large, will have visible texture stretching.
- **shoulder_width_r** (float): Define how wide the right ("forward") shoulder is before the gutter bevel. If too large, will have visible texture stretching.
- **gutter_profile** (2d vector): Define the shape of the tapered edge of the road. Vector represents the position to offset the vertex before extrusion.
- **prior_pt_init** (NodePath): Defines the next RoadPoint in the chain. If empty, then this is the en
- **next_pt_init** (NodePath): 
- **prior_mag** (float): Value is passed into the internal bezier curve "in" handle, aligned to the RoadPoint orientation. Making this value larger will make the the RoadSegment ease more into this RoadPoint from the prior RoadPoint.
- **next_mag** (float): Value is passed into the internal bezier curve "out" handle, aligned to the RoadPoint orientation. Making this value larger will make the the RoadSegment ease more into this RoadPoint from the next RoadPoint.



## Edit RoadPoints from code

Section WIP.

