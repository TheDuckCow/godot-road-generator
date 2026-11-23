using System;
using System.Diagnostics.CodeAnalysis;
using Godot;
using TheDuckCow.RoadGenerator.Util;

namespace TheDuckCow.RoadGenerator;

public readonly struct RoadLaneAgent
{
    public enum MoveDir
    {
        Forward = 1,
        Stop = 0,
        Backward = -1
    }

    public enum LaneChangeDir
    {
        Right = 1,
        Current = 0,
        Left = -1
    }

    public const string GDClassName = "RoadLaneAgent";

    public static RoadLaneAgent Bind(Node node)
    {
        if (!RoadGeneratorUtil.IsScriptClass(node, GDClassName))
        {
            throw new InvalidCastException($"Node {node.Name} cannot be cast to {nameof(RoadLaneAgent)}");
        }

        return new RoadLaneAgent(node);
    }

    public static bool TryBind(Node node, [NotNullWhen(true)] out RoadLaneAgent? roadLaneAgent)
    {
        if (RoadGeneratorUtil.IsScriptClass(node, GDClassName))
        {
            roadLaneAgent = new RoadLaneAgent(node);
            return true;
        }

        roadLaneAgent = null;
        return false;
    }

    public Node Node
    {
        get;
        init;
    }

    public NodePath? RoadManagerPath
    {
        get
        {
            return this.Node.Get("road_manager_path").AsNodePath();
        }
        set
        {
            this.Node.Set("road_manager_path", value ?? new Variant());
        }
    }

    public RoadLane? CurrentLane
    {
        get
        {
            if (this.Node.Get("current_lane").AsGodotObject() is not Path3D roadLaneObject)
            {
                return null;
            }

            if (RoadLane.TryBind(roadLaneObject, out RoadLane? roadLane))
            {
                return roadLane;
            }

            return null;
        }
    }

    public Node3D Actor
    {
        get
        {
            return this.Node.Get("actor").As<Node3D>();
        }
    }

    public RoadManager RoadManager
    {
        get
        {
            return RoadManager.Bind(this.Node.Get("road_manager").As<Node3D>());
        }
    }

    private RoadLaneAgent(Node node)
    {
        this.Node = node;
    }

    public RoadLane? UnassignLane()
    {
        if (RoadLane.TryBind(this.Node.Call("unassign_lane").As<Path3D>(), out RoadLane? roadLane))
        {
            return roadLane;
        }

        return null;
    }

    public RoadLane? FindNearestLane()
    {
        return this.FindNearestLane(null, 50f);
    }

    public RoadLane? FindNearestLane(Vector3? position, float distance = 50f)
    {
        Path3D? path3D = this.Node.Call("find_nearest_lane", position ?? new Variant(), distance).As<Path3D>();

        if (RoadLane.TryBind(path3D, out RoadLane? roadLane))
        {
            return roadLane;
        }

        return null;
    }

    public Error AssignNearestLane()
    {
        return (Error)this.Node.Call("assign_nearest_lane").AsInt32();
    }

    public void AssignLane(RoadLane newLane)
    {
        this.Node.Call("assign_lane", newLane.Path3D); //TODO Does this work?
    }

    public Vector3 GetClosestPathPoint(Path3D path, Vector3 position)
    {
        return this.Node.Call("get_closest_path_point", path, position).AsVector3();
    }

    public Vector3 MoveAlongLane(float distance)
    {
        return this.Node.Call("move_along_lane", distance).AsVector3();
    }

    public Vector3 TestMoveAlongLane(float distance)
    {
        return this.Node.Call("test_move_along_lane", distance).AsVector3();
    }

    public bool CloseToLaneEnd(float proximity, MoveDir moveDir)
    {
        return this.Node.Call("close_to_lane_end", proximity, (int)moveDir).AsBool();
    }

    public int FindContinuedLane(LaneChangeDir laneChangeDir, MoveDir moveDir)
    {
        return this.Node.Call("find_continued_lane", (int)laneChangeDir, (int)moveDir).AsInt32();
    }
}