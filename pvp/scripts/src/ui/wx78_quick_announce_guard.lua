-- WX-78 quick announcements read the native multi-bar display at click time.
-- Never copy chip identities into a legacy pool: the native UI reuses and
-- shifts its widgets when modules are removed, including from the middle.
local _G = GLOBAL
local WX78QuickAnnounce = {}
_G.BIRD_WX78_QUICK_ANNOUNCE_GUARD = WX78QuickAnnounce

local ENERGY_MESSAGES = { "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN" }
local CIRCUIT_BARS = {
    { id = _G.CIRCUIT_BARS.ALPHA, label = "α" },
    { id = _G.CIRCUIT_BARS.BETA, label = "β" },
    { id = _G.CIRCUIT_BARS.GAMMA, label = "γ" },
}

local function ForEachInstalledChip(display, fn)
    for bartype, pool in pairs(display.chip_objectpools) do
        local next_index = display.chip_poolindexes[bartype] or 1
        for index = 1, next_index - 1 do
            local chip = pool[index]
            if chip ~= nil then
                fn(chip)
            end
        end
    end
end

local function GetInstalledChipCount(display, selected)
    local installed = false
    local count = 0
    local name = selected.modulename
    ForEachInstalledChip(display, function(chip)
        installed = installed or chip == selected
        if name ~= nil and chip.modulename == name then
            count = count + 1
        end
    end)
    return installed and count or 0
end

function WX78QuickAnnounce.install_display(display, announce)
    -- Calling this again also covers any newly allocated native chip widgets.
    for _, pool in pairs(display.chip_objectpools) do
        for _, chip in ipairs(pool) do
            if not chip._bird_wx78_quick_announce_installed then
                chip._bird_wx78_quick_announce_installed = true
                local OnControl = chip.OnControl
                chip.OnControl = function(self, control, down, ...)
                    if down and control == _G.CONTROL_ACCEPT
                        and _G.TheInput:IsControlPressed(_G.CONTROL_FORCE_INSPECT) then
                        local count = GetInstalledChipCount(display, self)
                        if count > 0 then
                            local name = self.modulename
                            local item = _G.STRINGS.NAMES["WX78MODULE_" .. name:upper()] or name
                            local scheme = _G.NOMU_QA.SCHEME.ENERGY
                            -- Use qa_main's existing sender, including its team routing.
                            return announce(_G.subfmt(scheme.FORMATS.CHIP, { ITEM = item, NUM = count }))
                        end
                        return false
                    end
                    return OnControl(self, control, down, ...)
                end
            end
        end
    end
end

function WX78QuickAnnounce.get_energy_fields(display, scheme, get_mapping)
    local current = math.floor(display.energy_level + 0.5)
    local maximum = display.max_energy
    -- The old message names describe six battery levels. Scale those levels
    -- to the actual capacity so 6/7 no longer says "full", and 3/3 does.
    local level = maximum > 0 and math.floor(6 * math.max(0, math.min(current, maximum)) / maximum + 0.5) or 0
    local key = current == 7 and current == maximum and "SEVEN" or ENERGY_MESSAGES[level + 1]
    local message = get_mapping(scheme, "MESSAGE", key)
    if message == nil then
        -- Existing user schemes may predate seven-slot batteries. Keep their
        -- template and other messages, using the new default for this level.
        message = _G.STRINGS.DEFAULT_NOMU_QA.ENERGY.MAPPINGS.DEFAULT.MESSAGE[key]
    end

    local used = {}
    for _, bar in ipairs(CIRCUIT_BARS) do
        used[#used + 1] = bar.label .. ":" .. tostring(display.chip_slotsinuse[bar.id] or 0)
    end
    return {
        CURRENT = current,
        MAX = maximum,
        USED = table.concat(used, " / "),
        MESSAGE = message,
    }
end
