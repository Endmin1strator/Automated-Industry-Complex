return {
    Name = "IgnoreFarmZone",
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
            Name = "IgnoreFarmZone",
            IsFeature = true,
            Enabled = false,
        }

        function Feature:SetEnabled(Value)
            self.Enabled = Value == true

            if FeatureState and FeatureState.IgnoreFarmZone then
                FeatureState.IgnoreFarmZone.Enabled = self.Enabled
            end

            if Config.IgnoreFarmZone then
                Config.IgnoreFarmZone.Enabled = self.Enabled
            end
        end

        function Feature:CreateUI(Section)
            if Section and Section.AddToggle then
                self.Button = Section:AddToggle(
                    "Ignore Farm Zone",
                    self.Enabled,
                    function(Value)
                        self:SetEnabled(Value)
                    end
                )
            end
        end

        function Feature:Update()
        end

        function Feature:CreateUI()
            if Context.UIRef.FeatureSection then
                self.Button = AICUI.CreateFeature("Ignore Farm Zone", self.Enabled, function(Value)
                    self:SetEnabled(Value)
                    AICCombat.S.ClosestTarget = nil
                    table.clear(AICCombat.S.ValidMobs)
                    table.clear(AICCombat.S.CombatGroupCache)
                    AICCombat.ResetTargetReposition()
                    AICFeature.S.DeadzoneEscapePosition = nil
                    AICFeature.S.FarmReturnPosition = nil
                    AICFeature.S.LastFarmReturnCalculateTime = 0
                    AICCombat.UpdateValidMobs()
                    AICCombat.S.ClosestTarget = AICCombat.GetClosestGoblin()
                    AICProfile.SaveActiveProfile()
                end)
                FeatureState.IgnoreFarmZone.Button = self.Button
            end
        end

        Feature:CreateUI()

        return Feature
    end,
}
