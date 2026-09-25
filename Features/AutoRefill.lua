return {
    Name = "AutoRefill",
    IsFeature = true,
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
            Name = "AutoRefill",
            IsFeature = true,
        }
        function Feature.AutoRefillBooster()
            task.spawn(function()
                local PlayerStats = Player:FindFirstChild("PlayerStats")
                if not PlayerStats then
                    repeat task.wait(1) until Player:FindFirstChild("PlayerStats")
                    PlayerStats = Player:FindFirstChild("PlayerStats")
                end
                local ExpBoost = PlayerStats:FindFirstChild("Boost")
                local DropBoost = PlayerStats:FindFirstChild("BoostDrops")
        
                --// Resetting on boost-out is opt-in. The connection stays alive for the
                --// whole session, so the toggle has to be read at fire time, not here.
                local function ResetOnBoostOut(Value)
                    if not FeatureState.ResetOnBoostOut.Enabled then
                        return
                    end
        
                    if Value.Value ~= 0 then
                        return
                    end

                    --// Resolved at fire time. The connection outlives respawns,
                    --// so a Humanoid captured at setup would be the dead one.
                    local _, Humanoid = Runtime:GetCharacter()

                    if Humanoid then
                        Humanoid.Health = 0
                    end
                end
        
                if ExpBoost then
                    AICFeature.S.BoosterConnections[#AICFeature.S.BoosterConnections + 1] =
                        ExpBoost:GetPropertyChangedSignal("Value"):Connect(function()
                            ResetOnBoostOut(ExpBoost)
                        end)
                end
        
                if DropBoost then
                    AICFeature.S.BoosterConnections[#AICFeature.S.BoosterConnections + 1] =
                        DropBoost:GetPropertyChangedSignal("Value"):Connect(function()
                            ResetOnBoostOut(DropBoost)
                        end)
                end
            end)
        end
        
        --// Jump only when something jumpable is actually in the way. Movement used
        --// to hop on every frame of a retreat and whenever the next waypoint sat
        --// higher, including on a smooth ramp where the jump did nothing but slow
        --// the character down.
        --// Roblox disconnects a client it considers idle. The script moves the
        --// character through the Humanoid, which does not count as input, so the
        --// idle timer runs even while the bot is busy. Player.Idled fires shortly
        --// before the disconnect and a synthetic click clears it.

        AICFeature.AutoRefillBooster = function(...) return Feature.AutoRefillBooster(...) end

        function Feature:Update()
            --// Bootstrap connects AutoRefillBooster once. Calling it here added
            --// two new connections on every Heartbeat.
        end

        return Feature
    end,
}
