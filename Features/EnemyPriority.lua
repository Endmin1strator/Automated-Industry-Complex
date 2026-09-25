return {
    Name = "EnemyPriority",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig"},

    Start = function(Context)
        local Runtime = Context.Runtime
        local Config = Context.SaveConfig

        local Feature = {
            Name = "EnemyPriority",
            IsFeature = true,
        }

        function Feature:GetPriority()
            return Config.EnemyPriority
                or (Context.CONFIG and Context.CONFIG.TARGET_ENTITY_PRIORITY)
                or {}
        end

        function Feature:SetPriority(Value)
            Config.EnemyPriority = Value or {}

            if Context.CONFIG then
                Context.CONFIG.TARGET_ENTITY_PRIORITY = Config.EnemyPriority
            end
        end

        function Feature:IsPriority(Name)
            return table.find(self:GetPriority(), Name) ~= nil
        end

        function Feature:CreateUI(Section)
            if Section and Section.AddPriority then
                self.Component = Section:AddPriority(
                    "Enemy Priority",
                    self:GetPriority()
                )
            end
        end

        function Feature:Update()
        end

        return Feature
    end,
}
