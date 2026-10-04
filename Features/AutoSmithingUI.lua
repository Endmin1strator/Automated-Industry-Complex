-- AutoSmithingUI owns the Crafting tab: the Auto Smithing toggle and status,
-- the smithing table choice, the Recipe Priority list with a Target per
-- recipe, what each recipe is waiting on, and the Material Reserve list.
-- The lists are saved as the SMITH_RECIPES and SMITH_RESERVES settings; the
-- chosen table on the place config (SMITH_TABLE).
return {
    Name = "AutoSmithingUI",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "ProfileManager", "Components", "AutoSmithing", "SmithingRecipes"},

    Start = function(Context)
        local Runtime = Context.Runtime
        local AICConfig = Context.AICConfig
        local AICProfile = Context.AICProfile
        local AICUI = Context.AICUI
        local UIRef = Context.UIRef
        local NotifyAction = Context.NotifyAction
        local AutoSmithing = Context.AutoSmithing
        local Recipes = Context.SmithingRecipes

        local MAX_STACK = Context.SaveConfig.ITEM_MAX_STACK
        --// "Set Smithing Table" takes the nearest table within this.
        local SET_TABLE_MAX_DISTANCE = 20
        local INFO_INTERVAL = 1
        local NO_RECIPES_OPTION = "No recipes found"
        local NO_MATERIALS_OPTION = "No materials found"

        local Module = {
            Name = "AutoSmithingUI",
            IsFeature = true,
            RecipePicker = {},
            MaterialPicker = {},
            --// Add Recipe option label -> recipe name.
            RecipeOptions = {},
            RecipeLabels = {},
            LastInfo = 0,
        }

        local Section = UIRef.CraftSection

        AICUI.BindFeatureToggle("AutoSmithing", "Auto Smithing", function(Enabled)
            if not Enabled then
                AutoSmithing:Reset()
            end
        end, Section)

        --// AutoSmithing writes the text.
        UIRef.SmithStatusLabel = Section:AddLabel("STATUS  OFF")
        UIRef.SmithSkillLabel = Section:AddLabel("SMITHING SKILL  0")
        UIRef.SmithTableLabel = Section:AddLabel("TABLE  NEAREST")

        ------------------------------------------------------------------------
        --// Smithing table
        ------------------------------------------------------------------------

        local function SetTable(Position, Status)
            if not AICProfile.S.ActiveProfileName then
                AICUI.SetProfileStatus("CREATE / LOAD PROFILE FIRST")
                return
            end

            Runtime:GetPlaceConfig().SMITH_TABLE = Position and AICConfig.RoundVector3(Position) or nil
            AICProfile.SaveActiveProfile()
            AutoSmithing:Reset()
            NotifyAction("AUTO SMITHING", Status)
        end

        Section:AddButton("Set Smithing Table", function()
            local Table, Distance = AutoSmithing:GetNearestTable()

            if not Table or Distance > SET_TABLE_MAX_DISTANCE then
                NotifyAction("AUTO SMITHING", string.format("Stand within %d studs of a smithing table", SET_TABLE_MAX_DISTANCE))
                return
            end

            SetTable(AutoSmithing:GetTablePosition(Table), "Smithing table set")
        end)

        Section:AddButton("Use Nearest Table", function()
            SetTable(nil, "Using the nearest smithing table")
        end)

        ------------------------------------------------------------------------
        --// Recipe Priority
        ------------------------------------------------------------------------

        UIRef.RecipePriorityComponent = Section:AddPriority("Recipe Priority", {}, {
            Values = true,
            ValueLabel = "Target",
            Default = MAX_STACK,
            Min = 0,
            Max = MAX_STACK,
        })

        local RecipeList = UIRef.RecipePriorityComponent

        local LoadRecipeList = AICUI.BindCountList(RecipeList, "SMITH_RECIPES", "Target", function()
            AutoSmithing:Rescan()
            AICUI.RefreshRecipePicker(true)
            Module.LastInfo = 0
        end)

        LoadRecipeList()

        local function DescribeMaterials(Recipe)
            local Parts = {}

            for _, Material in ipairs(Recipe.Materials) do
                table.insert(Parts, string.format("%s x%d", Material.Name, Material.Amount))
            end

            return table.concat(Parts, ", ")
        end

        local function AddRecipe(Option)
            local Name = Module.RecipeOptions[Option]

            if not Name then
                return
            end

            if RecipeList:Add(Name, MAX_STACK) then
                NotifyAction("AUTO SMITHING", "Added " .. Name)
            end
        end

        --// Recipes not yet in the list, easiest first, each with its skill
        --// requirement and materials.
        function AICUI.RefreshRecipePicker(Force)
            local Options = {}
            table.clear(Module.RecipeOptions)

            for _, Recipe in ipairs(Recipes:GetAll()) do
                if not table.find(RecipeList.Priority, Recipe.Name) then
                    local Option = string.format("%s  [Skill %s]  %s", Recipe.Name, tostring(Recipe.Skill), DescribeMaterials(Recipe))
                    Module.RecipeOptions[Option] = Recipe.Name
                    table.insert(Options, Option)
                end
            end

            if #Options == 0 then
                Options = { NO_RECIPES_OPTION }
            end

            AICUI.RefreshDropdown(Module.RecipePicker, Section, "Add Recipe", Options, AddRecipe, Force)
        end

        AICUI.RefreshRecipePicker(true)

        Section:AddButton("Refresh Recipes", function()
            AICUI.RefreshRecipePicker(true)
            AICUI.RefreshMaterialPicker(true)
        end)

        ------------------------------------------------------------------------
        --// Recipe Status: one line per recipe in the list
        ------------------------------------------------------------------------

        local StatusSection = UIRef.CraftTab:AddSection("Recipe Status")

        local function DescribeState(Index, State)
            local Head = string.format("#%d  %s  %d/%d", Index, State.Name, State.Have, State.Target)

            if not State.Known then
                return Head .. "  //  UNKNOWN RECIPE"
            elseif State.Locked then
                return string.format("%s  //  LOCKED  SKILL %s / %s", Head, tostring(State.Recipe.Skill), tostring(State.Skill))
            elseif State.Remaining <= 0 then
                return Head .. "  //  DONE"
            elseif AutoSmithing:IsPaused(State.Name) then
                return Head .. "  //  PAUSED AFTER FAILURES"
            elseif State.Craftable < 1 and State.Short then
                return string.format("%s  //  NEED %s %d/%d", Head, State.Short.Name, State.Short.Have, State.Short.Need)
            end

            return string.format("%s  //  READY  x%d", Head, math.min(State.Craftable, State.Remaining))
        end

        --// A pool of labels, one per recipe; spare ones are hidden.
        local function RefreshRecipeStatus()
            local Lines = {}

            for Index, State in ipairs(Recipes:GetPlan()) do
                Lines[Index] = DescribeState(Index, State)
            end

            if #Lines == 0 then
                Lines[1] = "NO RECIPES IN PRIORITY"
            end

            for Index, Text in ipairs(Lines) do
                local Label = Module.RecipeLabels[Index]

                if not Label then
                    Label = StatusSection:AddLabel(Text)
                    Module.RecipeLabels[Index] = Label
                end

                if Label.Text ~= Text then
                    Label.Text = Text
                end

                Label.Visible = true
            end

            for Index = #Lines + 1, #Module.RecipeLabels do
                Module.RecipeLabels[Index].Visible = false
            end
        end

        ------------------------------------------------------------------------
        --// Material Reserve
        ------------------------------------------------------------------------

        local ReserveSection = UIRef.CraftTab:AddSection("Material Reserve")

        UIRef.MaterialReserveComponent = ReserveSection:AddPriority("Keep In Inventory", {}, {
            Values = true,
            ValueLabel = "Keep",
            Default = 0,
            Min = 0,
            Max = MAX_STACK,
        })

        local ReserveList = UIRef.MaterialReserveComponent

        local LoadReserveList = AICUI.BindCountList(ReserveList, "SMITH_RESERVES", "Keep", function()
            AutoSmithing:Rescan()
            AICUI.RefreshMaterialPicker(true)
            Module.LastInfo = 0
        end)

        LoadReserveList()

        local function AddReserve(Name)
            if Name ~= NO_MATERIALS_OPTION and ReserveList:Add(Name, 0) then
                NotifyAction("AUTO SMITHING", "Reserve added for " .. Name .. "; set how many to keep")
            end
        end

        --// Materials any recipe uses that have no reserve yet.
        function AICUI.RefreshMaterialPicker(Force)
            local Options = {}

            for _, Name in ipairs(Recipes:GetMaterialNames()) do
                if not table.find(ReserveList.Priority, Name) then
                    table.insert(Options, Name)
                end
            end

            if #Options == 0 then
                Options = { NO_MATERIALS_OPTION }
            end

            AICUI.RefreshDropdown(Module.MaterialPicker, ReserveSection, "Add Material", Options, AddReserve, Force)
        end

        AICUI.RefreshMaterialPicker(true)

        ------------------------------------------------------------------------

        local function RefreshInfo()
            UIRef.SmithSkillLabel.Text = "SMITHING SKILL  " .. tostring(Recipes:GetSkill())

            local Saved = Runtime:GetPlaceConfig().SMITH_TABLE
            UIRef.SmithTableLabel.Text = Saved
                and string.format("TABLE  SET  (%.0f, %.0f, %.0f)", Saved.X, Saved.Y, Saved.Z)
                or "TABLE  NEAREST"

            RefreshRecipeStatus()
        end

        function Module:Update()
            local now = os.clock()

            if now - Module.LastInfo >= INFO_INTERVAL then
                Module.LastInfo = now
                RefreshInfo()
            end
        end

        --// Called from updateFeatureButtons on every profile load.
        function AICUI.RefreshSmithingUI()
            LoadRecipeList()
            LoadReserveList()
            AICUI.RefreshRecipePicker(true)
            AICUI.RefreshMaterialPicker(true)
            AutoSmithing:Reset(true)
            Module.LastInfo = 0
        end

        return Module
    end,
}
