return {
    Name = "AutoCraft",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig"},

    Start = function(Context)
        local Feature = {
            Name = "AutoCraft",
            IsFeature = true,
            Enabled = false,
        }

        function Feature:SetEnabled(Value)
            self.Enabled = Value == true
        end

        function Feature:CreateUI(Section)
            if not Section or not Section.AddToggle then
                return
            end

            self.Button = Section:AddToggle(
                "Auto Craft",
                self.Enabled,
                function(Value)
                    self:SetEnabled(Value)
                end
            )
        end

        function Feature:Update()
            -- The supplied source only contains the Crafting tab/section
            -- and no crafting routine yet.
        end

        return Feature
    end,
}
