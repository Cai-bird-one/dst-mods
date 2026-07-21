-- Event-driven match settlement. The surface shard owns the result; caves only
-- report player state and play the victory effect sent by the surface.
local team_state = require("src/team/lobby_team_state")
local debug_log = require("src/core/debug")
local admin_privileges = require("src/admin/privileges")

local TEAM_RED = team_state.TEAM_RED
local TEAM_BLUE = team_state.TEAM_BLUE
local TEAM_COLOURS = {
    [TEAM_RED] = { 1, 0, 0, 1 },
    [TEAM_BLUE] = { 25 / 255, 88 / 255, 1, 1 },
}
local TEAM_NAMES = {
    [TEAM_RED] = "红队",
    [TEAM_BLUE] = "蓝队",
}
local PARTICIPANT_MODES = {
    alive = true,
    dead = true,
    migrating = true,
    disconnected = true,
    offline = true,
}

local ELIMINATION_COUNTDOWN_SECONDS = 10
local REGENERATE_DELAY_SECONDS = 10
local DISCONNECT_GRACE_SECONDS = 4 * 60
local SHARD_RPC_NAMESPACE = "bird_pvp_match"
local SHARD_RPC_PLAYER_STATE = "player_state"
local SHARD_RPC_VICTORY = "victory"
local SHARD_RPC_REFRESH_STATE = "refresh_state"
local SHARD_RPC_SET_ENABLED = "set_enabled"
local MOD_RPC_SET_ENABLED = "set_enabled"
local USER_COMMAND_NAME = "matchend"
local TEAM_REGISTRY_DIRTY_EVENT = "bird_lobby_teams_dirty"

local match = {
    enabled = true,
    started = false,
    ended = false,
    roster = {
        [TEAM_RED] = {},
        [TEAM_BLUE] = {},
    },
    players = {},
    countdown = nil,
    reset_task = nil,
    reset_remaining = 0,
}

local local_players = {}
local local_disconnect_tokens = {}
local local_victory_played = false
local EnsureMatchStarted
local EvaluateMatch
local FinishMatch
local RequestShardStates
local SetMatchEndEnabled

local function IsCaveShard()
    if TheWorld == nil then
        return false
    end
    return (TheWorld.HasTag ~= nil and TheWorld:HasTag("cave"))
        or TheWorld.worldprefab == "cave"
        or TheWorld.prefab == "cave"
end

local function IsAuthorityShard()
    return not IsCaveShard()
end

local function Schedule(delay, fn)
    if TheWorld == nil then
        return nil
    end
    if TheWorld.DoStaticTaskInTime ~= nil then
        return TheWorld:DoStaticTaskInTime(delay, fn)
    end
    return TheWorld:DoTaskInTime(delay, fn)
end

local function Announce(message, colour)
    if TheNet ~= nil and TheNet.Announce ~= nil then
        TheNet:Announce(message, colour)
    end
end

local function IsGameStarted()
    local net = TheWorld ~= nil and TheWorld.net or nil
    local lobby = net ~= nil
        and net.components ~= nil
        and net.components.worldcharacterselectlobby
        or nil
    return lobby ~= nil
        and lobby.HasGameStarted ~= nil
        and lobby:HasGameStarted()
end

local function IsValidUserid(userid)
    return userid ~= nil and userid ~= ""
end

local function IsDedicatedHostRecord(client)
    return TheNet ~= nil
        and not TheNet:GetServerIsClientHosted()
        and client ~= nil
        and client.performance ~= nil
end

local function IsPlayableClientRecord(client)
    return client ~= nil
        and IsValidUserid(client.userid)
        and not IsDedicatedHostRecord(client)
end

local function IsPlayerAlive(player)
    if player == nil or not player:IsValid() or player:HasTag("playerghost") then
        return false
    end
    local health = player.components ~= nil and player.components.health or nil
    return health ~= nil and not health:IsDead()
end

local function GetRosterTeam(userid)
    if match.roster[TEAM_RED][userid] then
        return TEAM_RED
    end
    if match.roster[TEAM_BLUE][userid] then
        return TEAM_BLUE
    end
    return nil
end

local function AddParticipant(userid, team_id)
    team_id = team_state.normalize(team_id)
    if not IsValidUserid(userid) or not team_state.is_playing_team(team_id) then
        return nil
    end

    local existing_team = GetRosterTeam(userid)
    if existing_team ~= nil then
        -- The round roster is authoritative after start. A stale shard mirror
        -- must not move a participant to the other team during migration.
        return existing_team
    end

    match.roster[team_id][userid] = true
    debug_log.log("match", "participant", tostring(userid), TEAM_NAMES[team_id])
    return team_id
end

local function CountTeam(team_id)
    local total = 0
    local alive = 0
    for userid in pairs(match.roster[team_id]) do
        total = total + 1
        local state = match.players[userid]
        if state ~= nil and state.team_id == team_id and state.alive then
            alive = alive + 1
        end
    end
    return total, alive
end

local function GetOutcomeCandidate()
    if not match.enabled or not match.started or match.ended then
        return nil, nil
    end

    local red_total, red_alive = CountTeam(TEAM_RED)
    local blue_total, blue_alive = CountTeam(TEAM_BLUE)

    -- Both teams must have actually entered this round. This prevents an empty
    -- team from ending the match as soon as the first player spawns.
    if red_total == 0 or blue_total == 0 then
        return nil, nil
    end

    if red_alive == 0 and blue_alive > 0 then
        return TEAM_BLUE, TEAM_RED
    end
    if blue_alive == 0 and red_alive > 0 then
        return TEAM_RED, TEAM_BLUE
    end
    return nil, nil
end

local function CancelEliminationCountdown(announce_cancelled)
    local countdown = match.countdown
    if countdown == nil then
        return
    end

    if countdown.task ~= nil then
        countdown.task:Cancel()
    end
    match.countdown = nil

    if announce_cancelled then
        Announce("全灭判定已取消，比赛继续。")
    end
end

local function PlayVictoryLocally(winner_team)
    if local_victory_played
        or TheWorld == nil
        or not TheWorld.ismastersim
        or not team_state.is_playing_team(winner_team) then
        return
    end
    local_victory_played = true

    for _, player in ipairs(AllPlayers or {}) do
        local player_team, pending = team_state.get_player_team(player, nil)
        if not pending and player_team == winner_team and IsPlayerAlive(player) then
            player:PushEvent("emote", {
                anim = "emoteXL_happycheer",
                sitting = true,
                mounted = true,
                mountsound = "yell",
            })

            local ok, fx = pcall(SpawnPrefab, "confetti_fx")
            if ok and fx ~= nil then
                fx.Transform:SetPosition(player.Transform:GetWorldPosition())
            end
        end
    end
end

local function BroadcastVictory(winner_team)
    PlayVictoryLocally(winner_team)

    if SendModRPCToShard == nil or GetShardModRPC == nil then
        return
    end
    local rpc = GetShardModRPC(SHARD_RPC_NAMESPACE, SHARD_RPC_VICTORY)
    if rpc ~= nil then
        SendModRPCToShard(rpc, nil, winner_team)
    end
end

local function RegenerateWorld()
    if not IsAuthorityShard() or TheNet == nil then
        return
    end

    Announce("正在重新生成世界...")
    local ok, err = pcall(function()
        TheNet:SendWorldResetRequestToServer()
    end)
    if not ok then
        debug_log.error("match", "world regeneration failed", tostring(err))
    end
end

local function StartRegenerateCountdown()
    match.reset_remaining = REGENERATE_DELAY_SECONDS
    Announce(string.format("本局已结算，%d 秒后重新生成世界。", match.reset_remaining))

    local function Tick()
        if TheWorld == nil or not TheWorld.ismastersim then
            match.reset_task = nil
            return
        end

        match.reset_remaining = match.reset_remaining - 1
        if match.reset_remaining <= 0 then
            match.reset_task = nil
            RegenerateWorld()
            return
        end

        if match.reset_remaining <= 5 then
            Announce(string.format("%d 秒后重新生成世界。", match.reset_remaining))
        end
        match.reset_task = Schedule(1, Tick)
    end

    match.reset_task = Schedule(1, Tick)
end

FinishMatch = function(winner_team, loser_team, reason)
    if match.ended or not team_state.is_playing_team(winner_team) then
        return
    end

    match.ended = true
    CancelEliminationCountdown(false)

    local result_message = reason == "surrender"
        and string.format("本局结束！%s投降，%s获胜！", TEAM_NAMES[loser_team], TEAM_NAMES[winner_team])
        or string.format("本局结束！%s全员死亡或掉线，%s获胜！", TEAM_NAMES[loser_team], TEAM_NAMES[winner_team])
    Announce(result_message, TEAM_COLOURS[winner_team])
    debug_log.log("match", "ended", TEAM_NAMES[winner_team], "winner", reason or "elimination")

    if TheWorld ~= nil and TheWorld.PushEvent ~= nil then
        TheWorld:PushEvent("bird_pvp_match_ended", {
            winner_team = winner_team,
            loser_team = loser_team,
            reason = reason or "elimination",
        })
    end

    BroadcastVictory(winner_team)
    StartRegenerateCountdown()
end

local function StartEliminationCountdown(winner_team, loser_team)
    if match.countdown ~= nil or match.ended then
        return
    end

    local countdown = {
        winner_team = winner_team,
        loser_team = loser_team,
        remaining = ELIMINATION_COUNTDOWN_SECONDS,
        task = nil,
    }
    match.countdown = countdown

    local function Tick()
        if match.countdown ~= countdown or match.ended then
            return
        end

        local current_winner, current_loser = GetOutcomeCandidate()
        if current_winner ~= winner_team or current_loser ~= loser_team then
            CancelEliminationCountdown(true)
            EvaluateMatch()
            return
        end

        if countdown.remaining <= 0 then
            FinishMatch(winner_team, loser_team)
            return
        end

        Announce(
            string.format(
                "%s已全员死亡或掉线，%s将在 %d 秒后获胜。",
                TEAM_NAMES[loser_team],
                TEAM_NAMES[winner_team],
                countdown.remaining
            ),
            TEAM_COLOURS[winner_team]
        )
        countdown.remaining = countdown.remaining - 1
        countdown.task = Schedule(1, Tick)
    end

    debug_log.log("match", "countdown", TEAM_NAMES[loser_team], "eliminated")
    Tick()
end

EvaluateMatch = function()
    if not IsAuthorityShard() or not match.enabled or not match.started or match.ended then
        return
    end

    local winner_team, loser_team = GetOutcomeCandidate()
    if winner_team == nil then
        CancelEliminationCountdown(match.countdown ~= nil)
        return
    end

    if match.countdown ~= nil then
        if match.countdown.winner_team == winner_team
            and match.countdown.loser_team == loser_team then
            return
        end
        CancelEliminationCountdown(false)
    end

    StartEliminationCountdown(winner_team, loser_team)
end

local function SetParticipantState(userid, team_id, mode, source)
    if not IsAuthorityShard() or not match.enabled or not match.started or match.ended then
        return
    end

    team_id = AddParticipant(userid, team_id)
    if team_id == nil then
        return
    end

    source = tostring(source or "unknown")
    mode = tostring(mode or "disconnected")
    if not PARTICIPANT_MODES[mode] then
        mode = "disconnected"
    end
    local current = match.players[userid]

    -- Ignore a late terminal/disconnect report from the shard the player
    -- already left. Destination state is authoritative once it has arrived.
    if (mode == "dead" or mode == "disconnected" or mode == "migrating" or mode == "offline")
        and current ~= nil
        and current.source ~= source
        and current.source ~= "connected"
        and current.mode ~= "migrating" then
        debug_log.log("match", "stale state ignored", tostring(userid), mode, source, current.source)
        return
    end

    -- Once dead, disconnecting or moving between shards must not disturb an
    -- elimination countdown. Only an explicit alive report can revive them.
    if mode == "disconnected" and current ~= nil and not current.alive then
        return
    end

    if mode == "disconnected"
        and current ~= nil
        and current.mode == "disconnected"
        and current.source == source then
        return
    end

    local revision = current ~= nil and (current.revision or 0) + 1 or 1
    local alive = mode == "alive" or mode == "migrating"
    if mode == "disconnected" then
        alive = current == nil or current.alive == true
    end
    match.players[userid] = {
        team_id = team_id,
        mode = mode,
        alive = alive,
        source = source,
        revision = revision,
    }
    debug_log.log("match", "state", tostring(userid), TEAM_NAMES[team_id], mode, source)

    if mode == "migrating" or mode == "disconnected" then
        debug_log.log(
            "match",
            "disconnect grace",
            tostring(userid),
            mode,
            tostring(DISCONNECT_GRACE_SECONDS)
        )
        Schedule(DISCONNECT_GRACE_SECONDS, function()
            local state = match.players[userid]
            if state ~= nil
                and state.revision == revision
                and state.mode == mode
                and state.source == source then
                SetParticipantState(userid, team_id, "offline", source)
            end
        end)
    end

    EvaluateMatch()
end

local function GetLocalPlayerTeam(player)
    local team_id, pending = team_state.get_player_team(player, nil)
    if pending or not team_state.is_playing_team(team_id) then
        return nil
    end
    return team_id
end

local function SendPlayerState(userid, team_id, mode)
    if not IsValidUserid(userid) or not team_state.is_playing_team(team_id) then
        return
    end

    if IsAuthorityShard() then
        SetParticipantState(userid, team_id, mode, "surface")
        return
    end

    if SendModRPCToShard == nil or GetShardModRPC == nil then
        return
    end
    local rpc = GetShardModRPC(SHARD_RPC_NAMESPACE, SHARD_RPC_PLAYER_STATE)
    if rpc ~= nil then
        SendModRPCToShard(rpc, nil, userid, team_id, mode)
    end
end

local function ReportLocalPlayer(player, forced_mode)
    if player == nil or not player:IsValid() or not IsValidUserid(player.userid) then
        return
    end

    -- An entity on this shard means any earlier local disconnect candidate is
    -- stale, even if its team mirror has not finished becoming ready yet.
    local_disconnect_tokens[player.userid] = nil

    if IsAuthorityShard() then
        EnsureMatchStarted()
    end

    local team_id = GetLocalPlayerTeam(player)
    if team_id == nil then
        return
    end

    local mode = forced_mode or (IsPlayerAlive(player) and "alive" or "dead")
    local_players[player.userid] = {
        team_id = team_id,
        mode = mode,
    }
    SendPlayerState(player.userid, team_id, mode)
end

local function RefreshLocalPlayers()
    for _, player in ipairs(AllPlayers or {}) do
        ReportLocalPlayer(player)
    end
end

RequestShardStates = function()
    if not IsAuthorityShard() or SendModRPCToShard == nil or GetShardModRPC == nil then
        return
    end

    local rpc = GetShardModRPC(SHARD_RPC_NAMESPACE, SHARD_RPC_REFRESH_STATE)
    if rpc ~= nil then
        SendModRPCToShard(rpc, nil)
    end
end

EnsureMatchStarted = function()
    if not IsAuthorityShard()
        or not match.enabled
        or match.started
        or match.ended
        or not IsGameStarted() then
        return match.started
    end

    local net = TheWorld ~= nil and TheWorld.net or nil
    if net == nil or net._bird_lobby_teams_ready ~= true then
        debug_log.log("match", "start deferred", "team registry not ready")
        return false
    end

    local authority_teams = net._bird_lobby_teams or {}
    for _, client in ipairs(TheNet:GetClientTable() or {}) do
        if IsPlayableClientRecord(client) then
            local team_id = team_state.normalize(authority_teams[client.userid])
            if team_state.is_playing_team(team_id) then
                AddParticipant(client.userid, team_id)
                match.players[client.userid] = match.players[client.userid] or {
                    team_id = team_id,
                    mode = "alive",
                    alive = true,
                    source = "connected",
                    revision = 0,
                }
            end
        end
    end

    match.started = true
    local red_total = CountTeam(TEAM_RED)
    local blue_total = CountTeam(TEAM_BLUE)
    debug_log.log("match", "started", "red", tostring(red_total), "blue", tostring(blue_total))
    RefreshLocalPlayers()
    RequestShardStates()
    Schedule(1, EvaluateMatch)
    return true
end

local function OnPlayerStateFromShard(sender_shard, userid, team_id, mode)
    if not IsAuthorityShard() then
        return
    end
    EnsureMatchStarted()
    SetParticipantState(userid, team_id, mode, "shard:" .. tostring(sender_shard))
end

local function OnVictoryFromShard(_, winner_team)
    PlayVictoryLocally(team_state.normalize(winner_team))
end

local function OnRefreshStateFromShard()
    if not IsAuthorityShard() then
        RefreshLocalPlayers()
    end
end

AddShardModRPCHandler(SHARD_RPC_NAMESPACE, SHARD_RPC_PLAYER_STATE, OnPlayerStateFromShard)
AddShardModRPCHandler(SHARD_RPC_NAMESPACE, SHARD_RPC_VICTORY, OnVictoryFromShard)
AddShardModRPCHandler(SHARD_RPC_NAMESPACE, SHARD_RPC_REFRESH_STATE, OnRefreshStateFromShard)

local function ParseEnabled(value)
    if value == true or value == 1 then
        return true
    end
    if value == false or value == 0 then
        return false
    end

    value = string.lower(tostring(value or ""))
    if value == "on" or value == "true" or value == "1" or value == "开启" then
        return true
    end
    if value == "off" or value == "false" or value == "0" or value == "关闭" then
        return false
    end
    return nil
end

local function CancelRegenerateCountdown()
    if match.reset_task ~= nil then
        match.reset_task:Cancel()
        match.reset_task = nil
    end
    match.reset_remaining = 0
end

SetMatchEndEnabled = function(enabled)
    if not IsAuthorityShard() then
        return false
    end

    enabled = enabled == true
    if match.enabled == enabled then
        Announce("自动结算当前已" .. (enabled and "开启。" or "关闭。"))
        if enabled then
            if match.started then
                RefreshLocalPlayers()
                RequestShardStates()
                Schedule(1, EvaluateMatch)
            else
                EnsureMatchStarted()
            end
        end
        return true
    end

    match.enabled = enabled
    if not enabled then
        CancelEliminationCountdown(false)
        CancelRegenerateCountdown()
        match.ended = false
        local_victory_played = false
        Announce("管理员已关闭自动结算。")
        debug_log.log("match", "disabled")
        return true
    end

    Announce("管理员已开启自动结算。")
    debug_log.log("match", "enabled")
    if match.started then
        RefreshLocalPlayers()
        RequestShardStates()
        Schedule(1, EvaluateMatch)
    else
        EnsureMatchStarted()
    end
    return true
end

local function RequestMatchEndEnabled(enabled)
    if IsAuthorityShard() then
        return SetMatchEndEnabled(enabled)
    end

    if SendModRPCToShard == nil or GetShardModRPC == nil then
        return false
    end
    local rpc = GetShardModRPC(SHARD_RPC_NAMESPACE, SHARD_RPC_SET_ENABLED)
    if rpc == nil then
        return false
    end

    SendModRPCToShard(rpc, nil, enabled == true)
    return true
end

local function SetEnabledFromCommand(value, caller)
    if caller ~= nil and not admin_privileges.is_lobby_admin(caller) then
        return false
    end

    local enabled = ParseEnabled(value)
    if enabled == nil then
        return false
    end
    return RequestMatchEndEnabled(enabled)
end

AddShardModRPCHandler(SHARD_RPC_NAMESPACE, SHARD_RPC_SET_ENABLED, function(_, enabled)
    if IsAuthorityShard() then
        local parsed = ParseEnabled(enabled)
        if parsed ~= nil then
            SetMatchEndEnabled(parsed)
        end
    end
end)

AddModRPCHandler(SHARD_RPC_NAMESPACE, MOD_RPC_SET_ENABLED, function(player, enabled)
    if admin_privileges.is_player_admin(player) then
        local parsed = ParseEnabled(enabled)
        if parsed ~= nil then
            RequestMatchEndEnabled(parsed)
        end
    end
end)

AddUserCommand(USER_COMMAND_NAME, {
    prettyname = "自动结算",
    desc = "开启或关闭自动结算",
    permission = COMMAND_PERMISSION.ADMIN,
    slash = true,
    usermenu = false,
    servermenu = false,
    params = { "state" },
    vote = false,
    serverfn = function(params, caller)
        local value = type(params) == "table" and (params.state or params[1]) or params
        SetEnabledFromCommand(value, caller)
    end,
})

function GLOBAL.c_bird_match_end(enabled)
    local parsed = ParseEnabled(enabled)
    if parsed == nil then
        debug_log.info("match", "Usage: c_bird_match_end(true|false)")
        return false
    end

    if TheWorld ~= nil and TheWorld.ismastersim then
        return RequestMatchEndEnabled(parsed)
    end

    if not admin_privileges.is_local_server_admin()
        or SendModRPCToServer == nil
        or GetModRPC == nil then
        return false
    end

    SendModRPCToServer(GetModRPC(SHARD_RPC_NAMESPACE, MOD_RPC_SET_ENABLED), parsed)
    return true
end

local function OnLocalPlayerDisconnected(_, data)
    local userid = data ~= nil and data.userid or nil
    if not IsValidUserid(userid) then
        return
    end

    local token = {}
    local_disconnect_tokens[userid] = token

    local cached = local_players[userid]
    if cached ~= nil and cached.mode == "migrating" then
        local_disconnect_tokens[userid] = nil
        return
    end

    Schedule(0.5, function()
        if local_disconnect_tokens[userid] ~= token then
            return
        end

        local state = local_players[userid]
        if state ~= nil and state.mode == "migrating" then
            local_disconnect_tokens[userid] = nil
            return
        end
        if state ~= nil and state.mode == "dead" then
            local_disconnect_tokens[userid] = nil
            return
        end

        local team_id = state ~= nil and state.team_id or GetRosterTeam(userid)
        if team_state.is_playing_team(team_id) then
            local_players[userid] = {
                team_id = team_id,
                mode = "disconnected",
            }
            SendPlayerState(userid, team_id, "disconnected")
        end
        local_disconnect_tokens[userid] = nil
    end)
end

local function OnLocalPlayerMigrating(_, data)
    local player = data ~= nil and data.player or nil
    if player ~= nil then
        -- Living players remain alive during shard transit. Ghosts remain dead,
        -- so moving a ghost between surface and cave cannot cancel settlement.
        ReportLocalPlayer(player, IsPlayerAlive(player) and "migrating" or "dead")
    end
end

AddPlayerPostInit(function(player)
    if TheWorld == nil or not TheWorld.ismastersim then
        return
    end

    player:ListenForEvent("bird_team_state_ready", function(inst)
        ReportLocalPlayer(inst)
    end)
    player:ListenForEvent("death", function(inst)
        ReportLocalPlayer(inst, "dead")
    end)
    player:ListenForEvent("respawnfromghost", function(inst)
        ReportLocalPlayer(inst, "alive")
    end)

    Schedule(0, function()
        if player:IsValid() then
            ReportLocalPlayer(player)
        end
    end)
end)

AddPrefabPostInit("world", function(world)
    if not world.ismastersim then
        return
    end

    world:ListenForEvent("ms_clientdisconnected", OnLocalPlayerDisconnected)
    world:ListenForEvent("ms_playerdespawnandmigrate", OnLocalPlayerMigrating)
    world:ListenForEvent("ms_playerdied", function(_, data)
        local player = data ~= nil and data.player or nil
        Schedule(0, function()
            if player ~= nil and player:IsValid() then
                ReportLocalPlayer(player, "dead")
            end
        end)
    end)
    world:ListenForEvent("ms_respawnedfromghost", function(_, data)
        local player = data ~= nil and data.player or nil
        if player ~= nil then
            Schedule(0, function()
                if player:IsValid() then
                    ReportLocalPlayer(player, "alive")
                end
            end)
        end
    end)

    if IsAuthorityShard() then
        world:ListenForEvent("ms_clientauthenticationcomplete", function()
            Schedule(0, EnsureMatchStarted)
        end)
        world:ListenForEvent("ms_playerspawn", function()
            Schedule(0, EnsureMatchStarted)
        end)
        world:ListenForEvent("playeractivated", function()
            Schedule(0, EnsureMatchStarted)
        end)
        world:ListenForEvent(TEAM_REGISTRY_DIRTY_EVENT, function()
            Schedule(0, EnsureMatchStarted)
        end)
        Schedule(0, EnsureMatchStarted)
    end
end)

AddPrefabPostInit("forest_network", function(network)
    if TheNet == nil or not TheNet:GetIsServer() then
        return
    end
    network:ListenForEvent("spawncharacterdelaydirty", function()
        Schedule(0, EnsureMatchStarted)
    end)
end)

-- Surrender voting shares the round roster and settlement pipeline without
-- exposing the mutable match tables themselves.
GLOBAL.BIRD_PVP_MATCH_END = {
    is_active = function()
        return match.started and not match.ended
    end,
    get_player_team = function(userid)
        return GetRosterTeam(userid)
    end,
    get_surrender_voters = function(team_id)
        team_id = team_state.normalize(team_id)
        if not match.started or match.ended or not team_state.is_playing_team(team_id) then
            return nil
        end

        local voters = {}
        for userid in pairs(match.roster[team_id]) do
            local state = match.players[userid]
            if state ~= nil
                and state.team_id == team_id
                and state.mode ~= "offline" then
                -- Integer half-vote units avoid floating point comparisons:
                -- alive/migrating = 1 vote, dead = 0.5 vote.
                voters[userid] = state.alive and 2 or 1
            end
        end
        return voters
    end,
    finish_surrender = function(loser_team)
        loser_team = team_state.normalize(loser_team)
        if not match.started or match.ended or not team_state.is_playing_team(loser_team) then
            return false
        end

        local winner_team = loser_team == TEAM_RED and TEAM_BLUE or TEAM_RED
        FinishMatch(winner_team, loser_team, "surrender")
        return match.ended
    end,
}
