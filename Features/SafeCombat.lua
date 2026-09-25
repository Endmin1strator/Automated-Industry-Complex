return {
    Name = "SafeCombat",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "Components"},

    Start = function(Context)
        local Runtime = Context.Runtime
        local FeatureState = Context.Feature
        local Config = Context.SaveConfig
        local AICCombat = Context.AICCombat
        local AICProfile = Context.AICProfile
        local AICUI = Context.AICUI
        local AICCombatUtils = Context.AICCombatUtils

        local Feature = {
            Name = "SafeCombat",
            IsFeature = true,
            Enabled = true,
        }

        function Feature:SetEnabled(Value)
            self.Enabled = Value == true

            if FeatureState and FeatureState.SafeCombat then
                FeatureState.SafeCombat.Enabled = self.Enabled
            end

            Config.SafeCombat = Config.SafeCombat or {}
            Config.SafeCombat.Enabled = self.Enabled
        end

        function Feature:Update()
        end

        function Feature:CreateUI()
            if Context.UIRef.FeatureSection then
                self.Button = AICUI.CreateFeature("Safe Combat", self.Enabled, function(Value)
                    self:SetEnabled(Value)
                    AICCombat.S.SafeCombatPositionEnabled = Value
                    AICCombat.ResetTargetReposition()
                    AICProfile.SaveActiveProfile()
                end)
                FeatureState.SafeCombat.Button = self.Button
            end
        end

        Feature:CreateUI()

        return Feature
    end,
}
