using Godot;

namespace TheDuckCow.RoadGenerator.Util;

public static class RoadGeneratorUtil
{
    public static bool IsScriptClass(GodotObject? godotObject, string scriptClassName)
    {
        if (godotObject == null)
        {
            return false;
        }

        if (godotObject.GetScript().AsGodotObject() is not Script script)
        {
            return false;
        }

        return script.GetGlobalName() == scriptClassName;
    }
}