-- Team-grouped layout for the vanilla lobby WaitingForPlayers widget.
-- Keeps the official ready checkbox, countdown and control handling, while
-- replacing only the central portrait grid with red/blue team sections.
local Grid = require("widgets/grid")
local Image = require("widgets/image")
local PlayerAvatarPortrait = require("widgets/redux/playeravatarportrait")
local Text = require("widgets/text")
local Widget = require("widgets/widget")
local TEMPLATES = require("widgets/redux/templates")

local lobby_team_state = require("src/team/lobby_team_state")

local TEAM_OBSERVER = 0
local TEAM_RED = 1
local TEAM_BLUE = 2
local TEAM_WAITING = 3

local MAX_COLUMNS = 6
local HORIZONTAL_SPACING = 148
local VERTICAL_SPACING = 130
local SINGLE_ROW_SCALE = 0.55
local MULTI_ROW_SCALE = 0.38

local RED_TITLE_Y = 292
local RED_GRID_CENTER_Y = 150
local DIVIDER_Y = 2
local BLUE_TITLE_Y = -5
local BLUE_GRID_CENTER_Y = -140

local TEAM_COLOURS = {
    [TEAM_RED] = { 0.95, 0.30, 0.24, 1 },
    [TEAM_BLUE] = { 0.32, 0.58, 1.00, 1 },
}

local ITEM_SWAP_OVERRIDES = {
    lavaarena_lucy = "swap_lucy_axe",
    book_fossil = "",
    lavaarena_armorlight = "armor_light",
    lavaarena_armorlightspeed = "armor_lightspeed",
    lavaarena_armormedium = "armor_medium",
}

local function GetLocalUserId()
    local userid = TheNet ~= nil and TheNet:GetUserID() or nil
    return userid ~= "" and userid or nil
end

local function GetTeamForPlayer(player)
    if player == nil or player.userid == nil then
        return TEAM_WAITING
    end

    local team = lobby_team_state.get(player.userid)
    if team ~= TEAM_RED and team ~= TEAM_BLUE then
        return TEAM_WAITING
    end
    return team
end

local function SortPlayers(players)
    local local_userid = GetLocalUserId()
    table.sort(players, function(a, b)
        local a_local = local_userid ~= nil and a.userid == local_userid
        local b_local = local_userid ~= nil and b.userid == local_userid
        if a_local ~= b_local then
            return a_local
        end
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)
end

local function CreatePortrait()
    local portrait = PlayerAvatarPortrait()
    portrait.frame:SetScale(0.43)
    portrait._playerreadytext = portrait:AddChild(Text(
        CHATFONT_OUTLINE,
        20,
        STRINGS.UI.LOBBY_WAITING_FOR_PLAYERS_SCREEN.PLAYER_VOTED_TO_FORCE_START,
        UICOLOURS.GOLD
    ))
    portrait._playerreadytext:SetPosition(0, -143)
    portrait._playerreadytext:SetHAlign(ANCHOR_MIDDLE)
    portrait._playerreadytext:Hide()
    return portrait
end

local function ClearPortrait(widget)
    widget.userid = nil
    widget.performance = nil
    widget.lobbycharacter = nil
    widget:SetEmpty()
    widget._playerreadytext:Hide()
end

local function ApplyStartingItems(widget, prefab)
    if prefab == "" or prefab == "random" then
        return
    end

    local all_starting_items = TUNING.GAMEMODE_STARTING_ITEMS
    local mode_items = all_starting_items ~= nil and all_starting_items[TheNet:GetServerGameMode()] or nil
    local character_items = mode_items ~= nil and mode_items[string.upper(prefab)] or nil
    if character_items == nil then
        return
    end

    local weapon = character_items[1]
    weapon = ITEM_SWAP_OVERRIDES[weapon] or (weapon ~= nil and ("swap_" .. weapon) or nil)
    if weapon ~= nil and weapon ~= "" then
        widget.puppet.animstate:OverrideSymbol("swap_object", weapon, weapon)
        widget.puppet.animstate:Show("ARM_carry")
        widget.puppet.animstate:Hide("ARM_normal")
    else
        widget.puppet.animstate:ClearOverrideSymbol("swap_object")
        widget.puppet.animstate:Hide("ARM_carry")
        widget.puppet.animstate:Show("ARM_normal")
    end

    local armour = character_items[2]
    armour = ITEM_SWAP_OVERRIDES[armour] or armour
    if armour ~= nil and armour ~= "" then
        widget.puppet.animstate:OverrideSymbol("swap_body", armour, "swap_body")
    else
        widget.puppet.animstate:ClearOverrideSymbol("swap_body")
    end
end

local function UpdatePortrait(widget, data)
    if data == nil or next(data) == nil then
        ClearPortrait(widget)
        return
    end

    local prefab = data.lobbycharacter or data.prefab or ""
    widget.userid = data.userid
    widget.performance = data.performance
    widget.lobbycharacter = prefab
    widget:UpdatePlayerListing(
        data.name,
        data.colour,
        prefab,
        GetSkinsDataFromClientTableData(data)
    )
    ApplyStartingItems(widget, prefab)
end

local function BuildTeamSection(parent, name, title_text, colour, title_y, grid_center_y, slots)
    local section = parent:AddChild(Widget(name))

    section.title = section:AddChild(Text(HEADERFONT, 30, title_text, colour))
    section.title:SetPosition(0, title_y)

    section.line = section:AddChild(Image("images/ui.xml", "line_horizontal_6.tex"))
    section.line:SetScale(1.55, 0.22)
    section.line:SetPosition(0, title_y - 25)
    section.line:SetTint(colour[1], colour[2], colour[3], 0.85)
    section.line:SetClickable(false)

    local columns = math.max(1, math.min(MAX_COLUMNS, slots))
    local rows = math.max(1, math.ceil(slots / columns))
    local scale = rows > 1 and MULTI_ROW_SCALE or SINGLE_ROW_SCALE

    section.listing = {}
    for _ = 1, slots do
        local portrait = CreatePortrait()
        portrait:SetScale(scale)
        section.listing[#section.listing + 1] = portrait
    end

    section.grid = section:AddChild(Grid())
    section.grid:FillGrid(columns, HORIZONTAL_SPACING, VERTICAL_SPACING, section.listing)

    local grid_x = -((columns - 1) * HORIZONTAL_SPACING) * 0.5
    local grid_y = grid_center_y + ((rows - 1) * VERTICAL_SPACING) * 0.5
    section.grid:SetPosition(grid_x, grid_y)

    section.slots = slots
    return section
end

local function UpdateSection(section, players)
    section.title:SetString(section.base_title .. "  " .. tostring(#players))
    for index, portrait in ipairs(section.listing) do
        UpdatePortrait(portrait, players[index])
    end
end

local function RefreshVisibleReady(self)
    if TheWorld == nil or TheWorld.net == nil or TheWorld.net.components.worldcharacterselectlobby == nil then
        return
    end

    local lobby = TheWorld.net.components.worldcharacterselectlobby
    local full = self:IsServerFull()
    local ready_text = full
        and STRINGS.UI.LOBBY_WAITING_FOR_PLAYERS_SCREEN.PLAYER_READY_TO_START
        or STRINGS.UI.LOBBY_WAITING_FOR_PLAYERS_SCREEN.PLAYER_VOTED_TO_FORCE_START

    local function RefreshSection(section)
        for _, portrait in ipairs(section.listing) do
            if portrait.userid ~= nil and lobby:IsPlayerReadyToStart(portrait.userid) then
                portrait._playerreadytext:SetString(ready_text)
                portrait._playerreadytext:Show()
            else
                portrait._playerreadytext:Hide()
            end
        end
    end

    RefreshSection(self.bird_red_section)
    RefreshSection(self.bird_blue_section)
end

local function Install(self)
    if self.bird_team_waiting_installed then
        return
    end
    self.bird_team_waiting_installed = true

    -- Preserve the original widget and all of its non-list behaviour. Only the
    -- vanilla central portrait grid is hidden and replaced.
    if self.list_root ~= nil then
        self.list_root:Hide()
    end

    local max_players = TheNet ~= nil and TheNet:GetServerMaxPlayers() or 12
    -- Allocate enough portrait slots for a temporarily unbalanced lobby.
    -- For a 12-player server each team gets a 6x2 official portrait grid.
    local slots_per_team = math.max(1, max_players)

    self.bird_team_root = self.proot:AddChild(Widget("bird_waiting_team_root"))

    self.bird_red_section = BuildTeamSection(
        self.bird_team_root,
        "bird_waiting_red",
        "红队",
        TEAM_COLOURS[TEAM_RED],
        RED_TITLE_Y,
        RED_GRID_CENTER_Y,
        slots_per_team
    )
    self.bird_red_section.base_title = "红队"

    self.bird_blue_section = BuildTeamSection(
        self.bird_team_root,
        "bird_waiting_blue",
        "蓝队",
        TEAM_COLOURS[TEAM_BLUE],
        BLUE_TITLE_Y,
        BLUE_GRID_CENTER_Y,
        slots_per_team
    )
    self.bird_blue_section.base_title = "蓝队"

    self.bird_middle_divider = self.bird_team_root:AddChild(Image("images/ui.xml", "line_horizontal_6.tex"))
    self.bird_middle_divider:SetScale(2.55, 0.28)
    self.bird_middle_divider:SetPosition(0, DIVIDER_Y)
    self.bird_middle_divider:SetClickable(false)

    local base_refresh_players_ready = self.RefreshPlayersReady

    self.RefreshPlayersReady = function(widget)
        base_refresh_players_ready(widget)
        RefreshVisibleReady(widget)

        -- [PATCH] 原版 waitingforplayers 会仅在未连接手柄时显示准备按钮；
        -- 红蓝队玩家强制显示/启用，等待区/OB 玩家隐藏准备按钮。
        if widget.playerready_checkbox ~= nil then
            if widget.spawn_countdown_active then
                widget.playerready_checkbox:Disable()
                widget.playerready_checkbox:Hide()
            else
                local local_userid = TheNet ~= nil and TheNet:GetUserID() or nil
                local local_team = local_userid ~= nil and lobby_team_state.get(local_userid) or TEAM_WAITING
                if local_team == TEAM_WAITING or local_team == TEAM_OBSERVER then
                    widget.playerready_checkbox:Hide()
                    widget.playerready_checkbox:Disable()
                else
                    widget.playerready_checkbox:Enable()
                    widget.playerready_checkbox:Show()
                end
            end
        end
    end

    self.Refresh = function(widget, force)
        widget.players = widget:GetPlayerTable()

        local red = {}
        local blue = {}
        for _, player in ipairs(widget.players) do
            local team = GetTeamForPlayer(player)
            if team == TEAM_RED then
                red[#red + 1] = player
            elseif team == TEAM_BLUE then
                blue[#blue + 1] = player
            end
            -- Observers are intentionally omitted from the waiting panel.
        end

        SortPlayers(red)
        SortPlayers(blue)
        UpdateSection(widget.bird_red_section, red)
        UpdateSection(widget.bird_blue_section, blue)
        widget:RefreshPlayersReady()
    end

    -- [PATCH] 原版 waitingforplayers 在人未满时第一次点准备会弹确认窗，
    -- 导致等待区玩家点了没反应、不增加准备人数。此处替换为直接发送准备命令。
    if self.playerready_checkbox ~= nil then
        self.playerready_checkbox.onclick = function(widget)
            widget.checked = not widget.checked
            widget:Disable()
            widget:Refresh()

            UserCommands.RunUserCommand(
                "playerreadytostart",
                { ready = "true" },
                TheNet:GetClientTableForUser(TheNet:GetUserID())
            )

            widget.timeout_task = widget.inst:DoTaskInTime(5, function()
                widget.checked = TheWorld.net ~= nil
                    and TheWorld.net.components.worldcharacterselectlobby:IsPlayerReadyToStart(TheNet:GetUserID())
                    or false
                widget:Enable()
                widget:Refresh()
            end)
        end
    end

    self:Refresh(true)
end

return Install
