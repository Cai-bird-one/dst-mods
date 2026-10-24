-- Load complete native and PVP chat scripts; only engine services are stubs.
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function pack(...)
    return { n = select("#", ...), ... }
end
local function noop() end
function Class(constructor)
    local cls = {}
    cls.__index = cls
    return setmetatable(cls, { __call = function(self)
        local instance = setmetatable({}, self)
        constructor(instance)
        return instance
    end })
end
local team_state = {
    get_player_team = function(player) return player.team, player.pending end,
    get_component_team = function(player) return player.team end,
    get_world_team = noop,
    get = noop,
    is_waiting_team = function(team) return team == -1 end,
    is_valid = function(team) return team == 0 or team == 1 or team == 2 end,
}
function require(name)
    if name == "src/team/lobby_team_state" then return team_state end
    if name == "src/observer/privileges" then
        return { can_view_team_chat = function(player) return player.observer == true end }
    end
    return {}
end
STRINGS = { CHARACTER_NAMES = {}, NAMES = {}, UI = { CHATINPUTSCREEN = { WHISPER_DESIGNATOR = "whisper" } } }
SAY_COLOR, WHISPER_COLOR = {}, {}
AddClientModRPCHandler, AddShardModRPCHandler, AddModRPCHandler = noop, noop, noop
AddComponentPostInit, AddSimPostInit = noop, noop
ThePlayer = { userid = "viewer", team = 1 }
AllPlayers = {}
assert(loadstring(native_chat_source))()

local captured, calls = nil, 0
local native_add = ChatHistory.AddToHistory
ChatHistory.AddToHistory = function(self, ...)
    calls = calls + 1
    captured = pack(...)
    return native_add(self, ...), nil, "future return", nil
end
assert(loadstring(pvp_chat_source))()
local notifications = 0
ChatHistory:AddChatHistoryListener(function() notifications = notifications + 1 end)
local function send(message, silent, chat_type)
    return ChatHistory:AddToHistory(chat_type or ChatTypes.Message, nil, nil, "sender", message,
        { 1, 1, 1, 1 }, nil, false, false, nil, silent)
end

local result = pack(send("quiet NPC", true, ChatTypes.ChatterMessage))
eq(notifications, 0, "silent NPC must not notify listeners")
eq(ChatHistory:GetChatMessageAtIndex(1), result[1], "silent NPC remains in history")
eq(result.n, 4, "preserve trailing nil return")
eq(result[2], nil, "preserve middle nil return")
eq(result[3], "future return", "preserve extra return")
send("audible NPC", false, ChatTypes.ChatterMessage)
eq(notifications, 1, "audible NPC notifies once")
send("ordinary message")
eq(notifications, 2, "omitted silent still notifies")

for _, silent in ipairs({ false, true }) do
    for _, viewer in ipairs({
        { team = 1, allowed = true },
        { team = 2, allowed = false },
        { pending = true, allowed = false },
        { team = 0, observer = true, allowed = true },
    }) do
        ThePlayer = viewer
        local previous_calls, previous_notifications = calls, notifications
        local previous_message = ChatHistory:GetChatMessageAtIndex(1)
        local data = send("/d1wprivate team message", silent)
        eq(calls, previous_calls + (viewer.allowed and 1 or 0), "team filter before native history")
        eq(notifications, previous_notifications + (viewer.allowed and not silent and 1 or 0), "team filter and silent notifications")
        if viewer.allowed then
            eq(data.message, "private team message", "team message formatting retained")
            eq(ChatHistory:GetChatMessageAtIndex(1), data, "allowed team message retained")
        else
            eq(data, nil, "hidden team message return")
            eq(ChatHistory:GetChatMessageAtIndex(1), previous_message, "hidden team message absent from history")
        end
    end
end

ThePlayer = { team = 2 }
eq(send("/d1opublic team message", false).message, "public team message", "public cross-team messages retained")
local future = {}
ChatHistory:AddToHistory(ChatTypes.Message, nil, nil, "sender", "future parameters", { 1, 1, 1, 1 },
    nil, nil, nil, nil, true, nil, future, nil)
eq(captured.n, 14, "preserve complete argument count")
eq(captured[10], nil, "preserve absent text filter context")
eq(captured[11], true, "preserve silent position")
eq(captured[12], nil, "preserve middle nil argument")
eq(captured[13], future, "preserve future argument identity")
eq(captured[14], nil, "preserve trailing nil argument")
return checks
