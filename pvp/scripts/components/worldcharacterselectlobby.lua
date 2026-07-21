--------------------------------------------------------------------------
--[[ WorldCharacterSelectLobby class definition ]]
--------------------------------------------------------------------------

local team_state = require("src/team/lobby_team_state")
local debug_log = require("src/core/debug")

return Class(function(self, inst)

--------------------------------------------------------------------------
--[[ Constants ]]
--------------------------------------------------------------------------

local ALLOW_DEBUG_START = BRANCH == "dev"

local COUNTDOWN_TIME = ALLOW_DEBUG_START and 1 or 6
local COUNTDOWN_INACTIVE = 255

--------------------------------------------------------------------------
--[[ Member variables ]]
--------------------------------------------------------------------------

--Public
self.inst = inst

self.LATE_JOIN = true
self.START_PAUSE_DURATION = 30

--Private
local _world = TheWorld
local _ismastersim = _world.ismastersim

local _lobby_up_time = 0
local _client_wait_time = {}

--Master simulation
local _countdownf = -1
local _start_server_pause_active = false
local _countdown_finished_handled = false
local _start_pause_released = false
local _start_pause_pending = false
local _start_pause_countdown_task = nil
local _start_pause_countdown_remaining = nil
local _game_start_announced = false
local _suppress_auto_start = false
local TryStartCountdown

--Network
local _countdowni = net_byte(inst.GUID, "worldcharacterselectlobby._countdowni", "spawncharacterdelaydirty")
local _lockedforshutdown = net_bool(inst.GUID, "worldcharacterselectlobby._lockedforshutdown", "lockedforshutdown")

local _players_ready_to_start = {}
for i = 1, TheNet:GetServerMaxPlayers() do
	table.insert(_players_ready_to_start, net_string(inst.GUID, "worldcharacterselectlobby._players_ready_to_start."..i, "player_ready_to_start_dirty"))
end

--------------------------------------------------------------------------
--[[ Local Functions ]]
--------------------------------------------------------------------------
local function GetPlayersClientTable()
    local clients = TheNet:GetClientTable() or {}
    local result = {}
    local isdedicated = not TheNet:GetServerIsClientHosted()

    for _, client in ipairs(clients) do
        local userid = client.userid
        if (not isdedicated or client.performance == nil) and userid ~= nil and userid ~= "" then
            table.insert(result, client)
        end
    end

    return result
end

local function AddClock(clocks, clock)
    if clock == nil then
        return
    end

    for _, existing in ipairs(clocks) do
        if existing == clock then
            return
        end
    end

    table.insert(clocks, clock)
end

local function GetWorldClocks()
    local clocks = {}

    if _world ~= nil and _world.components ~= nil then
        AddClock(clocks, _world.components.clock)
    end

    local net = _world ~= nil and _world.net or nil
    if net ~= nil and net.components ~= nil then
        AddClock(clocks, net.components.clock)
    end

    return clocks
end

local function InstallClockPauseGuard(clock)
    if clock == nil or clock._bird_preselect_clock_guard_installed then
        return
    end

    clock._bird_preselect_clock_guard_installed = true

    local OnUpdate = clock.OnUpdate
    local OnStaticUpdate = clock.OnStaticUpdate or OnUpdate
    local LongUpdate = clock.LongUpdate or OnUpdate

    function clock:OnUpdate(dt, ...)
        if self._bird_preselect_clock_paused then
            -- A zero-delta update keeps shard_clock synchronized without
            -- advancing the day while players are still in the lobby.
            return OnUpdate(self, 0, ...)
        end
        return OnUpdate(self, dt, ...)
    end

    function clock:OnStaticUpdate(dt, ...)
        if self._bird_preselect_clock_paused then
            return OnStaticUpdate(self, 0, ...)
        end
        return OnStaticUpdate(self, dt, ...)
    end

    function clock:LongUpdate(dt, ...)
        if self._bird_preselect_clock_paused then
            return LongUpdate(self, 0, ...)
        end
        return LongUpdate(self, dt, ...)
    end
end

local function SetLobbyClockPaused(paused)
    local clocks = GetWorldClocks()
    if #clocks <= 0 then
        return false
    end

    for _, clock in ipairs(clocks) do
        InstallClockPauseGuard(clock)

        if paused then
            if not clock._bird_preselect_clock_paused then
                clock._bird_preselect_clock_paused = true
            end
        elseif clock._bird_preselect_clock_paused then
            clock._bird_preselect_clock_paused = nil
            if _ismastersim and clock.LongUpdate ~= nil then
                clock:LongUpdate(0)
            end
        end
    end

    return true
end

local function HasSpawnedPlayers()
    return AllPlayers ~= nil and #AllPlayers > 0
end

local function ShouldPauseLobbyClock()
    if _countdowni:value() ~= 0 then
        return true
    end

    -- The countdown can finish before any lobby player has actually spawned.
    -- Keep time frozen during that gap so failed/blocked StartGame flows do not
    -- let the world clock run behind the preselect screen.
    return _ismastersim and not _start_pause_released and not HasSpawnedPlayers()
end

local function RefreshLobbyClockPause()
    if not SetLobbyClockPaused(ShouldPauseLobbyClock()) then
        inst:DoTaskInTime(0, RefreshLobbyClockPause)
    end
end

local function IsServerPaused()
    if TheNet == nil then
        return false
    end

    local ok, paused = pcall(function()
        return TheNet:IsServerPaused()
    end)
    return ok and paused == true
end

local function SetStartServerPaused(paused)
    if not _ismastersim or TheNet == nil then
        return
    end

    -- Native dedicated-server pausing is rejected unless an admin client is
    -- connected. Freeze the authoritative simulation directly so automatic
    -- start pause does not depend on who joins first. Static tasks still run.
    if TheNet:IsDedicated() then
        if paused then
            local ok = TheSim ~= nil and pcall(function()
                TheSim:SetTimeScale(0)
            end)
            _start_server_pause_active = ok == true
            debug_log.log(
                "start-pause",
                "dedicated",
                _start_server_pause_active and "applied" or "failed"
            )
        elseif _start_server_pause_active then
            _start_server_pause_active = false
            if TheSim ~= nil then
                pcall(function()
                    TheSim:SetTimeScale(1)
                end)
            end
            debug_log.log("start-pause", "dedicated", "released")
        end
        return
    end

    if paused then
        local ok = true
        if not IsServerPaused() then
            ok = pcall(function()
                TheNet:SetServerPaused(true)
            end)
        end
        _start_server_pause_active = ok == true
        return
    end

    if _start_server_pause_active then
        _start_server_pause_active = false
        if IsServerPaused() then
            pcall(function()
                TheNet:SetServerPaused(false)
            end)
        end
    end
end

local function CancelStartPauseCountdown()
    if _start_pause_countdown_task ~= nil then
        _start_pause_countdown_task:Cancel()
        _start_pause_countdown_task = nil
    end
    _start_pause_countdown_remaining = nil
end

local function AnnounceStartPause(message)
    if TheNet ~= nil and TheNet.Announce ~= nil then
        TheNet:Announce(message)
    end
end

local function AnnounceGameStarted(reason)
    if _game_start_announced then
        return
    end
    _game_start_announced = true
    AnnounceStartPause(reason == "admin" and "管理员已开始游戏。" or "游戏已开始。")
end

local function ReleaseStartPause(reason)
    CancelStartPauseCountdown()
    _start_pause_pending = false
    _start_pause_released = true
    SetStartServerPaused(false)
    RefreshLobbyClockPause()

    if reason == "admin" or reason == "automatic" then
        AnnounceGameStarted(reason)
    end
end

local function StartPauseCountdownTick()
    _start_pause_countdown_task = nil

    if _start_pause_countdown_remaining == nil then
        return
    end

    if not _start_server_pause_active
        or (not TheNet:IsDedicated() and not IsServerPaused()) then
        ReleaseStartPause("admin")
        return
    end

    _start_pause_countdown_remaining = _start_pause_countdown_remaining - 1
    if _start_pause_countdown_remaining <= 0 then
        ReleaseStartPause("automatic")
        return
    end

    if _start_pause_countdown_remaining <= 5
        or _start_pause_countdown_remaining % 10 == 0 then
        AnnounceStartPause(string.format(
            "游戏将在 %d 秒后自动开始。",
            _start_pause_countdown_remaining
        ))
    end

    _start_pause_countdown_task = _world:DoStaticTaskInTime(1, StartPauseCountdownTick)
end

local function StartPauseCountdown()
    CancelStartPauseCountdown()
    _start_pause_countdown_remaining = math.max(
        0,
        math.floor(tonumber(self.START_PAUSE_DURATION) or 0)
    )
    if _start_pause_countdown_remaining <= 0 then
        AnnounceGameStarted("automatic")
        return
    end
    AnnounceStartPause(string.format(
        "游戏将在 %d 秒后自动开始。",
        _start_pause_countdown_remaining
    ))
    _start_pause_countdown_task = _world:DoStaticTaskInTime(1, StartPauseCountdownTick)
end

local function ApplyStartPause()
    CancelStartPauseCountdown()
    _start_pause_pending = (tonumber(self.START_PAUSE_DURATION) or 0) > 0
    RefreshLobbyClockPause()
end

local function SetPlayerReadyToStart(userid, is_ready)
	if _countdowni:value() ~= COUNTDOWN_INACTIVE then
		return
	end
	    
    if is_ready then
		local empty_slot = nil
		for i, v in ipairs(_players_ready_to_start) do
			local value = v:value()
			if value == userid then
				return
			elseif value == "" then
				empty_slot = i
			end
		end
		if empty_slot ~= nil then
			_players_ready_to_start[empty_slot]:set(userid)
		end
    else
		for i, v in ipairs(_players_ready_to_start) do
			if v:value() == userid then
				_players_ready_to_start[i]:set("")
				return
			end
		end
	end
end

local function TogglePlayerReadyToStart(userid)
	if _countdowni:value() ~= COUNTDOWN_INACTIVE then
		return
	end

	local empty_slot = nil
	for i, v in ipairs(_players_ready_to_start) do
		local value = v:value()
		if value == userid then
			_players_ready_to_start[i]:set("")
			return
		elseif value == "" then
			empty_slot = i
		end
	end
	if empty_slot ~= nil then
		_players_ready_to_start[empty_slot]:set(userid)
	end
end

--------------------------------------------------------------------------
--[[ Global Setup ]]
--------------------------------------------------------------------------

AddUserCommand("playerreadytostart", {
    prettyname = nil, --default to STRINGS.UI.BUILTINCOMMANDS.RESCUE.PRETTYNAME
    desc = nil, --default to STRINGS.UI.BUILTINCOMMANDS.RESCUE.DESC
    permission = COMMAND_PERMISSION.USER,
    slash = false,
    usermenu = false,
    servermenu = false,
    params = {"ready"},
    vote = false,
    canstartfn = function(command, caller, targetid)
        return _countdowni:value() == COUNTDOWN_INACTIVE and not _lockedforshutdown:value()
    end,
    serverfn = function(params, caller)
		TogglePlayerReadyToStart(caller.userid)
        TryStartCountdown()
    end,
})

--------------------------------------------------------------------------
--[[ Private Server event handlers ]]
--------------------------------------------------------------------------

local function ClearAllPlayersReadyToStart()
	_suppress_auto_start = true
	for i, v in ipairs(_players_ready_to_start) do
		v:set("")
	end
	_suppress_auto_start = false
end

local function CalcLobbyUpTime()
	return _lobby_up_time and (GetTimeRealSeconds() - _lobby_up_time) or 0
end

local function StarTimer(time)
	debug_log.log("lobby", "countdown started")
	TheNet:Announce("Starting game in "..time.." seconds...")

	local analytics = TheWorld.components.lavaarenaanalytics or TheWorld.components.quagmireanalytics
	if analytics ~= nil then
		analytics:SendAnalyticsLobbyEvent("lobby.startmatch", nil, { up_time = CalcLobbyUpTime() })
	
		for userid, _ in pairs(_client_wait_time) do
			local data = {play_t = _client_wait_time[userid] ~= nil and (GetTimeRealSeconds() - _client_wait_time[userid]) or 0}
			analytics:SendAnalyticsLobbyEvent("lobby.clientstartmatch", userid, data)
		end
	end

	_countdownf = time
    CancelStartPauseCountdown()
    _start_pause_pending = false
    _start_server_pause_active = false
    _countdown_finished_handled = false
    _start_pause_released = false
    _game_start_announced = false
    _countdowni:set(math.ceil(time))
    RefreshLobbyClockPause()

	if not self.LATE_JOIN then
		TheNet:SetAllowNewPlayersToConnect(false)
	end
    TheNet:SetIsMatchStarting(true)
	ClearAllPlayersReadyToStart()

	self.inst:StartWallUpdatingComponent(self)
end

-- used by the admin's "start" button
AddUserCommand("forcestartgame", {
	prettyname = nil, --default to STRINGS.UI.BUILTINCOMMANDS.RESCUE.PRETTYNAME
	desc = nil, --default to STRINGS.UI.BUILTINCOMMANDS.RESCUE.DESC
	permission = COMMAND_PERMISSION.ADMIN,
	-- seems like slash commands dont work in the lobby screen :(
	slash = true,
	usermenu = false,
	servermenu = false,
	params = {},
	vote = false,
	canstartfn = function(command, caller, targetid)
		return _countdowni:value() == COUNTDOWN_INACTIVE and not _lockedforshutdown:value()
	end,
	serverfn = function(params, caller)
		StarTimer(COUNTDOWN_TIME)
	end,
})

local function CountPlayersReadyToStart()
	local count = 0
	for i, v in ipairs(_players_ready_to_start) do
		if v:value() ~= "" then
			count = count + 1
		end
	end
	return count
end

local function CountPlayingTeamReadyStatus()
    local ready_users = {}
    for _, netvar in ipairs(_players_ready_to_start) do
        local userid = netvar:value()
        if userid ~= "" then
            ready_users[userid] = true
        end
    end

    local ready_count = 0
    local total_count = 0
    for _, client in ipairs(GetPlayersClientTable()) do
        local team_id = nil
        local teams_ready = false
        if _ismastersim then
            team_id, teams_ready = team_state.get_server_team(client.userid)
        elseif team_state.is_remote_ready() then
            team_id = team_state.get(client.userid)
            teams_ready = true
        end

        if teams_ready and team_state.is_playing_team(team_id) then
            total_count = total_count + 1
            if ready_users[client.userid] then
                ready_count = ready_count + 1
            end
        end
    end

    return ready_count, total_count
end

TryStartCountdown = function()
	if _suppress_auto_start or not self:IsAllowingCharacterSelect() then
		return
	end

    local ready_count, total_count = CountPlayingTeamReadyStatus()
    if total_count > 0 and ready_count >= total_count then
        StarTimer(COUNTDOWN_TIME)
    end
end

local function OnRequestLobbyCharacter(world, data)
	if data == nil or not self:IsAllowingCharacterSelect() then
		return
	end

	local client = TheNet:GetClientTableForUser(data.userid)
	if not client then
		return
	end

	TheNet:SetLobbyCharacter(data.userid, data.prefab_name, data.skin_base, data.clothing_body, data.clothing_hand, data.clothing_legs, data.clothing_feet)
	SetPlayerReadyToStart(data.userid, false)
	
	TryStartCountdown()
end

local function OnLobbyClientConnected(src, data)
	ClearAllPlayersReadyToStart()

	if _countdowni:value() == COUNTDOWN_INACTIVE then
		if GetTableSize(_client_wait_time) == 0 then
			_lobby_up_time = GetTimeRealSeconds()
		end
		_client_wait_time[data.userid] = GetTimeRealSeconds()

		
		local analytics = TheWorld.components.lavaarenaanalytics or TheWorld.components.quagmireanalytics
		if analytics ~= nil then
			local msg = {}
			msg.up_time = CalcLobbyUpTime()
			analytics:SendAnalyticsLobbyEvent("lobby.join", nil, msg)
		end		
	else		
		-- players will have no choice but to disconncet at this point.
	end
end

local function OnLobbyClientDisconnected(src, data)
	ClearAllPlayersReadyToStart()

	if self:IsAllowingCharacterSelect() and _client_wait_time[data.userid] ~= nil then
		local wait_time = _client_wait_time[data.userid] and (GetTimeRealSeconds() - _client_wait_time[data.userid]) or 0
		_client_wait_time[data.userid] = nil 
		local num_remaining_players = GetTableSize(_client_wait_time)

		local analytics = TheWorld.components.lavaarenaanalytics or TheWorld.components.quagmireanalytics
		if analytics ~= nil then
			local msg = {}
			msg.up_time = CalcLobbyUpTime()
			msg.play_t = wait_time
			msg.consecutive_match = TheNet:IsConsecutiveMatchForPlayer(data.userid)
			local analytics = TheWorld.components.lavaarenaanalytics or TheWorld.components.quagmireanalytics
			analytics:SendAnalyticsLobbyEvent("lobby.leave", data.userid, msg)
		
			if GetTableSize(_client_wait_time) == 0 then
				local msg2 = {}
				msg2.up_time = msg.up_time
				analytics:SendAnalyticsLobbyEvent("lobby.cancelmatch", nil, msg2)

				_lobby_up_time = nil
			end
		end
	end
end

local function OnLobbyPlayerEnteredWorld()
    if _ismastersim and _countdowni:value() == 0 then
        _start_pause_released = true
        if _start_pause_pending then
            _start_pause_pending = false
            SetStartServerPaused(true)
            StartPauseCountdown()
        elseif not _start_server_pause_active
            and _start_pause_countdown_remaining == nil then
            AnnounceGameStarted("automatic")
        end
    end
    RefreshLobbyClockPause()
end



--------------------------------------------------------------------------
--[[ Private Client event handlers ]]
--------------------------------------------------------------------------

local function OnCountdownDirty()
    if _ismastersim and _countdowni:value() == 0 then
        if not _countdown_finished_handled then
            _countdown_finished_handled = true
            ApplyStartPause()
            inst:StopWallUpdatingComponent(self)
            debug_log.log("lobby", "countdown finished")

            --Use regular update to poll for when to clear match starting flag
            inst:StartUpdatingComponent(self)
        end
    end

    local t = _countdowni:value()
    RefreshLobbyClockPause()
    local client = TheNet ~= nil
        and TheNet.GetUserID ~= nil
        and TheNet.GetClientTableForUser ~= nil
        and TheNet:GetClientTableForUser(TheNet:GetUserID())
        or nil
    local has_character = client ~= nil
        and client.lobbycharacter ~= nil
        and client.lobbycharacter ~= ""

    if t == COUNTDOWN_INACTIVE or has_character then
        _world:PushEvent("lobbyplayerspawndelay", { time = t, active = t ~= COUNTDOWN_INACTIVE })
    end
end

--------------------------------------------------------------------------
--[[ Initialization ]]
--------------------------------------------------------------------------

--Initialize network variables
_countdowni:set(COUNTDOWN_INACTIVE)

--Register network variable sync events
inst:ListenForEvent("spawncharacterdelaydirty", OnCountdownDirty)
inst:DoTaskInTime(0, RefreshLobbyClockPause)
-- playeractivated is a client-side activation event. A dedicated server has
-- no local player, so start-pause must be armed from the server join event.
if _ismastersim then
    inst:ListenForEvent("ms_playerjoined", OnLobbyPlayerEnteredWorld, _world)
else
    inst:ListenForEvent("playeractivated", OnLobbyPlayerEnteredWorld, _world)
end

if _ismastersim then
    TheNet:SetIsMatchStarting(false) --Reset flag in case it's invalid

    --Register events
    inst:ListenForEvent("ms_requestedlobbycharacter", OnRequestLobbyCharacter, _world)
    inst:ListenForEvent("player_ready_to_start_dirty", TryStartCountdown)
    inst:ListenForEvent("bird_lobby_teams_dirty", TryStartCountdown, _world)
    inst:ListenForEvent("ms_clientauthenticationcomplete", OnLobbyClientConnected, _world)
    inst:ListenForEvent("ms_clientdisconnected", OnLobbyClientDisconnected, _world)

	local clients = GetPlayersClientTable()
	for _, c in ipairs(clients) do
		OnLobbyClientConnected(TheWorld, {userid = c.userid})
	end
end

--------------------------------------------------------------------------
--[[ Public members ]]
--------------------------------------------------------------------------

function self:GetSpawnDelay()
	local delay = _countdowni:value()
	return delay ~= COUNTDOWN_INACTIVE and delay or -1
end

if _ismastersim then function self:IsAllowingCharacterSelect()
	return _countdowni:value() == COUNTDOWN_INACTIVE and not _lockedforshutdown:value()
end end

function self:IsServerLockedForShutdown()
	return _lockedforshutdown:value()
end

function self:IsPlayerReadyToStart(userid)
	for i, v in ipairs(_players_ready_to_start) do
		if v:value() == userid then
			return true
		end
	end
	return false
end

if _ismastersim then function self:OnPostInit()
	if TheNet:GetDeferredServerShutdownRequested() then
		_lockedforshutdown:set(true)
	end
    RefreshLobbyClockPause()
end end

-- TheWorld.net.components.worldcharacterselectlobby:Dump()
function self:Dump()
	local str = ""
	for i, v in ipairs(_players_ready_to_start) do
		str = str .. ", " .. tostring(v:value())
	end
	debug_log.info("lobby", "ready players", str)
end

function self:CanPlayersSpawn()
	return _countdownf == 0
end

-- Simple wrapper of the local function to expose it as a public function
function self:CountPlayersReadyToStart()
	return CountPlayersReadyToStart()
end

function self:GetPlayingTeamReadyStatus()
    return CountPlayingTeamReadyStatus()
end

-- client will need to know if the game has started (e.g. so they go to the game instead of the lobby)
-- similar to CanPlayersSpawn() but works clientside
function self:HasGameStarted()
	return _countdowni:value() == 0
end

function self:ReleaseStartPause()
    local clock_pause_active = _countdowni:value() == 0 and not _start_pause_released
    if not _start_pause_pending and not _start_server_pause_active and not clock_pause_active then
        return false
    end

    ReleaseStartPause("admin")
    return true
end

function self:OnRemoveFromEntity()
    CancelStartPauseCountdown()
    _start_pause_pending = false
    _start_pause_released = true
    SetStartServerPaused(false)
    SetLobbyClockPaused(false)
end

--------------------------------------------------------------------------
--[[ Update ]]
--------------------------------------------------------------------------

function self:OnWallUpdate(dt)
	_countdownf = math.max(0, _countdownf - dt)
	local c = math.ceil(_countdownf)
	if _countdowni:value() ~= c then
		_countdowni:set(c)
	end
    if _ismastersim and c == 0 then
        OnCountdownDirty()
    end
end

function self:OnUpdate(dt)
    RefreshLobbyClockPause()

    if #AllPlayers <= 0 and #GetPlayersClientTable() > 0 then
        -- Still someone connected.
        return
    end
    --Either someone has spawned in, or everybody disconnceted
    TheNet:SetIsMatchStarting(false)
    inst:StopUpdatingComponent(self)
end

--------------------------------------------------------------------------
--[[ Save/Load ]]
--------------------------------------------------------------------------

if _ismastersim then function self:OnSave()
	local data =
	{
		match_started = _countdowni:value() == 0,
	}

	return data
end end

if _ismastersim then function self:OnLoad(data)
	if data then
		if data.match_started then
			_countdownf = 0
			_countdowni:set(0)
            inst:StartUpdatingComponent(self)
			if not self.LATE_JOIN then
				inst:DoTaskInTime(0, function() TheNet:SetAllowNewPlayersToConnect(false) end)
			end
		end
	end
    inst:DoTaskInTime(0, RefreshLobbyClockPause)
end end

--------------------------------------------------------------------------
--[[ End ]]
--------------------------------------------------------------------------

end)
