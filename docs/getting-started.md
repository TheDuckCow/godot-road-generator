# Getting started


## Step 1: Download and add to project

Download the latest release (main may be unstable). Then, copy the `addons/road-generator` folder into your project. If you have any other addons installed, then your current addons folder will already exist.

## Step 2: Enable the plugin

1. Go to the Project menu > Project Settings.
1. Select the Plugins tab
1. Enable the road-generator plugin


## Step 3: Add a RoadNetwork

1. In any 3D scene, open the add child node menu
1. Search for RoadNetwork
1. Add the node (it may appear twice, either one is fine)

You will now have a RoadNetwork in your scene, with an automatically set up Points and Segments set of nodes. We recommend you keep the default hierarchy under the RoadNetwork.

The structure should look like:

```
- RoadNetwork (Spatial, road_network.gd)
  - points (Spatial, no script)
  - segments (Spatial, no script)
```

## Step 4: Add a road

You could manually add two RoadPoints as a child of the segments node, but the
easier way is the following:

1. Select the RoadNetwork
1. Click on the "Create" menu that now appears in the 3D view (similar to where you would change your curve editor tools if you had a path selected)
1. Click create 2x2 road (or any others that appear in the future)

You should now have the following setup:
```
- RoadNetwork (Spatial, road_network.gd)
  - points (Spatial, no script)
    - RP_001 (RoadPoint)
    - RP_002 (RoadPoint)
  - segments (Spatial, no script)
    - (nothing visible in editor, but under the hood there is one RoadSegment)
```

## Step 5: Change the number of lanes

After selecting one of the RoadPoints, use the panel in the Inspector or the 3D viewport widgets to change the number of lanes. You can also change the lane width. All settings on a single RoadPoint are specific to itself, and will be interpolated between two RoadPoints.

In the future, we will have bulk tools making it easier to change the lane counts of multiple (or all) RoadPoints at once, but for now you have to modify them one by one.

## Step 6: Add another RoadPoint

Again you could do this manually, but requires you to manually edit nodepaths of each RoadPoint to appropriate point to the right position. Better to use the Inspector panel:

1. Select the first or last RoadPoint in a continuous road. How to get the last RoadPoint in a road?
    - Easiest: Click the "Select Next/Prior RoadPoint" to quickly traverse
    - Navigate in your 3D view to put the end of the road in frame, then left click on the blue square area
    - Or just simply select the right RoadPoint in the Scene hierarchy view
1. In the inspector panel, click the button that now says"+ Next RoadPoint" (instead of "Select Next RoadPoint")
1. The new RoadPoint will be added and immediately selected
    - This RoadPoint will have the same configurations (lanes, shoulder size, handle size) as the previously selected RoadPoint that it is now connected to.
    - In the future, we will create additional methods to quickly "draw" roads by point and click
1. Move this RoadPoint around. It's a Spatial node, making it easy to use all the different built in tools for that. This means you can also use the Transform panel in the Inspector window to set very fine tuned placement if needed.
1. Add more RoadPoints to your heart's desire!


## Step 7: Create a closed loop

Let's say you want to have a closed loop track for your road, with no intersections or anything like that. 

1. Create and place all the RoadPoints necessary, such that you are left with a gap for just one more RoadSegment
1. Select either this first or last RoadPoint. Make a mental note of the name of this node
1. Select the *other* ending RoadPoint node.
1. In the inspector panel, click on the `Prior Point Init` or `Next Point Init` (whichever isn't yet populated)
1. In the popup, select the node you identified from step 2, and hit confirm
1. Technically optional, but "is probably safer": Do the reverse, so that the node identified in step 2 also points to the next node

## Step 8: Connect two different RoadNetworks

Have multiple scenes with their own RoadNetworks? Or need Roads with two different materials? You can functionally follow the same instructions as outlined in Step 7. Note: There might be some race condition as to which network will be the one responsible for generating the RoadSegment between the RoadPoints from the different networks, so be mindful of that.
