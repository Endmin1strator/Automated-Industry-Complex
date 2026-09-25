return {
    Name = "Bootstrap",
    Dependencies = {"Runtime", "ProfileManager", "Components", "ProfileSettings", "Waypoints", "Farmzone", "Deadzone", "DebugVisualizer", "CombatUtils", "Targeting", "Navigation", "Combat", "AutoFarming", "AutoBlock", "AutoPatrol", "ReturnToFarmZone", "AntiAFK", "AutoRefill"},
    Start = function(Context)
        local Runtime = Context.Runtime
        local Services = Context.Services
        local Players = Services.Players
        local Replicated = Services.Replicated
        local StarterGui = Services.StarterGui
        local RunService = Services.RunService
        local UserInputService = Services.UserInputService
        local MarketplaceService = Services.MarketplaceService
        local PathfindingService = Services.PathfindingService
        local HttpService = Services.HttpService
        local Player = Context.Player
        local PlayerGui = Context.PlayerGui
        local CONFIG = Context.CONFIG
        local AICConfig = Context.AICConfig
        local AICProfile = Context.AICProfile
        local AICCombatUtils = Context.AICCombatUtils
        local AICCombat = Context.AICCombat
        local AICFeature = Context.AICFeature
        local AICUI = Context.AICUI
        local AICDebug = Context.AICDebug
        local Feature = Context.Feature
        local MiningFeature = Context.MiningFeature
        local UI = Context.UI
        local UIRef = Context.UIRef
        local PatrolState = Context.PatrolState
        local NotifyAction = Context.NotifyAction
        local AICPlaceConfig = Runtime:GetPlaceConfig()
        local BasePlaceConfig = Runtime:GetBasePlaceConfig()
        local InputBindableFunction = Runtime:GetInputBindableFunction()
        local FaceOrientation = Runtime:GetFaceOrientation()

        --// Bootstrap / composition root
        --//
        --// Composition root. Creates the window, every control and the debug
        --// visualiser, then restores the last used profile. Nothing here runs
        --// per frame.
        ------------------------------------------------------------------------
        
        --======================================================================
        --// SECTION 3  ::  BOOTSTRAP AND RUNTIME
        --// Everything that actually executes, in its original order.
        --======================================================================
        
        
        AICPlaceConfig = AICConfig.IsValidPlace(game.PlaceId)
        
        AICPlaceConfig = AICConfig.NormalizePlaceConfig(AICPlaceConfig or {})
        Runtime:SetPlaceConfig(AICPlaceConfig)
        Context.PLACE_CONFIG = AICPlaceConfig
        
        BasePlaceConfig = AICConfig.NormalizePlaceConfig(AICConfig.IsValidPlace(game.PlaceId) or {})
        Runtime:SetBasePlaceConfig(BasePlaceConfig)
        
        
        
        
        if AICPlaceConfig then
            CONFIG.TARGET_ENTITY_PRIORITY = AICPlaceConfig.DEFAULT_TARGET_PRIORITY
        end
        
        AICFeature.updateCharacter()
        
        AICFeature.CreateToggleContainer()
        AICFeature.RegenStamina()
        
        Player.CharacterAdded:Connect(function()
            task.wait()
        
            AICFeature.S.DEATH_COUNT += 1
            CONFIG.CURRENT_WAYPOINT_TARGET = 1
            AICDebug.ResetDebugWaypoints()
            AICDebug.UpdateDebugWaypointColors()
            AICCombat.S.ClosestTarget = nil
            Runtime:SetInputBindableFunction(nil)
            AICFeature.S.BlockValue = nil
            AICFeature.S.Equipped = false
            AICCombat.S.RETREATING = false
            AICCombat.S.SkillRetreatPosition = nil
            AICCombat.S.LastSkillRetreatTime = 0
            AICCombat.S.SkillThreatUntil = 0
            AICCombat.S.LastSkillSolverTime = 0
            AICFeature.S.LAST_EQUIP_TIME = 0
            PatrolState.PatrolLegsRemaining = 0
            PatrolState.PatrolHeading = nil
            AICCombatUtils.S.StuckSamplePosition = nil
            AICCombatUtils.S.StuckStrikes = 0
            AICCombat.S.LAST_ATTACK_TIME = 0
            AICCombat.S.LAST_SKILL_TIME = 0
            AICCombat.S.LAST_COMBAT_TARGET_CHECK = 0
            AICCombat.S.COMBAT_TARGET_LOST_SINCE = nil
            AICCombat.S.COMBAT_TARGET_SCORE = math.huge
            AICCombat.S.COMBAT_ATTACK_PHASE = 0
            AICCombat.S.COMBAT_NEXT_ATTACK_TIME = 0
            AICCombat.S.COMBAT_NEXT_SKILL_TIME = 0
            AICFeature.S.LAST_CONSUME_TIME = 0
            AICFeature.S.LAST_INTERACTION_TIME = 0
            AICCombatUtils.S.LAST_STUCK_POSITION = nil
            AICFeature.S.FaceAttachment = nil
            Runtime:SetFaceOrientation(nil)
        
            if AICCombatUtils.S.DebugFolder then
                --// Keep the debug instances, but reset their state/colors for the new life.
                for Index, Data in AICDebug.S.DebugWaypointData do
                    if Data.Label then
                        Data.Label.TextColor3 = DEBUG_COLORS.WaypointPending
                    end
                    if Data.Marker then
                        Data.Marker.BackgroundColor3 = DEBUG_COLORS.WaypointPending
                    end
                end
            end
        
            if AICFeature.S.StaminaConnection then
                AICFeature.S.StaminaConnection:Disconnect()
                AICFeature.S.StaminaConnection = nil
            end
        
            table.clear(AICCombat.S.ValidMobs)
            table.clear(AICCombat.S.CombatGroupCache)
            table.clear(AICCombat.S.CombatBladeCache)
            table.clear(AICCombatUtils.S.BladePartCache)
            AICCombat.ClearUnreachableMobs()
        
            task.delay(0.5, function()
                AICFeature.S.Equipped = false
            end)
        
            AICFeature.updateCharacter()
            AICCombat.ResetTargetReposition()
            AICFeature.CreateToggleContainer()
            AICFeature.RegenStamina()
        end)
        AICFeature.AutoRefillBooster()
        
        
        
        --//==============================================================
        --// Utility UI
        --//==============================================================
        
        --UI:SetTheme({
        --    Background      = CONFIG.UI_PANEL,
        --    BackgroundLight = CONFIG.UI_SURFACE,
        --    Panel           = CONFIG.UI_SURFACE,
        --    PanelLight      = CONFIG.UI_HOVER,
        --    PanelHover      = Color3.fromRGB(48, 50, 60),
        --    Element         = CONFIG.UI_SURFACE,
        --    ElementHover    = CONFIG.UI_HOVER,
        --    Text            = CONFIG.UI_TEXT,
        --    TextSecondary   = Color3.fromRGB(190, 193, 204),
        --    TextMuted       = CONFIG.UI_MUTED,
        --    Cyan            = CONFIG.UI_ACCENT,
        --    CyanDark        = Color3.fromRGB(80, 90, 190),
        --    CyanDim         = Color3.fromRGB(150, 160, 255),
        --    White           = CONFIG.UI_TEXT,
        --    Border          = CONFIG.UI_BORDER,
        --    BorderDim       = Color3.fromRGB(45, 48, 58),
        --    Danger          = Color3.fromRGB(255, 65, 65),
        --    Warning         = Color3.fromRGB(255, 180, 0),
        --    Black           = Color3.fromRGB(10, 10, 14),
        --})
        
        UIRef.OreDropdown = UIRef.MineSection:AddDropdown(
            "Add Ores",
            CONFIG.PREFERED_ORES,
            function(Value)
                --TODO
            end
        )
        
        --// Feature toggles
        Feature.ResetStats.Enabled = true
        
        --// Priority component
        UIRef.PriorityComponent = UIRef.TargetSection:AddPriority(
            "Enemy Priority",
            CONFIG.TARGET_ENTITY_PRIORITY
        )
        
        -- Keep CONFIG and the Utils priority component on the same table.
        CONFIG.TARGET_ENTITY_PRIORITY = UIRef.PriorityComponent.Priority
        
        --// Capture the stock methods before the overrides below replace them.
        AICUI.S.OriginalPriorityAdd      = UIRef.PriorityComponent.Add
        AICUI.S.OriginalPriorityRemove   = UIRef.PriorityComponent.Remove
        AICUI.S.OriginalPriorityMoveUp   = UIRef.PriorityComponent.MoveUp
        AICUI.S.OriginalPriorityMoveDown = UIRef.PriorityComponent.MoveDown
        
        function UIRef.PriorityComponent:Add(EntityName)
            if not AICProfile.S.ActiveProfileName then
                return false
            end
        
            local Changed = AICUI.S.OriginalPriorityAdd(self, EntityName)
        
            if Changed then
                AICUI.SyncPriorityState(true)
            end
        
            return Changed
        end
        
        function UIRef.PriorityComponent:Remove(EntityName)
            if not AICProfile.S.ActiveProfileName then
                return false
            end
        
            local Changed = AICUI.S.OriginalPriorityRemove(self, EntityName)
        
            if Changed then
                AICUI.SyncPriorityState(true)
            end
        
            return Changed
        end
        
        function UIRef.PriorityComponent:MoveUp(EntityName)
            if not AICProfile.S.ActiveProfileName then
                return
            end
        
            AICUI.S.OriginalPriorityMoveUp(self, EntityName)
            AICUI.SyncPriorityState(true)
        end
        
        function UIRef.PriorityComponent:MoveDown(EntityName)
            if not AICProfile.S.ActiveProfileName then
                return
            end
        
            AICUI.S.OriginalPriorityMoveDown(self, EntityName)
            AICUI.SyncPriorityState(true)
        end
        
        AICUI.S.AddPriorityTarget = function(EntityName)
            if not EntityName or EntityName == "" or EntityName == "No detected enemies" then
                return
            end
        
            if AICCombat.IsEntityInPriority(EntityName) then
                return
            end
        
            UIRef.PriorityComponent:Add(EntityName)
        end
        
        UIRef.TargetRefreshButton = UIRef.TargetSection:AddButton(
            "Refresh Detected Targets",
            function()
                AICUI.RefreshTargetDropdown()
            end
        )

        --// Pinned items
        --// Lives outside the tabs so the panel can be dragged or popped out.
        UIRef.PinPanel = UI:AddPin("Pinned Items")

        UIRef.PinPanel.OnChanged = function()
            AICProfile.QueueProfileSave()
        end

        task.spawn(function()
            local PlayerStats = Player:WaitForChild("PlayerStats", 30)
            local Inventory = PlayerStats and PlayerStats:WaitForChild("Inventory", 30)

            if Inventory then
                UI:BindPinToValue(UIRef.PinPanel, Inventory)
            end
        end)

        --// Breaks ties between mobs of equal priority. Disabled keeps nearest first.
        UIRef.TargetTypeDropdown = UIRef.TargetSection:AddDropdown(
            "Target Type",
            { "Disabled", "Highest HP", "Lowest HP" },
            function(Value)
                CONFIG.TARGET_HP_MODE = tostring(Value or "Disabled")
                AICCombat.ResetTargetState()
                AICProfile.SaveActiveProfile()
            end
        )
        
        UIRef.TargetTypeDropdown:Set(tostring(CONFIG.TARGET_HP_MODE or "Disabled"), false)
        
        
        AICUI.RefreshTargetDropdown()
        
        AICUI.updateFeatureButtons()
        
        return {Name = "Bootstrap"}
    end,
}
