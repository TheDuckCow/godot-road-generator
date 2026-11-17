using System;
using System.Diagnostics.CodeAnalysis;
using Godot;
using TheDuckCow.RoadGenerator.Util;

namespace TheDuckCow.RoadGenerator;

public readonly struct RoadLane
{
    public const string GDClassName = "RoadLane";

    public static RoadLane Bind(Path3D path3D)
    {
        if (!RoadGeneratorUtil.IsScriptClass(path3D, GDClassName))
        {
            throw new InvalidCastException($"Node {path3D.Name} cannot be cast to {nameof(RoadLane)}");
        }

        return new RoadLane(path3D);
    }

    public static bool TryBind(Path3D path3D, [NotNullWhen(true)] out RoadLane? roadLane)
    {
        if (RoadGeneratorUtil.IsScriptClass(path3D, GDClassName))
        {
            roadLane = new RoadLane(path3D); 
            return true;
        }

        roadLane = null;
        return false;
    }

    public Path3D Path3D
    {
        get;
    }

    private RoadLane(Path3D path3D)
    {
        this.Path3D = path3D;
    }
}