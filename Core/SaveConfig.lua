return {
    Name = "SaveConfig",
    Dependencies = {},

    Start = function()
        return {
            Profile = {},

            AutoFarm = {
                Enabled = true,
            },

            AutoBlock = {
                Enabled = true,
                Whitelist = {},
            },

            AutoCraft = {
                Enabled = false,
            },

            AutoPatrol = {
                Enabled = false,
            },

            ReturnToFarmZone = {
                Enabled = true,
            },

            IgnoreFarmZone = {
                Enabled = false,
            },

            AutoHeal = {
                Enabled = true,
                HealthPercent = 65,
            },

            AutoRefill = {
                Enabled = true,
            },

            AntiAFK = {
                Enabled = true,
            },

            AutoSkill = {
                Enabled = true,
            },

            AutoFind = {
                Enabled = false,
            },

            SafeCombat = {
                Enabled = true,
            },

            ResetOnBoostOut = {
                Enabled = true,
            },

            ResetStats = {
                Enabled = true,
            },

            EnemyPriority = {},
            Waypoints = {},
            Farmzone = {},
            Deadzone = {},

            DebugVisualizer = {
                Enabled = false,
            },
        }
    end,
}
