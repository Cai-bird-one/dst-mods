local UserCommands = require "usercommands"
local Widget = require "widgets/widget"

local START_PAUSE_DURATIONS = {
    [0] = true,
    [10] = true,
    [20] = true,
    [30] = true,
    [40] = true,
    [50] = true,
    [60] = true,
}

local function IsRegularLobby()
    return TheNet ~= nil and TheNet:GetServerGameMode() == "survival"
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
    lobby.LATE_JOIN = GetModConfigData("LATE_JOIN") ~= false
    local pause_duration = tonumber(GetModConfigData("START_PAUSE_DURATION"))
    lobby.START_PAUSE_DURATION = START_PAUSE_DURATIONS[pause_duration] and pause_duration or 30
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

local function GetWaitingTitle()
    local lobby = GetWorldLobby()
    local ready_count, total_count = 0, 0
    if lobby ~= nil and lobby.GetPlayingTeamReadyStatus ~= nil then
        ready_count, total_count = lobby:GetPlayingTeamReadyStatus()
    end
    return string.format("准备 %d/%d", ready_count, total_count)
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

    if CanAdminStart() then
        wrapper.next_button_title = STRINGS.UI.LOBBYSCREEN.START
    end

    local function RefreshWaitingTitle()
        wrapper.title = GetWaitingTitle()
        if owner.panel_title ~= nil then
            owner.panel_title:SetString(wrapper.title)
        end
    end

    panel.inst:ListenForEvent("player_ready_to_start_dirty", RefreshWaitingTitle, TheWorld.net)
    if TheGlobalInstance ~= nil then
        panel.inst:ListenForEvent("bird_lobby_teams_dirty", RefreshWaitingTitle, TheGlobalInstance)
    end

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
end)
