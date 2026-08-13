-- Give the smaller opening team walking sticks at dusk on day one.
local debug_log = require("src/core/debug")
local team_state = require("src/team/lobby_team_state")

if GetModConfigData("AUTO_WALKING_STICK") ~= true then
    return
end

local TEAM_RED = team_state.TEAM_RED
local TEAM_BLUE = team_state.TEAM_BLUE
local TEAM_REGISTRY_DIRTY_EVENT = "bird_lobby_teams_dirty"

local function is_game_started(world)
    local net = world ~= nil and world.net or nil
    local lobby = net ~= nil
        and net.components ~= nil
        and net.components.worldcharacterselectlobby
        or nil
    return lobby ~= nil
        and lobby.HasGameStarted ~= nil
        and lobby:HasGameStarted()
end

local function is_dedicated_host_record(client)
    return TheNet ~= nil
        and not TheNet:GetServerIsClientHosted()
        and client ~= nil
        and client.performance ~= nil
end

local function capture_opening_counts(world)
    if world._bird_stick_opening_counts ~= nil or not is_game_started(world) then
        return
    end

    local net = world.net
    if net == nil or net._bird_lobby_teams_ready ~= true then
        return
    end

    local counts = { [TEAM_RED] = 0, [TEAM_BLUE] = 0 }
    local authority_teams = net._bird_lobby_teams or {}
    for _, client in ipairs(TheNet:GetClientTable() or {}) do
        if client ~= nil
            and client.userid ~= nil
            and client.userid ~= ""
            and not is_dedicated_host_record(client) then
            local team_id = team_state.normalize(authority_teams[client.userid])
            if counts[team_id] ~= nil then
                counts[team_id] = counts[team_id] + 1
            end
        end
    end

    world._bird_stick_opening_counts = counts
    debug_log.log(
        "auto-stick",
        "opening snapshot",
        "red",
        tostring(counts[TEAM_RED]),
        "blue",
        tostring(counts[TEAM_BLUE])
    )
end

local function give_to_smaller_team(world)
    if world._bird_stick_granted or world.state.cycles ~= 0 then
        return
    end
    world._bird_stick_granted = true

    local counts = world._bird_stick_opening_counts
    if counts == nil then
        debug_log.log("auto-stick", "skipped", "opening snapshot unavailable")
        return
    end

    local red = counts[TEAM_RED]
    local blue = counts[TEAM_BLUE]
    local smaller_team = red > 0 and blue > 0 and red ~= blue
        and (red < blue and TEAM_RED or TEAM_BLUE)
        or nil
    if smaller_team == nil then
        debug_log.log("auto-stick", "skipped", "red", tostring(red), "blue", tostring(blue))
        return
    end

    local actions = require("src/observer/actions")
    local count = actions.give_team_walking_sticks(smaller_team)
    debug_log.log("auto-stick", "granted", "team", tostring(smaller_team), "players", tostring(count))
end

AddPrefabPostInit("world", function(world)
    if not world.ismastersim or world:HasTag("cave") then
        return
    end

    local function try_capture()
        if world._bird_stick_opening_counts ~= nil then
            return
        end
        world:DoTaskInTime(0, function()
            if world:IsValid() then
                capture_opening_counts(world)
            end
        end)
    end

    world:ListenForEvent("ms_clientauthenticationcomplete", try_capture)
    world:ListenForEvent("ms_playerspawn", try_capture)
    world:ListenForEvent("playeractivated", try_capture)
    world:ListenForEvent(TEAM_REGISTRY_DIRTY_EVENT, try_capture)
    world:WatchWorldState("phase", function(_, phase)
        if phase == "dusk" then
            give_to_smaller_team(world)
        end
    end)
    try_capture()
end)

AddPrefabPostInit("forest_network", function(network)
    if TheNet == nil or not TheNet:GetIsServer() then
        return
    end
    network:ListenForEvent("spawncharacterdelaydirty", function()
        local world = TheWorld
        if world ~= nil and world.ismastersim then
            world:DoTaskInTime(0, function()
                capture_opening_counts(world)
            end)
        end
    end)
end)
