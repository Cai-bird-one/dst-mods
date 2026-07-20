-- Early client-mod blocker.
--
-- This runs before this mod's modmain, so with the max priority from
-- modinfo.lua it can filter lower-priority client-only mods before their
-- modmain.lua gets a chance to execute.

local _G = GLOBAL

local blocked_client_mods = _G.rawget(_G, "BIRD_BLOCKED_CLIENT_MODS")
if blocked_client_mods == nil then
    blocked_client_mods = {}
    _G.rawset(_G, "BIRD_BLOCKED_CLIENT_MODS", blocked_client_mods)
end

local function log(...)
    if _G.print ~= nil then
        _G.print("[BirdPVP][client-mod-check]", ...)
    end
end

local function get_mod_info(modname)
    if _G.KnownModIndex == nil or _G.KnownModIndex.GetModInfo == nil then
        return nil
    end

    return _G.KnownModIndex:GetModInfo(modname)
end

local function is_current_user_admin()
    -- [PATCH] 世界生成阶段（worldgen_main）没有 TheNet 全局；直接用 rawget 读取，
    -- 避免 strict.lua 对未声明全局报错。
    local thenet = _G.rawget(_G, "TheNet")
    if thenet == nil then
        return false
    end

    local ok_userid, userid = _G.pcall(function()
        return thenet:GetUserID()
    end)
    if not ok_userid or userid == nil then
        return false
    end

    local ok_client, client = _G.pcall(function()
        return thenet:GetClientTableForUser(userid)
    end)
    return ok_client and client ~= nil and client.admin == true
end

local function is_blocked_client_mod(modname)
    if modname == nil then
        return false
    end

    if is_current_user_admin() then
        return false
    end

    if _G.KnownModIndex == nil or _G.KnownModIndex.GetModInfo == nil then
        return false
    end

    local modinfo = get_mod_info(modname)
    return modinfo == nil or modinfo.client_only_mod == true
end

local function mark_blocked(modname, reason)
    if modname == nil or blocked_client_mods[modname] then
        return
    end

    blocked_client_mods[modname] = true
    log(reason or "blocked client mod", _G.tostring(modname))
end

local function path_modname(path)
    if _G.type(path) ~= "string" then
        return nil
    end

    local workshop_id = path:match("workshop%-(%d+)")
    if workshop_id ~= nil then
        return "workshop-" .. workshop_id
    end

    return path:match("[/\\]mods[/\\]([^/\\]+)[/\\]")
end

local function remove_blocked_package_paths(blocked_modname)
    if _G.package == nil or _G.type(_G.package.path) ~= "string" then
        return
    end

    local kept = {}
    local changed = false

    for entry in (_G.package.path .. ";"):gmatch("([^;]*);") do
        local modname = path_modname(entry)
        local remove = false

        if blocked_modname ~= nil and entry:find(blocked_modname, 1, true) ~= nil then
            remove = true
        elseif modname ~= nil and is_blocked_client_mod(modname) then
            mark_blocked(modname, "removed package path for client mod")
            remove = true
        end

        if remove then
            changed = true
        else
            _G.table.insert(kept, entry)
        end
    end

    if changed then
        _G.package.path = _G.table.concat(kept, ";")
    end
end

local function install_compatibility_hook()
    if _G.KnownModIndex == nil
        or _G.KnownModIndex.IsModCompatibleWithMode == nil
        or _G.KnownModIndex._bird_client_mod_compatibility_hooked
    then
        return
    end

    local base_is_mod_compatible = _G.KnownModIndex.IsModCompatibleWithMode
    _G.KnownModIndex._bird_client_mod_compatibility_hooked = true

    _G.KnownModIndex.IsModCompatibleWithMode = function(self, modname, ...)
        if is_blocked_client_mod(modname) then
            mark_blocked(modname, "marked client mod incompatible")
            return false
        end

        return base_is_mod_compatible(self, modname, ...)
    end
end

local function install_loader_hook()
    if _G.ModManager == nil
        or _G.ModManager.InitializeModMain == nil
        or _G.ModManager._bird_client_mod_loader_hooked
    then
        return
    end

    local base_initialize_mod_main = _G.ModManager.InitializeModMain
    _G.ModManager._bird_client_mod_loader_hooked = true

    _G.ModManager.InitializeModMain = function(self, modname, ...)
        if is_blocked_client_mod(modname) then
            mark_blocked(modname, "blocked client mod load")
            remove_blocked_package_paths(modname)
            return true
        end

        return base_initialize_mod_main(self, modname, ...)
    end
end

install_compatibility_hook()
install_loader_hook()
