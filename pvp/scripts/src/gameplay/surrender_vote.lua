-- Server-authoritative, team-only surrender voting. The surface shard owns
-- the vote; cave shards validate their local caller and forward the request.
local team_state = require("src/team/lobby_team_state")
local protocol = require("src/gameplay/surrender_protocol")
local debug_log = require("src/core/debug")

local TEAM_RED = team_state.TEAM_RED
local TEAM_BLUE = team_state.TEAM_BLUE
local TEAM_NAMES = {
    [TEAM_RED] = "红队",
    [TEAM_BLUE] = "蓝队",
}
local TEAM_COLOURS = {
    [TEAM_RED] = { 1, 0, 0, 1 },
    [TEAM_BLUE] = { 25 / 255, 88 / 255, 1, 1 },
}
local ALL_VOTED_DELAY = 2

local active_vote = nil
local serial = 0

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

local function GetVoteTime()
    if GetStaticTime ~= nil then
        return GetStaticTime()
    end
    return GetTimeRealSeconds()
end

local function Announce(message, colour)
    if TheNet ~= nil and TheNet.Announce ~= nil then
        TheNet:Announce(message, colour)
    end
end

local function GetMatchAPI()
    return GLOBAL.BIRD_PVP_MATCH_END
end

local function IsNativeVoteActive()
    local network = TheWorld ~= nil and TheWorld.net or nil
    local worldvoter = network ~= nil
        and network.components ~= nil
        and network.components.worldvoter
        or nil
    return worldvoter ~= nil
        and worldvoter.IsVoteActive ~= nil
        and worldvoter:IsVoteActive()
end

local function InstallNetworkVars(network)
    if network == nil or network._bird_surrender_active ~= nil then
        return
    end

    network._bird_surrender_active = net_bool(
        network.GUID,
        protocol.NET_ACTIVE,
        protocol.NET_DIRTY_EVENT
    )
    network._bird_surrender_team = net_tinybyte(
        network.GUID,
        protocol.NET_TEAM,
        protocol.NET_DIRTY_EVENT
    )
    network._bird_surrender_remaining = net_byte(
        network.GUID,
        protocol.NET_REMAINING,
        protocol.NET_DIRTY_EVENT
    )
    network._bird_surrender_yes_units = net_byte(
        network.GUID,
        protocol.NET_YES_UNITS,
        protocol.NET_DIRTY_EVENT
    )
    network._bird_surrender_no_units = net_byte(
        network.GUID,
        protocol.NET_NO_UNITS,
        protocol.NET_DIRTY_EVENT
    )
    network._bird_surrender_starter = net_string(
        network.GUID,
        protocol.NET_STARTER,
        protocol.NET_DIRTY_EVENT
    )
    network._bird_surrender_serial = net_byte(
        network.GUID,
        protocol.NET_SERIAL,
        protocol.NET_DIRTY_EVENT
    )
end

local function ApplyNetworkState(is_active, team_id, remaining, yes_units, no_units, starter, vote_serial)
    local network = TheWorld ~= nil and TheWorld.net or nil
    if network == nil or not TheWorld.ismastersim then
        return
    end

    InstallNetworkVars(network)
    network._bird_surrender_team:set(tonumber(team_id) or 0)
    network._bird_surrender_remaining:set(math.max(0, math.min(255, tonumber(remaining) or 0)))
    network._bird_surrender_yes_units:set(math.max(0, math.min(255, tonumber(yes_units) or 0)))
    network._bird_surrender_no_units:set(math.max(0, math.min(255, tonumber(no_units) or 0)))
    network._bird_surrender_starter:set(tostring(starter or ""))
    network._bird_surrender_serial:set(math.max(0, math.min(255, tonumber(vote_serial) or 0)))
    network._bird_surrender_active:set(is_active == true)
    network:PushEvent(protocol.NET_DIRTY_EVENT)
end

local function GetRemaining()
    if active_vote == nil then
        return 0
    end
    return math.max(0, math.ceil(active_vote.deadline - GetVoteTime()))
end

local function Recount()
    local yes_units = 0
    local no_units = 0
    if active_vote ~= nil then
        for _, ballot in pairs(active_vote.ballots) do
            if ballot.selection == protocol.VOTE_YES then
                yes_units = yes_units + ballot.units
            elseif ballot.selection == protocol.VOTE_NO then
                no_units = no_units + ballot.units
            end
        end
    end
    return yes_units, no_units
end

local function AllEligibleVoted()
    if active_vote == nil then
        return false
    end
    for userid in pairs(active_vote.eligible) do
        if active_vote.ballots[userid] == nil then
            return false
        end
    end
    return true
end

local function BroadcastState()
    local is_active = active_vote ~= nil
    local team_id = is_active and active_vote.team_id or 0
    local remaining = is_active and GetRemaining() or 0
    local yes_units, no_units = Recount()
    local starter = is_active and active_vote.starter_name or ""
    local vote_serial = is_active and active_vote.serial or serial

    ApplyNetworkState(is_active, team_id, remaining, yes_units, no_units, starter, vote_serial)

    if SendModRPCToShard ~= nil and GetShardModRPC ~= nil then
        local rpc = GetShardModRPC(protocol.RPC_NAMESPACE, protocol.SHARD_RPC_SYNC)
        if rpc ~= nil then
            SendModRPCToShard(
                rpc,
                nil,
                is_active,
                team_id,
                remaining,
                yes_units,
                no_units,
                starter,
                vote_serial
            )
        end
    end
end

local function CancelVote()
    if active_vote == nil then
        return
    end
    if active_vote.tick_task ~= nil then
        active_vote.tick_task:Cancel()
    end
    if active_vote.finish_task ~= nil then
        active_vote.finish_task:Cancel()
    end
    active_vote = nil
    BroadcastState()
end

local function ResolveVote()
    local vote = active_vote
    if vote == nil then
        return
    end

    local yes_units, no_units = Recount()
    local passed = protocol.has_passed(yes_units, no_units)
    local team_id = vote.team_id
    local team_name = TEAM_NAMES[team_id] or "队伍"

    if vote.tick_task ~= nil then
        vote.tick_task:Cancel()
    end
    if vote.finish_task ~= nil then
        vote.finish_task:Cancel()
    end
    active_vote = nil
    BroadcastState()

    debug_log.log(
        "surrender",
        passed and "passed" or "failed",
        team_name,
        "yes_units",
        tostring(yes_units),
        "no_units",
        tostring(no_units)
    )

    if passed then
        local api = GetMatchAPI()
        if api == nil or api.finish_surrender == nil or not api.finish_surrender(team_id) then
            Announce(team_name .. "投降投票已通过，但当前比赛无法结算。")
        end
    else
        Announce(
            string.format(
                "%s投降投票未通过（赞成 %s 票，反对 %s 票）。",
                team_name,
                protocol.format_units(yes_units),
                protocol.format_units(no_units)
            ),
            TEAM_COLOURS[team_id]
        )
    end
end

local function TickVote()
    if active_vote == nil then
        return
    end

    active_vote.tick_task = nil
    if GetRemaining() <= 0 then
        ResolveVote()
        return
    end

    BroadcastState()
    active_vote.tick_task = Schedule(1, TickVote)
end

local function StartVote(userid, starter_name)
    if not IsAuthorityShard()
        or active_vote ~= nil
        or IsNativeVoteActive()
        or userid == nil
        or userid == "" then
        return false
    end

    local api = GetMatchAPI()
    if api == nil or api.is_active == nil or not api.is_active() then
        return false
    end

    local team_id = api.get_player_team ~= nil and api.get_player_team(userid) or nil
    if not team_state.is_playing_team(team_id) then
        return false
    end

    local weighted_voters = api.get_surrender_voters ~= nil and api.get_surrender_voters(team_id) or nil
    if weighted_voters == nil or weighted_voters[userid] == nil then
        return false
    end

    local eligible = {}
    for voter_userid in pairs(weighted_voters) do
        eligible[voter_userid] = true
    end

    serial = serial % 255 + 1
    active_vote = {
        serial = serial,
        team_id = team_id,
        starter = userid,
        starter_name = tostring(starter_name or userid),
        deadline = GetVoteTime() + protocol.VOTE_DURATION,
        eligible = eligible,
        ballots = {},
        tick_task = nil,
        finish_task = nil,
    }

    Announce(
        string.format(
            "%s发起投降投票，请在 %d 秒内投票（存活 1 票，死亡 0.5 票；赞成票须严格大于反对票的两倍）。",
            TEAM_NAMES[team_id],
            protocol.VOTE_DURATION
        ),
        TEAM_COLOURS[team_id]
    )
    debug_log.log("surrender", "started", TEAM_NAMES[team_id], tostring(userid))
    BroadcastState()
    active_vote.tick_task = Schedule(1, TickVote)
    active_vote.finish_task = Schedule(protocol.VOTE_DURATION, function()
        if active_vote ~= nil then
            active_vote.finish_task = nil
        end
        ResolveVote()
    end)
    return true
end

local function SubmitVote(userid, selection)
    selection = tonumber(selection)
    if not IsAuthorityShard()
        or active_vote == nil
        or userid == nil
        or active_vote.ballots[userid] ~= nil
        or (selection ~= protocol.VOTE_YES and selection ~= protocol.VOTE_NO) then
        return false
    end

    local api = GetMatchAPI()
    local current_team = api ~= nil and api.get_player_team ~= nil and api.get_player_team(userid) or nil
    local weighted_voters = api ~= nil
        and api.get_surrender_voters ~= nil
        and api.get_surrender_voters(active_vote.team_id)
        or nil
    local units = weighted_voters ~= nil and weighted_voters[userid] or nil
    if current_team ~= active_vote.team_id or (units ~= 1 and units ~= 2) then
        return false
    end

    active_vote.eligible[userid] = true
    active_vote.ballots[userid] = {
        selection = selection,
        units = units,
    }
    debug_log.log(
        "surrender",
        "vote",
        tostring(userid),
        selection == protocol.VOTE_YES and "yes" or "no",
        units == 2 and "1" or "0.5"
    )
    BroadcastState()

    if AllEligibleVoted() and active_vote.finish_task ~= nil then
        active_vote.finish_task:Cancel()
        local remaining = math.max(0, active_vote.deadline - GetVoteTime())
        active_vote.finish_task = Schedule(math.min(ALL_VOTED_DELAY, remaining), function()
            if active_vote ~= nil then
                active_vote.finish_task = nil
            end
            ResolveVote()
        end)
    end
    return true
end

local function GetLocalPlayingTeam(player)
    local team_id, pending = team_state.get_player_team(player, nil)
    if pending or not team_state.is_playing_team(team_id) then
        return nil
    end
    return team_id
end

local function ForwardToAuthority(rpc_name, userid, value)
    if SendModRPCToShard == nil or GetShardModRPC == nil then
        return false
    end
    local rpc = GetShardModRPC(protocol.RPC_NAMESPACE, rpc_name)
    if rpc == nil then
        return false
    end
    SendModRPCToShard(rpc, nil, userid, value)
    return true
end

AddModRPCHandler(protocol.RPC_NAMESPACE, protocol.MOD_RPC_START, function(player)
    if player == nil or GetLocalPlayingTeam(player) == nil then
        return
    end
    if IsAuthorityShard() then
        StartVote(player.userid, player.name)
    else
        ForwardToAuthority(protocol.SHARD_RPC_START, player.userid, player.name)
    end
end)

AddModRPCHandler(protocol.RPC_NAMESPACE, protocol.MOD_RPC_VOTE, function(player, selection)
    if player == nil or GetLocalPlayingTeam(player) == nil then
        return
    end
    if IsAuthorityShard() then
        SubmitVote(player.userid, selection)
    else
        ForwardToAuthority(protocol.SHARD_RPC_VOTE, player.userid, selection)
    end
end)

AddShardModRPCHandler(protocol.RPC_NAMESPACE, protocol.SHARD_RPC_START, function(_, userid, starter_name)
    if IsAuthorityShard() then
        StartVote(userid, starter_name)
    end
end)

AddShardModRPCHandler(protocol.RPC_NAMESPACE, protocol.SHARD_RPC_VOTE, function(_, userid, selection)
    if IsAuthorityShard() then
        SubmitVote(userid, selection)
    end
end)

AddShardModRPCHandler(
    protocol.RPC_NAMESPACE,
    protocol.SHARD_RPC_SYNC,
    function(_, is_active, team_id, remaining, yes_units, no_units, starter, vote_serial)
        if not IsAuthorityShard() then
            ApplyNetworkState(
                is_active,
                team_id,
                remaining,
                yes_units,
                no_units,
                starter,
                vote_serial
            )
        end
    end
)

local function OnNetworkPostInit(network)
    InstallNetworkVars(network)
    if TheWorld ~= nil and TheWorld.ismastersim then
        ApplyNetworkState(false, 0, 0, 0, 0, "", serial)
    end
end

AddPrefabPostInit("forest_network", OnNetworkPostInit)
AddPrefabPostInit("cave_network", OnNetworkPostInit)

AddPrefabPostInit("world", function(world)
    if world.ismastersim and IsAuthorityShard() then
        world:ListenForEvent("bird_pvp_match_ended", function()
            CancelVote()
        end)
    end
end)
