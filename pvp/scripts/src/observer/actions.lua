-- OB/referee RPC actions.
local status = require("src/observer/status")
local observer_camera = require("src/observer/camera_mode")
local observer_privileges = require("src/observer/privileges")
local admin_privileges = require("src/admin/privileges")
local team_state = require("src/team/lobby_team_state")

local TEAM_COLOURS = {
    [team_state.TEAM_RED] = { 1, 0, 0, 1 },
    [team_state.TEAM_BLUE] = { 25 / 255, 88 / 255, 1, 1 },
}

local function is_observer(player)
    local fn = observer_privileges.is_observer
    return fn ~= nil and fn(player) == true
end

local function is_admin(player)
    local fn = admin_privileges.is_player_admin
    return fn ~= nil and fn(player) == true
end

local M = {}

function M.ditu(player)
    if is_observer(player) then
        observer_camera.reveal_full_map(player)
    end
end

function M.chuansong(player, x, z)
    observer_camera.teleport(player, x, z)
end

local function give_item(player, prefab)
    if player.components.inventory == nil then
        return false
    end

    local item = SpawnPrefab(prefab)
    if item == nil then
        return false
    end

    player.components.inventory:GiveItem(item)
    return true
end

local function get_team_name(team_id)
    if team_id == team_state.TEAM_RED then
        return "红队"
    end
    if team_id == team_state.TEAM_BLUE then
        return "蓝队"
    end
    return "OB"
end

local function get_team_colour(team_id)
    return TEAM_COLOURS[team_id] or { 1, 1, 1, 1 }
end

function M.give_team_walking_sticks(team_id)
    team_id = team_state.normalize(team_id)
    if team_id ~= team_state.TEAM_RED and team_id ~= team_state.TEAM_BLUE then
        return 0
    end

    local count = 0
    for _, player in ipairs(AllPlayers) do
        if player:IsValid() then
            local player_team_id, pending = team_state.get_player_team(player)
            if not pending and player_team_id == team_id then
                if give_item(player, "walking_stick") then
                    count = count + 1
                end
            end
        end
    end

    if TheNet ~= nil then
        TheNet:Announce(
            string.format("已给%s发放木手杖 x%d", get_team_name(team_id), count),
            get_team_colour(team_id)
        )
    end
    return count
end

function M.give_team_item(observer, team_id, prefab)
    if not is_admin(observer) or prefab ~= "walking_stick" then
        return
    end

    M.give_team_walking_sticks(team_id)
end

function M.zhaoji(player)
    if not is_admin(player) then
        return
    end

    for _, other in ipairs(AllPlayers) do
        if other:IsValid() and other ~= player then
            local pos = player:GetPosition()
            local offset = FindWalkableOffset(pos, math.random() * 2 * PI, math.random(3), 10, true)
            if offset ~= nil then
                pos = pos + offset
            end
            other.Transform:SetPosition(pos.x, pos.y, pos.z)
        end
    end
end

function M.chakan(player, enabled)
    status.set_subscribed(player, enabled == 1)
end

function M.youxi(player)
    if not is_admin(player) then
        return
    end

    local lobby = TheWorld ~= nil
        and TheWorld.net ~= nil
        and TheWorld.net.components ~= nil
        and TheWorld.net.components.worldcharacterselectlobby
        or nil
    if lobby ~= nil and lobby.ReleaseStartPause ~= nil and lobby:ReleaseStartPause() then
        return
    end

    SetServerPaused()
end

function M.wanjia(observer, action, userid)
    if not is_admin(observer) then
        return
    end

    local target = LookupPlayerInstByUserID(userid)
    if target == nil or not target:IsValid() then
        if observer.components.talker ~= nil then
            observer.components.talker:Say("target not found")
        end
        return
    end

    if action == 1 then
        local pos = target:GetPosition()
        observer.Transform:SetPosition(pos.x, pos.y, pos.z)
    elseif action == 2 and target:HasTag("playerghost") then
        target:PushEvent("respawnfromghost")
    elseif action == 3 and not IsEntityDeadOrGhost(target, true) then
        target.components.health:Kill()
    end
end

return M
