local UserCommands = require "usercommands"
local Widget = require "widgets/widget"

local function IsRegularLobby()
    return TheNet ~= nil and TheNet:GetServerGameMode() == "survival"
end

-- [PATCH] 隐藏选人界面原版地形预览/世界预览小窗口，避免与 PVP 选人界面重叠。
-- 通过递归查找常见命名并隐藏；同时打印未命中名称便于后续精确匹配。
local TERRAIN_PREVIEW_NAMES = {
    "world_preview",
    "server_preview",
    "map_preview",
    "terrain_preview",
    "worldsettings",
    "server_settings",
    "world_regen",
    "preview",
}

local TERRAIN_PREVIEW_TEXTS = {
    "地形预览",
    "world preview",
    "terrain preview",
    "预览",
    "preview",
}

local function get_widget_text(widget)
    if widget == nil then
        return nil
    end
    if widget.GetString ~= nil then
        return widget:GetString()
    elseif widget.text ~= nil and widget.text.GetString ~= nil then
        return widget.text:GetString()
    end
    return nil
end

local function text_contains_any(str, texts)
    if str == nil then
        return false
    end
    str = string.lower(tostring(str))
    for _, t in ipairs(texts) do
        if str:find(t, 1, true) then
            return true
        end
    end
    return false
end

local function is_button_like(widget)
    if widget == nil then
        return false
    end
    -- ImageButton / StandardButton 常见特征。
    return widget.SetOnClick ~= nil
        or widget.onclick ~= nil
        or (widget.name ~= nil and string.find(string.lower(tostring(widget.name)), "button", 1, true))
end

local function hide_terrain_preview_widget(widget)
    if widget == nil then
        return
    end
    if widget.Hide ~= nil then
        widget:Hide()
    end
    if widget.SetClickable ~= nil then
        widget:SetClickable(false)
    end
end

local function hide_terrain_preview_recursive(root, depth)
    if root == nil or depth == nil then
        depth = 0
    end
    if depth > 12 then
        return false
    end

    local matched = false

    -- 1. 按控件名匹配常见预览命名。
    if root.name ~= nil then
        local name = string.lower(tostring(root.name))
        for _, pattern in ipairs(TERRAIN_PREVIEW_NAMES) do
            if name:find(pattern, 1, true) then
                print("[preselect] hide terrain preview widget by name:", root.name)
                hide_terrain_preview_widget(root)
                matched = true
                break
            end
        end
    end

    -- 2. 如果当前控件自身文本匹配，隐藏自身。
    if not matched and text_contains_any(get_widget_text(root), TERRAIN_PREVIEW_TEXTS) then
        print("[preselect] hide terrain preview widget by text:", root.name)
        hide_terrain_preview_widget(root)
        matched = true
    end

    -- 3. 如果当前控件是按钮且任意后代文本匹配，隐藏该按钮。
    if not matched and is_button_like(root) then
        local child_text_matched = false
        local children = root.children
        if children ~= nil then
            for _, child in ipairs(children) do
                if text_contains_any(get_widget_text(child), TERRAIN_PREVIEW_TEXTS)
                    or hide_terrain_preview_recursive(child, depth + 1) then
                    child_text_matched = true
                    break
                end
            end
        end
        if child_text_matched then
            print("[preselect] hide terrain preview button:", root.name)
            hide_terrain_preview_widget(root)
            matched = true
        end
    end

    -- 4. 继续递归非按钮后代。
    if not matched then
        local children = root.children
        if children ~= nil then
            for _, child in ipairs(children) do
                if hide_terrain_preview_recursive(child, depth + 1) then
                    matched = true
                end
            end
        end
    end

    return matched
end

local function hide_lobby_terrain_preview(screen)
    if screen == nil then
        return
    end
    print("[preselect] scanning lobby screen children for terrain preview")
    hide_terrain_preview_recursive(screen, 0)
end

local function GetWorldLobby()
    return TheWorld ~= nil
        and TheWorld.net ~= nil
        and TheWorld.net.components ~= nil
        and TheWorld.net.components.worldcharacterselectlobby
        or nil
end

local function GetClientUser()
    if TheNet == nil then
        return nil
    end

    local userid = TheNet:GetUserID()
    return userid ~= nil and TheNet:GetClientTableForUser(userid) or nil
end

local function IsValidStartCharacter(character)
    return type(character) == "string" and character ~= ""
end

local function GetCurrentSelectedCharacter(owner)
    if owner == nil then
        return nil
    end

    if IsValidStartCharacter(owner.character_for_game) then
        return owner.character_for_game
    end

    local client = GetClientUser()
    if client ~= nil and IsValidStartCharacter(client.lobbycharacter) then
        return client.lobbycharacter
    end

    if IsValidStartCharacter(owner.lobbycharacter) then
        return owner.lobbycharacter
    end
    if IsValidStartCharacter(owner.cached_currentcharacter) then
        return owner.cached_currentcharacter
    end
    if owner.loadout ~= nil and IsValidStartCharacter(owner.loadout.currentcharacter) then
        return owner.loadout.currentcharacter
    end
    if owner.panel ~= nil
        and owner.panel.loadout ~= nil
        and IsValidStartCharacter(owner.panel.loadout.currentcharacter) then
        return owner.panel.loadout.currentcharacter
    end
    if owner.character_scroll_list ~= nil
        and owner.character_scroll_list.selectedportrait ~= nil
        and IsValidStartCharacter(owner.character_scroll_list.selectedportrait.currentcharacter) then
        return owner.character_scroll_list.selectedportrait.currentcharacter
    end

    return nil
end

local function InstallWorldCharacterSelectLobby(inst)
    if inst.components.worldcharacterselectlobby == nil then
        inst:AddComponent("worldcharacterselectlobby")
    end

    local lobby = inst.components.worldcharacterselectlobby
    lobby.MIN_PLAYERS = GetModConfigData("MIN_PLAYERS") or 2
    -- [PATCH] 强制为“全员准备”模式：管理员点准备不会立刻开局，必须所有玩家都准备才能开始。
    lobby.ADMIN_MODE = "ALL"
    lobby.LATE_JOIN = GetModConfigData("LATE_JOIN") ~= false
    lobby.KEEP_PAUSED_AFTER_START = GetModConfigData("KEEP_PAUSED_AFTER_START") ~= false
end

AddPrefabPostInit("forest_network", InstallWorldCharacterSelectLobby)

local function EnsureStartGameLoadout(owner)
    owner.currentskins = owner.currentskins or {}

    local character = GetCurrentSelectedCharacter(owner)
    if character ~= nil then
        owner.character_for_game = character
    end

    local loadout = owner.panel ~= nil and owner.panel.loadout or owner.loadout
    if loadout ~= nil then
        if loadout.selected_skins ~= nil then
            owner.currentskins = loadout.selected_skins
        end
        if IsValidStartCharacter(loadout.currentcharacter) then
            owner.character_for_game = loadout.currentcharacter
        end
    end

    owner.currentskins = owner.currentskins or {}
    return IsValidStartCharacter(owner.character_for_game)
end

local function SetStartButton(owner)
    if owner.next_button ~= nil then
        owner.next_button:SetText(STRINGS.UI.LOBBYSCREEN.START)
        owner.next_button:Enable()
        if not TheInput:ControllerAttached() then
            owner.next_button:Show()
        end
    end
end

local function StartGame(owner)
    if not EnsureStartGameLoadout(owner) then
        SetStartButton(owner)
        return false
    end

    if owner.next_button ~= nil then
        owner.next_button:Disable()
    end

    if owner.cb ~= nil then
        local skins = owner.currentskins or {}
        owner.cb(owner.character_for_game, skins.base, skins.body, skins.hand, skins.legs, skins.feet)
        return true
    end

    SetStartButton(owner)
    return false
end


local function FinalizeLoadout(owner, panel, game_started)
    owner.currentskins = panel.loadout.selected_skins or {}
    owner.character_for_game = panel.loadout.currentcharacter
    local selected_character = owner.character_for_game

    if not IsValidStartCharacter(owner.character_for_game) then
        SetStartButton(owner)
        return false
    end

    owner.profile:SetCollectionTimestamp(GetInventoryTimestamp())

    if not IsCharacterOwned(owner.character_for_game) then
        DisplayCharacterUnownedPopup(owner.character_for_game, panel.loadout.subscreener)
        return false
    end

    if owner.character_for_game == "random" then
        local char_list = GetActiveCharacterList()
        for i = #char_list, 1, -1 do
            if not IsCharacterOwned(char_list[i]) then
                table.remove(char_list, i)
            end
        end

        local all_chars = ExceptionArrays(char_list, MODCHARACTEREXCEPTIONS_DST)
        owner.character_for_game = all_chars[math.random(#all_chars)]

        local bases = owner.profile:GetSkinsForPrefab(owner.character_for_game)
        owner.currentskins.base = GetRandomItem(bases)
    else
        panel.loadout:_SaveLoadout()
    end

    if not game_started then
        if selected_character == "random" then
            TheNet:SendLobbyCharacterRequestToServer("random")
        else
            local skins = owner.currentskins
            TheNet:SendLobbyCharacterRequestToServer(
                owner.character_for_game,
                skins.base,
                skins.body,
                skins.hand,
                skins.legs,
                skins.feet
            )
        end
    end

    return true
end
local function WrapLoadoutPanel(panel_def)
    local old_panelfn = panel_def.panelfn

    panel_def.panelfn = function(owner)
        local panel = old_panelfn(owner)
        panel.next_button_title = STRINGS.UI.LOBBYSCREEN.SELECT

        local function RefreshButtonTitle(data)
            local lobby = GetWorldLobby()
            if data ~= nil and data.time == 0 or lobby ~= nil and lobby:HasGameStarted() then
                panel.next_button_title = STRINGS.UI.LOBBYSCREEN.START
            else
                panel.next_button_title = STRINGS.UI.LOBBYSCREEN.SELECT
            end

            if owner.next_button ~= nil then
                owner.next_button:SetText(panel.next_button_title)
            end
        end

        panel.inst:ListenForEvent("lobbyplayerspawndelay", function(_, data)
            RefreshButtonTitle(data)
        end, TheWorld)
        RefreshButtonTitle()

        function panel:OnNextButton()
            local lobby = GetWorldLobby()
            local game_started = lobby ~= nil and lobby:HasGameStarted()
            if not FinalizeLoadout(owner, self, game_started) then
                return false
            end

            if game_started then
                StartGame(owner)
                return false
            end

            return true
        end

        function panel:GetHelpText()
            local controller_id = TheInput:GetControllerID()
            return TheInput:GetLocalizedControl(controller_id, CONTROL_MENU_START).."  "..self.next_button_title
        end

        return panel
    end
end

local function GetReadyCount(lobby)
    return lobby ~= nil and lobby.CountPlayersReadyToStart ~= nil and lobby:CountPlayersReadyToStart() or 0
end

local function GetWaitingTitle()
    local lobby = GetWorldLobby()
    if lobby == nil then
        return STRINGS.UI.LOBBYSCREEN.WAITING_FOR_PLAYERS_TITLE
    end

    local mode = lobby.ADMIN_MODE
    local ready_count = GetReadyCount(lobby)
    local min_players = lobby.MIN_PLAYERS or 2
    local player_count = TheNet:GetPlayerCount()

    if mode == "ALL" then
        return STRINGS.UI.LOBBYSCREEN.WAITING_FOR_PLAYERS_TITLE.." ("..subfmt(STRINGS.UI.LOBBYSCREEN.NUM_PLAYERS_FMT, { num = ready_count, max = math.max(min_players, player_count) })..")"
    elseif mode == "MIN" then
        return STRINGS.UI.LOBBYSCREEN.WAITING_FOR_PLAYERS_TITLE.." ("..subfmt(STRINGS.UI.LOBBYSCREEN.NUM_PLAYERS_FMT, { num = ready_count, max = min_players })..")"
    elseif mode == "ADMIN" then
        return "Waiting For Admin"
    end

    return STRINGS.UI.LOBBYSCREEN.WAITING_FOR_PLAYERS_TITLE
end

local function CanAdminStart()
    local client = GetClientUser()
    return client ~= nil
        and UserCommands.CanUserAccessCommand("forcestartgame", client, nil)
        and UserCommands.CanUserStartCommand("forcestartgame", client, nil)
end

local function BuildPreselectPanel(owner)
    local PreselectPanel = require "widgets/shuiyue_preselect_panel"
    local wrapper = Widget("ShuiyueWaitingPanel")
    local panel = wrapper:AddChild(PreselectPanel(owner, TheNet:GetServerMaxPlayers()))

    wrapper.waiting_for_players = panel
    wrapper.focus_forward = panel
    wrapper.title = GetWaitingTitle()
    panel:SetTitle(wrapper.title)

    -- [PATCH] 隐藏原版 LobbyScreen 顶部偏左的标题，由自定义面板在红蓝队中间显示。
    if owner ~= nil and owner.panel_title ~= nil then
        owner.panel_title:Hide()
    end

    local lobby = GetWorldLobby()
    if lobby ~= nil and lobby.ADMIN_MODE == "ADMIN" and CanAdminStart() then
        wrapper.next_button_title = STRINGS.UI.LOBBYSCREEN.START
    end

    panel.inst:ListenForEvent("player_ready_to_start_dirty", function()
        wrapper.title = GetWaitingTitle()
        -- [PATCH] 标题改由自定义面板的中央标题显示，不再依赖原版的 panel_title。
        panel:SetTitle(wrapper.title)
    end, TheWorld.net)

    function wrapper:OnNextButton()
        if self.next_button_title ~= nil then
            UserCommands.RunUserCommand("forcestartgame", {}, GetClientUser(), nil)
        end
        return false
    end

    function wrapper:OnUpdate()
        if self.on_character_reset_cb ~= nil then
            self.on_character_reset_cb(self)
        end
        panel:Refresh()
    end

    function wrapper:OnBackButton()
        local client = GetClientUser()
        if client == nil or client.lobbycharacter == nil or client.lobbycharacter == "" then
            self.on_character_reset_cb = nil
            owner.back_button:Enable()
            if not TheInput:ControllerAttached() then
                owner.back_button:Show()
            end
            return true
        end

        if not self.pending_reset_character_request then
            self.pending_reset_character_request = true
            owner:Disable()
            TheNet:SendLobbyCharacterRequestToServer("")
            self.on_character_reset_cb = function()
                local current_client = GetClientUser()
                if current_client ~= nil and current_client.lobbycharacter ~= nil and current_client.lobbycharacter ~= "" then
                    return
                end

                self.on_character_reset_cb = nil
                self.pending_reset_character_request = nil
                owner.back_button:Enable()
                owner:Enable()
                owner.back_button:onclick()
                owner.inst:DoTaskInTime(0, function()
                    owner.back_button:Enable()
                    if not TheInput:ControllerAttached() then
                        owner.back_button:Show()
                    end
                end)
            end
        end

        owner.back_button:Disable()
        owner.back_button:Hide()
        return false
    end

    function wrapper:GetHelpText()
        return panel.GetHelpText ~= nil and panel:GetHelpText() or ""
    end

    return wrapper
end

local function InstallCountdownStart(screen)
    screen.inst:ListenForEvent("lobbyplayerspawndelay", function(_, data)
        if data == nil or not data.active or screen.panel == nil then
            return
        end

        if data.time == 0 then
            if screen.panel.name == "ShuiyueWaitingPanel" then
                if StartGame(screen) then
                    return
                end

                if screen.panel.OnBackButton == nil or screen.panel:OnBackButton() then
                    screen:ToNextPanel(-1)
                end
            else
                SetStartButton(screen)
            end
            return
        end

        if screen.panel.name == "ShuiyueWaitingPanel" then
            screen.back_button:Disable()
            screen.back_button:Hide()
        end
    end, TheWorld)
end

AddClassPostConstruct("screens/redux/lobbyscreen", function(self)
    if not IsRegularLobby() or self.shuiyue_preselect_installed then
        return
    end

    self.shuiyue_preselect_installed = true
    EnsureStartGameLoadout(self)
    self.inst:DoTaskInTime(0, function()
        EnsureStartGameLoadout(self)
    end)

    if self.panels == nil or #self.panels < 2 then
        return
    end

    WrapLoadoutPanel(self.panels[2])

    table.insert(self.panels, 3, {
        panelfn = BuildPreselectPanel,
    })

    InstallCountdownStart(self)

    -- [PATCH] 隐藏选人界面原版地形预览，避免与自定义选人面板冲突。
    -- 部分 mod 的按钮是延迟生成的，因此在构造后多次扫描，并在选人阶段持续轮询。
    local preview_scan_times = { 0, 0.25, 0.5, 1, 2, 3, 5 }
    for _, t in ipairs(preview_scan_times) do
        self.inst:DoTaskInTime(t, function()
            hide_lobby_terrain_preview(self)
        end)
    end

    local preview_scan_task = nil
    preview_scan_task = self.inst:DoPeriodicTask(1, function()
        hide_lobby_terrain_preview(self)
        -- 一旦进入游戏（倒计时结束或世界存在且不再处于选人），停止扫描。
        if TheWorld ~= nil
            and TheWorld.net ~= nil
            and TheWorld.net.components.worldcharacterselectlobby ~= nil
            and TheWorld.net.components.worldcharacterselectlobby:HasGameStarted() then
            if preview_scan_task ~= nil then
                preview_scan_task:Cancel()
            end
        end
    end)
end)
