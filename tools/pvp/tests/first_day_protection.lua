-- Runs the installed engine's exact Combat methods with minimal engine stubs.
-- The actual protection file registers both the damage and attacked-event hooks.
local assertions = 0
local function eq(actual, expected, description)
    assertions = assertions + 1
    assert(actual == expected, description .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

TheWorld = { ismastersim = true, state = { cycles = 0 } }
EQUIPSLOTS = { HANDS = "hands" }
GetTime = function() return 123 end
IsRangedWeapon = function() return false end
SpDamageUtil = {
    ApplySpDefense = function(_, damage) return damage end,
    CalcTotalDamage = function(damage) return damage.planar or 0 end,
}
local player_hook, stategraph_hook
local team_state = {
    TEAM_OBSERVER = 0,
    get_player_team = function(inst) return inst.team or 1, inst.pending or false end,
    is_playing_team = function(team) return team == 1 or team == 2 end,
}
local env = setmetatable({
    require = function(name)
        assert(name == "src/team/lobby_team_state")
        return team_state
    end,
    AddComponentPostInit = function() end,
    AddPrefabPostInit = function() end,
    AddPlayerPostInit = function(fn) player_hook = fn end,
    AddStategraphPostInit = function(name, fn)
        assert(name == "wilson")
        stategraph_hook = fn
    end,
    EventHandler = function(name, fn) return { name = name, fn = fn } end,
}, { __index = _G })
-- loadstring compiles the unchanged source under Lua 5.1 before executing it.
setfenv(assert(loadstring(protection_source, "@pvp/scripts/src/protection/player.lua")), env)()
local graph = { events = { attacked = { fn = function(inst) inst.staggers = inst.staggers + 1 end } } }
stategraph_hook(graph)

local function entity(tags)
    local inst = { tags = tags or {}, components = {}, staggers = 0, events = {}, prefab = "test_entity" }
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:PushEvent(name, data)
        self.events[name] = data
        if name == "attacked" then graph.events.attacked.fn(self, data) end
    end
    inst.Transform = { GetWorldPosition = function() return 0, 0, 0 end }
    inst.sg = { HasStateTag = function() return false end, statemem = {} }
    inst.components.inventory = {
        GetEquippedItem = function() return inst.hand end,
        ApplyDamage = function(_, damage, _, _, special)
            inst.armor_calls = (inst.armor_calls or 0) + 1
            return damage, special
        end,
    }
    local health = { currenthealth = 100 }
    function health:IsDead() return self.currenthealth <= 0 end
    function health:IsInvincible() return false end
    function health:DoDelta(delta)
        self.currenthealth = self.currenthealth + delta
        return delta
    end
    inst.components.health = health
    local combat = setmetatable({ inst = inst }, { __index = Combat })
    combat.externaldamagetakenmultipliers = { Get = function() return 1 end }
    function combat:ShouldRecoil(_, _, damage) return false, damage end
    function combat:GetWeapon() return inst.hand and inst.hand.components.weapon and inst.hand or nil end
    function combat:CanHitTarget() return true end
    function combat:IsValidTarget() return true end
    function combat:CalcDamage() return 30, { planar = 8 } end
    function combat:CalcReflectedDamage() return 0 end
    function combat:ClearAttackTemps() end
    inst.components.combat = combat
    return inst
end

local function attack_case(mode, kind, day, blocked, observer, pending)
    TheWorld.state.cycles = day
    local target = entity({ player = true })
    target.team, target.pending = observer and 0 or 1, pending
    player_hook(target)
    local attacker = entity({ player = kind ~= "mob" and kind ~= "follower", wereplayer = kind == "wereplayer" })
    local weapon = entity()
    weapon.components.weapon = { CanRangedAttack = function() return false end, OnAttack = function() end }
    if kind == "weapon" then attacker.hand = weapon end
    if kind == "tool" then attacker.hand = entity() end
    if kind == "follower" then attacker.components.follower = { leader = entity({ player = true }) } end
    local combat = attacker.components.combat
    local attackweapon = kind == "weapon" and weapon or nil
    if mode == "DoAttack" then
        combat:DoAttack(target, attackweapon)
    elseif mode == "DoAreaAttack" then
        TheSim = { FindEntities = function() return { target } end }
        eq(combat:DoAreaAttack(attacker, 5, attackweapon), 1, "AOE return count")
    elseif mode == "DoAreaAttack onlyontarget" then
        eq(combat:DoAreaAttack(target, 5, attackweapon, nil, nil, nil, true), 1, "target AOE return count")
    else
        target.components.combat[mode](target.components.combat, attacker, 30, attackweapon, "test", { planar = 8 }, true)
    end
    local prefix = mode .. "/" .. kind .. "/cycle=" .. day
    eq(target.components.health.currenthealth, blocked and 100 or 62, prefix .. " health")
    -- Baseline deliberately reproduces the symptom: health drops, existing SG guard suppresses hit reaction.
    local stagger_blocked = blocked or (day == 0 and kind == "weapon")
    eq(target.staggers, stagger_blocked and 0 or 1, prefix .. " SG dispatch")
    eq(target.armor_calls or 0, blocked and 0 or 1, prefix .. " armor damage entry")
    if not blocked then
        eq(target.events.attacked.spdamage.planar, 8, prefix .. " special damage")
        eq(target.events.attacked.from_doattack, mode ~= "GetAttacked" and true or nil, prefix .. " from_doattack")
    end
end

if is_baseline then
    attack_case("DoAttack", "weapon", 0, false)
    attack_case("DoAreaAttack", "weapon", 0, false)
    return assertions
end

for _, mode in ipairs({ "DoAttack", "DoAreaAttack", "DoAreaAttack onlyontarget", "GetAttacked", "GetAttacked_Internal" }) do
    attack_case(mode, "weapon", 0, true)
    attack_case(mode, "tool", 0, true)
    attack_case(mode, "wereplayer", 0, true)
    attack_case(mode, "follower", 0, true)
    attack_case(mode, "fist", 0, false)
    attack_case(mode, "weapon", 1, false)
    attack_case(mode, "mob", 0, false)
    attack_case(mode, "fist", 1, true, true)
    attack_case(mode, "fist", 1, false, true, true)
end

-- Verify wrapper forwarding (including nil holes, future extra arguments, all return values)
-- independently from the current engine's fixed-arity method signature.
for _, method in ipairs({ "GetAttacked_Internal", "GetAttacked" }) do
    TheWorld.state.cycles = 1
    local target = entity({ player = true })
    local special, marker = {}, {}
    target.components.combat = { inst = target }
    target.components.combat[method] = function(self, attacker, damage, weapon, stimuli, spdamage, from_doattack, extra)
        eq(self.inst, target, method .. " self")
        eq(damage, 12, method .. " damage")
        eq(weapon, nil, method .. " nil weapon")
        eq(stimuli, nil, method .. " nil stimuli")
        eq(spdamage, special, method .. " special identity")
        eq(from_doattack, true, method .. " from_doattack passthrough")
        eq(extra, marker, method .. " future argument")
        return false, nil, marker
    end
    player_hook(target)
    local a, b, c = target.components.combat[method](target.components.combat, entity({ player = true }), 12, nil, nil, special, true, marker)
    eq(a, false, method .. " first return")
    eq(b, nil, method .. " nil return")
    eq(c, marker, method .. " third return")
end

-- Client entities must retain the original method; authority stays on the server.
TheWorld.ismastersim = false
local client = entity({ player = true })
local original = client.components.combat.GetAttacked_Internal
player_hook(client)
eq(client.components.combat.GetAttacked_Internal, original, "client hook excluded")
return assertions
