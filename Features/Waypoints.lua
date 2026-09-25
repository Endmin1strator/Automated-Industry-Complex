return {
    Name = "Waypoints",
    Dependencies = {"Runtime", "ProfileManager", "ProfileSettings", "Components"},
    Start = function(Context)
        local Runtime = Context.Runtime
        local CONFIG = Context.CONFIG
        local AICProfile = Context.AICProfile
        local AICUI = Context.AICUI
        local AICDebug = Context.AICDebug
        local AICConfig = Context.AICConfig
        local UIRef = Context.UIRef
        local UI = Context.UI
        local Feature = Context.Feature
        local AICFeature = Context.AICFeature
        local AICCombat = Context.AICCombat
        local BasePlaceConfig = Context.Runtime:GetBasePlaceConfig()
        local NotifyAction = Context.NotifyAction
        local function GetRootPart()
            local _, _, RootPart = Runtime:GetCharacter()
            return RootPart
        end

        local Module = {Name = "Waypoints", IsFeature = true}
        UIRef.WaypointSection = UIRef.ProfileTab:AddSection("Waypoints")

UIRef.WaypointSection:AddButton("Add Waypoint Here", function()
    if not GetRootPart() then
        AICUI.SetProfileStatus("CHARACTER NOT READY")
        return
    end

    if not AICProfile.S.ActiveProfileName then
        AICUI.SetProfileStatus("CREATE / LOAD PROFILE FIRST")
        return
    end

    table.insert(Runtime:GetPlaceConfig().WAYPOINTS, GetRootPart().Position)
    CONFIG.CURRENT_WAYPOINT_TARGET = math.clamp(
        CONFIG.CURRENT_WAYPOINT_TARGET,
        1,
        math.max(1, #Runtime:GetPlaceConfig().WAYPOINTS)
    )

    AICUI.RefreshWaypointList()
    AICDebug.ResetDebugWaypoints()
    AICDebug.UpdateDebugVisualizer()
    AICProfile.SaveActiveProfile()
    AICUI.SetProfileStatus("WAYPOINT ADDED #" .. tostring(#Runtime:GetPlaceConfig().WAYPOINTS))
    NotifyAction("Waypoint", "Added waypoint #" .. tostring(#Runtime:GetPlaceConfig().WAYPOINTS))
end)

UIRef.WaypointSection:AddButton("Clear Waypoints", function()
    if not AICProfile.S.ActiveProfileName then
        AICUI.SetProfileStatus("CREATE / LOAD PROFILE FIRST")
        return
    end

    table.clear(Runtime:GetPlaceConfig().WAYPOINTS)
    CONFIG.CURRENT_WAYPOINT_TARGET = 1

    AICUI.RefreshWaypointList()
    AICDebug.ResetDebugWaypoints()
    AICDebug.UpdateDebugVisualizer()
    AICProfile.SaveActiveProfile()
    AICUI.SetProfileStatus("WAYPOINTS CLEARED")
    NotifyAction("Waypoint", "Cleared all waypoints")
end)

UIRef.WaypointListComponent = UIRef.WaypointSection:AddPriority("All Waypoints", AICUI.BuildWaypointLabels(), {
    --// Seconds to stand at each waypoint before heading to the next.
    Values = true,
    ValueLabel = "Wait (s)",
    Default = 0,
    Min = 0,
    Max = AICConfig.MAX_WAYPOINT_WAIT,
})

UIRef.WaypointListComponent.OnValueChanged = function(Index, Value)
    local PlaceConfig = Runtime:GetPlaceConfig()

    if not AICProfile.S.ActiveProfileName then
        AICUI.SetProfileStatus("DEFAULT PLACE_CONFIG IS READ-ONLY")
        AICUI.RefreshWaypointList()
        return
    end

    PlaceConfig.WAYPOINT_WAITS = AICConfig.NormalizeWaitList(PlaceConfig.WAYPOINT_WAITS, #PlaceConfig.WAYPOINTS)
    PlaceConfig.WAYPOINT_WAITS[Index] = Value
    AICProfile.QueueProfileSave()
    AICUI.SetProfileStatus("WAYPOINT #" .. tostring(Index) .. " WAIT " .. tostring(Value) .. "s")
end

--// Swaps two waypoints together with their wait times.
local function SwapWaypoints(A, B)
    local PlaceConfig = Runtime:GetPlaceConfig()
    local Waits = AICConfig.NormalizeWaitList(PlaceConfig.WAYPOINT_WAITS, #PlaceConfig.WAYPOINTS)
    local Zones = AICConfig.NormalizeZonePairs(PlaceConfig.WAYPOINT_ZONES, #PlaceConfig.WAYPOINTS, #PlaceConfig.FARM_ZONES)

    PlaceConfig.WAYPOINTS[A], PlaceConfig.WAYPOINTS[B] = PlaceConfig.WAYPOINTS[B], PlaceConfig.WAYPOINTS[A]
    Waits[A], Waits[B] = Waits[B], Waits[A]
    Zones[A], Zones[B] = Zones[B], Zones[A]
    PlaceConfig.WAYPOINT_WAITS = Waits
    PlaceConfig.WAYPOINT_ZONES = Zones
end

AICUI.S.OriginalWaypointMoveUp = UIRef.WaypointListComponent.MoveUp
AICUI.S.OriginalWaypointMoveDown = UIRef.WaypointListComponent.MoveDown
AICUI.S.OriginalWaypointRemove = UIRef.WaypointListComponent.Remove

function UIRef.WaypointListComponent:MoveUp(Label)
    if not AICProfile.S.ActiveProfileName then
        AICUI.SetProfileStatus("DEFAULT PLACE_CONFIG IS READ-ONLY")
        return
    end

    local Index = table.find(AICUI.BuildWaypointLabels(), Label)

    if Index and Index > 1 then
        SwapWaypoints(Index, Index - 1)

        AICUI.S.OriginalWaypointMoveUp(self, Label)
        CONFIG.CURRENT_WAYPOINT_TARGET = math.clamp(
            CONFIG.CURRENT_WAYPOINT_TARGET,
            1,
            math.max(1, #Runtime:GetPlaceConfig().WAYPOINTS)
        )
        AICUI.RefreshWaypointList()
        AICDebug.ResetDebugWaypoints()
        AICDebug.UpdateDebugVisualizer()
        AICProfile.SaveActiveProfile()
        AICUI.SetProfileStatus("WAYPOINT MOVED UP")
        NotifyAction("Waypoint", "Moved up")
    end
end

function UIRef.WaypointListComponent:MoveDown(Label)
    if not AICProfile.S.ActiveProfileName then
        AICUI.SetProfileStatus("DEFAULT PLACE_CONFIG IS READ-ONLY")
        return
    end

    local Index = table.find(AICUI.BuildWaypointLabels(), Label)

    if Index and Index < #Runtime:GetPlaceConfig().WAYPOINTS then
        SwapWaypoints(Index, Index + 1)

        AICUI.S.OriginalWaypointMoveDown(self, Label)
        CONFIG.CURRENT_WAYPOINT_TARGET = math.clamp(
            CONFIG.CURRENT_WAYPOINT_TARGET,
            1,
            math.max(1, #Runtime:GetPlaceConfig().WAYPOINTS)
        )
        AICUI.RefreshWaypointList()
        AICDebug.ResetDebugWaypoints()
        AICDebug.UpdateDebugVisualizer()
        AICProfile.SaveActiveProfile()
        AICUI.SetProfileStatus("WAYPOINT MOVED DOWN")
        NotifyAction("Waypoint", "Moved down")
    end
end

function UIRef.WaypointListComponent:Remove(Label)
    if not AICProfile.S.ActiveProfileName then
        AICUI.SetProfileStatus("DEFAULT PLACE_CONFIG IS READ-ONLY")
        return
    end

    local Index = table.find(AICUI.BuildWaypointLabels(), Label)

    if Index then
        local PlaceConfig = Runtime:GetPlaceConfig()
        PlaceConfig.WAYPOINT_WAITS = AICConfig.NormalizeWaitList(PlaceConfig.WAYPOINT_WAITS, #PlaceConfig.WAYPOINTS)
        PlaceConfig.WAYPOINT_ZONES = AICConfig.NormalizeZonePairs(PlaceConfig.WAYPOINT_ZONES, #PlaceConfig.WAYPOINTS, #PlaceConfig.FARM_ZONES)
        table.remove(PlaceConfig.WAYPOINTS, Index)
        table.remove(PlaceConfig.WAYPOINT_WAITS, Index)
        table.remove(PlaceConfig.WAYPOINT_ZONES, Index)
        AICUI.S.OriginalWaypointRemove(self, Label)
        CONFIG.CURRENT_WAYPOINT_TARGET = math.clamp(
            CONFIG.CURRENT_WAYPOINT_TARGET,
            1,
            math.max(1, #Runtime:GetPlaceConfig().WAYPOINTS)
        )
        AICUI.RefreshWaypointList()
        AICDebug.ResetDebugWaypoints()
        AICDebug.UpdateDebugVisualizer()
        AICProfile.SaveActiveProfile()
        AICUI.SetProfileStatus("WAYPOINT REMOVED #" .. tostring(Index))
    end
end


UIRef.ReachDistanceBox = UIRef.WaypointSection:AddTextbox(
    "Waypoint Reach Distance",
    tostring(Runtime:GetPlaceConfig().REACH_DISTANCE or 5),
    function(Value)
        if not AICProfile.S.ActiveProfileName then
            return
        end

        local Number = tonumber(Value)

        if Number and Number > 0 then
            Runtime:GetPlaceConfig().REACH_DISTANCE = Number
            AICProfile.SaveActiveProfile()
            AICUI.SetProfileStatus("REACH DISTANCE SAVED")
        end
    end
)

        return Module
    end,
}
