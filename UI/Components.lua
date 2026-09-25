return {
    Name = "Components",
    Dependencies = {"Runtime"},
    Start = function(Context)
        local Runtime = Context.Runtime
        local Services = Context.Services
        local Players = Services.Players
        local Player = Context.Player
        local PlayerGui = Context.PlayerGui
        local Replicated = Services.Replicated
        local StarterGui = Services.StarterGui
        local RunService = Services.RunService
        local PathfindingService = Services.PathfindingService
        local HttpService = Services.HttpService
        local CONFIG = Context.CONFIG
        local AICConfig = Context.AICConfig
        local AICProfile = Context.AICProfile
        local AICCombatUtils = Context.AICCombatUtils
        local AICCombat = Context.AICCombat
        local AICFeature = Context.AICFeature
        local AICUI = Context.AICUI
        local AICDebug = Context.AICDebug
        local UIRef = Context.UIRef
        local UI = Context.UI
        local FeatureState = Context.Feature
        local PatrolState = Context.PatrolState
        local NotifyAction = Context.NotifyAction
        local Module = Context.AICUI
        function AICUI.CreateFeature(Name, Default, Callback)
            local Component = UIRef.FeatureSection:AddToggle(Name, Default, Callback)
        
            return Component
        end
        function AICUI.SetFeatureComponent(Name, Value)
            local Data = Feature[Name]
        
            if Data and Data.Button then
                Data.Button:Set(Value, false)
            end
        end
        function AICUI.RefreshTargetDropdown()
            AICCombat.S.DetectedEntities = AICCombat.GetDetectedEnemyEntities()
        
            local Options = {}
        
            for _, Name in ipairs(AICCombat.S.DetectedEntities) do
                if not AICCombat.IsEntityInPriority(Name) then
                    table.insert(Options, Name)
                end
            end
        
            if #Options == 0 then
                Options = {"No detected enemies"}
            end
        
            if UIRef.TargetDropdown then
                if UIRef.TargetDropdown.Popup then
                    UIRef.TargetDropdown.Popup:Destroy()
                end
        
                if UIRef.TargetDropdown.Frame then
                    UIRef.TargetDropdown.Frame:Destroy()
                end
            end
        
            UIRef.TargetDropdown = UIRef.TargetSection:AddDropdown("Add Target", Options, function(Value)
                AICUI.S.AddPriorityTarget(Value)
            end)
        end
        function AICUI.SyncPriorityState(RefreshDropdown)
            CONFIG.TARGET_ENTITY_PRIORITY = UIRef.PriorityComponent.Priority
            AICCombat.ResetTargetState()
        
            if RefreshDropdown then
                AICUI.RefreshTargetDropdown()
            end
        
            AICProfile.SaveActiveProfile()
        end
        
        --// Utility UI status helpers
        function AICUI.updateFeatureButtons()
            --// Called from every path that loads, creates, imports or deletes a
            --// profile, so the two new controls are resynced from here rather than
            --// repeating the call at each of those sites.
            --// SetState resolves every count through the bound inventory, so no
            --// separate refresh is needed here any more.
            if UIRef.PinPanel and type(CONFIG.PINNED_STATE) == "table" then
                UIRef.PinPanel:SetState(CONFIG.PINNED_STATE)
            end
        
            if UIRef.ExecuteChargeSlider then
                UIRef.ExecuteChargeSlider:Set(
                    math.clamp(tonumber(CONFIG.EXECUTE_CHARGE_HP_PERCENT) or 0, 0, 90),
                    false
                )
            end
        
            if UIRef.TargetTypeDropdown then
                UIRef.TargetTypeDropdown:Set(tostring(CONFIG.TARGET_HP_MODE or "Disabled"), false)
            end
        
            if UIRef.BlockWhitelistComponent then
                UIRef.BlockWhitelistComponent:SetPriority(table.clone(CONFIG.BLOCK_WHITELIST or {}))
                CONFIG.BLOCK_WHITELIST = UIRef.BlockWhitelistComponent.Priority
                AICUI.RefreshWhitelistPlayerDropdown()
            end
        
            AICUI.SetFeatureComponent("AutoFarm", AICFeature.S.Enabled)
            AICUI.SetFeatureComponent("AutoBlock", Feature.AutoBlock.Enabled)
            AICUI.SetFeatureComponent("SafeCombat", Feature.SafeCombat.Enabled)
            AICUI.SetFeatureComponent("AutoSkill", Feature.AutoSkill.Enabled)
            AICUI.SetFeatureComponent("AutoFind", Feature.AutoFind.Enabled)
            AICUI.SetFeatureComponent("IgnoreFarmZone", Feature.IgnoreFarmZone.Enabled)
            AICUI.SetFeatureComponent("AutoPatrol", Feature.AutoPatrol.Enabled)
            AICUI.SetFeatureComponent("ReturnToFarmZone", Feature.ReturnToFarmZone.Enabled)
            AICUI.SetFeatureComponent("ResetOnBoostOut", Feature.ResetOnBoostOut.Enabled)
            if Feature.DebugWaypoints.Button then Feature.DebugWaypoints.Button:Set(Feature.DebugWaypoints.Enabled, false) end
            if Feature.DebugFarmZones.Button then Feature.DebugFarmZones.Button:Set(Feature.DebugFarmZones.Enabled, false) end
            if Feature.DebugDeadzones.Button then Feature.DebugDeadzones.Button:Set(Feature.DebugDeadzones.Enabled, false) end
            if Feature.DebugRadiusLabels.Button then Feature.DebugRadiusLabels.Button:Set(Feature.DebugRadiusLabels.Enabled, false) end
        end
        function AICUI.updateButton()
            Feature.AutoFarm.Enabled = AICFeature.S.Enabled
            AICUI.SetFeatureComponent("AutoFarm", AICFeature.S.Enabled)
        end
        function AICUI.FormatVector3(Position)
            if typeof(Position) ~= "Vector3" then
                return "0, 0, 0"
            end
        
            return string.format("%.1f, %.1f, %.1f", Position.X, Position.Y, Position.Z)
        end
        function AICUI.BuildWaypointLabels()
        local PlaceConfig = Runtime:GetPlaceConfig()
            local Labels = {}
        
            for Index, Position in ipairs(PlaceConfig.WAYPOINTS or {}) do
                Labels[Index] = string.format("#%d  (%s)", Index, AICUI.FormatVector3(Position))
            end
        
            return Labels
        end
        function AICUI.BuildZoneLabels(Zones, Prefix)
            local Labels = {}
        
            for Index, Zone in ipairs(Zones or {}) do
                Labels[Index] = string.format(
                    "#%d  R:%g  (%s)",
                    Index,
                    tonumber(Zone.Radius) or 0,
                    AICUI.FormatVector3(Zone.Center)
                )
            end
        
            return Labels
        end
        function AICUI.ReplacePriorityList(Component, Values)
            if not Component then
                return
            end
        
            Component:SetPriority(Values)
        end
        function AICUI.RefreshWaypointList()
            AICUI.ReplacePriorityList(UIRef.WaypointListComponent, AICUI.BuildWaypointLabels())
        end
        function AICUI.RefreshFarmZoneList()
        local PlaceConfig = Runtime:GetPlaceConfig()
            AICUI.ReplacePriorityList(
                UIRef.FarmZoneListComponent,
                AICUI.BuildZoneLabels(PlaceConfig.FARM_ZONES, "Farm")
            )
        end
        function AICUI.RefreshDeadzoneList()
        local PlaceConfig = Runtime:GetPlaceConfig()
            AICUI.ReplacePriorityList(
                UIRef.DeadzoneListComponent,
                AICUI.BuildZoneLabels(PlaceConfig.DEADZONES, "Deadzone")
            )
        end
        function AICUI.GetZonePickerOptions(Zones, Prefix)
            local Options = {}
        
            for Index in ipairs(Zones or {}) do
                table.insert(Options, string.format("#%d", Index))
            end
        
            if #Options == 0 then
                Options = {"No " .. Prefix .. " Zones"}
            end
        
            return Options
        end
        function AICUI.RefreshFarmZonePicker()
        local PlaceConfig = Runtime:GetPlaceConfig()
            local Options = AICUI.GetZonePickerOptions(PlaceConfig.FARM_ZONES, "Farm")
        
            if UIRef.FarmZonePicker then
                if UIRef.FarmZonePicker.Popup then UIRef.FarmZonePicker.Popup:Destroy() end
                if UIRef.FarmZonePicker.Frame then UIRef.FarmZonePicker.Frame:Destroy() end
            end
        
            AICProfile.S.SelectedFarmZoneIndex = math.clamp(AICProfile.S.SelectedFarmZoneIndex, 1, math.max(1, #PlaceConfig.FARM_ZONES))
            local SelectedOption = Options[AICProfile.S.SelectedFarmZoneIndex] or Options[1]
        
            UIRef.FarmZonePicker = UIRef.FarmzoneSection:AddDropdown("Edit Farm Zone", Options, function(Value)
                if Value == "No Farm Zones" then return end
                local Index = table.find(Options, Value)
                if not Index or not PlaceConfig.FARM_ZONES[Index] then return end
        
                AICProfile.S.SelectedFarmZoneIndex = Index
                UIRef.FarmRadiusSlider:Set(tonumber(PlaceConfig.FARM_ZONES[Index].Radius) or 100, false)
            end)
        
            if SelectedOption then UIRef.FarmZonePicker:Set(SelectedOption) end
        end
        function AICUI.RefreshDeadzonePicker()
        local PlaceConfig = Runtime:GetPlaceConfig()
            local Options = AICUI.GetZonePickerOptions(PlaceConfig.DEADZONES, "Deadzone")
        
            if UIRef.DeadzonePicker then
                if UIRef.DeadzonePicker.Popup then UIRef.DeadzonePicker.Popup:Destroy() end
                if UIRef.DeadzonePicker.Frame then UIRef.DeadzonePicker.Frame:Destroy() end
            end
        
            AICProfile.S.SelectedDeadzoneIndex = math.clamp(AICProfile.S.SelectedDeadzoneIndex, 1, math.max(1, #PlaceConfig.DEADZONES))
            local SelectedOption = Options[AICProfile.S.SelectedDeadzoneIndex] or Options[1]
        
            UIRef.DeadzonePicker = UIRef.DeadzoneSection:AddDropdown("Edit Deadzone", Options, function(Value)
                if Value == "No Deadzone Zones" then return end
                local Index = table.find(Options, Value)
                if not Index or not PlaceConfig.DEADZONES[Index] then return end
        
                AICProfile.S.SelectedDeadzoneIndex = Index
                UIRef.DeadzoneRadiusSlider:Set(tonumber(PlaceConfig.DEADZONES[Index].Radius) or 35, false)
            end)
        
            if SelectedOption then UIRef.DeadzonePicker:Set(SelectedOption) end
        end
        
        --// UI stats
        function AICUI.neededExp(lvl)
            lvl = lvl - 1
        
            local total = 9
        
            for i = 1, lvl do
                total = total + (6 * (i + 2))
            end
        
            return total
        end
        function AICUI.GetItem(String, ItemName)
            for Item in string.gmatch(String, "([^,]+)") do
                local Name, Amount = string.match(Item, "([^|]+)|(.+)")
        
                if Name == ItemName then
                    return Name, tonumber(Amount) or 0
                end
            end
        
            return ItemName, 0
        end
        function AICUI.updateEventCurrency()
            local PlayerStats = Player:FindFirstChild("PlayerStats")
        
            if not PlayerStats then
                AICUI.S.EventCurrency = 0
                UIRef.EventCurrencyLabel.Text = "EVENT CURRENCY  0"
                UIRef.ExpLabel.Text = "EXP            0/0"
                AICUI.S.LastInventory = nil
                return
            end
        
            local PlayerLvl = PlayerStats:FindFirstChild("Level")
            local PlayerExp = PlayerStats:FindFirstChild("EXP")
        
            if PlayerLvl and PlayerExp then
                UIRef.ExpLabel.Text = "EXP            " .. PlayerExp.Value .. "/" .. AICUI.neededExp(PlayerLvl.Value)
            else
                UIRef.ExpLabel.Text = "EXP            0/0"
            end
        
            local Inventory = PlayerStats:FindFirstChild("Inventory")
        
            if not Inventory then
                AICUI.S.EventCurrency = 0
                UIRef.EventCurrencyLabel.Text = "EVENT CURRENCY  0"
                return
            end
        
            local InventoryValue = Inventory.Value
        
            if InventoryValue == AICUI.S.LastInventory then
                return
            end
        
            AICUI.S.LastInventory = InventoryValue
        
            local _, Amount = AICUI.GetItem(InventoryValue, AICUI.S.TargetCurrency)
        
            AICUI.S.EventCurrency = Amount
            UIRef.EventCurrencyLabel.Text = "EVENT CURRENCY  " .. tostring(AICUI.S.EventCurrency)
        end
        function AICUI.updatePlayTime()
            local ServerAge = math.floor(workspace.DistributedGameTime)
        
            local Hours   = math.floor(ServerAge / 3600)
            local Minutes = math.floor((ServerAge % 3600) / 60)
            local Seconds = ServerAge % 60
        
            UIRef.ServerAgeLabel.Text = "PLAY TIME      " .. string.format("%02d:%02d:%02d", Hours, Minutes, Seconds)
        end
        function AICUI.updatePosition()
        local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if RootPart then
                local Position = RootPart.Position
        
                UIRef.PositionLabel.Text = string.format(
                    "POSITION       %.1f, %.1f, %.1f",
                    Position.X,
                    Position.Y,
                    Position.Z
                )
            else
                UIRef.PositionLabel.Text = "POSITION       --"
            end
        end
        
        --// Refresh the dropdown whenever the mob set changes.
        --// Subscribes the picker to the mob watcher. Assigned here rather than
        --// called from there, so the dependency runs UI -> Combat only.
        AICCombat.OnMobSetChanged = function()
            AICUI.RefreshEnemyPicker()
        end
        function AICUI.RefreshEnemyPicker()
            AICUI.RefreshTargetDropdown()
        end
        
        
        ------------------------------------------------------------------------
        --// AICDebug
        --//
        --// in-world waypoint and zone visualiser
        --//
        --// 10 function(s). Definitions only; nothing here runs
        --// at load time.
        ------------------------------------------------------------------------
        
        ------------------------------------------------------------------------
        --// AICDebug  ::  in-world waypoint and zone visualiser
        --// 10 function(s)
        ------------------------------------------------------------------------
        --// ============================================================
        --// DEBUG VISUALIZER
        --// ============================================================
        return Module
    end,
}
