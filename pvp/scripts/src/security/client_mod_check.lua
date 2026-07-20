-- Client-side mod policy.
--
-- Low-priority client-only mods are silently temp-disabled for all clients.
-- Client-only mods whose priority is at least this mod's priority are treated
-- as unsafe, because they may have already executed before this mod.

local PopupDialogScreen = require("screens/redux/popupdialog")

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
            print("[BirdPVP][client-mod-check] blocked client mod load", tostring(modname), tostring(mainfile))
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
        if blocked_client_mods[modname]
            or (KnownModIndex.IsModEnabled ~= nil and KnownModIndex:IsModEnabled(modname))
        then
            local modinfo = get_mod_info(modname)
            table.insert(enabled, {
                modname = modname,
                name = get_mod_display_name(modname, modinfo),
                priority = sanitize_priority(modinfo ~= nil and modinfo.priority or nil),
            })
        end
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
        print("[BirdPVP][client-mod-check] temp disable client mod", tostring(mod.modname))
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
        table.insert(lines, string.format("- %s (%s), priority=%s", mod.name, mod.modname, tostring(mod.priority)))
    end

    return table.concat(lines, "\n")
end

local function request_server_kick()
    if MOD_RPC ~= nil and MOD_RPC.Justice ~= nil and MOD_RPC.Justice.b ~= nil then
        SendModRPCToServer(MOD_RPC.Justice.b)
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

        request_server_kick()

        if DoRestart ~= nil then
            DoRestart(true)
        elseif TheNet ~= nil and TheNet.Disconnect ~= nil then
            TheNet:Disconnect(false)
        end
    end

    print("[BirdPVP][client-mod-check] high priority client mod detected", details)

    if TheFrontEnd ~= nil then
        TheFrontEnd:PushScreen(PopupDialogScreen(PRIORITY_WARNING_TITLE, body, {
            {
                text = "Leave Game",
                cb = leave_game,
            },
        }))
        request_server_kick()
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

AddModRPCHandler("Justice", "b", function(player)
    if player == nil or player.userid == nil then
        return
    end

    local client = TheNet:GetClientTableForUser(player.userid)
    if client ~= nil and client.admin == true then
        return
    end

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
