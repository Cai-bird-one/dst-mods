-- Lightweight beta-version debug logging.
-- Enabled only when modinfo version contains "beta".
local M = {}

local PREFIX = "[BirdPVP]"

local function contains_beta(text)
    text = tostring(text or "")
    return string.find(string.lower(text), "beta", 1, true) ~= nil
end

local function get_global(name)
    return _G ~= nil and rawget(_G, name) or nil
end

local function get_version()
    local value = get_global("BIRD_PVP_VERSION")
    if value ~= nil then
        return tostring(value)
    end

    value = get_global("version")
    if value ~= nil then
        return tostring(value)
    end

    local known_mod_index = get_global("KnownModIndex")
    local current_mod_name = get_global("modname")
    if known_mod_index ~= nil and current_mod_name ~= nil and known_mod_index.GetModInfo ~= nil then
        local ok, info = pcall(known_mod_index.GetModInfo, known_mod_index, current_mod_name)
        if ok and info ~= nil and info.version ~= nil then
            return tostring(info.version)
        end
    end
    return ""
end

function M.enabled()
    local enabled = get_global("BIRD_PVP_DEBUG")
    if enabled ~= nil then
        return enabled == true
    end
    return contains_beta(get_version())
end

function M.log(scope, ...)
    if not M.enabled() then
        return
    end
    print(PREFIX .. "[" .. tostring(scope or "debug") .. "]", ...)
end

function M.info(scope, ...)
    print(PREFIX .. "[" .. tostring(scope or "info") .. "]", ...)
end

function M.error(scope, ...)
    print(PREFIX .. "[" .. tostring(scope or "error") .. "][error]", ...)
end

function M.team_payload(teams)
    if type(teams) ~= "table" then
        return tostring(teams)
    end

    local entries = {}
    for userid, team_id in pairs(teams) do
        entries[#entries + 1] = tostring(userid) .. "=" .. tostring(team_id)
    end
    table.sort(entries)
    return table.concat(entries, ";")
end

return M
