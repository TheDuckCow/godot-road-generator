using System;
using System.Diagnostics.CodeAnalysis;
using Godot;
using TheDuckCow.RoadGenerator.Util;

namespace TheDuckCow.RoadGenerator;

public readonly struct RoadContainer
{
    public const string GDClassName = "RoadContainer";

    public static RoadContainer Bind(Node3D node3D)
    {
        if (!RoadGeneratorUtil.IsScriptClass(node3D, GDClassName))
        {
            throw new InvalidCastException($"Node {node3D.Name} cannot be cast to {nameof(RoadContainer)}");
        }

        return new RoadContainer(node3D);
    }

    public static bool TryBind(Node3D node3D, [NotNullWhen(true)] out RoadContainer? roadContainer)
    {
        if (RoadGeneratorUtil.IsScriptClass(node3D, GDClassName))
        {
            roadContainer = new RoadContainer(node3D);
            return true;
        }

        roadContainer = null;
        return false;
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

    private RoadContainer(Node3D node3D)
    {
        this.Node3D = node3D;
    }

}