-- [PATCH] 新增：掉线自动暂停与预留位置保护。
-- 对局开始后，红/蓝队玩家掉线时自动冻结游戏时间；
-- 只有当本局人满时，才为掉线玩家预留位置并阻止非本局玩家进入；
-- 人未坐满时，其他玩家仍可进入，但游戏会一直保持冻结，直到所有掉线玩家回归。
-- 注意：不处理上下洞切换，上下洞自动暂停已按需求移除。

local team_state = require("src/team/lobby_team_state")
local pause = require("src/lobby/pause")

local TEAM_RED = team_state.TEAM_RED
local TEAM_BLUE = team_state.TEAM_BLUE

-- 本局红/蓝队名单：userid -> team_id
local _match_roster = {}
-- 对局过程中掉线的本局玩家：userid -> true
local _disconnected = {}
-- 人满时用于阻止非本局玩家进入的预留名单：userid -> true
local _reserved = {}
-- 名单是否已在对局开始时捕获
local _roster_captured = false
-- 对局开始时是否人满（用于决定是否预留位置）
local _roster_full = false

local function GetWorldLobby()
    local net = TheWorld ~= nil and TheWorld.net or nil
    return net ~= nil and net.components ~= nil and net.components.worldcharacterselectlobby or nil
end

local function IsGameStarted()
    local lobby = GetWorldLobby()
    return lobby ~= nil and lobby.HasGameStarted ~= nil and lobby:HasGameStarted()
end

-- 从服务端大厅队伍表获取玩家队伍；仅红/蓝队视为本局玩家。
local function GetServerTeam(userid)
    if userid == nil or userid == "" then
        return nil
    end
    local team, _ = team_state.get_server_team(userid)
    if team == TEAM_RED or team == TEAM_BLUE then
        return team
    end
    return nil
end

-- 对局开始后捕获本局红/蓝队名单，并记录是否人满。
local function CaptureMatchRoster()
    if _roster_captured then
        return
    end
    if not IsGameStarted() then
        return
    end

    local count = 0
    for _, client in ipairs(TheNet:GetClientTable() or {}) do
        local team = GetServerTeam(client.userid)
        if team ~= nil then
            _match_roster[client.userid] = team
            count = count + 1
        end
    end

    -- [PATCH] 人满判断：本局红/蓝队人数达到服务器最大人数时视为满员。
    local max_players = TheNet:GetServerMaxPlayers() or 0
    _roster_full = max_players > 0 and count >= max_players
    _roster_captured = true
end

local function IsMatchPlayer(userid)
    return _match_roster[userid] ~= nil
end

local function IsDisconnectedPlayer(userid)
    return _disconnected[userid] == true
end

local function IsReservedPlayer(userid)
    return _reserved[userid] == true
end

-- 冻结/恢复游戏时间；使用共享暂停管理器，避免与开局暂停冲突。
local function SetDisconnectPaused(paused)
    if not (TheWorld ~= nil and TheWorld.ismastersim) or TheSim == nil then
        return
    end

    if paused then
        pause.Pause("disconnect")
    else
        pause.Resume("disconnect")
    end
end

local function ResetReservedState()
    _match_roster = {}
    _disconnected = {}
    _reserved = {}
    _roster_captured = false
    _roster_full = false
    SetDisconnectPaused(false)
end

-- 红/蓝队玩家掉线：冻结游戏时间；人满时再额外预留位置。
local function OnPlayerDisconnected(_, data)
    if not (TheWorld ~= nil and TheWorld.ismastersim) then
        return
    end
    if data == nil or data.userid == nil or data.userid == "" then
        return
    end
    if not IsGameStarted() then
        return
    end

    CaptureMatchRoster()

    -- [PATCH] 兜底：如果掉线发生在名单捕获之前，直接按服务端队伍表补录该玩家。
    local userid = data.userid
    local team = GetServerTeam(userid)
    if team ~= nil then
        _match_roster[userid] = team
    end

    if not IsMatchPlayer(userid) then
        return
    end
    if IsDisconnectedPlayer(userid) then
        return
    end

    _disconnected[userid] = true

    local client = TheNet:GetClientTableForUser(userid)
    local name = client ~= nil and client.name or userid

    if _roster_full then
        -- [PATCH] 人满时预留位置，禁止非本局玩家进入。
        _reserved[userid] = true
        if TheNet ~= nil and TheNet.Announce ~= nil then
            TheNet:Announce(tostring(name) .. " 掉线，本局已满员，已为其保留位置。等待回归...")
        end
    else
        -- [PATCH] 人未坐满时只冻结时间，不阻止其他玩家进入，但冻结会保持到掉线玩家回归。
        if TheNet ~= nil and TheNet.Announce ~= nil then
            TheNet:Announce(tostring(name) .. " 掉线，游戏已暂停，等待该玩家回归。人未坐满时其他玩家仍可进入。")
        end
    end

    SetDisconnectPaused(true)
end

-- 非本局玩家尝试进入已有预留位置的对局：踢出并提示原因。
local function KickNonMatchPlayer(userid)
    if userid == nil or userid == "" then
        return
    end

    if TheNet ~= nil and TheNet.Announce ~= nil then
        TheNet:Announce("已有预留位置，等待掉线玩家回归。")
    end
    if TheNet ~= nil and TheNet.Kick ~= nil then
        pcall(function()
            TheNet:Kick(userid)
        end)
    end
end

-- 玩家连接：掉线玩家回归才解除冻结；人满且存在预留时阻止非本局玩家进入。
local function OnClientConnected(_, data)
    if not (TheWorld ~= nil and TheWorld.ismastersim) then
        return
    end
    if data == nil or data.userid == nil or data.userid == "" then
        return
    end
    if not IsGameStarted() then
        return
    end

    CaptureMatchRoster()

    -- [PATCH] 兜底：如果连接发生在名单捕获之前，直接按服务端队伍表补录该玩家。
    local userid = data.userid
    local team = GetServerTeam(userid)
    if team ~= nil then
        _match_roster[userid] = team
    end

    if IsDisconnectedPlayer(userid) then
        _disconnected[userid] = nil
        _reserved[userid] = nil

        local client = TheNet:GetClientTableForUser(userid)
        local name = client ~= nil and client.name or userid
        if TheNet ~= nil and TheNet.Announce ~= nil then
            TheNet:Announce(tostring(name) .. " 已回归。")
        end

        -- [PATCH] 只有所有掉线玩家都回归后，才自动恢复时间流速。
        if next(_disconnected) == nil then
            SetDisconnectPaused(false)
        end
        return
    end

    -- [PATCH] 人满且存在预留位置时，非本局玩家不允许进入。
    if _roster_full and next(_reserved) ~= nil and not IsMatchPlayer(userid) then
        KickNonMatchPlayer(userid)
        return
    end

    -- [PATCH] 非掉线玩家进入时（人未满时允许），不恢复冻结；冻结只由掉线玩家回归解除。
end

AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then
        return
    end

    -- [PATCH] 监听掉线与连接事件，实现自动冻结和预留位置保护。
    inst:ListenForEvent("ms_clientdisconnected", OnPlayerDisconnected, inst)
    inst:ListenForEvent("ms_clientauthenticationcomplete", OnClientConnected, inst)

    -- 对局开始后首次有人生成时捕获本局名单。
    inst:ListenForEvent("ms_playerspawn", function()
        if IsGameStarted() then
            CaptureMatchRoster()
        end
    end, inst)

    -- 回到大厅（允许重新选人）时清空预留状态，准备下一局。
    inst:ListenForEvent("ms_clientauthenticationcomplete", function()
        local lobby = GetWorldLobby()
        if lobby ~= nil and lobby.IsAllowingCharacterSelect ~= nil and lobby:IsAllowingCharacterSelect() then
            ResetReservedState()
        end
    end, inst)
end)
