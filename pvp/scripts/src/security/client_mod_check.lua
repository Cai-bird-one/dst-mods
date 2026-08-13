-- Client-side mod policy.
--
-- Low-priority client-only mods are silently temp-disabled for all clients.
-- Client-only mods whose priority is at least this mod's priority are treated
-- as unsafe, because they may have already executed before this mod.
--
-- SECURITY NOTE: This file runs on the client. A determined user can modify
-- their local copy of this mod (or disable it) to bypass all checks here.
-- Treat these checks as "best-effort discourage casual cheating", not as a
-- hard security boundary. Server-side validation of gameplay state is still
-- required for anything security-critical.

local PopupDialogScreen = require("screens/redux/popupdialog")
local debug_log = require("src/core/debug")

local BIRD_PVP_PRIORITY = 9007199254740991
local PRIORITY_WARNING_TITLE = "High priority client mod detected"
local PRIORITY_WARNING_BODY = "A local client mod has priority >= Bird PVP.\n"
    .. "This can run before the PvP security code and cannot be allowed.\n\n"
    .. "Disable or lower the priority of these client mods, then rejoin:\n%s"

local blocked_client_mods = rawget(GLOBAL, "BIRD_BLOCKED_CLIENT_MODS")
if blocked_client_mods == nil then
    blocked_client_mods = {}
    rawset(GLOBAL, "BIRD_BLOCKED_CLIENT_MODS", blocked_client_mods)
end

local function is_current_user_admin()
    if TheNet == nil then
        return false
    end

    local ok_userid, userid = pcall(function()
        return TheNet:GetUserID()
    end)
    if not ok_userid or userid == nil then
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

local function sanitize_priority(priority)
    local priority_type = type(priority)
    if priority_type == "number" then
        return priority
    elseif priority_type == "string" then
        return tonumber(priority) or 0
    end

    return 0
end

local function get_mod_info(modname)
    if KnownModIndex == nil or KnownModIndex.GetModInfo == nil then
        return nil
    end

    return KnownModIndex:GetModInfo(modname)
end

local function get_mod_display_name(modname, modinfo)
    if modinfo ~= nil and type(modinfo.name) == "string" and modinfo.name ~= "" then
        return modinfo.name
    end

    return tostring(modname)
end

local function is_client_only_mod(modname)
    local modinfo = get_mod_info(modname)
    return modinfo ~= nil and modinfo.client_only_mod == true
end

local function path_modname(path)
    if type(path) ~= "string" then
        return nil
    end

    local workshop_id = path:match("workshop%-(%d+)")
    if workshop_id ~= nil then
        return "workshop-" .. workshop_id
    end

    return path:match("[/\\]mods[/\\]([^/\\]+)[/\\]")
end

local function remove_blocked_package_paths(blocked_modname)
    if package == nil or type(package.path) ~= "string" then
        return
    end

    local kept = {}
    local changed = false

    for entry in (package.path .. ";"):gmatch("([^;]*);") do
        local modname = path_modname(entry)
        local remove = false

        if blocked_modname ~= nil and entry:find(blocked_modname, 1, true) ~= nil then
            remove = true
        elseif modname ~= nil and is_client_only_mod(modname) then
            blocked_client_mods[modname] = true
            remove = true
        end

        if remove then
            changed = true
        else
            table.insert(kept, entry)
        end
    end

    if changed then
        package.path = table.concat(kept, ";")
    end
end

local function install_client_mod_loader_hook()
    if ModManager == nil or ModManager.InitializeModMain == nil or ModManager._bird_client_mod_loader_hooked then
        return
    end

    local base_initialize_mod_main = ModManager.InitializeModMain
    ModManager._bird_client_mod_loader_hooked = true

    ModManager.InitializeModMain = function(self, modname, env, mainfile, safe)
        if is_current_user_admin() then
            return base_initialize_mod_main(self, modname, env, mainfile, safe)
        end

        if is_client_only_mod(modname) then
            blocked_client_mods[modname] = true
            remove_blocked_package_paths(modname)
            debug_log.info("client-mod-check", "blocked client mod load", tostring(modname), tostring(mainfile))
            return true
        end

        return base_initialize_mod_main(self, modname, env, mainfile, safe)
    end
end

install_client_mod_loader_hook()

local function get_enabled_client_mods()
    local enabled = {}

    if KnownModIndex == nil or KnownModIndex.GetClientModNames == nil then
        return enabled
    end

    for _, modname in ipairs(KnownModIndex:GetClientModNames()) do
        local modinfo = get_mod_info(modname)
        local blocked = blocked_client_mods[modname] == true
        local configured_enabled = KnownModIndex.IsModEnabled ~= nil
            and KnownModIndex:IsModEnabled(modname) == true
        local temp_disabled = KnownModIndex.IsModTempDisabled ~= nil
            and KnownModIndex:IsModTempDisabled(modname) == true
        local enabled_any = KnownModIndex.IsModEnabledAny ~= nil
            and KnownModIndex:IsModEnabledAny(modname) == true
        local priority = sanitize_priority(modinfo ~= nil and modinfo.priority or nil)

        debug_log.info(
            "client-mod-check",
            "client mod scan",
            "name=" .. get_mod_display_name(modname, modinfo),
            "modname=" .. tostring(modname),
            "priority=" .. tostring(priority),
            "blocked=" .. tostring(blocked),
            "enabled=" .. tostring(configured_enabled),
            "temp_disabled=" .. tostring(temp_disabled),
            "enabled_any=" .. tostring(enabled_any)
        )

        if blocked or configured_enabled then
            table.insert(enabled, {
                modname = modname,
                name = get_mod_display_name(modname, modinfo),
                priority = priority,
                blocked = blocked,
                configured_enabled = configured_enabled,
                temp_disabled = temp_disabled,
                enabled_any = enabled_any,
            })
        end
    end

    if #enabled == 0 then
        debug_log.info("client-mod-check", "active client mod scan", "none")
    end

    return enabled
end

local function temp_disable_client_mods(mods)
    local disabled_any = false

    if KnownModIndex == nil or KnownModIndex.TempDisable == nil then
        return false
    end

    if KnownModIndex.DisableClientMods ~= nil then
        KnownModIndex:DisableClientMods(true)
    end

    for _, mod in ipairs(mods) do
        debug_log.info("client-mod-check", "temp disable client mod", tostring(mod.modname))
        KnownModIndex:TempDisable(mod.modname)
        disabled_any = true
    end

    if disabled_any and KnownModIndex.Save ~= nil then
        KnownModIndex:Save()
    end

    return disabled_any
end

local function should_skip_low_priority_check(owner)
    if TheNet == nil or not TheNet:GetIsClient() then
        return true
    end

    return is_current_user_admin()
end

local function get_priority_violations(client_mods)
    local violations = {}

    if is_current_user_admin() then
        return violations
    end

    for _, mod in ipairs(client_mods) do
        if mod.priority >= BIRD_PVP_PRIORITY then
            table.insert(violations, mod)
        end
    end

    return violations
end

local function describe_violations(violations)
    local lines = {}

    for _, mod in ipairs(violations) do
        table.insert(lines, string.format(
            "- %s (%s), priority=%s, blocked=%s, enabled=%s, temp_disabled=%s, enabled_any=%s",
            mod.name,
            mod.modname,
            tostring(mod.priority),
            tostring(mod.blocked),
            tostring(mod.configured_enabled),
            tostring(mod.temp_disabled),
            tostring(mod.enabled_any)
        ))
    end

    return table.concat(lines, "\n")
end

local kick_requested = false
local function request_server_kick(details)
    if kick_requested then
        return true
    end

    if MOD_RPC ~= nil and MOD_RPC.Justice ~= nil and MOD_RPC.Justice.b ~= nil then
        kick_requested = true
        local report = tostring(details or "unknown")
            :gsub("[%c]", " ")
            :sub(1, 1000)
        SendModRPCToServer(MOD_RPC.Justice.b, report)
        return true
    end

    return false
end

local priority_warning_open = false
local function show_priority_warning_and_leave(violations)
    if priority_warning_open then
        return
    end

    priority_warning_open = true

    local details = describe_violations(violations)
    local body = string.format(PRIORITY_WARNING_BODY, details)

    local function leave_game()
        if TheFrontEnd ~= nil then
            TheFrontEnd:PopScreen()
        end

        request_server_kick(details)

        if DoRestart ~= nil then
            DoRestart(true)
        elseif TheNet ~= nil and TheNet.Disconnect ~= nil then
            TheNet:Disconnect(false)
        end
    end

    debug_log.info("client-mod-check", "high priority client mod detected", details)

    if TheFrontEnd ~= nil then
        TheFrontEnd:PushScreen(PopupDialogScreen(PRIORITY_WARNING_TITLE, body, {
            {
                text = "Leave Game",
                cb = leave_game,
            },
        }))
        request_server_kick(details)
    else
        leave_game()
    end
end

AddModRPCHandler("Justice", "a", function(player, userid_hash)
    if player == nil or userid_hash ~= hash(player.userid) then
        return
    end

    player.pass_check = true
end)

AddModRPCHandler("Justice", "b", function(player, reported_details)
    if player == nil or player.userid == nil then
        return
    end

    local client = TheNet:GetClientTableForUser(player.userid)
    if client ~= nil and client.admin == true then
        debug_log.info(
            "client-mod-check",
            "kick request ignored for admin",
            tostring(player.userid),
            tostring(player.name or "")
        )
        return
    end

    local details = tostring(reported_details or "unknown")
        :gsub("[%c]", " ")
        :sub(1, 1000)
    debug_log.info(
        "client-mod-check",
        "client reported high-priority mods",
        "userid=" .. tostring(player.userid),
        "name=" .. tostring(player.name or ""),
        "mods=" .. details
    )

    TheNet:BanForTime(player.userid, 20)
    TheNet:Announce((player.name or player.userid) .. " was kicked for high-priority client mods (20s)")
end)

local checked_this_session = false

AddClassPostConstruct("screens/playerhud", function(self)
    local CreateOverlays = self.CreateOverlays

    function self:CreateOverlays(...)
        CreateOverlays(self, ...)

        if checked_this_session then
            return
        end

        checked_this_session = true

        self.owner:DoTaskInTime(0.5, function()
            local client_mods = get_enabled_client_mods()
            local priority_violations = get_priority_violations(client_mods)
            if #priority_violations > 0 then
                show_priority_warning_and_leave(priority_violations)
                return
            end

            if should_skip_low_priority_check(self.owner) then
                return
            end

            if #client_mods == 0 then
                return
            end

            temp_disable_client_mods(client_mods)
        end)
    end
end)
