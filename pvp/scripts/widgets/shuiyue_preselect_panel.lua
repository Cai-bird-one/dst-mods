local Grid = require "widgets/grid"
local Image = require "widgets/image"
local PlayerAvatarPortrait = require "widgets/redux/playeravatarportrait"
local Widget = require "widgets/widget"
local UserCommands = require "usercommands"
local Text = require "widgets/text"

local TEMPLATES = require "widgets/redux/templates"

local lobby_team_state = require "src/team/lobby_team_state"

local TEAM_OBSERVER = 0
local TEAM_RED = 1
local TEAM_BLUE = 2
local TEAM_WAITING = 3

-- Waiting-area layout: red team left, blue team right.
local SECTION_WIDTH = 410
local SECTION_HEIGHT = 430
local MAX_COLUMNS = 3
local PORTRAIT_BASE_WIDTH = 324 * 0.43
local PORTRAIT_BASE_HEIGHT = 511 * 0.43
local PORTRAIT_X_STEP = PORTRAIT_BASE_WIDTH + 110.68
local PORTRAIT_Y_STEP = PORTRAIT_BASE_HEIGHT + 50

local RED_COLUMN_X = -230
local BLUE_COLUMN_X = 230
local TEAM_TITLE_Y = 245
local TEAM_GRID_CENTER_Y = 25
local DIVIDER_X = 0
local DIVIDER_Y = 25

local TEAM_COLOURS = {
    [TEAM_RED] = { 0.95, 0.30, 0.24, 1 },
    [TEAM_BLUE] = { 0.32, 0.58, 1.00, 1 },
}

local item_swap_overrides =
{
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
    if team == TEAM_RED or team == TEAM_BLUE then
        return team
    end

    return TEAM_WAITING
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
    portrait.frame:SetScale(.43)
    portrait._playerreadytext = portrait:AddChild(Text(
        CHATFONT_OUTLINE,
        20,
        STRINGS.UI.LOBBY_WAITING_FOR_PLAYERS_SCREEN.PLAYER_READY_TO_START,
        UICOLOURS.GOLD
    ))
    portrait._playerreadytext:SetPosition(0, -143)
    portrait._playerreadytext:SetHAlign(ANCHOR_MIDDLE)
    portrait._playerreadytext:Hide()
    return portrait
end

local function ClearPortrait(widget)
    widget:Hide()
    widget.userid = nil
    widget.performance = nil
    widget._playerreadytext:Hide()
end

local function ClearStartingItems(widget)
    if widget.puppet == nil or widget.puppet.animstate == nil then
        return
    end

    widget.puppet.animstate:ClearOverrideSymbol("swap_object")
    widget.puppet.animstate:Hide("ARM_carry")
    widget.puppet.animstate:Show("ARM_normal")
    widget.puppet.animstate:ClearOverrideSymbol("swap_body")
end

local function ApplyStartingItems(widget, prefab)
    ClearStartingItems(widget)

    if prefab == nil or prefab == "" or prefab == "random" then
        return
    end

    local all_starting_items = TUNING.GAMEMODE_STARTING_ITEMS
    local mode_items = all_starting_items ~= nil and all_starting_items[TheNet:GetServerGameMode()] or nil
    local character_items = mode_items ~= nil and mode_items[string.upper(prefab)] or nil
    if character_items == nil then
        return
    end

    local weapon = character_items[1]
    weapon = item_swap_overrides[weapon] or (weapon ~= nil and ("swap_" .. weapon) or nil)
    if weapon ~= nil and weapon ~= "" then
        widget.puppet.animstate:OverrideSymbol("swap_object", weapon, weapon)
        widget.puppet.animstate:Show("ARM_carry")
        widget.puppet.animstate:Hide("ARM_normal")
    end

    local armour = character_items[2]
    armour = item_swap_overrides[armour] or armour
    if armour ~= nil and armour ~= "" then
        widget.puppet.animstate:OverrideSymbol("swap_body", armour, "swap_body")
    end
end

local function UpdatePortrait(widget, player)
    widget.userid = player.userid
    widget.performance = player.performance

    local prefab = player.lobbycharacter or player.prefab or ""
    widget:UpdatePlayerListing(
        player.name,
        player.colour,
        prefab,
        GetSkinsDataFromClientTableData(player)
    )
    ApplyStartingItems(widget, prefab)
    widget:Show()
end

local function CalculateLayout(player_count)
    if player_count <= 0 then
        return 1, 1, 1
    end

    local columns = math.min(MAX_COLUMNS, player_count)
    local rows = math.ceil(player_count / columns)

    -- Reduce columns when doing so keeps the same row count and centres the grid.
    while columns > 1 and math.ceil(player_count / (columns - 1)) == rows do
        columns = columns - 1
    end

    local required_width = PORTRAIT_BASE_WIDTH + (columns - 1) * PORTRAIT_X_STEP
    local required_height = PORTRAIT_BASE_HEIGHT + (rows - 1) * PORTRAIT_Y_STEP
    local scale = math.min(1, SECTION_WIDTH / required_width, SECTION_HEIGHT / required_height)

    return columns, rows, scale
end

local function LayoutTeam(grid, widgets, center_x, center_y)
    local count = #widgets
    if count == 0 then
        -- Remove the previous team's portraits. Grid:Clear kills its children,
        -- so callers must discard all references to those old widgets.
        grid:Clear()
        grid:Hide()
        return
    end

    local columns, rows, scale = CalculateLayout(count)
    for _, widget in ipairs(widgets) do
        widget:SetScale(scale)
    end

    local x_step = PORTRAIT_X_STEP * scale
    local y_step = PORTRAIT_Y_STEP * scale
    grid:FillGrid(columns, x_step, y_step, widgets)
    grid:SetPosition(
        center_x - x_step * (columns - 1) / 2,
        center_y + y_step * (rows - 1) / 2
    )
    grid:Show()
end

local WaitingForPlayers = Class(Widget, function(self, owner, max_players)
    self.owner = owner
    Widget._ctor(self, "WaitingForPlayers")

    self.players = self:GetPlayerTable()
    self.proot = self:AddChild(Widget("ROOT"))

    -- Grid:FillGrid owns and destroys its child widgets whenever it is rebuilt.
    -- Keep only the portraits from the latest rebuild; never reuse widgets that
    -- a previous FillGrid call has already killed.
    self.red_player_listing = {}
    self.blue_player_listing = {}
    self.player_listing = {}
    self.player_listing_signature = nil

    self.red_title = self.proot:AddChild(Text(HEADERFONT, 30, "红队  0", TEAM_COLOURS[TEAM_RED]))
    self.red_title:SetPosition(RED_COLUMN_X, TEAM_TITLE_Y)

    self.blue_title = self.proot:AddChild(Text(HEADERFONT, 30, "蓝队  0", TEAM_COLOURS[TEAM_BLUE]))
    self.blue_title:SetPosition(BLUE_COLUMN_X, TEAM_TITLE_Y)

    -- [PATCH] 在红队与蓝队标题中间放置等待标题/已准备人数，替代原版偏左的标题。
    self.title_text = self.proot:AddChild(Text(HEADERFONT, 32, "", UICOLOURS.GOLD))
    self.title_text:SetPosition(0, TEAM_TITLE_Y - 35)
    self.title_text:SetHAlign(ANCHOR_MIDDLE)

    self.team_divider = self.proot:AddChild(Image("images/ui.xml", "line_horizontal_6.tex"))
    self.team_divider:SetScale(1.8, .25)
    self.team_divider:SetRotation(90)
    self.team_divider:SetPosition(DIVIDER_X, DIVIDER_Y)
    self.team_divider:SetClickable(false)

    self.red_list_root = self.proot:AddChild(Grid())
    self.blue_list_root = self.proot:AddChild(Grid())
    self:UpdatePlayerListing(true)

    local function playerready_checkbox_onclicked(widget)
        widget.checked = not widget.checked
        widget:Disable()
        widget:Refresh()

        UserCommands.RunUserCommand("playerreadytostart", { ready = "true" }, TheNet:GetClientTableForUser(TheNet:GetUserID()))
        widget.timeout_task = widget.inst:DoTaskInTime(5, function()
            widget.checked = TheWorld.net ~= nil
                and TheWorld.net.components.worldcharacterselectlobby:IsPlayerReadyToStart(TheNet:GetUserID())
                or false
            widget:Enable()
            widget:Refresh()
        end)
    end

    local playerready_checkbox = self:AddChild(TEMPLATES.LabelCheckbox(playerready_checkbox_onclicked, false, ""))
    playerready_checkbox.votestart_warned = false
    playerready_checkbox.RecenterCheckbox = function()
        local text_width = playerready_checkbox.text:GetRegionSize()
        playerready_checkbox.text:SetPosition(playerready_checkbox._text_offset + text_width / 2, 0)
        playerready_checkbox:SetPosition(-text_width / 2, -314)
    end

    self.inst:ListenForEvent("player_ready_to_start_dirty", function(net)
        if net.components.worldcharacterselectlobby:IsPlayerReadyToStart(TheNet:GetUserID()) == playerready_checkbox.checked then
            if playerready_checkbox.timeout_task ~= nil then
                playerready_checkbox.timeout_task:Cancel()
                playerready_checkbox.timeout_task = nil
            end
            playerready_checkbox:Enable()
        elseif playerready_checkbox.timeout_task == nil then
            playerready_checkbox.checked = net.components.worldcharacterselectlobby:IsPlayerReadyToStart(TheNet:GetUserID())
            playerready_checkbox:Enable()
            playerready_checkbox:Refresh()
        end
    end, TheWorld.net)

    self.playerready_checkbox = playerready_checkbox
    self.playerready_checkbox:Hide()

    local spawndelaytext = self:AddChild(Text(CHATFONT, 50))
    spawndelaytext:SetPosition(0, -290)
    spawndelaytext:SetColour(UICOLOURS.GOLD)
    spawndelaytext:Hide()

    self:RefreshPlayersReady()

    self.inst:ListenForEvent("player_ready_to_start_dirty", function()
        self:RefreshPlayersReady()
        self:UpdatePlayerListing()
    end, TheWorld.net)

    self.inst:ListenForEvent("lobbyplayerspawndelay", function(_, data)
        if data and data.active then
            self.spawn_countdown_active = true
            self:RefreshPlayersReady()
            self:UpdatePlayerListing()

            local str = subfmt(
                STRINGS.UI.LOBBY_WAITING_FOR_PLAYERS_SCREEN.SPAWN_DELAY,
                { time = math.max(0, data.time - 1) }
            )
            if str ~= spawndelaytext:GetString() or not spawndelaytext.shown then
                spawndelaytext:SetString(str)
                spawndelaytext:Show()
                TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/WorldDeathTick")
            end
        end
    end, TheWorld)
end)

local function BuildPlayerListingSignature(players)
    local parts = {
        tostring(lobby_team_state.get_revision ~= nil and lobby_team_state.get_revision() or 0),
    }

    for _, player in ipairs(players) do
        if player ~= nil then
            table.insert(parts, table.concat({
                tostring(player.userid or ""),
                tostring(player.name or ""),
                tostring(player.lobbycharacter or player.prefab or ""),
                tostring(GetTeamForPlayer(player)),
                tostring(player.skin_base or player.base_skin or ""),
                tostring(player.skin_body or player.body_skin or ""),
                tostring(player.skin_hand or player.hand_skin or ""),
                tostring(player.skin_legs or player.legs_skin or ""),
                tostring(player.skin_feet or player.feet_skin or ""),
            }, ":"))
        end
    end

    return table.concat(parts, "|")
end

function WaitingForPlayers:UpdatePlayerListing(force)
    local players = self:GetPlayerTable() or {}
    self.players = players

    local signature = BuildPlayerListingSignature(players)
    if not force and signature == self.player_listing_signature then
        return
    end
    self.player_listing_signature = signature

    local red_players = {}
    local blue_players = {}

    for _, player in ipairs(players) do
        if player ~= nil and player.userid ~= nil then
            local team = GetTeamForPlayer(player)
            if team == TEAM_RED then
                table.insert(red_players, player)
            elseif team == TEAM_BLUE then
                table.insert(blue_players, player)
            end
            -- Observers are intentionally not displayed in this panel.
        end
    end

    SortPlayers(red_players)
    SortPlayers(blue_players)

    -- Create fresh portraits for this rebuild. FillGrid clears and kills the
    -- previous children, so reusing the old portrait objects is invalid.
    local red_widgets = {}
    for _, player in ipairs(red_players) do
        local widget = CreatePortrait()
        UpdatePortrait(widget, player)
        table.insert(red_widgets, widget)
    end

    local blue_widgets = {}
    for _, player in ipairs(blue_players) do
        local widget = CreatePortrait()
        UpdatePortrait(widget, player)
        table.insert(blue_widgets, widget)
    end

    self.red_title:SetString("红队  " .. tostring(#red_players))
    self.blue_title:SetString("蓝队  " .. tostring(#blue_players))

    LayoutTeam(self.red_list_root, red_widgets, RED_COLUMN_X, TEAM_GRID_CENTER_Y)
    LayoutTeam(self.blue_list_root, blue_widgets, BLUE_COLUMN_X, TEAM_GRID_CENTER_Y)

    self.red_player_listing = red_widgets
    self.blue_player_listing = blue_widgets
    self.player_listing = {}
    for _, widget in ipairs(red_widgets) do
        table.insert(self.player_listing, widget)
    end
    for _, widget in ipairs(blue_widgets) do
        table.insert(self.player_listing, widget)
    end

    -- New portrait widgets need their ready marker applied immediately.
    if self.playerready_checkbox ~= nil then
        self:RefreshPlayersReady()
    end
end

function WaitingForPlayers:Refresh()
    self:UpdatePlayerListing()
    self:RefreshPlayersReady()
end

function WaitingForPlayers:SetTitle(title)
    if self.title_text ~= nil then
        self.title_text:SetString(title or "")
    end
end

function WaitingForPlayers:IsServerFull()
    return #self.players == TheNet:GetServerMaxPlayers()
end

function WaitingForPlayers:GetPlayerTable()
    local source = TheNet:GetClientTable()
    if source == nil then
        return {}
    end

    local clients = {}
    for _, client in ipairs(source) do
        if client.userid ~= nil and client.userid ~= "" then
            table.insert(clients, client)
        end
    end

    if not TheNet:GetServerIsClientHosted() then
        for index = #clients, 1, -1 do
            if clients[index].performance ~= nil then
                table.remove(clients, index)
            end
        end
    end

    if self.show_local_player_first then
        local local_user_id = TheNet:GetUserID()
        table.sort(clients, function(a, b)
            return a.userid == local_user_id and b.userid ~= local_user_id
        end)
    end

    return clients
end

function WaitingForPlayers:RefreshPlayersReady()
    local lobby = TheWorld.net ~= nil
        and TheWorld.net.components.worldcharacterselectlobby
        or nil

    for _, widget in ipairs(self.player_listing) do
        if lobby ~= nil and widget.userid ~= nil and lobby:IsPlayerReadyToStart(widget.userid) then
            widget._playerreadytext:SetString(STRINGS.UI.LOBBY_WAITING_FOR_PLAYERS_SCREEN.PLAYER_READY_TO_START)
            widget._playerreadytext:Show()
        else
            widget._playerreadytext:Hide()
        end
    end

    -- [PATCH] 加存在性保护，避免出生倒计时事件触发时组件尚未初始化而报错。
    if self.playerready_checkbox == nil then
        return
    end

    if self.spawn_countdown_active then
        if self.playerready_checkbox.timeout_task ~= nil then
            self.playerready_checkbox.timeout_task:Cancel()
            self.playerready_checkbox.timeout_task = nil
        end
        self.playerready_checkbox:Disable()
        self.playerready_checkbox:Hide()
    else
        -- [PATCH] 等待区/OB 玩家不显示准备按钮，点准备无效；红蓝队玩家正常显示。
        local local_userid = TheNet ~= nil and TheNet:GetUserID() or nil
        local local_team = local_userid ~= nil and lobby_team_state.get(local_userid) or TEAM_WAITING
        if local_team == TEAM_WAITING or local_team == TEAM_OBSERVER then
            self.playerready_checkbox:Hide()
            self.playerready_checkbox:Disable()
        else
            self.playerready_checkbox:SetText(STRINGS.UI.LOBBY_WAITING_FOR_PLAYERS_SCREEN.LOCAL_PLAYER_READY_TO_START)
            -- [PATCH] 准备按钮应对所有玩家可见，不再因手柄连接而隐藏。
            self.playerready_checkbox:RecenterCheckbox()
            self.playerready_checkbox:Show()
            self.playerready_checkbox:Enable()
        end
    end
end

function WaitingForPlayers:OnControl(control, down)
    if Widget.OnControl(self, control, down) then
        return true
    end

    if not down and control == CONTROL_PAUSE then
        if self.playerready_checkbox:IsEnabled() then
            self.playerready_checkbox.onclick()
        end
        return true
    end
end

function WaitingForPlayers:GetHelpText()
    local controller_id = TheInput:GetControllerID()
    local help = {}

    if self.playerready_checkbox:IsEnabled() then
        local text = STRINGS.UI.LOBBY_WAITING_FOR_PLAYERS_SCREEN.LOCAL_PLAYER_READY_CANCEL_HELPTEXT
        if not self.playerready_checkbox.checked then
            text = self:IsServerFull()
                and STRINGS.UI.LOBBY_WAITING_FOR_PLAYERS_SCREEN.LOCAL_PLAYER_READY_TO_START
                or subfmt(
                    STRINGS.UI.LOBBY_WAITING_FOR_PLAYERS_SCREEN.LOCAL_PLAYER_VOTE_TO_START,
                    { num = #self.players, max = TheNet:GetServerMaxPlayers() }
                )
        end
        table.insert(help, TheInput:GetLocalizedControl(controller_id, CONTROL_PAUSE) .. " " .. text)
    end

    return table.concat(help, "  ")
end

return WaitingForPlayers
