-- ESC surrender entry and the original-style top-right vote dialog.
local team_state = require("src/team/lobby_team_state")
local player_state = require("src/team/player_state")
local protocol = require("src/gameplay/surrender_protocol")
local ImageButton = require("widgets/imagebutton")

local TEAM_NAMES = {
    [team_state.TEAM_RED] = "红队",
    [team_state.TEAM_BLUE] = "蓝队",
}
local TEAM_COLOURS = {
    [team_state.TEAM_RED] = { 1, 0, 0, 1 },
    [team_state.TEAM_BLUE] = { 25 / 255, 88 / 255, 1, 1 },
}

local function GetPlayerTeam(player)
    local team_id, pending = team_state.get_player_team(player, nil)
    if pending or not team_state.is_playing_team(team_id) then
        return nil
    end
    return team_id
end

local function SendServerRPC(name, value)
    if SendModRPCToServer == nil or GetModRPC == nil then
        return false
    end
    local rpc = GetModRPC(protocol.RPC_NAMESPACE, name)
    if rpc == nil then
        return false
    end
    if value == nil then
        SendModRPCToServer(rpc)
    else
        SendModRPCToServer(rpc, value)
    end
    return true
end

local function ReadVoteState(owner)
    local network = TheWorld ~= nil and TheWorld.net or nil
    if network == nil
        or network._bird_surrender_active == nil
        or not network._bird_surrender_active:value() then
        return nil
    end

    local team_id = tonumber(network._bird_surrender_team:value())
    if not team_state.is_playing_team(team_id) then
        return nil
    end

    return {
        active = true,
        team_id = team_id,
        team_name = TEAM_NAMES[team_id],
        team_colour = TEAM_COLOURS[team_id],
        remaining = tonumber(network._bird_surrender_remaining:value()) or 0,
        yes_units = tonumber(network._bird_surrender_yes_units:value()) or 0,
        no_units = tonumber(network._bird_surrender_no_units:value()) or 0,
        starter_name = network._bird_surrender_starter:value(),
        serial = tonumber(network._bird_surrender_serial:value()) or 0,
        canvote = GetPlayerTeam(owner) == team_id,
    }
end

local function IsVoteActive()
    local network = TheWorld ~= nil and TheWorld.net or nil
    return network ~= nil
        and network._bird_surrender_active ~= nil
        and network._bird_surrender_active:value()
end

local function ReflowPauseMenu(screen)
    local menu = screen.menu
    if menu == nil or menu.items == nil then
        return
    end

    local count = #menu.items
    local spacing = count >= 10 and 44 or 50
    menu.offset = -spacing
    for index, item in ipairs(menu.items) do
        item:SetPosition(0, -spacing * (index - 1), 0)
        item:SetScale(0.7)
    end
    menu:DoFocusHookups()
    menu:SetPosition(0, spacing * (count - 1) / 2, 0)

    if screen.bg ~= nil and screen.bg.SetSize ~= nil then
        screen.bg:SetSize(190, math.min(500, spacing * count + 30))
    end
end

local function AddSurrenderButton(screen)
    if screen == nil
        or screen.menu == nil
        or screen._bird_surrender_button ~= nil
        or GetPlayerTeam(screen.owner) == nil then
        return
    end

    local button = screen.menu:AddItem("投降", function()
        if screen.active == false then
            return
        end
        SendServerRPC(protocol.MOD_RPC_START)
        screen:unpause()
    end)
    screen._bird_surrender_button = button

    -- Append at the bottom while keeping the original close action last.
    local items = screen.menu.items
    table.remove(items, #items)
    table.insert(items, math.max(1, #items), button)

    if IsVoteActive() then
        button:Disable()
    end
    ReflowPauseMenu(screen)
end

AddClassPostConstruct("screens/redux/pausescreen", function(screen)
    local BuildMenu = screen.BuildMenu
    screen.BuildMenu = function(self, ...)
        self._bird_surrender_button = nil
        BuildMenu(self, ...)
        AddSurrenderButton(self)
    end
    AddSurrenderButton(screen)
end)

AddClassPostConstruct("widgets/controls", function(controls)
    local dialog = controls.votedialog
    if dialog == nil or controls.owner == nil or dialog._bird_surrender_installed then
        return
    end
    dialog._bird_surrender_installed = true

    local close_button = dialog.dialogroot:AddChild(ImageButton(
        "images/global_redux.xml",
        "close.tex"
    ))
    close_button:SetNormalScale(0.6)
    close_button:SetFocusScale(0.66)
    close_button:SetImageNormalColour(0.9, 0.9, 0.9, 1)
    close_button:SetHoverText(STRINGS.UI.HELP.CLOSE)
    close_button:Hide()

    local function PositionCloseButton()
        local fill_dist = dialog.num_options > 0
            and dialog.num_options * dialog.bg.filler_size
            or 0
        close_button:SetPosition(
            150,
            0.5 * fill_dist + 0.82 * dialog.bg.start_cap_size,
            0
        )
    end

    close_button:SetOnClick(function()
        if not dialog._bird_surrender_visible then
            return
        end
        dialog._bird_surrender_dismissed_serial = dialog._bird_surrender_serial
        dialog._bird_surrender_visible = false
        close_button:Hide()
        dialog:HideDialog()
    end)

    local function BuildOptionData(data)
        return {
            name = "bird_surrender",
            starterclient = {
                name = data.starter_name or "",
                colour = data.team_colour or { 0, 0, 0, 1 },
            },
            votetitlefmt = (data.team_name or "队伍") .. "投降投票",
            options = {
                { description = "是 (" .. protocol.format_units(data.yes_units) .. ")" },
                { description = "否 (" .. protocol.format_units(data.no_units) .. ")" },
            },
        }
    end

    for index, button in ipairs(dialog.buttons or {}) do
        local selection = index
        local native_onclick = button.onclick
        button:SetOnClick(function()
            if not dialog._bird_surrender_visible then
                if native_onclick ~= nil then
                    native_onclick()
                end
                return
            end

            if selection <= 2
                and dialog.started
                and dialog.settled
                and dialog._bird_surrender_canvote
                and dialog._bird_surrender_selection == nil then
                dialog._bird_surrender_selection = selection
                dialog._bird_surrender_canvote = false
                dialog:UpdateSelection(selection, false)
                SendServerRPC(protocol.MOD_RPC_VOTE, selection)
            end
        end)
    end

    local function RefreshVoteDialog()
        local data = ReadVoteState(controls.owner)
        if data == nil then
            if dialog._bird_surrender_active then
                local was_visible = dialog._bird_surrender_visible
                dialog._bird_surrender_active = false
                dialog._bird_surrender_visible = false
                dialog._bird_surrender_serial = nil
                dialog._bird_surrender_dismissed_serial = nil
                dialog._bird_surrender_selection = nil
                dialog._bird_surrender_canvote = false
                close_button:Hide()
                if was_visible then
                    dialog:HideDialog()
                end
            end
            return
        end

        local option_data = BuildOptionData(data)
        if not dialog._bird_surrender_active or dialog._bird_surrender_serial ~= data.serial then
            dialog._bird_surrender_active = true
            dialog._bird_surrender_visible = true
            dialog._bird_surrender_serial = data.serial
            dialog._bird_surrender_dismissed_serial = nil
            dialog._bird_surrender_selection = nil
            dialog:ShowDialog(option_data)
            PositionCloseButton()
            close_button:Show()
        elseif dialog._bird_surrender_dismissed_serial == data.serial then
            return
        else
            dialog:UpdateOptions(option_data)
            PositionCloseButton()
            close_button:Show()
        end

        dialog:UpdateTimer(math.max(0, data.remaining or 0))
        dialog._bird_surrender_canvote = data.canvote == true
            and dialog._bird_surrender_selection == nil
        dialog:UpdateSelection(
            dialog._bird_surrender_selection,
            dialog._bird_surrender_canvote
        )
    end

    dialog.inst:ListenForEvent("showvotedialog", function()
        if dialog._bird_surrender_visible then
            dialog._bird_surrender_dismissed_serial = dialog._bird_surrender_serial
            dialog._bird_surrender_visible = false
            close_button:Hide()
        end
    end, TheWorld)

    local network = TheWorld ~= nil and TheWorld.net or nil
    if network ~= nil then
        controls.inst:ListenForEvent(protocol.NET_DIRTY_EVENT, RefreshVoteDialog, network)
    end
    controls.owner:ListenForEvent(player_state.EVENT_READY, RefreshVoteDialog)
    controls.owner:ListenForEvent(player_state.EVENT_PENDING, RefreshVoteDialog)
    RefreshVoteDialog()
    controls.inst:DoTaskInTime(0, RefreshVoteDialog)
end)
