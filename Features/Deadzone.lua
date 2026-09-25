return {
    Name = "Deadzone",
    IsFeature = true,
    Dependencies = {"Runtime", "ProfileManager", "ProfileSettings", "CombatUtils", "Components"},
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
        local FeatureState = Context.Feature
        local AICConfig = Context.AICConfig
        local AICProfile = Context.AICProfile
        local AICCombatUtils = Context.AICCombatUtils
        local AICCombat = Context.AICCombat
        local AICFeature = Context.AICFeature
        local AICUI = Context.AICUI
        local AICDebug = Context.AICDebug
        local UIRef = Context.UIRef
        local UI = Context.UI
        local PatrolState = Context.PatrolState
        local MiningFeature = Context.MiningFeature
        local NotifyAction = Context.NotifyAction

        local Feature = {
            Name = "Deadzone",
            IsFeature = true,
        }
        function Feature.GetDeadzoneEscapePosition()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if not RootPart then
                return nil
            end
        
            local now = os.clock()
        
            if AICFeature.S.DeadzoneEscapePosition
                and now - AICFeature.S.LastDeadzoneEscapeTime < CONFIG.DEADZONE_ESCAPE_INTERVAL
            then
                return AICFeature.S.DeadzoneEscapePosition
            end
        
            AICFeature.S.LastDeadzoneEscapeTime = now
            AICFeature.S.DeadzoneEscapePosition = nil
        
        
            local Origin = RootPart.Position
        
            for Index = 1, CONFIG.DEADZONE_ESCAPE_DIRECTIONS do
                local Angle = (Index / CONFIG.DEADZONE_ESCAPE_DIRECTIONS) * math.pi * 2
        
                local Direction = Vector3.new(
                    math.cos(Angle),
                    0,
                    math.sin(Angle)
                )
        
                local Candidate = Origin + Direction * CONFIG.DEADZONE_ESCAPE_DISTANCE
        
                if AICCombatUtils.IsEscapePathClear(Candidate) then
                    AICFeature.S.DeadzoneEscapePosition = Candidate
                    return Candidate
                end
            end
        
            return nil
        end
        function Feature.HandleDeadzoneEscape()
            local Character, Humanoid, RootPart = Runtime:GetCharacter()
            if FeatureState.IgnoreFarmZone.Enabled then
                AICFeature.S.DeadzoneEscapePosition = nil
        
                return false
            end
        
            if not RootPart or not Humanoid then
                return false
            end
        
            if not AICCombatUtils.IsInsideFarmDeadzone(RootPart.Position) then
                AICFeature.S.DeadzoneEscapePosition = nil
        
        
                return false
            end
        
            local EscapePosition = AICFeature.GetDeadzoneEscapePosition()
        
            if EscapePosition then
                Humanoid:MoveTo(EscapePosition)
                return true
            end
        
            return false
        end
        
        
        
        ------------------------------------------------------------------------
        --// AICUI
        --//
        --// tabs, controls, status readouts
        --//
        --// 26 function(s). Definitions only; nothing here runs
        --// at load time.
        ------------------------------------------------------------------------
        
        ------------------------------------------------------------------------
        --// AICUI  ::  tabs, controls, status readouts
        --// 25 function(s)
        ------------------------------------------------------------------------

        AICFeature.GetDeadzoneEscapePosition = function(...) return Feature.GetDeadzoneEscapePosition(...) end
        AICFeature.HandleDeadzoneEscape = function(...) return Feature.HandleDeadzoneEscape(...) end

        return Feature
    end,
}
