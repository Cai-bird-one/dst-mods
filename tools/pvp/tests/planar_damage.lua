-- Execute complete PVP files and this installation's exact four Combat methods.
local assertions = 0
local function eq(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

GLOBAL = _G
TheWorld = { ismastersim = true, state = { cycles = 1 } }
TheSim = { GetGameID = function() return "DST" end }
TUNING = {}
EQUIPSLOTS = { HANDS = "hands" }
GetTime = function() return 123 end
IsRangedWeapon = function() return false end
SpDamageUtil = {
    ApplySpDefense = function(_, damage) return damage end,
    CalcTotalDamage = function(damage)
        local total = 0
        for _, value in pairs(damage) do total = total + value end
        return total
    end,
}
local hooks, player_hook, stategraph_hook = {}, nil, nil
local team_state = {
    TEAM_OBSERVER = 0,
    get_player_team = function(inst) return inst.team or 1, false end,
    is_playing_team = function(team) return team == 1 or team == 2 end,
}
local modenv = {
    GLOBAL = GLOBAL,
    GetModConfigData = function(name)
        return ({ hbstyle = "heart", hbcolor = "dynamic", hblength = 10, hbpos = 1 })[name]
    end,
    require = function(name)
        if name == "src/team/lobby_team_state" then return team_state end
        assert(name == "src/observer/privileges")
        return { can_receive_healthbar = function(inst) return inst.observer == true end }
    end,
    AddComponentPostInit = function(name, fn)
        hooks[name] = hooks[name] or {}
        table.insert(hooks[name], fn)
    end,
    AddPrefabPostInit = function() end,
    AddPlayerPostInit = function(fn) player_hook = fn end,
    AddStategraphPostInit = function(name, fn)
        assert(name == "wilson")
        stategraph_hook = fn
    end,
    EventHandler = function(name, fn) return { name = name, fn = fn } end,
}
modenv.env = modenv
setfenv(assert(loadstring(health_bar_source, "@pvp/scripts/src/ui/health_bar.lua")), modenv)()
setfenv(assert(loadstring(protection_source, "@pvp/scripts/src/protection/player.lua")), modenv)()
local graph = { events = { attacked = { fn = function(inst) inst.staggers = inst.staggers + 1 end } } }
stategraph_hook(graph)
AllPlayers = {{
    observer = true,
    IsValid = function() return true end,
    GetDistanceSqToPoint = function() return 0 end,
}}

local function netvar()
    return { set_local = function() end, set = function(self, value) self.value = value end }
end

local function component_hooks(name, inst)
    for _, hook in ipairs(hooks[name] or {}) do hook(inst.components[name], inst) end
end

local function entity(player, skip_hooks)
    local inst = { tags = { player = player }, components = {}, events = {}, staggers = 0, prefab = "test_entity" }
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:IsValid() return true end
    function inst:PushEvent(name, data)
        self.events[name] = data
        if name == "attacked" and self:HasTag("player") then graph.events.attacked.fn(self, data) end
    end
    inst.Transform = { GetWorldPosition = function() return 0, 0, 0 end }
    inst.sg = { HasStateTag = function() return false end, statemem = {} }
    inst.dychealthbar = { resets = 0, dychp_net = netvar(), dychpmax_net = netvar() }
    function inst.dychealthbar:DYCHBSetTimer(value)
        eq(value, 0, "health bar resets timer to zero")
        self.resets = self.resets + 1
    end
    inst.components.inventory = {
        GetEquippedItem = function() return inst.hand end,
        ApplyDamage = function(_, damage, _, _, special)
            inst.armor_special = special
            return damage, special
        end,
    }
    local health = { inst = inst, currenthealth = 100, maxhealth = 100 }
    function health:IsDead() return self.currenthealth <= 0 end
    function health:IsInvincible() return false end
    function health:SetInvincible() end
    function health:DoDelta(delta)
        self.currenthealth = self.currenthealth + delta
        return delta
    end
    inst.components.health = health
    local combat = setmetatable({ inst = inst }, { __index = Combat })
    combat.externaldamagetakenmultipliers = { Get = function() return 1 end }
    function combat:SetTarget(target) self.target = target end
    function combat:ShouldRecoil(_, _, damage) return false, damage end
    function combat:GetWeapon() return inst.hand end
    function combat:CanHitTarget() return true end
    function combat:IsValidTarget() return true end
    function combat:CalcDamage() return inst.damage or 0, inst.special end
    function combat:CalcReflectedDamage() return 0 end
    function combat:ClearAttackTemps() end
    inst.components.combat = combat
    if not skip_hooks then
        component_hooks("health", inst)
        component_hooks("combat", inst)
        if player then player_hook(inst) end
    end
    return inst
end

local modes = { "GetAttacked", "GetAttacked_Internal", "DoAttack", "DoAreaAttack", "DoAreaAttack onlyontarget" }
local function attack(mode, attacker, target)
    local combat, weapon = attacker.components.combat, attacker.hand
    if mode == "DoAttack" then
        combat:DoAttack(target, weapon)
    elseif mode == "DoAreaAttack" then
        TheSim.FindEntities = function() return { target } end
        eq(combat:DoAreaAttack(attacker, 5, weapon), 1, "area hit count")
    elseif mode == "DoAreaAttack onlyontarget" then
        eq(combat:DoAreaAttack(target, 5, weapon, nil, nil, nil, true), 1, "target area hit count")
    else
        target.components.combat[mode](target.components.combat, attacker, attacker.damage, weapon, "test", attacker.special, true)
    end
end

if is_baseline then
    for _, mode in ipairs(modes) do
        local attacker, target = entity(true), entity(true)
        attacker.damage, attacker.special = 30, { planar = 8 }
        attack(mode, attacker, target)
        eq(target.components.health.currenthealth, mode == "GetAttacked" and 70 or 62, mode .. " baseline health")
    end
    local attacker, target = entity(false), entity(false)
    attacker.damage, attacker.special = 0, { planar = 8 }
    attack("DoAttack", attacker, target)
    eq(target.components.health.currenthealth, 92, "baseline pure planar leak")
    return assertions
end

for _, mode in ipairs(modes) do
    for _, player in ipairs({ true, false }) do
        for _, damage_case in ipairs({ { 30, 8 }, { 0, 8 }, { 30 } }) do
            local attacker, target = entity(player), entity(player)
            attacker.damage = damage_case[1]
            attacker.special = damage_case[2] and { planar = damage_case[2] } or nil
            attack(mode, attacker, target)
            local label = mode .. "/player=" .. tostring(player) .. "/damage=" .. attacker.damage
            eq(target.components.health.currenthealth, 100 - attacker.damage, label .. " health")
            eq(target.armor_special, nil, label .. " armor receives no planar")
            if attacker.special then eq(attacker.special.planar, 8, label .. " original special preserved") end
            local event = target.events.attacked or target.events.blocked
            eq(event.spdamage, nil, label .. " event contains no planar")
            eq(event.from_doattack, mode ~= "GetAttacked" and true or nil, label .. " native source flag")
            eq(target.dychealthbar.resets, attacker.damage == 0 and 1 or 2, label .. " target hit/health bar updates")
            eq(attacker.dychealthbar.resets, 1, label .. " attacker hit bar update")
        end
    end
end

-- A shared area-damage table retains planar for its owner, while every target
-- receives only the unrelated special type. The engine stub sums special types.
do
    local attacker, first, second = entity(false), entity(false), entity(true)
    local shared = { planar = 8, third_party = 4 }
    attacker.damage, attacker.special = 30, shared
    TheSim.FindEntities = function() return { first, second } end
    eq(attacker.components.combat:DoAreaAttack(attacker, 5), 2, "shared AOE count")
    for _, target in ipairs({ first, second }) do
        eq(target.components.health.currenthealth, 66, "only unrelated special damage retained")
        eq(target.armor_special.planar, nil, "filtered table lacks planar")
        eq(target.armor_special.third_party, 4, "unrelated special retained")
        eq(target.armor_special == shared, false, "shared source not passed for mutation")
    end
    eq(shared.planar, 8, "shared planar unchanged after multiple targets")
    eq(shared.third_party, 4, "shared other special unchanged")
end

-- Use the real protection file as the outer AddPlayerPostInit hook, matching DST.
for _, mode in ipairs(modes) do
    for _, case in ipairs({ { 0, true, 0 }, { 0, false, 30 }, { 1, true, 30 } }) do
        TheWorld.state.cycles = case[1]
        local attacker, target = entity(true), entity(true)
        attacker.damage, attacker.special = 30, { planar = 8 }
        if case[2] then
            attacker.hand = { components = { weapon = {
                CanRangedAttack = function() return false end,
                OnAttack = function() end,
            } } }
        end
        attack(mode, attacker, target)
        eq(target.components.health.currenthealth, 100 - case[3], mode .. " first-day composition health")
        eq(target.staggers, case[3] == 0 and 0 or 1, mode .. " first-day composition SG")
    end
end
TheWorld.state.cycles = 1

-- Check old-build fallback and forward-compatible calling conventions using
-- spies only for the original method; execute the actual installed wrapper.
for _, method in ipairs({ "GetAttacked_Internal", "GetAttacked" }) do
    for _, special in ipairs({ { planar = 8 }, { planar = 8, third_party = 4 }, { third_party = 4 }, {} }) do
        local target, attacker, marker = entity(false), entity(false), {}
        local has_planar, has_other = special.planar ~= nil, special.third_party ~= nil
        local combat = { inst = target, SetTarget = function() end }
        combat[method] = function(self, source, damage, weapon, stimuli, filtered, from_doattack, hole, extra)
            eq(self, combat, method .. " self")
            eq(source, attacker, method .. " attacker")
            eq(damage, 12, method .. " ordinary damage")
            eq(weapon, nil, method .. " weapon nil preserved")
            eq(stimuli, nil, method .. " stimuli nil preserved")
            eq(filtered and filtered.planar, nil, method .. " planar filtered")
            eq(filtered and filtered.third_party, has_other and 4 or nil, method .. " other special")
            if not has_planar then eq(filtered, special, method .. " unchanged special identity") end
            if has_planar and not has_other then eq(filtered, nil, method .. " empty filtered table becomes nil") end
            eq(from_doattack, true, method .. " source flag")
            eq(hole, nil, method .. " tail nil hole")
            eq(extra, marker, method .. " future argument")
            return false, nil, marker
        end
        target.components.combat = combat
        component_hooks("combat", target)
        local a, b, c = combat[method](combat, attacker, 12, nil, nil, special, true, nil, marker)
        eq(a, false, method .. " first result")
        eq(b, nil, method .. " nil result")
        eq(c, marker, method .. " third result")
        eq(special.planar, has_planar and 8 or nil, method .. " source table unchanged")
    end
end

-- Redirect and reflected damage also enter the actual native internal method.
do
    local attacker, target, redirected = entity(false), entity(false), entity(false)
    attacker.damage, attacker.special = 30, { planar = 8 }
    target.components.combat.redirectdamagefn = function() return redirected end
    attack("DoAttack", attacker, target)
    eq(target.components.health.currenthealth, 100, "redirect original target unharmed")
    eq(redirected.components.health.currenthealth, 70, "redirect excludes planar")
    eq(redirected.events.attacked.from_doattack, true, "redirect source flag")
    target.components.combat.redirectdamagefn = nil
    attacker.components.combat.CalcReflectedDamage = function() return 10, { planar = 8 } end
    attack("DoAttack", attacker, target)
    eq(attacker.components.health.currenthealth, 90, "reflected damage excludes planar")
end

TheWorld.ismastersim = false
local client = entity(true, true)
local internal, public, settarget = client.components.combat.GetAttacked_Internal, client.components.combat.GetAttacked, client.components.combat.SetTarget
component_hooks("combat", client)
player_hook(client)
eq(client.components.combat.GetAttacked_Internal, internal, "client internal unmodified")
eq(client.components.combat.GetAttacked, public, "client public unmodified")
eq(client.components.combat.SetTarget, settarget, "client target method unmodified")
return assertions
