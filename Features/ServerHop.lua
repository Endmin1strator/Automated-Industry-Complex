-- ServerHop owns moving between servers and watching who is in this one,
-- ported from Iambatman:
--   Rejoin, Server Hop (a random public server with a free slot) and joining
--   a server by Job ID; reading the public server list for the browser;
--   Leave On Danger Group, which leaves at once when a member of
--   DANGER_GROUP_ID is in the server; Join Alerts for players off the Auto
--   Block whitelist; and the Player Log of who joined and left.
-- ServerUI draws all of it on the Server tab.
return {
    Name = "ServerHop",
    IsFeature = true,
    Dependencies = {"Runtime", "SaveConfig", "AutoBlock"},

    Start = function(Context)
        local Services = Context.Services
        local Players = Services.Players
        local HttpService = Services.HttpService
        local TeleportService = game:GetService("TeleportService")
        local Player = Context.Player
        local Feature = Context.Feature
        local AICFeature = Context.AICFeature
        local NotifyAction = Context.NotifyAction

        --// The group Iambatman leaves the server for.
        local DANGER_GROUP_ID = 5928691
        local DANGER_HOP_MAX_ATTEMPTS = 3
        local DANGER_HOP_RETRY_DELAY = 3
        local GROUP_CHECK_MAX_ATTEMPTS = 3
        local GROUP_CHECK_RETRY_DELAY = 5
        --// Players are checked again this often, so a player taken off the
        --// whitelist, or a toggle switched on, is acted on.
        local SCAN_INTERVAL = 2
        --// Pages of the public server list a hop reads before giving up.
        local HOP_MAX_PAGES = 4
        local LOG_LIMIT = 100
        local SERVER_LIST_URL = "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"

        local ServerHop = {
            Name = "ServerHop",
            IsFeature = true,
            DANGER_GROUP_ID = DANGER_GROUP_ID,
            S = {
                Teleporting = false,
                Status = "IDLE",
                --// UserId -> true once found in the danger group.
                DangerUsers = {},
                CheckedUsers = {},
                CheckInFlight = {},
                CheckFailures = {},
                DangerHopStarted = false,
                DangerHopAttempts = 0,
                AlertSeen = {},
                Log = {},
                --// Bumped on every log change, so the UI redraws only then.
                LogVersion = 0,
                Online = {},
                LastScan = 0,
                --// Set by the first Update, once the profile is loaded.
                Ready = false,
            },
        }

        local S = ServerHop.S

        local function IsWhitelisted(OtherPlayer)
            return AICFeature.IsWhitelisted ~= nil and AICFeature.IsWhitelisted(OtherPlayer.UserId) == true
        end

        local function SetStatus(Text)
            S.Status = Text
        end

        function ServerHop:GetStatus()
            return S.Status
        end

        function ServerHop:IsDangerPlayer(OtherPlayer)
            return S.DangerUsers[tostring(OtherPlayer.UserId)] == true
        end

        ------------------------------------------------------------------------
        --// Player Log
        ------------------------------------------------------------------------

        local function RecordLog(OtherPlayer, Event)
            if not OtherPlayer or OtherPlayer == Player then
                return
            end

            table.insert(S.Log, {
                Time = os.date("%H:%M:%S"),
                Event = Event,
                Name = OtherPlayer.Name,
                UserId = tostring(OtherPlayer.UserId),
            })

            while #S.Log > LOG_LIMIT do
                table.remove(S.Log, 1)
            end

            S.LogVersion += 1
        end

        --// Newest first.
        function ServerHop:GetLog()
            local Result = {}

            for Index = #S.Log, 1, -1 do
                table.insert(Result, S.Log[Index])
            end

            return Result
        end

        function ServerHop:ClearLog()
            table.clear(S.Log)
            S.LogVersion += 1
        end

        ------------------------------------------------------------------------
        --// Teleports
        ------------------------------------------------------------------------

        local function TeleportToInstance(JobId, Status)
            if S.Teleporting then
                return false
            end

            S.Teleporting = true
            SetStatus(Status)

            task.spawn(function()
                local Success, Error = pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, JobId, Player)
                end)

                if not Success then
                    S.Teleporting = false
                    SetStatus("TELEPORT FAILED")
                    NotifyAction("SERVER", tostring(Error), 6)
                end
            end)

            return true
        end

        function ServerHop:Rejoin()
            local JobId = tostring(game.JobId or "")

            if JobId == "" then
                NotifyAction("SERVER", "This server has no Job ID, so Rejoin is unavailable", 4)
                return false
            end

            NotifyAction("SERVER", "Rejoining this server...")
            return TeleportToInstance(JobId, "REJOINING")
        end

        function ServerHop:Join(JobId)
            JobId = tostring(JobId or ""):gsub("%s+", "")

            if JobId == "" or JobId == game.JobId then
                NotifyAction("SERVER", "That Job ID is empty or is this server", 4)
                return false
            end

            return TeleportToInstance(JobId, "JOINING SERVER")
        end

        --// One page of public servers with a free slot, other than this one.
        --// Returns the servers and the next page's cursor, or nil and an error.
        function ServerHop:ReadPublicServers(Cursor)
            local Url = string.format(SERVER_LIST_URL, game.PlaceId)

            if type(Cursor) == "string" and Cursor ~= "" then
                Url ..= "&cursor=" .. HttpService:UrlEncode(Cursor)
            end

            local Success, Body = pcall(function()
                return game:HttpGet(Url)
            end)

            if not Success then
                return nil, nil, Body
            end

            local Decoded, Payload = pcall(function()
                return HttpService:JSONDecode(Body)
            end)

            if not Decoded or type(Payload) ~= "table" or type(Payload.data) ~= "table" then
                return nil, nil, "The public server list response was invalid"
            end

            local Servers = {}

            for _, Server in ipairs(Payload.data) do
                local Playing = tonumber(Server.playing)
                local MaxPlayers = tonumber(Server.maxPlayers)

                if type(Server.id) == "string" and Server.id ~= game.JobId
                    and Playing and MaxPlayers and Playing < MaxPlayers
                then
                    table.insert(Servers, {
                        Id = Server.id,
                        Playing = Playing,
                        MaxPlayers = MaxPlayers,
                        Ping = tonumber(Server.ping),
                        FPS = tonumber(Server.fps),
                    })
                end
            end

            local NextCursor = type(Payload.nextPageCursor) == "string" and Payload.nextPageCursor or nil
            return Servers, NextCursor
        end

        function ServerHop:Hop()
            if S.Teleporting then
                return false
            end

            SetStatus("FINDING SERVER")

            task.spawn(function()
                local Cursor

                for _ = 1, HOP_MAX_PAGES do
                    local Servers, NextCursor, Error = ServerHop:ReadPublicServers(Cursor)

                    if not Servers then
                        SetStatus("HOP FAILED")
                        NotifyAction("SERVER HOP", "Could not read the server list: " .. tostring(Error), 6)
                        return
                    end

                    if #Servers > 0 then
                        NotifyAction("SERVER HOP", "Joining another public server...")
                        TeleportToInstance(Servers[math.random(1, #Servers)].Id, "HOPPING")
                        return
                    end

                    Cursor = NextCursor

                    if not Cursor then
                        break
                    end
                end

                SetStatus("NO OTHER SERVER")
                NotifyAction("SERVER HOP", "No other public server with a free slot was found", 6)
            end)

            return true
        end

        ------------------------------------------------------------------------
        --// Leave On Danger Group
        ------------------------------------------------------------------------

        local function ShouldLeaveFor(OtherPlayer)
            return Feature.DangerGroupHop.Enabled
                and OtherPlayer.Parent == Players
                and ServerHop:IsDangerPlayer(OtherPlayer)
                and not IsWhitelisted(OtherPlayer)
        end

        --// Any server will do, so this lets Roblox pick one: it does not
        --// depend on the server list being readable.
        local function LeaveFor(OtherPlayer)
            if S.DangerHopStarted
                or S.DangerHopAttempts >= DANGER_HOP_MAX_ATTEMPTS
                or not ShouldLeaveFor(OtherPlayer)
            then
                return
            end

            S.DangerHopStarted = true
            S.DangerHopAttempts += 1
            S.Teleporting = true
            SetStatus("LEAVING (DANGER GROUP)")

            if S.DangerHopAttempts == 1 then
                NotifyAction("DANGER", string.format("@%s is in group %d. Leaving this server.", OtherPlayer.Name, DANGER_GROUP_ID), 7)
            end

            task.spawn(function()
                local Success, Error = pcall(function()
                    TeleportService:Teleport(game.PlaceId, Player)
                end)

                if Success then
                    return
                end

                warn("[ServerHop] Danger group hop failed:", Error)
                S.DangerHopStarted = false
                S.Teleporting = false

                if S.DangerHopAttempts < DANGER_HOP_MAX_ATTEMPTS then
                    task.delay(DANGER_HOP_RETRY_DELAY, LeaveFor, OtherPlayer)
                else
                    SetStatus("TELEPORT FAILED")
                    NotifyAction("DANGER", "Teleport failed after " .. DANGER_HOP_MAX_ATTEMPTS .. " attempts", 7)
                end
            end)
        end

        --// IsInGroupAsync where the client has it, IsInGroup otherwise. Errors
        --// from the second reach the caller's pcall.
        local function IsInDangerGroup(OtherPlayer)
            local Success, IsMember = pcall(function()
                return OtherPlayer:IsInGroupAsync(DANGER_GROUP_ID)
            end)

            if Success then
                return IsMember
            end

            return OtherPlayer:IsInGroup(DANGER_GROUP_ID)
        end

        --// Group membership is asked once per player; the answer is kept for
        --// as long as they are in the server.
        local function CheckDangerGroup(OtherPlayer)
            if OtherPlayer == Player or OtherPlayer.Parent ~= Players then
                return
            end

            local UserId = tostring(OtherPlayer.UserId)

            if S.DangerUsers[UserId] then
                LeaveFor(OtherPlayer)
                return
            end

            if S.CheckedUsers[UserId] or S.CheckInFlight[UserId] then
                return
            end

            S.CheckInFlight[UserId] = true

            task.spawn(function()
                local Success, IsMember = pcall(IsInDangerGroup, OtherPlayer)

                if not Success then
                    S.CheckFailures[UserId] = (S.CheckFailures[UserId] or 0) + 1
                    warn("[ServerHop] Group check failed for @" .. OtherPlayer.Name .. ":", IsMember)

                    --// Not marked checked: a scan after the retry delay asks
                    --// again, until the last attempt has failed.
                    if S.CheckFailures[UserId] >= GROUP_CHECK_MAX_ATTEMPTS then
                        S.CheckedUsers[UserId] = true
                        NotifyAction("GROUP CHECK", "Could not check @" .. OtherPlayer.Name .. " after " .. GROUP_CHECK_MAX_ATTEMPTS .. " tries", 7)
                    else
                        task.wait(GROUP_CHECK_RETRY_DELAY)
                    end

                    S.CheckInFlight[UserId] = nil
                    return
                end

                S.CheckInFlight[UserId] = nil
                S.CheckFailures[UserId] = nil
                S.CheckedUsers[UserId] = true

                if IsMember and OtherPlayer.Parent == Players then
                    S.DangerUsers[UserId] = true
                    S.LogVersion += 1
                    LeaveFor(OtherPlayer)
                end
            end)
        end

        ------------------------------------------------------------------------
        --// Join Alerts
        ------------------------------------------------------------------------

        local function AlertIfStranger(OtherPlayer, WasAlreadyHere)
            if OtherPlayer == Player or not Feature.JoinAlerts.Enabled or IsWhitelisted(OtherPlayer) then
                return
            end

            local UserId = tostring(OtherPlayer.UserId)

            if S.AlertSeen[UserId] then
                return
            end

            S.AlertSeen[UserId] = true
            NotifyAction(
                WasAlreadyHere and "PLAYER ALREADY HERE" or "PLAYER JOINED",
                "@" .. OtherPlayer.Name .. (WasAlreadyHere and " is already in this server" or " joined the server"),
                6
            )
        end

        --// Called when Join Alerts is switched on: everyone already here.
        function ServerHop:ScanJoinAlerts()
            for _, OtherPlayer in ipairs(Players:GetPlayers()) do
                AlertIfStranger(OtherPlayer, true)
            end
        end

        ------------------------------------------------------------------------

        local function OnPlayerAdded(OtherPlayer, WasAlreadyHere)
            if OtherPlayer == Player then
                return
            end

            local UserId = tostring(OtherPlayer.UserId)

            if not S.Online[UserId] then
                S.Online[UserId] = true
                RecordLog(OtherPlayer, WasAlreadyHere and "present" or "joined")
            end

            task.defer(AlertIfStranger, OtherPlayer, WasAlreadyHere)

            --// Before the first Update the profile, and with it the
            --// whitelist, is not loaded yet; that scan covers everyone.
            if S.Ready then
                CheckDangerGroup(OtherPlayer)
            end
        end

        Players.PlayerAdded:Connect(function(OtherPlayer)
            OnPlayerAdded(OtherPlayer, false)
        end)

        Players.PlayerRemoving:Connect(function(OtherPlayer)
            local UserId = tostring(OtherPlayer.UserId)

            if S.Online[UserId] then
                RecordLog(OtherPlayer, "left")
            end

            S.Online[UserId] = nil
            S.AlertSeen[UserId] = nil
            S.CheckedUsers[UserId] = nil
            S.CheckFailures[UserId] = nil
        end)

        for _, OtherPlayer in ipairs(Players:GetPlayers()) do
            OnPlayerAdded(OtherPlayer, true)
        end

        TeleportService.TeleportInitFailed:Connect(function(Who, _, ErrorMessage)
            if Who ~= Player then
                return
            end

            S.Teleporting = false
            SetStatus("TELEPORT FAILED")
            NotifyAction("SERVER", tostring(ErrorMessage or "Teleport failed"), 6)

            --// A failed danger hop tries again on the next scan.
            S.DangerHopStarted = false
        end)

        function ServerHop:Update()
            local now = os.clock()

            if now - S.LastScan < SCAN_INTERVAL then
                return
            end

            S.LastScan = now

            --// A profile that loaded with Join Alerts on: everyone already here.
            if not S.Ready and Feature.JoinAlerts.Enabled then
                ServerHop:ScanJoinAlerts()
            end

            S.Ready = true

            for _, OtherPlayer in ipairs(Players:GetPlayers()) do
                CheckDangerGroup(OtherPlayer)
            end
        end

        return ServerHop
    end,
}
