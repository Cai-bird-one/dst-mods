-- Team chat transport, visibility filtering, formatting, and speech-bubble filtering.
local TEAM_CHAT_PREFIX = "/d"
local TEAM_ONE_COLOUR = { 1, 0, 0, 1 }
local TEAM_TWO_COLOUR = { 25 / 255, 88 / 255, 1, 1 }
local OBSERVER_COLOUR = { 1, 1, 1, 1 }
local RPC_NAMESPACE = "bird_team_chat"
local MOD_RPC_SEND = "send"
local CLIENT_RPC_RECEIVE = "receive"
local SHARD_RPC_FORWARD = "forward"
local debug_log = require("src/core/debug")
local observer_privileges = require("src/observer/privileges")
local team_state = require("src/team/lobby_team_state")
local directed_team_message = false
local delivered_message_ids = {}
local delivered_message_order = {}
local next_message_sequence = 0

local function can_view_team_chat(player)
    local fn = observer_privileges.can_view_team_chat or observer_privileges.is_observer
    return fn ~= nil and fn(player) == true
end

local function get_local_userid()
    if TheNet == nil or TheNet.GetUserID == nil then
        return nil
    end

    local ok, userid = pcall(TheNet.GetUserID, TheNet)
    return ok and userid or nil
end

local function get_character_prefab(userid)
    if userid == nil or userid == "" then
        return nil
    end

    if TheNet ~= nil and TheNet.GetClientTableForUser ~= nil then
        local client = TheNet:GetClientTableForUser(userid)
        if client ~= nil then
            local prefab = client.prefab
            if prefab == nil or prefab == "" then
                prefab = client.lobbycharacter
            end
            local normalized = type(prefab) == "string" and string.lower(prefab) or nil
            if normalized ~= nil
                and normalized ~= ""
                and normalized ~= "random"
                and normalized ~= "unknown"
                and normalized ~= "loading" then
                return prefab
            end
        end
    end

    for _, player in ipairs(AllPlayers or {}) do
        if player.userid == userid and player.prefab ~= nil and player.prefab ~= "" then
            return player.prefab
        end
    end
end

local function get_character_display_name(userid)
    local prefab = get_character_prefab(userid)
    if prefab == nil then
        return nil
    end

    local key = string.upper(prefab)
    local character_names = STRINGS.CHARACTER_NAMES or {}
    return character_names[key]
        or character_names[prefab]
        or STRINGS.NAMES[key]
        or prefab
end

local function get_userid_by_player_name(player_name)
    if player_name == nil or player_name == "" or TheNet == nil then
        return nil
    end

    for _, client in ipairs(TheNet:GetClientTable() or {}) do
        if client.name == player_name and client.userid ~= nil and client.userid ~= "" then
            return client.userid
        end
    end
end

local function append_character_name(sender_userid, sender_name)
    if sender_name == nil or sender_name == "" then
        return sender_name
    end

    sender_userid = sender_userid or get_userid_by_player_name(sender_name)
    local character_name = get_character_display_name(sender_userid)
    if character_name == nil or character_name == "" then
        return sender_name
    end

    local suffix = "(" .. character_name .. ")"
    if string.sub(sender_name, -#suffix) == suffix then
        return sender_name
    end

    return sender_name .. suffix
end

local function replace_plain(text, search, replacement)
    if search == nil or search == "" then
        return text
    end

    local parts = {}
    local start_index = 1
    while true do
        local first, last = string.find(text, search, start_index, true)
        if first == nil then
            parts[#parts + 1] = string.sub(text, start_index)
            break
        end

        parts[#parts + 1] = string.sub(text, start_index, first - 1)
        parts[#parts + 1] = replacement
        start_index = last + 1
    end

    return table.concat(parts)
end

local function append_character_names_in_message(message)
    if type(message) ~= "string" or message == "" or TheNet == nil then
        return message
    end

    local replacements = {}
    for _, client in ipairs(TheNet:GetClientTable() or {}) do
        local name = client.name
        local decorated = append_character_name(client.userid, name)
        if name ~= nil and name ~= "" and decorated ~= nil and decorated ~= name then
            replacements[#replacements + 1] = {
                name = name,
                decorated = decorated,
            }
        end
    end

    table.sort(replacements, function(a, b)
        return #a.name > #b.name
    end)

    local result = message
    for index, replacement in ipairs(replacements) do
        local token = "\1bird_player_" .. tostring(index) .. "\2"
        replacement.token = token
        result = replace_plain(result, replacement.decorated, token)
        result = replace_plain(result, replacement.name, token)
    end
    for _, replacement in ipairs(replacements) do
        result = replace_plain(result, replacement.token, replacement.decorated)
    end

    return result
end

local function get_preselect_team(player)
    local userid = player ~= nil and player.userid or nil
    if userid == nil or userid == "" then
        userid = get_local_userid()
    end

    local team_id = team_state.get(userid)
    if team_id ~= nil and not team_state.is_waiting_team(team_id) then
        return team_id
    end

    return nil
end

local function get_team_id(player)
    local team_id, pending = team_state.get_player_team(player)
    if team_id ~= nil and not team_state.is_waiting_team(team_id) then
        return team_id
    end

    if pending and player ~= nil and player.userid ~= nil then
        local world_team = team_state.get_world_team(player.userid)
        if world_team ~= nil and not team_state.is_waiting_team(world_team) then
            return world_team
        end
    end

    team_id = team_state.get_component_team(player)
    if team_id ~= nil and not team_state.is_waiting_team(team_id) then
        return team_id
    end

    team_id = get_preselect_team(player)
    if team_id ~= nil then
        return team_id
    end

    if pending then
        return nil
    end

    return nil
end

local function can_see_team_message(player, team_id)
    if can_view_team_chat(player) then
        return true
    end

    local viewer_team = get_team_id(player)
    return viewer_team ~= nil and viewer_team == team_id
end

local function parse_team_message(message)
    if type(message) ~= "string" or string.sub(message, 1, 2) ~= TEAM_CHAT_PREFIX then
        return nil
    end

    local team_id = tonumber(string.sub(message, 3, 3))
    local chat_mode = string.sub(message, 4, 4)
    if not team_state.is_valid(team_id) or (chat_mode ~= "w" and chat_mode ~= "o") then
        return nil
    end

    return team_id, chat_mode, string.sub(message, 5)
end

local function is_valid_chat_message(message)
    return type(message) == "string"
        and message ~= ""
        and message:utf8len() <= MAX_CHAT_INPUT_LENGTH
end

local function is_chat_team(team_id)
    return team_state.is_valid(team_id) and not team_state.is_waiting_team(team_id)
end

local function send_to_local_recipients(message_id, sender_userid, sender_name, team_id, message)
    if TheWorld == nil or not TheWorld.ismastersim or not is_chat_team(team_id) then
        return
    end
    if message_id ~= nil and message_id ~= "" and delivered_message_ids[message_id] then
        return
    end
    if message_id ~= nil and message_id ~= "" then
        delivered_message_ids[message_id] = true
        delivered_message_order[#delivered_message_order + 1] = message_id
        if #delivered_message_order > 128 then
            local expired_id = table.remove(delivered_message_order, 1)
            delivered_message_ids[expired_id] = nil
        end
    end

    local rpc = CLIENT_MOD_RPC ~= nil
        and CLIENT_MOD_RPC[RPC_NAMESPACE] ~= nil
        and CLIENT_MOD_RPC[RPC_NAMESPACE][CLIENT_RPC_RECEIVE]
        or nil
    if rpc == nil then
        return
    end

    for _, recipient in ipairs(AllPlayers or {}) do
        if recipient:IsValid() and recipient.userid ~= nil then
            local recipient_team = get_team_id(recipient)
            if recipient_team == team_id or can_view_team_chat(recipient) then
                SendModRPCToClient(
                    rpc,
                    recipient.userid,
                    sender_userid or "",
                    sender_name or "",
                    team_id,
                    message
                )
            end
        end
    end
end

local function forward_to_other_shards(message_id, sender_userid, sender_name, team_id, message)
    if SendModRPCToShard == nil or GetShardModRPC == nil then
        return
    end

    local rpc = GetShardModRPC(RPC_NAMESPACE, SHARD_RPC_FORWARD)
    if rpc ~= nil then
        SendModRPCToShard(rpc, nil, message_id, sender_userid or "", sender_name or "", team_id, message)
    end
end

AddClientModRPCHandler(RPC_NAMESPACE, CLIENT_RPC_RECEIVE, function(sender_userid, sender_name, team_id, message)
    team_id = team_state.normalize(team_id)
    if ChatHistory == nil or not is_chat_team(team_id) or not is_valid_chat_message(message) then
        return
    end

    local encoded = TEAM_CHAT_PREFIX .. tostring(team_id) .. "w" .. message
    local netid = TheNet ~= nil and TheNet:GetNetIdForUser(sender_userid) or nil
    local colour = team_id == 1 and { 1, 0, 0, 1 }
        or team_id == 2 and { 25 / 255, 88 / 255, 1, 1 }
        or { 1, 1, 1, 1 }

    directed_team_message = true
    local ok, error_message = pcall(
        ChatHistory.AddToHistory,
        ChatHistory,
        ChatTypes.Message,
        sender_userid,
        netid,
        sender_name,
        encoded,
        colour,
        "default",
        false,
        false,
        TEXT_FILTER_CTX_CHAT
    )
    directed_team_message = false
    if not ok then
        debug_log.error("team-chat", "client display failed", tostring(error_message))
    end
end)

AddShardModRPCHandler(RPC_NAMESPACE, SHARD_RPC_FORWARD, function(_, message_id, sender_userid, sender_name, team_id, message)
    team_id = team_state.normalize(team_id)
    if type(message_id) ~= "string"
        or message_id == ""
        or not is_chat_team(team_id)
        or not is_valid_chat_message(message) then
        return
    end
    send_to_local_recipients(message_id, sender_userid, sender_name, team_id, message)
end)

AddModRPCHandler(RPC_NAMESPACE, MOD_RPC_SEND, function(player, message)
    if player == nil or player.userid == nil or not is_valid_chat_message(message) then
        return
    end

    local team_id = get_team_id(player)
    if not is_chat_team(team_id) then
        return
    end

    next_message_sequence = next_message_sequence + 1
    local message_id = table.concat({
        tostring(player.userid),
        tostring(GetTime()),
        tostring(next_message_sequence),
    }, ":")
    send_to_local_recipients(message_id, player.userid, player.name, team_id, message)
    forward_to_other_shards(message_id, player.userid, player.name, team_id, message)
end)

local function send_team_message(message)
    local rpc = GetModRPC ~= nil and GetModRPC(RPC_NAMESPACE, MOD_RPC_SEND) or nil
    if rpc ~= nil then
        SendModRPCToServer(rpc, message)
        return true
    end
    return false
end

local function install_chat_input()
    local ChatInputScreen = require("screens/chatinputscreen")
    local UserCommands = require("usercommands")

    function ChatInputScreen:Run()
        local message = self.chat_edit:GetString()
        message = message ~= nil and message:match("^%s*(.-%S)%s*$") or ""

        if message == "" then
            return
        end

        if string.sub(message, 1, 1) == "/" then
            UserCommands.RunTextUserCommand(string.sub(message, 2), ThePlayer, false)
            return
        end

        if message:utf8len() <= MAX_CHAT_INPUT_LENGTH then
            local team_id = get_team_id(ThePlayer)
            if team_id == nil then
                TheNet:Say(message, self.whisper)
                return
            end

            local encoded = TEAM_CHAT_PREFIX .. team_id
            if self.whisper then
                self.whisper = false
                send_team_message(message)
                return
            end

            TheNet:Say(encoded .. "o" .. message, false)
        end
    end
end

local function install_chat_history()
    if ChatHistory == nil then
        return
    end

    local AddToHistory = ChatHistory.AddToHistory
    function ChatHistory:AddToHistory(chat_type, sender_userid, sender_netid, sender_name, message, colour, icondata, whisper, localonly, text_filter_context, ...)
        local team_id, chat_mode = parse_team_message(message)
        if team_id ~= nil and chat_mode == "w" and ThePlayer ~= nil and not directed_team_message then
            if not can_see_team_message(ThePlayer, team_id) then
                return
            end
        end

        return AddToHistory(self, chat_type, sender_userid, sender_netid, sender_name, message, colour, icondata, whisper, localonly, text_filter_context, ...)
    end

    local GenerateChatMessage = ChatHistory.GenerateChatMessage
    function ChatHistory:GenerateChatMessage(chat_type, sender_userid, sender_netid, sender_name, message, colour, icondata, whisper, localonly, text_filter_context)
        local display_sender_name = append_character_name(sender_userid, sender_name)
        local display_message = message
        if chat_type ~= ChatTypes.Message and chat_type ~= ChatTypes.ChatterMessage then
            display_message = append_character_names_in_message(message)
        end
        local data = GenerateChatMessage(self, chat_type, sender_userid, sender_netid, display_sender_name, display_message, colour, icondata, whisper, localonly, text_filter_context)
        local team_id, chat_mode, text = parse_team_message(message)
        if team_id ~= nil and data ~= nil then
            data.message = text

            if display_sender_name ~= nil then
                data.sender = (chat_mode == "w" and "[T]" or "[A]") .. display_sender_name
                data.s_colour = team_id == 1 and TEAM_ONE_COLOUR
                    or team_id == 2 and TEAM_TWO_COLOUR
                    or OBSERVER_COLOUR
            end
        end

        return data
    end
end

local function install_talker_filter()
    AddComponentPostInit("talker", function(self)
        local Say = self.Say

        function self:Say(message, ...)
            if type(message) == "string" and string.sub(message, 1, 2) == TEAM_CHAT_PREFIX then
                return
            end
            return Say(self, message, ...)
        end
    end)
end

install_chat_input()
install_chat_history()
install_talker_filter()

AddSimPostInit(function()
    STRINGS.UI.CHATINPUTSCREEN.WHISPER = "队伍聊天:"
end)
