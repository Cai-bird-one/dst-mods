-- Native client-mod policy and administrator reload bridge.
--
-- Set the native policy while this high-priority worldgen entry is loaded by
-- the front end, before a hosted server is created. Do not gate this on
-- TheNet:GetIsServer(), because that role is not ready during front-end load.

local _G = GLOBAL
local debug_log = require("src/core/debug")

local function log(...)
    debug_log.info("client-mod-check", ...)
end

_G.KnownModIndex:DisableClientMods(true)
log("native client mods disabled", "injected=true")

local function is_current_user_admin()
    if _G.TheNet == nil then
        return false
    end

    if _G.TheNet.GetIsServerAdmin ~= nil then
        local ok_admin, is_admin = _G.pcall(_G.TheNet.GetIsServerAdmin, _G.TheNet)
        if ok_admin and is_admin == true then
            return true
        end
    end

    local ok_userid, userid = _G.pcall(function()
        return _G.TheNet:GetUserID()
    end)
    if not ok_userid or userid == nil or userid == "" then
        return false
    end

    local ok_client, client = _G.pcall(function()
        return _G.TheNet:GetClientTableForUser(userid)
    end)
    return ok_client and client ~= nil and client.admin == true
end

local function sanitize_priority(priority)
    if _G.type(priority) == "number" then
        return priority
    end
    if _G.type(priority) == "string" then
        return _G.tonumber(priority) or 0
    end
    return 0
end

local function is_enabled_before_native_disable(modname)
    local index = _G.KnownModIndex
    return (index.IsModEnabled ~= nil and index:IsModEnabled(modname) == true)
        or (index.IsModForceEnabled ~= nil and index:IsModForceEnabled(modname) == true)
        or (index.IsModTempEnabled ~= nil and index:IsModTempEnabled(modname) == true)
end

local function is_already_queued(modname)
    for _, env in _G.ipairs(_G.ModManager.mods or {}) do
        if env.modname == modname then
            return true
        end
    end
    return false
end

local function get_admin_client_mods()
    local result = {}
    local index = _G.KnownModIndex
    if index == nil or index.GetClientModNames == nil then
        return result
    end

    for _, modname in _G.ipairs(index:GetClientModNames() or {}) do
        local modinfo = index.GetModInfo ~= nil and index:GetModInfo(modname) or nil
        if modinfo ~= nil
            and modinfo.client_only_mod == true
            and is_enabled_before_native_disable(modname)
            and not is_already_queued(modname) then
            result[#result + 1] = {
                modname = modname,
                modinfo = modinfo,
                priority = sanitize_priority(modinfo.priority),
            }
        end
    end

    _G.table.sort(result, function(a, b)
        if a.priority == b.priority then
            return _G.tostring(a.modname) < _G.tostring(b.modname)
        end
        return a.priority > b.priority
    end)
    return result
end

local function remove_added_environments(added)
    local added_set = {}
    for _, env in _G.ipairs(added) do
        added_set[env] = true
    end
    for index = #_G.ModManager.mods, 1, -1 do
        if added_set[_G.ModManager.mods[index]] then
            _G.table.remove(_G.ModManager.mods, index)
        end
    end
end

local function append_admin_client_mods()
    if _G.TheNet == nil
        or not _G.TheNet:GetIsClient()
        or _G.TheNet:GetIsServer()
        or _G.ModManager == nil
        or _G.ModManager.worldgen
    then
        return
    end

    if GetModConfigData("ADMIN_CLIENT_MODS") ~= true then
        log("administrator reload skipped", "disabled by configuration")
        return
    end

    if not is_current_user_admin() then
        log("administrator reload skipped", "admin identity unavailable or false")
        return
    end

    local candidates = get_admin_client_mods()
    if #candidates == 0 then
        log("administrator reload", "no enabled client mods")
        return
    end

    local added = {}
    for _, candidate in _G.ipairs(candidates) do
        local modname = candidate.modname
        if _G.KnownModIndex.LoadModConfigurationOptions ~= nil then
            _G.KnownModIndex:LoadModConfigurationOptions(modname, true)
        end

        local env = _G.CreateEnvironment(modname, false)
        env.modinfo = candidate.modinfo
        _G.table.insert(_G.ModManager.mods, env)
        added[#added + 1] = env
        log(
            "administrator client mod queued",
            "modname=" .. _G.tostring(modname),
            "priority=" .. _G.tostring(candidate.priority)
        )
    end

    local ok, error_message = _G.pcall(_G.kleiregistermods, added)
    if not ok then
        remove_added_environments(added)
        debug_log.error("client-mod-check", "administrator registration failed", _G.tostring(error_message))
        return
    end

    local reloaded = _G.rawget(_G, "BIRD_ADMIN_RELOADED_CLIENT_MODS") or {}
    for _, env in _G.ipairs(added) do
        reloaded[env.modname] = true
    end
    _G.rawset(_G, "BIRD_ADMIN_RELOADED_CLIENT_MODS", reloaded)
    log("administrator client mods registered", "count=" .. _G.tostring(#added))
end

append_admin_client_mods()
