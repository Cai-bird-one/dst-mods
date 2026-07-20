-- Installs the team network variable and mirrors the already-selected world team on spawn.
-- This is a registration script and must be loaded with modimport.
local markers = require("src/team/markers")
local team_state = require("src/team/lobby_team_state")
local player_state = require("src/team/player_state")
local observer_camera = require("src/observer/camera_mode")
local debug_log = require("src/core/debug")

local TEAM_REGISTRY_DIRTY_EVENT = "bird_lobby_teams_dirty"
local APPLY_RETRY_DELAYS = { 0, 0.1, 0.5, 1, 2, 5, 10 }
local apply_authoritative_team_with_retries

local function IsValidUserId(userid)
    return userid ~= nil and userid ~= ""
end

local function IsCaveShard()
    if TheWorld == nil then
        return false
    end

    if TheWorld.HasTag ~= nil and TheWorld:HasTag("cave") then
        return true
    end

    return TheWorld.worldprefab == "cave"
        or TheWorld.prefab == "cave"
end

local function set_component_team(component, team_id)
    if component == nil then
        return false
    end

    if component.Choose ~= nil then
        return component:Choose(team_id)
    end

    component.duiwu = team_id
    return true
end

local function apply_ready_team(player, data)
    if player == nil or not player:IsValid() then
        return
    end

    local team_id = data ~= nil and team_state.normalize(data.team_id) or nil
    if team_id == nil then
        team_id = player_state.get(player)
    end
    if team_id == nil then
        return
    end
    local component = player.components ~= nil and player.components.player_duiwu_qe or nil
    if team_state.is_waiting_team(team_id) then
        debug_log.log("team-apply", "waiting broadcast", tostring(player.userid), tostring(player.prefab))
        if component ~= nil and component.ClearTeam ~= nil then
            component:ClearTeam()
        end
        observer_camera.disable(player)
        markers.refresh_teammate_icons()
        return
    end

    debug_log.log("team-apply", "ready broadcast", tostring(player.userid), tostring(player.prefab), "team", tostring(team_id))
    set_component_team(component, team_id)
    if component ~= nil and component.ApplyGroundFx ~= nil then
        component:ApplyGroundFx(team_id)
    end

    if team_state.is_playing_team(team_id) then
        observer_camera.disable(player)
    else
        observer_camera.enable(player)
    end

    markers.refresh_teammate_icons()
end

local function apply_pending_team(player)
    debug_log.log("team-apply", "pending broadcast", tostring(player ~= nil and player.userid or nil))
    markers.refresh_teammate_icons()
end

local function get_component_mirror_team(inst, component)
    local team_id = component._bird_has_loaded_team and team_state.normalize(component._bird_loaded_team) or nil
    if team_id == nil then
        debug_log.log("team-apply", "component fallback unavailable", tostring(inst.userid))
        return nil
    end

    debug_log.log("team-apply", "component mirror", tostring(inst.userid), tostring(team_id))
    return team_id
end

local function get_loaded_component_team(component)
    if component == nil or not component._bird_has_loaded_team then
        return nil
    end

    return team_state.normalize(component._bird_loaded_team)
end

local function get_missing_default_team()
    local net = TheWorld ~= nil and TheWorld.net or nil
    local lobby = net ~= nil and net.components ~= nil and net.components.worldcharacterselectlobby or nil
    if not IsCaveShard()
        and lobby ~= nil
        and lobby.HasGameStarted ~= nil
        and lobby:HasGameStarted() then
        return team_state.TEAM_OBSERVER, "default-observer"
    end

    return team_state.TEAM_WAITING, "default-waiting"
end

local function resolve_missing_ready_team(inst, source)
    local team_id, default_source = get_missing_default_team()
    local effective_source = source
    if default_source == "default-observer"
        and (effective_source == nil or string.find(effective_source, "default%-waiting", 1) ~= nil) then
        effective_source = default_source
    end
    effective_source = effective_source or default_source

    local fn = not IsCaveShard() and _G ~= nil and rawget(_G, "BirdSetAuthoritativeLobbyTeam") or nil
    if fn ~= nil then
        fn(inst.userid, team_id, effective_source)
    end

    debug_log.log("team-apply", default_source, tostring(inst.userid), tostring(effective_source))
    return team_id, effective_source
end

local function request_authoritative_team(inst)
    local fn = _G ~= nil and rawget(_G, "BirdRequestAuthoritativeLobbyTeam") or nil
    if fn == nil then
        return false
    end

    if player_state.is_requested(inst) then
        return true
    end

    player_state.mark_requested(inst, "request-authoritative")
    debug_log.log("team-apply", "request authority", tostring(inst.userid))
    local requested = fn(inst.userid, "player-team-state", function(team_id, source, success)
        if inst == nil or not inst:IsValid() then
            return
        end

        if team_id == nil and success == true then
            team_id, source = resolve_missing_ready_team(inst, "request-default-waiting")
        end

        if player_state.set_ready(inst, team_id, source) then
            debug_log.log("team-apply", "resolved authority", tostring(inst.userid), tostring(team_id), tostring(source))
        else
            player_state.set_failed(inst, source or "missing")
            debug_log.log("team-apply", "resolve failed", tostring(inst.userid), tostring(source))
        end
    end)

    if not requested then
        return false
    end

    local _, ready = player_state.get(inst)
    return not ready and player_state.is_requested(inst)
end

local function apply_authoritative_team(inst, attempt)
    if inst == nil or not inst:IsValid() then
        debug_log.log("team-apply", "skip invalid", tostring(attempt))
        return true
    end

    local component = inst.components ~= nil and inst.components.player_duiwu_qe or nil
    if component == nil then
        debug_log.log("team-apply", "skip missing component", tostring(inst.userid), tostring(attempt))
        return true
    end
    if not IsValidUserId(inst.userid) then
        debug_log.log("team-apply", "waiting userid", tostring(inst.userid), tostring(inst.prefab), "attempt", tostring(attempt))
        return false
    end

    local team_id = nil
    local cached_ready = false
    team_id, cached_ready = player_state.get(inst)

    local server_ready = false
    if IsCaveShard() then
        local shard_team = nil
        shard_team, server_ready = team_state.get_server_team(inst.userid)
        if shard_team ~= nil and shard_team ~= team_id then
            team_id = shard_team
            player_state.set_ready(inst, team_id, "shard-mirror")
            debug_log.log("team-apply", "cave shard mirror", tostring(inst.userid), tostring(team_id))
        end
    end

    if team_id == nil then
        if IsCaveShard() then
            local loaded_team = get_loaded_component_team(component)
            if loaded_team ~= nil then
                team_id = get_component_mirror_team(inst, component)
                player_state.set_ready(inst, team_id, "component-mirror")
            else
                local netvar_team, netvar_ready = player_state.get_netvar(inst)
                if netvar_ready then
                    team_id = netvar_team
                    player_state.set_ready(inst, team_id, "entity-teamvar")
                else
                    debug_log.log("team-apply", "cave waiting entity team", tostring(inst.userid), "attempt", tostring(attempt))
                    observer_camera.disable(inst)
                    return false
                end
            end
        else
            team_id, server_ready = team_state.get_server_team(inst.userid)
        end
        if team_id ~= nil then
            local source = IsCaveShard() and "entity-mirror" or "world"
            player_state.set_ready(inst, team_id, source)
        elseif server_ready then
            local source = nil
            team_id, source = resolve_missing_ready_team(inst, "world-ready-default-waiting")
            player_state.set_ready(inst, team_id, source)
        else
            if request_authoritative_team(inst) then
                observer_camera.disable(inst)
                return false
            end

            team_id = player_state.get(inst)
        end
    end

    if team_id == nil then
        -- Missing here means the ground registry is still unavailable, or the
        -- cave player migration data has not loaded its component mirror yet.
        debug_log.log("team-apply", "missing team", tostring(inst.userid), "server_ready", tostring(server_ready), "cached_ready", tostring(cached_ready), "attempt", tostring(attempt))
        observer_camera.disable(inst)
        return false
    end

    local _, ready = player_state.get(inst)
    if not ready then
        player_state.set_ready(inst, team_id, "resolved")
    end
    debug_log.log("team-apply", "resolved", tostring(inst.userid), tostring(inst.prefab), "team", tostring(team_id), "attempt", tostring(attempt))
    return true
end

function apply_authoritative_team_with_retries(inst, attempt)
    if apply_authoritative_team(inst, attempt) then
        return
    end

    attempt = attempt + 1
    local delay = APPLY_RETRY_DELAYS[attempt]
    if delay == nil then
        debug_log.log("team-apply", "give up", tostring(inst ~= nil and inst.userid or nil))
        return
    end

    debug_log.log("team-apply", "retry scheduled", tostring(inst.userid), "attempt", tostring(attempt), "delay", tostring(delay))
    inst:DoTaskInTime(delay, function(player)
        apply_authoritative_team_with_retries(player, attempt)
    end)
end

local function retry_pending_team_on_registry_dirty(inst)
    local _, ready = player_state.get(inst)
    if ready then
        return
    end

    debug_log.log("team-apply", "registry dirty retry", tostring(inst ~= nil and inst.userid or nil))
    apply_authoritative_team_with_retries(inst, 0)
end

AddPlayerPostInit(function(inst)
    player_state.install_netvar(inst)

    if not TheWorld.ismastersim then
        inst:ListenForEvent(player_state.NET_DIRTY_EVENT, function()
            if TheGlobalInstance ~= nil then
                TheGlobalInstance:PushEvent(TEAM_REGISTRY_DIRTY_EVENT)
            end
        end)
        return
    end

    if inst.components.player_duiwu_qe == nil then
        inst:AddComponent("player_duiwu_qe")
    end

    local component = inst.components.player_duiwu_qe

    -- The lobby/world registry is authoritative before player entities spawn.
    -- If it is briefly unavailable, wait instead of exposing a temporary OB team.
    inst:ListenForEvent(player_state.EVENT_PENDING, apply_pending_team)
    inst:ListenForEvent(player_state.EVENT_READY, apply_ready_team)
    inst:ListenForEvent(TEAM_REGISTRY_DIRTY_EVENT, function()
        retry_pending_team_on_registry_dirty(inst)
    end, TheWorld)
    local loaded_team = IsCaveShard() and get_loaded_component_team(component) or nil
    if loaded_team ~= nil then
        player_state.set_ready(inst, loaded_team, "component-preseed")
        inst:DoTaskInTime(0, function(player)
            apply_ready_team(player, {
                team_id = loaded_team,
                source = "component-preseed",
            })
        end)
    elseif IsCaveShard() then
        player_state.ensure(inst)
    else
        player_state.set_pending(inst, "spawn")
    end
    debug_log.log("team-apply", "player post init", tostring(inst.userid), tostring(inst.prefab))
    apply_authoritative_team_with_retries(inst, 0)
    inst:DoTaskInTime(0, function(player)
        apply_authoritative_team_with_retries(player, 0)
    end)
end)
