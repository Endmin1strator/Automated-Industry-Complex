return {
    Name = "ResetOnBoostOut",
    IsFeature = true,
    Dependencies = {"Runtime", "ProfileManager", "Components"},

    Start = function(Context)
        local FeatureState = Context.Feature
        local AICProfile = Context.AICProfile
        local AICUI = Context.AICUI
        local Feature = {
            Name = "ResetOnBoostOut",
            IsFeature = true,
            Enabled = true,
        }

        function Feature:Update()
        end

        function Feature:SetEnabled(Value)
            self.Enabled = Value == true
            FeatureState.ResetOnBoostOut.Enabled = self.Enabled
        end

        function Feature:CreateUI()
            if Context.UIRef.FeatureSection then
                self.Button = AICUI.CreateFeature("Refill Booster", self.Enabled, function(Value)
                    self:SetEnabled(Value)
                    AICProfile.SaveActiveProfile()
                end)
                FeatureState.ResetOnBoostOut.Button = self.Button
            end
        end

        Feature:CreateUI()

        return Feature
    end,
}
