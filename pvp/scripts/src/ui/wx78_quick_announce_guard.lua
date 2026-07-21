-- The bundled quick-announce file patches WX-78's module display from a
-- minified legacy script. Modern DST split chip pools into
-- chip_objectpools/chip_poolindexes, while the legacy script still expects
-- chip_objectpool/chip_poolindex. Provide a compatibility view and guard the
-- legacy callbacks so WX-78 HUD creation cannot break character spawn.

local debug_log = require("src/core/debug")

local Guard = rawget(_G, "BIRD_WX78_QUICK_ANNOUNCE_GUARD") or {}
rawset(_G, "BIRD_WX78_QUICK_ANNOUNCE_GUARD", Guard)

local function log_guard_error(scope, err)
    debug_log.error("wx78-qa-guard", scope, tostring(err))
end

local get_module_definition_from_netid
local function get_module_name(module_netid)
    if module_netid == nil then
        return nil
    end

    if get_module_definition_from_netid == nil then
        local ok, moduledefs = pcall(require, "wx78_moduledefs")
        if not ok or moduledefs == nil then
            return nil
        end
        get_module_definition_from_netid = moduledefs.GetModuleDefinitionFromNetID or false
    end

    if type(get_module_definition_from_netid) ~= "function" then
        return nil
    end

    local ok, module_def = pcall(get_module_definition_from_netid, module_netid)
    return ok and module_def ~= nil and module_def.name or nil
end

local function shallow_copy_indexes(indexes)
    if type(indexes) ~= "table" then
        return nil
    end

    local copy = {}
    for key, value in pairs(indexes) do
        copy[key] = value
    end
    return copy
end

local function append_unique(list, seen, chip)
    if chip == nil or seen[chip] then
        return
    end

    seen[chip] = true
    table.insert(list, chip)
end

local function append_pool(list, seen, pool)
    if type(pool) ~= "table" then
        return
    end

    for _, chip in ipairs(pool) do
        append_unique(list, seen, chip)
    end

    for _, chip in pairs(pool) do
        append_unique(list, seen, chip)
    end
end

local function rebuild_legacy_pool(display)
    if type(display) ~= "table" then
        return nil
    end

    local has_modern_pools = type(display.chip_objectpools) == "table"
    local legacy_pool = display.chip_objectpool
    if type(legacy_pool) == "table" and not legacy_pool._bird_compat_pool and not has_modern_pools then
        return legacy_pool
    end

    if type(legacy_pool) ~= "table" or not legacy_pool._bird_compat_pool then
        legacy_pool = {}
        legacy_pool._bird_compat_pool = true
        display.chip_objectpool = legacy_pool
    end

    for index = #legacy_pool, 1, -1 do
        legacy_pool[index] = nil
    end

    local seen = {}
    local pools = display.chip_objectpools
    if type(pools) == "table" then
        for _, pool in ipairs(pools) do
            append_pool(legacy_pool, seen, pool)
        end

        for _, pool in pairs(pools) do
            append_pool(legacy_pool, seen, pool)
        end
    end

    if #legacy_pool == 0 and type(display.chip_objectpool) == "table" then
        append_pool(legacy_pool, seen, display.chip_objectpool)
    end

    return legacy_pool
end

local function find_chip_index(pool, chip)
    if pool == nil or chip == nil then
        return nil
    end

    for index, candidate in ipairs(pool) do
        if candidate == chip then
            return index
        end
    end

    return nil
end

local function find_added_chip(display, previous_indexes)
    local pools = type(display) == "table" and display.chip_objectpools or nil
    local indexes = type(display) == "table" and display.chip_poolindexes or nil
    if type(pools) ~= "table" or type(indexes) ~= "table" then
        return nil
    end

    for key, current_index in pairs(indexes) do
        local previous_index = previous_indexes ~= nil and previous_indexes[key] or nil
        if type(current_index) == "number"
            and (type(previous_index) ~= "number" or current_index > previous_index)
        then
            local pool = pools[key]
            if type(pool) == "table" then
                return pool[current_index - 1] or pool[current_index] or pool[#pool]
            end
        end
    end

    return nil
end

local function update_legacy_index(display, legacy_pool, added_chip)
    if type(display) ~= "table" then
        return
    end

    local added_index = find_chip_index(legacy_pool, added_chip)
    if added_index ~= nil then
        display.chip_poolindex = added_index + 1
        return
    end

    if type(display.chip_poolindexes) == "table" then
        local largest_next_index = 1
        for _, index in pairs(display.chip_poolindexes) do
            if type(index) == "number" and index > largest_next_index then
                largest_next_index = index
            end
        end
        display.chip_poolindex = largest_next_index
        return
    end

    if type(display.chip_poolindex) ~= "number" then
        display.chip_poolindex = #legacy_pool + 1
    end
end

local function guard_method(widget, method_name, scope)
    if widget == nil or type(widget[method_name]) ~= "function" then
        return
    end

    local wrapper_key = "_bird_guarded_" .. method_name .. "_wrapper"
    if widget[method_name] == widget[wrapper_key] then
        return
    end

    local base = widget[method_name]
    local wrapper = function(self, ...)
        local ok, result = pcall(base, self, ...)
        if ok then
            return result
        end
        log_guard_error(scope or method_name, result)
        return false
    end
    widget[wrapper_key] = wrapper
    widget[method_name] = wrapper
end

local function guard_chips(display)
    local chips = display ~= nil and display.chip_objectpool or nil
    if chips == nil then
        return
    end

    for _, chip in ipairs(chips) do
        guard_method(chip, "OnControl", "chip OnControl")
    end
end

function Guard.prepare_display(display, previous_indexes, module_netid)
    local legacy_pool = rebuild_legacy_pool(display)
    if legacy_pool == nil then
        return
    end

    local added_chip = find_added_chip(display, previous_indexes)
    local module_name = get_module_name(module_netid)
    if added_chip ~= nil and module_name ~= nil then
        added_chip.modname = module_name
    end

    update_legacy_index(display, legacy_pool, added_chip)
    guard_chips(display)
end

function Guard.wrap_on_module_added(display)
    if display == nil or type(display.OnModuleAdded) ~= "function" then
        return
    end

    if display.OnModuleAdded == display._bird_wx78_on_module_added_wrapper then
        return
    end

    local base = display.OnModuleAdded
    local wrapper = function(self, ...)
        local module_netid = ...
        local previous_indexes = shallow_copy_indexes(self.chip_poolindexes)
        local ok, result = pcall(base, self, ...)
        Guard.prepare_display(self, previous_indexes, module_netid)
        if ok then
            return result
        end

        log_guard_error("OnModuleAdded", result)
        return false
    end
    display._bird_wx78_on_module_added_wrapper = wrapper
    display.OnModuleAdded = wrapper
end

AddClassPostConstruct("widgets/upgrademodulesdisplay", function(self)
    Guard.prepare_display(self)
    Guard.wrap_on_module_added(self)
end)
