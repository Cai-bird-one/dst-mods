local checks = 0
local function equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(actual, expected, label)
    checks = checks + 1
    assert(string.find(actual, expected, 1, true), label .. ": " .. actual)
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

GLOBAL = _G
CONTROL_ACCEPT, CONTROL_FORCE_INSPECT, KEY_LCTRL = 1, 2, 3
MAX_CIRCUIT_SLOTS = 7
TUNING = { WX78_MAXELECTRICCHARGE = 6 }
local inspect = true
local role = "client"
local enabled = true
local imports, hooks, messages, errors = {}, {}, {}, {}
ThePlayer = { prefab = "wx78", team = 1 }
TheInput = { IsControlPressed = function() return inspect end, IsKeyDown = function() return false end }
TheNet = {
    GetIsClient = function() return role == "client" end,
    GetServerIsClientHosted = function() return role == "host" end,
    IsDedicated = function() return role == "dedicated" end,
    Say = function(_, message, whisper) messages[#messages + 1] = { text = message, whisper = whisper } end,
}
function GetModConfigData() return enabled end
function AddClassPostConstruct(path, fn)
    hooks[path] = hooks[path] or {}
    table.insert(hooks[path], fn)
end
local original_register = AddClassPostConstruct
function modimport(path)
    imports[#imports + 1] = path
    local source = path == "scripts/src/ui/wx78_quick_announce_guard.lua" and guard_source
        or path == "scripts/qa_main.lua" and qa_fragment_source
    assert(source, "Unexpected import: " .. path)
    assert(loadstring(source, path))()
end
function require(path)
    if path == "src/core/debug" then
        return { error = function(...) errors[#errors + 1] = {...} end }
    elseif path == "wx78_moduledefs" then
        return { GetModuleDefinitionFromNetID = GetModuleDefinitionFromNetID }
    elseif path == "src/team/lobby_team_state" then
        return { get_player_team = function(player) return player.team end }
    end
    error("Unexpected require: " .. path)
end
function Vector3(x, y, z) return { x = x, y = y, z = z } end
function GetModuleDefinitionFromNetID(id) return module_definitions[id] end
assert(loadstring(native_source))()

STRINGS = { NAMES = {}, LMB = "LMB" }
assert(loadstring(defaults_source))()
NOMU_QA = { DATA = { DEFAULT_WHISPER = false, CHARACTER_SPECIFIC = true }, SCHEME = copy(STRINGS.DEFAULT_NOMU_QA) }
local ids = {}
for id, definition in pairs(module_definitions) do
    ids[definition.name] = id
    STRINGS.NAMES["WX78MODULE_" .. definition.name:upper()] = "name:" .. definition.name
end

-- The real loader must still exclude dedicated servers and respect the option.
role = "dedicated"
assert(loadstring(loader_source))()
equal(#imports, 0, "dedicated has no UI imports")
role, enabled = "client", false
assert(loadstring(loader_source))()
equal(#imports, 0, "disabled quick announce has no UI imports")
enabled = true
assert(loadstring(loader_source))()
equal(AddClassPostConstruct, original_register, "registration API restored/unchanged")

local function make_chip()
    local animation = setmetatable({}, { __index = function() return function() end end })
    local chip = {
        GetAnimState = function() return animation end,
        SetPosition = function() end,
        Show = function() end,
        Hide = function() end,
        HookCallback = function() end,
        UnhookCallback = function() end,
        OnControl = function(self, control, down, value)
            self.native_controls = (self.native_controls or 0) + 1
            return "native", nil, value
        end,
    }
    chip.cooldown = { GetAnimState = chip.GetAnimState, SetPosition = chip.SetPosition }
    return chip
end
local function make_display()
    local display = setmetatable({
        chip_objectpools = {}, chip_poolindexes = {}, chip_slotsinuse = {}, module_bars = {},
        max_energy = 6, energy_level = 6, focus = true, open = true,
        anim = make_chip(), energy_blinking = make_chip(), energy_backing = make_chip(),
        GetChipXOffset = function() return 0 end,
        PlayUpgradeModuleSound = function() end,
        UpdateEnergyLevel = function(self, value) self.energy_level = value end,
        UpdateSlotCount = function() end,
    }, { __index = UpgradeModulesDisplay })
    -- Native construction includes an extra reserved pool, as well as 0/1/2.
    for bar = 0, 3 do
        display.chip_objectpools[bar] = {}
        for index = 1, MAX_CIRCUIT_SLOTS do display.chip_objectpools[bar][index] = make_chip() end
        display.chip_poolindexes[bar], display.chip_slotsinuse[bar] = 1, 0
        display.module_bars[bar] = {}
    end
    return display
end
local function install(display)
    for _, hook in ipairs(hooks["widgets/upgrademodulesdisplay"] or {}) do hook(display) end
end
local function add(display, name)
    local definition = module_definitions[ids[name]]
    display:OnModuleAdded(definition.type, ids[name])
    return display.chip_objectpools[definition.type][display.chip_poolindexes[definition.type] - 1]
end
local function announce_chip(chip)
    local before = #messages
    local result = chip:OnControl(CONTROL_ACCEPT, true)
    if result and #messages > before then return messages[#messages].text end
end
local function expected_chip(name, count)
    return "/d" .. ThePlayer.team .. "wLMB " .. subfmt(NOMU_QA.SCHEME.ENERGY.FORMATS.CHIP, {
        ITEM = STRINGS.NAMES["WX78MODULE_" .. name:upper()], NUM = count,
    })
end

if is_baseline then
    for _, case in ipairs({ { "maxhealth", nil }, { "movespeed", "maxhealth" }, { "screech", "maxsanity1" } }) do
        local display = make_display()
        install(display)
        local chip = add(display, case[1])
        equal(chip.modulename, case[1], "baseline native identity")
        equal(chip.modname, case[2], "baseline wrong legacy identity")
    end
    local display = make_display()
    display.max_energy, display.energy_level = 7, 7
    AnnounceWXEnergy(display)
    contains(messages[#messages].text, "7/6", "baseline wrong capacity")
    contains(messages[#messages].text, "{USED}", "baseline missing used slots")
    contains(messages[#messages].text, "{MESSAGE}", "baseline missing seven-slot message")
    return checks
end

-- Correct names in every circuit bar; existing modules before hook installation.
local display = make_display()
local alpha = add(display, "maxhealth")
local beta = add(display, "movespeed2")
local gamma = add(display, "screech")
install(display)
equal(display.OnModuleAdded, UpgradeModulesDisplay.OnModuleAdded, "native add method untouched")
equal(display.PopModuleAtIndex, UpgradeModulesDisplay.PopModuleAtIndex, "native removal method untouched")
equal(announce_chip(alpha), expected_chip("maxhealth", 1), "preexisting alpha")
equal(announce_chip(beta), expected_chip("movespeed2", 1), "preexisting beta")
equal(announce_chip(gamma), expected_chip("screech", 1), "preexisting gamma")
equal(messages[#messages].whisper, false, "original team sender retained")

local alpha2 = add(display, "maxhealth")
equal(announce_chip(alpha), expected_chip("maxhealth", 2), "duplicates counted")
display:PopOneModule(CIRCUIT_BARS.ALPHA)
equal(announce_chip(alpha), expected_chip("maxhealth", 1), "unloaded duplicate excluded")
equal(announce_chip(alpha2), nil, "unloaded widget does not announce")
local replacement = add(display, "maxsanity1")
equal(replacement, alpha2, "native pool widget reused")
equal(announce_chip(replacement), expected_chip("maxsanity1", 1), "reused widget reads current name")

-- Native removal shifts the next module's identity into the preceding widget.
display:PopModuleAtIndex(CIRCUIT_BARS.ALPHA, 1)
equal(announce_chip(alpha), expected_chip("maxsanity1", 1), "middle removal updates shifted identity")
equal(announce_chip(alpha2), nil, "shifted-from stale widget excluded")
display:PopAllModules(true)
equal(announce_chip(alpha), nil, "all-unloaded stale alpha excluded")
equal(announce_chip(beta), nil, "all-unloaded stale beta excluded")
equal(announce_chip(gamma), nil, "all-unloaded stale gamma excluded")
gamma = add(display, "digestion")
equal(announce_chip(gamma), expected_chip("digestion", 1), "fresh module after unload all")

-- Native input and return values survive, including while inspect is held.
local a, b, c = gamma:OnControl(99, true, "sentinel")
equal(a, "native", "unrelated control delegated")
equal(b, nil, "nil return preserved")
equal(c, "sentinel", "extra return preserved")
a = gamma:OnControl(CONTROL_ACCEPT, false)
equal(a, "native", "release delegated")
inspect = false
a = gamma:OnControl(CONTROL_ACCEPT, true)
equal(a, "native", "normal accept delegated")
inspect = true

-- Multiple calls and fresh/rebuilt displays do not stack input handlers.
local old_control = gamma.OnControl
install(display)
equal(gamma.OnControl, old_control, "repeated install is idempotent")
display.chip_objectpools[2][2] = make_chip()
install(display)
local gamma2 = add(display, "digestion")
equal(announce_chip(gamma2), expected_chip("digestion", 2), "newly allocated widget installed")
local fresh = make_display()
install(fresh)
ThePlayer.team = 2
equal(announce_chip(add(fresh, "movespeed2")), expected_chip("movespeed2", 1), "fresh display and blue team")
ThePlayer.team = 1

-- Battery text uses independent bar occupancy and dynamic native capacity.
local battery = make_display()
install(battery)
add(battery, "maxhealth")
add(battery, "movespeed2")
add(battery, "screech")
AnnounceWXEnergy(battery)
local text = messages[#messages].text
contains(text, "6/6", "six-slot capacity")
contains(text, "α:1 / β:2 / γ:3", "per-bar slots")
equal(string.find(text, "{", 1, true), nil, "no unresolved placeholders")
battery:UpdateMaxEnergy(7, 6)
battery.energy_level = 7
AnnounceWXEnergy(battery)
contains(messages[#messages].text, "7/7", "native capacity upgrade")
contains(messages[#messages].text, "电量：满格", "seven-slot full message")
battery.energy_level = 6
AnnounceWXEnergy(battery)
equal(string.find(messages[#messages].text, "满格", 1, true), nil, "six of seven is not full")
battery:UpdateMaxEnergy(3, 7)
battery.energy_level = 3
AnnounceWXEnergy(battery)
contains(messages[#messages].text, "3/3", "native capacity shrink")
contains(messages[#messages].text, "电量：满格", "three of three is full")
battery:PopAllModules(true)
AnnounceWXEnergy(battery)
contains(messages[#messages].text, "α:0 / β:0 / γ:0", "zero occupancy after native unload")

-- Existing saved/custom schemes keep templates and have a seven-slot fallback.
NOMU_QA.SCHEME.ENERGY.FORMATS.DEFAULT = "custom {CURRENT}|{MAX}|{USED}|{MESSAGE}"
NOMU_QA.SCHEME.ENERGY.MAPPINGS.DEFAULT.MESSAGE.SEVEN = nil
battery:UpdateMaxEnergy(7, 3)
battery.energy_level = 7
AnnounceWXEnergy(battery)
contains(messages[#messages].text, "custom 7|7|", "custom template preserved")
contains(messages[#messages].text, "电量：满格", "old scheme seven fallback")
equal(string.find(messages[#messages].text, "{", 1, true), nil, "old scheme has no placeholders")
NOMU_QA.SCHEME.ENERGY.MAPPINGS.WX78 = { MESSAGE = { SEVEN = "custom full" } }
AnnounceWXEnergy(battery)
contains(messages[#messages].text, "custom full", "character-specific mapping preserved")

-- The same UI entry is supported for a client-hosted game.
hooks, imports, role = {}, {}, "host"
assert(loadstring(loader_source))()
equal(#imports, 2, "host loads helper and quick announce")
local hostdisplay = make_display()
install(hostdisplay)
equal(announce_chip(add(hostdisplay, "maxhealth")), expected_chip("maxhealth", 1), "host announcement")
equal(#errors, 0, "no swallowed guard errors")
return checks
