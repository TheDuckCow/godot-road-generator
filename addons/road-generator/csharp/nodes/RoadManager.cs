using System;
using System.Collections.Generic;
using Godot;
using Godot.Collections;
using TheDuckCow.RoadGenerator.Util;

namespace TheDuckCow.RoadGenerator;

public readonly struct RoadManager
{
    public const string GDClassName = "RoadManager";

    public static RoadManager Bind(Node3D node3D)
    {
        if (!RoadGeneratorUtil.IsScriptClass(node3D, GDClassName))
        {
            throw new InvalidCastException($"Node {node3D.Name} cannot be cast to {nameof(RoadManager)}");
        }

        return new RoadManager(node3D);
    }

    public Node3D Node3D
    {
        get;
        init;
    }

    public string AiLaneGroup
    {
        get
        {
            return this.Node3D.Get("ai_lane_group").AsString();
        }
    }

    private RoadManager(Node3D node3D)
    {
        this.Node3D = node3D;
    }

    public List<RoadContainer> GetContainers()
    {
        List<RoadContainer> roadContainers = [];
        Array<Node3D> res = this.Node3D.Call("get_containers").AsGodotArray<Node3D>();

        foreach (Node3D node in res)
        {
            if (!RoadContainer.TryBind(node, out RoadContainer? roadContainer))
            {
                continue;
            }

            roadContainers.Add(roadContainer.Value);
        }

        return roadContainers;
    }
}