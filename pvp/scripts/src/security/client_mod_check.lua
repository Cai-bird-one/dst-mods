-- Client-side policy diagnostics.
-- Native client_mods_disabled filtering and administrator queue restoration
-- run earlier from modworldgenmain.lua.

local debug_log = require("src/core/debug")

local function is_current_user_admin()
    if TheNet == nil then
        return false
    end

    if TheNet.GetIsServerAdmin ~= nil then
        local ok_admin, is_admin = pcall(TheNet.GetIsServerAdmin, TheNet)
        if ok_admin and is_admin == true then
            return true
        end
    end

    local ok_userid, userid = pcall(function()
        return TheNet:GetUserID()
    end)
    if not ok_userid or userid == nil or userid == "" then
        return false
    end

    local ok_client, client = pcall(function()
        return TheNet:GetClientTableForUser(userid)
    end)
    return ok_client and client ~= nil and client.admin == true
end

if TheNet:GetIsClient() then
    local base_execute_console_command = GLOBAL.ExecuteConsoleCommand

    GLOBAL.ExecuteConsoleCommand = function(...)
        if is_current_user_admin() and base_execute_console_command ~= nil then
            return base_execute_console_command(...)
        end
    end
end

local function is_loaded(modname)
    for _, loaded_modname in ipairs(ModManager.enabledmods or {}) do
        if loaded_modname == modname then
            return true
        end
    end
    return false
end

local function log_client_mod_state()
    if KnownModIndex == nil or KnownModIndex.GetClientModNames == nil then
        return
    end

    local reloaded = rawget(GLOBAL, "BIRD_ADMIN_RELOADED_CLIENT_MODS") or {}
    for _, modname in ipairs(KnownModIndex:GetClientModNames() or {}) do
        local modinfo = KnownModIndex.GetModInfo ~= nil and KnownModIndex:GetModInfo(modname) or nil
        local display_name = modinfo ~= nil and modinfo.name or modname
        local enabled = KnownModIndex.IsModEnabled ~= nil and KnownModIndex:IsModEnabled(modname) == true
        local temp_disabled = KnownModIndex.IsModTempDisabled ~= nil
            and KnownModIndex:IsModTempDisabled(modname) == true

        debug_log.info(
            "client-mod-check",
            "client mod state",
            "name=" .. tostring(display_name),
            "modname=" .. tostring(modname),
            "enabled=" .. tostring(enabled),
            "temp_disabled=" .. tostring(temp_disabled),
            "loaded=" .. tostring(is_loaded(modname)),
            "admin_reloaded=" .. tostring(reloaded[modname] == true)
        )
    end
end

local checked_this_session = false
AddClassPostConstruct("screens/playerhud", function(self)
    local create_overlays = self.CreateOverlays

    function self:CreateOverlays(...)
        create_overlays(self, ...)
        if checked_this_session then
            return
        end

        checked_this_session = true
        self.owner:DoTaskInTime(0.5, log_client_mod_state)
    end
end)
