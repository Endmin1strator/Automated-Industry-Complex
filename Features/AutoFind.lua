return {
    Name = "AutoFind",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "Components"},

    Start = function(Context)
        local Runtime = Context.Runtime
        local FeatureState = Context.Feature
        local Config = Context.SaveConfig
        local AICFeature = Context.AICFeature
        local AICCombat = Context.AICCombat
        local AICProfile = Context.AICProfile
        local AICUI = Context.AICUI

        local Feature = {
            Name = "AutoFind",
            IsFeature = true,
            Enabled = false,
        }

        function Feature:SetEnabled(Value)
            self.Enabled = Value == true

            if FeatureState and FeatureState.AutoFind then
                FeatureState.AutoFind.Enabled = self.Enabled
            end

            Config.AutoFind = Config.AutoFind or {}
            Config.AutoFind.Enabled = self.Enabled
        end

        function Feature:Update()
        end

        function Feature:CreateUI()
            if Context.UIRef.FeatureSection then
                self.Button = AICUI.CreateFeature("Auto Find", self.Enabled, function(Value)
                    self:SetEnabled(Value)
                    AICFeature.S.WaypointEnabled = not Value
                    AICCombat.S.ClosestTarget = nil
                    table.clear(AICCombat.S.ValidMobs)
                    table.clear(AICCombat.S.CombatGroupCache)
                    AICCombat.ResetTargetReposition()
                    AICCombat.UpdateValidMobs()
                    AICCombat.S.ClosestTarget = AICCombat.AcquireCombatTarget(os.clock())
                    AICProfile.SaveActiveProfile()
                end)
                FeatureState.AutoFind.Button = self.Button
            end
        end

        Feature:CreateUI()

        return Feature
    end,
}
