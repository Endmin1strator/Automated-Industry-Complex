return {
    Name = "AutoSkill",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "Components"},

    Start = function(Context)
        local Runtime = Context.Runtime
        local FeatureState = Context.Feature
        local Config = Context.SaveConfig
        local AICProfile = Context.AICProfile
        local AICUI = Context.AICUI

        local Feature = {
            Name = "AutoSkill",
            IsFeature = true,
            Enabled = true,
        }

        function Feature:SetEnabled(Value)
            self.Enabled = Value == true

            if FeatureState and FeatureState.AutoSkill then
                FeatureState.AutoSkill.Enabled = self.Enabled
            end

            Config.AutoSkill = Config.AutoSkill or {}
            Config.AutoSkill.Enabled = self.Enabled
        end

        function Feature:Update()
        end

        function Feature:CreateUI()
            if Context.UIRef.FeatureSection then
                self.Button = AICUI.CreateFeature("Auto Skill", self.Enabled, function(Value)
                    self:SetEnabled(Value)
                    AICProfile.SaveActiveProfile()
                end)
                FeatureState.AutoSkill.Button = self.Button
            end
        end

        Feature:CreateUI()

        return Feature
    end,
}
