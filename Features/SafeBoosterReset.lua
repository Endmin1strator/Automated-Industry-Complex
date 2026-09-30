return {
	Name = "SafeBoosterReset",
	IsFeature = true,
	Dependencies = {"Runtime", "ProfileManager", "Components"},
	Start = function(Context)
		local Runtime = Context.Runtime
		local Services = Context.Services
		--local Players = Services.Players
		local Player = Context.Player
		--local PlayerGui = Context.PlayerGui
		local Replicated = Services.Replicated
		--local StarterGui = Services.StarterGui
		--local RunService = Services.RunService
		--local PathfindingService = Services.PathfindingService
		--local HttpService = Services.HttpService
		--local CONFIG = Context.CONFIG
		local FeatureState = Context.Feature
		--local AICConfig = Context.AICConfig
		local AICProfile = Context.AICProfile
		--local AICCombatUtils = Context.AICCombatUtils
		--local AICCombat = Context.AICCombat
		local AICFeature = Context.AICFeature
		local AICUI      = Context.AICUI
		--local AICDebug = Context.AICDebug
		--local UIRef = Context.UIRef
		--local UI = Context.UI
		--local PatrolState = Context.PatrolState
		--local MiningFeature = Context.MiningFeature
		--local NotifyAction = Context.NotifyAction

		local Feature = {
			Name = "SafeBoosterReset",
			IsFeature = true,
			Enabled = false,
		}

		function Feature.SafeBoosterReset()
			task.spawn(function()
				local PlayerStats = Player:FindFirstChild("PlayerStats")
				if not PlayerStats then
					repeat task.wait(1) until Player:FindFirstChild("PlayerStats")
					PlayerStats = Player:FindFirstChild("PlayerStats")
				end
				local ExpBoost = PlayerStats:FindFirstChild("Boost")

				--// Resetting on boost-out is opt-in. The connection stays alive for the
				--// whole session, so the toggle has to be read at fire time, not here.
				local function SafeBoosterReset(Value)
					if not FeatureState.SafeBoosterReset.Enabled then
						return
					end

					if Value.Value ~= 0 then
						return
					end

					local DamageTag = Replicated.PlayerDamageTags:FindFirstChild(Player.Name.."MobDamaged")
					if DamageTag then
						return
					end

					local _, Humanoid = Runtime:GetCharacter()

					if Humanoid then
						Humanoid.Health = 0
					end
				end

				if ExpBoost then
					AICFeature.S.BoosterConnections[#AICFeature.S.BoosterConnections + 1] =
						ExpBoost:GetPropertyChangedSignal("Value"):Connect(function()
							SafeBoosterReset(ExpBoost)
						end
					)
				end
			end)
		end

		AICFeature.SafeBoosterReset = function(...) return Feature.SafeBoosterReset(...) end

		function Feature:Update()
		end

		function Feature:SetEnabled(Value)
			self.Enabled = Value == true
			FeatureState.SafeBoosterReset.Enabled = self.Enabled
		end

		function Feature:CreateUI()
			if Context.UIRef.FeatureSection then
				self.Button = AICUI.CreateFeature("Safe Booster Reset", self.Enabled, function(Value)
					self:SetEnabled(Value)
					AICProfile.SaveActiveProfile()
				end)
				FeatureState.SafeBoosterReset.Button = self.Button
			end
		end

		Feature:CreateUI()

		return Feature
	end,
}
