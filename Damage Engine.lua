OnInit("Damage Engine", function() --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Total_Initialization.lua
--Lua Version 3 Preview
--Author: Bribe
Require "Event" --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Event.lua

local onEvent = Require "RegisterAnyPlayerUnitEvent"  --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Lua-Infused-GUI.lua
local remap   = Require.lazily "GlobalRemap"          --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Global_Variable_Remapper.lua

--Configurables:
local _USE_GUI           = remap    --GUI only works if Global Variable Remapper is included.
local _USE_ROOT_TRACKING = true     --If you don't use DamageEventLevel/DamageEventAOE or SourceDamageEvent, set this to false
local _USE_LEGACY_API    = true     --Whether to support classic Damage Engine API (DamageModifierEvent, DamageEvent and AOEDamageEvent)
local _USE_ARMOR_MOD     = true     --If you do not modify nor detect armor/defense types, set this to false
local _USE_MELEE_RANGE   = true     --If you do not detect melee nor ranged damage, set this to false
local _USE_LETHAL        = true     --If false, LethalDamageEvent and explosive damage will be disabled.

Damage =
{   DEATH_VAL   = 0.405 --In case M$ ever change this, it'll be a quick fix here.
,   CODE        = 1     --If you use GUI, this must align with udg_DamageTypeCode.
,   PURE        = 2     --If you use GUI, this must align with udg_DamageTypePure.
}

---@class damageInstance
---@field source        unit
---@field target        unit
---@field damage        number
---@field prevAmt       number
---@field userAmt       number
---@field isAttack      boolean
---@field isRanged      boolean
---@field isMelee       boolean
---@field attackType    attacktype
---@field damageType    damagetype
---@field weaponType    weapontype
---@field isCode        boolean
---@field isSpell       boolean
---@field userData      any
---@field armorPierced  number
---@field armorType     integer
---@field defenseType   integer
---@field prevArmorT    integer
---@field prevDefenseT  integer
local currentInstance
local recursiveInstance ---@type damageInstance
local execute = {}      ---@type { [string]: fun(d:damageInstance) }

---@diagnostic disable: undefined-global, lowercase-global, cast-local-type, param-type-mismatch, undefined-field

local ATTACK_TYPE_SPELLS, DAMAGE_TYPE_PHYSICAL, DAMAGE_TYPE_HIDDEN,  WEAPON_TYPE_NONE
    = ATTACK_TYPE_NORMAL, DAMAGE_TYPE_NORMAL,   DAMAGE_TYPE_UNKNOWN, WEAPON_TYPE_WHOKNOWS

--further reading on these following types: https://www.hiveworkshop.com/threads/spell-ability-damage-types-and-what-they-mean.316271
local attacksImmune =
{   [ATTACK_TYPE_MELEE]         = true
,   [ATTACK_TYPE_PIERCE]        = true
,   [ATTACK_TYPE_SIEGE]         = true
,   [ATTACK_TYPE_CHAOS]         = true
,   [ATTACK_TYPE_HERO]          = true
}
local damagesImmune =
{   [DAMAGE_TYPE_HIDDEN]        = true
,   [DAMAGE_TYPE_PHYSICAL]      = true
,   [DAMAGE_TYPE_ENHANCED]      = true
,   [DAMAGE_TYPE_POISON]        = true
,   [DAMAGE_TYPE_DISEASE]       = true
,   [DAMAGE_TYPE_ACID]          = true
,   [DAMAGE_TYPE_DEMOLITION]    = true
,   [DAMAGE_TYPE_SLOW_POISON]   = true
,   [DAMAGE_TYPE_UNIVERSAL]     = true
}
local recursiveDamageType =
{   [DAMAGE_TYPE_PLANT]         = true
,   [DAMAGE_TYPE_DEFENSIVE]     = true
,   [DAMAGE_TYPE_SPIRIT_LINK]   = true
}

if _USE_ROOT_TRACKING then
    local GroupClear, IsUnitInGroup, GroupAddUnit
        = GroupClear, IsUnitInGroup, GroupAddUnit
    Damage.root = {
        targets = udg_DamageEventAOEGroup or CreateGroup(),
        run = function(self, d)
            if self.instance then
                execute.Source(self.instance)
                if not d or not d.isCode then
                    self.instance = d
                    self.level    = 1
                    GroupClear(self.targets)
                end
            end
        end,
        add = function(self, d)
            if not d.isCode then
                if (d.source ~= self.instance.source) then
                    self:run(d)
                end
                if IsUnitInGroup(d.target, self.targets) then
                    self.level  = self.level + 1
                    if self.instance.target ~= d.target then
                        self.instance = d --the original event was not hitting the primary target. Adjust the root to this new event.
                    end
                else
                    GroupAddUnit(self.targets, d.target)
                end
            end
        end
    }
end

local setArmor
if _USE_ARMOR_MOD then
    local GetUnitField,           SetUnitField,           GetUnitArmor,    SetUnitArmor,    ARMOR_FIELD,        DEFENSE_FIELD
        = BlzGetUnitIntegerField, BlzSetUnitIntegerField, BlzGetUnitArmor, BlzSetUnitArmor, UNIT_IF_ARMOR_TYPE, UNIT_IF_DEFENSE_TYPE

    ---@param d damageInstance
    ---@param reset? boolean
    ---@param basic? boolean
    function setArmor(d, reset, basic)
        if basic then
            d.armorType      = GetUnitField(d.target, ARMOR_FIELD)
            d.defenseType    = GetUnitField(d.target, DEFENSE_FIELD)
            d.prevArmorT     = d.armorType
            d.prevDefenseT   = d.defenseType
        else
            if d.armorPierced then
                SetUnitArmor(d.target, GetUnitArmor(d.target) + (reset and d.armorPierced or -d.armorPierced))
            end
            if d.prevArmorT   ~= d.armorType then
                SetUnitField(d.target, ARMOR_FIELD,              reset and d.prevArmorT   or  d.armorType)
            end
            if d.prevDefenseT ~= d.defenseType then
                SetUnitField(d.target, DEFENSE_FIELD,            reset and d.prevDefenseT or  d.defenseType)
            end
        end
    end
else
    setArmor = DoNothing
end

local awaitDamagedEvent, nextMelee, nextRanged, nextData

local function finishInstance(d, keepFrozen)
    d = d or currentInstance
    if d then
        if awaitDamagedEvent then
            awaitDamagedEvent = false
            setArmor(d, true)
        end
        if d.prevAmt ~= 0 and d.damageType ~= DAMAGE_TYPE_HIDDEN then
            execute.After(d)
        end
        currentInstance = nil
    end
    if not keepFrozen then
        Event.freeze(false)
    end
end
local setMeleeAndRange
local GetDamageAmt      = GetEventDamage
local SetDamage         = BlzSetEventDamage
do
    local GetSource     = GetEventDamageSource
    local GetTarget     = GetTriggerUnit
    local GetIsAttack   = BlzGetEventIsAttack
    local GetAttackType = BlzGetEventAttackType
    local GetDamageType = BlzGetEventDamageType
    local GetWeaponType = BlzGetEventWeaponType
    local SetAttackType = BlzSetEventAttackType
    local SetDamageType = BlzSetEventDamageType
    local SetWeaponType = BlzSetEventWeaponType
    local IsUnitType    = IsUnitType
    local IMMUNE_UNIT   = UNIT_TYPE_MAGIC_IMMUNE

    if _USE_MELEE_RANGE then
        local MELEE_UNIT    = UNIT_TYPE_MELEE_ATTACKER
        local RANGED_UNIT   = UNIT_TYPE_RANGED_ATTACKER

        ---@param d? damageInstance
        ---@param ranged? boolean
        function setMeleeAndRange(d, ranged)
            if not d then
                nextMelee       = ranged == false --nil parameter would mean it is neither a melee nor a ranged attack.
                nextRanged      = ranged
            elseif d.isCode then
                if d.isAttack and not d.isSpell then
                    d.isMelee   = nextMelee
                    d.isRanged  = nextRanged
                end
            elseif (d.damageType == DAMAGE_TYPE_PHYSICAL) and d.isAttack then
                d.isMelee       = IsUnitType(d.source, MELEE_UNIT)
                d.isRanged      = IsUnitType(d.source, RANGED_UNIT)
                if d.isMelee and d.isRanged then
                    d.isMelee   = d.weaponType == WEAPON_TYPE_NONE  --Melee units play a sound when damaging; in naturally-occuring cases where a
                    d.isRanged  = not d.isMelee                     --unit is both ranged and melee, the ranged attack plays no sound.
                end
            end
        end
    end
    
    local timer;timer =
    {   timer = CreateTimer()
    ,   await = function()
            finishInstance()
            if _USE_ROOT_TRACKING then Damage.root:run() end
            Event.freeze(false)
            recursiveInstance, currentInstance, timer.started = nil, nil, nil
        end
    }

    onEvent(EVENT_PLAYER_UNIT_DAMAGING, function()
        local amt = GetDamageAmt()
        local d = ---@type damageInstance
        {   source      = GetSource()
        ,   target      = GetTarget()
        ,   damage      = amt
        ,   isAttack    = GetIsAttack()
        ,   isCode      = nextData
        ,   attackType  = GetAttackType()
        ,   damageType  = GetDamageType()
        ,   weaponType  = GetWeaponType()
        ,   prevAmt     = amt
        ,   userAmt     = amt
        ,   userData    = nextData
        }
        d.isSpell       = d.attackType == ATTACK_TYPE_SPELLS and not d.isAttack
        nextData        = nil
        if _USE_MELEE_RANGE then setMeleeAndRange(d) end
        if not timer.started then
            timer.started = true
            TimerStart(timer.timer, 0, false, timer.await)
            Event.freeze(true)
        elseif awaitDamagedEvent and recursiveDamageType[d.damageType] then
            recursiveInstance = currentInstance --WarCraft 3 didn't run the DAMAGED event despite running the DAMAGING event.
        else
            finishInstance()
        end
        if _USE_ROOT_TRACKING then Damage.root:add(d) end
        setArmor(d, nil, true)
        currentInstance = d
        
        if amt == 0 then
            execute.Zero(d)
        elseif d.damageType ~= DAMAGE_TYPE_HIDDEN then
            execute.Pre(d)
            SetAttackType(d.attackType)
            SetDamageType(d.damageType)
            SetWeaponType(d.weaponType)
            SetDamage(d.damage)
            setArmor(d, false)
        end
        awaitDamagedEvent = not recursiveInstance or attacksImmune[d.attackType] or damagesImmune[d.damageType] or not IsUnitType(d.target, IMMUNE_UNIT)
    end)
end
do
    local GetUnitLife = GetWidgetLife

    onEvent(EVENT_PLAYER_UNIT_DAMAGED, function()
        local amt = GetDamageAmt()
        local d = currentInstance ---@type damageInstance
        if d.prevAmt == 0 and amt == 0 then
            finishInstance(d)
            return
        elseif awaitDamagedEvent then
            awaitDamagedEvent = false --this should occur in 99% of scenarios.
        else
            finishInstance(d, true) --spirit link or defensive/thorns recursive damage have finished, and it's time to wrap them up and load the triggering damage data.
            d, currentInstance, recursiveInstance = recursiveInstance, recursiveInstance, nil
        end
        setArmor(d, true)
        d.userAmt, d.damage = d.damage, amt
        
        if d.damageType ~= DAMAGE_TYPE_HIDDEN then
            if amt > 0 then
                execute.Armor(d)
                if _USE_LETHAL then
                    d.life = GetUnitLife(d.target) - d.damage
                    if d.life <= Damage.DEATH_VAL then
                        execute.Lethal(d)
                        d.damage = GetUnitLife(d.target) - d.life
                        if (type(d.userData) == "number") and (d.userData < 0) and (d.life <= Damage.DEATH_VAL) then
                            SetUnitExploded(d.target, true)
                        end
                    end
                end
            end
            execute.On(d)
            amt = d.damage
            SetDamage(amt)
        end
        if amt == 0 then finishInstance(d) end
    end)
end
do
    local opConds =
    {   [LESS_THAN]             = "Attack"
    ,   [LESS_THAN_OR_EQUAL]    = "Melee"
    ,   [GREATER_THAN_OR_EQUAL] = "Ranged"
    ,   [GREATER_THAN]          = "Spell"
    ,   [NOT_EQUAL]             = "Code"
    }
    local eventConds =
    {   Pre    = "(d.userData ~= Damage.PURE) or (d.damageType ~= DAMAGE_TYPE_UNKNOWN)"
    ,   Armor  = "(d.damage > 0)"
    ,   Lethal = "(d.life <= Damage.DEATH_VAL)"
    ,   AOE    = "(BlzGroupGetSize(Damage.root.targets) > 1)"
    }
    ---@param name string
    ---@param func function
    ---@param priority? number
    ---@param limitop? limitop
    function Damage.register(name, func, priority, limitop)
        local eventCond = eventConds[name]
        if opConds[limitop] then
            local opCond = "(d.is"..opConds[limitop]..")"
            eventCond = eventCond and (eventCond .. " and " .. opCond) or opCond
        end
        if eventCond then
            func = load([[return function(func)
                return function(d)
                    if ]]..eventCond..[[ then
                        func(d)
                    end
                end
            end]])()(func)
        end
        return Event[name.."DamageEvent"].oldRegister(func, priority)
    end
end
do
    ---@param ref string
    local function createRegistry(ref)
        local event    = ref.."DamageEvent"
        local executor = Event[event].execute
        execute[ref]   = function(d)
            executor(d.userData, true, d)
        end
        Event[event].oldRegister = Event[event].register
        Event[event].register = function(func, priority, _, limitop)
            return Damage.register(ref, func, priority, limitop)
        end
    end
    Event.PreDamageEvent        = Event.new(); createRegistry "Pre"
    Event.ZeroDamageEvent       = Event.new(); createRegistry "Zero"
    Event.ArmorDamageEvent      = Event.new(); createRegistry "Armor"
    Event.OnDamageEvent         = Event.new(); createRegistry "On"
    Event.AfterDamageEvent      = Event.new(); createRegistry "After"
    if _USE_LETHAL then
        Event.LethalDamageEvent = Event.new(); createRegistry "Lethal"
    end
    if _USE_ROOT_TRACKING then
        Event.SourceDamageEvent = Event.new(); createRegistry "Source"
    end
    if _USE_LEGACY_API then
        if _USE_ROOT_TRACKING then
            Event.AOEDamageEvent             = Event.new(); createRegistry "AOE"
            Event.AOEDamageEvent.await       = Event.SourceDamageEvent.await
            Event.AOEDamageEvent.oldRegister = Event.SourceDamageEvent.oldRegister
        end
        Event.create "DamageModifierEvent"
        .register = function(func, priority, trig, op)
            return Event[priority < 4 and "PreDamageEvent" or "ArmorDamageEvent"].register(func, priority, trig, op)
        end
        Event.create "DamageEvent"
        .register = function(func, priority, trig, op)
            return Event[(priority == 0 or priority == 2) and "ZeroDamageEvent" or "OnDamageEvent"].register(func, priority, trig, op)
        end
    end
end
do
    local UDT = UnitDamageTarget
    ---Replaces UnitDamageTarget. Missing parameters are filled in.
    ---@param source unit
    ---@param target unit
    ---@param amount number
    ---@param attack? boolean
    ---@param ranged? boolean
    ---@param attackType? attacktype
    ---@param damageType? damagetype
    ---@param weaponType? weapontype
    function Damage.apply(source, target, amount, attack, ranged, attackType, damageType, weaponType)
        Event.queue(function()
            nextData = nextData or Damage.CODE
            if attack == nil then
                attack = (ranged ~= nil) or (damageType == DAMAGE_TYPE_PHYSICAL)
            end
            if _USE_MELEE_RANGE then setMeleeAndRange(nil, ranged) end
            UDT(source, target, amount, attack, ranged, attackType, damageType, weaponType)
            finishInstance()
        end)
    end
    UnitDamageTarget = Damage.apply

    ---Allow syntax like Damage.data("whatever").apply(source, target, ...)
    ---@param id any
    function Damage.data(id)
        nextData = id
        return Damage
    end
end
if _USE_GUI then
    udg_NextDamageWeaponT = WEAPON_TYPE_NONE
    
    function UnitDamageTargetBJ(source, target, amount, attackType, damageType)
        local isAttack = udg_NextDamageIsAttack; udg_NextDamageIsAttack = false
        local weapon   = udg_NextDamageWeaponT;  udg_NextDamageWeaponT  = WEAPON_TYPE_NONE
        local isRanged, isMelee
        if _USE_MELEE_RANGE then
            isRanged = udg_NextDamageIsRanged
            isMelee  = udg_NextDamageIsMelee
            udg_NextDamageIsRanged = false
            udg_NextDamageIsMelee  = false
        end
        Damage.apply(source, target, amount, isAttack, isRanged or not isMelee, attackType, damageType, weapon)
    end

    ---@param str string
    ---@return string
    local function CAPStoCap(str) return str:sub(1,1)..(str:sub(2):lower()) end

    ---@param debugStrs table
    ---@param varPrefix string
    ---@param ... string
    local function setTypes(debugStrs, varPrefix, ...)
        for _,suffix in ipairs{...} do
            local handle = _G[varPrefix..suffix]
            local debugStr
            --Scan strings to translate JASS2 keywords into Editor keywords:
            if varPrefix == "ATTACK_TYPE_" then
                if     suffix == "NORMAL" then  suffix = "SPELLS"
                elseif suffix == "MELEE" then   suffix = "NORMAL"
                end
            elseif suffix == "WHOKNOWS" then --"WHOKNOWS" indicates that an on-hit effect should not play a sound.
                suffix   = "NONE"
                debugStr = "NONE"
                goto skipReformat
            elseif varPrefix == "WEAPON_TYPE_" then
                debugStr = suffix
                suffix   = suffix:gsub("^([A-Z])[A-Z]+_([A-Z])[A-Z]+", "\x251\x252") --METAL_LIGHT_SLICE -> ML_SLICE (var name only)
                goto skipOverwrite
            elseif varPrefix == "DEFENSE_TYPE_" then
                if     suffix == "NONE" then    suffix = "UNARMORED"
                elseif suffix == "LARGE" then   suffix = "HEAVY"
                elseif suffix == "FORT" then    suffix = "FORTIFIED"
                end
            end
            debugStr = suffix
            ::skipOverwrite::
            debugStr = debugStr:gsub("_", " "):gsub("([A-Z]+)", CAPStoCap) --"METAL_LIGHT_SLICE" -> "Metal Light Slice" (debug string only)
            ::skipReformat::
            debugStrs[handle] = debugStr
            _G["udg_"..varPrefix..suffix] = handle
        end
    end
    --Armor Types simply affect the sounds that play on-hit.
    setTypes(udg_ArmorTypeDebugStr,   "ARMOR_TYPE_",   "FLESH",  "WOOD",   "METAL",  "ETHEREAL", "STONE", "WHOKNOWS")
    
    --Further reading on attack types VS defense types: http://classic.battle.net/war3/basics/armorandweapontypes.shtml
    setTypes(udg_AttackTypeDebugStr,  "ATTACK_TYPE_",            "PIERCE", "MELEE",  "MAGIC",    "SIEGE", "HERO", "CHAOS",  "NORMAL")
    setTypes(udg_DefenseTypeDebugStr, "DEFENSE_TYPE_", "NONE",   "LIGHT",  "MEDIUM", "LARGE",    "FORT",  "HERO", "DIVINE", "NORMAL")

    --These can be complex to understand. I recommend this for reference: https://www.hiveworkshop.com/threads/spell-ability-damage-types-and-what-they-mean.316271/
    setTypes(udg_DamageTypeDebugStr,  "DAMAGE_TYPE_",
        "MAGIC",  "LIGHTNING", "DIVINE", "SONIC",   "COLD", "SHADOW_STRIKE", "DEFENSIVE",  "SPIRIT_LINK", "FORCE", "PLANT", "DEATH", "FIRE", "MIND",--Cannot affect spell immune units under any circumstances.
        "NORMAL", "ENHANCED",  "POISON", "DISEASE", "ACID", "SLOW_POISON",   "DEMOLITION", "UNKNOWN",     "UNIVERSAL")                              --Can affect Spell Immune units, under the right circumstances.
    
    --Weapon Types simply affect the sounds that play on-hit.
    setTypes(udg_WeaponTypeDebugStr,  "WEAPON_TYPE_", "WHOKNOWS",
        "METAL_LIGHT_CHOP",  "METAL_MEDIUM_CHOP",  "METAL_HEAVY_CHOP",   "AXE_MEDIUM_CHOP", --METAL & AXE CHOP
            "WOOD_LIGHT_BASH",   "WOOD_MEDIUM_BASH",   "WOOD_HEAVY_BASH", "METAL_MEDIUM_BASH", "METAL_HEAVY_BASH", "ROCK_HEAVY_BASH", --METAL, WOOD & ROCK BASH
        "METAL_LIGHT_SLICE", "METAL_MEDIUM_SLICE", "METAL_HEAVY_SLICE",  --METAL SLICE

        --None of the following can be selected in the Object Editor, so would not occur naturally in-game:
        "WOOD_LIGHT_SLICE",  "WOOD_MEDIUM_SLICE",  "WOOD_HEAVY_SLICE",  --WOOD SLICE
        "CLAW_LIGHT_SLICE",  "CLAW_MEDIUM_SLICE",  "CLAW_HEAVY_SLICE",  --CLAW SLICE
        "WOOD_LIGHT_STAB",   "WOOD_MEDIUM_STAB",                      "METAL_MEDIUM_STAB", "METAL_HEAVY_STAB") --WOOD & METAL STAB
    
    GlobalRemapArray("udg_CONVERTED_ATTACK_TYPE", function(attackType) return attackType end)
    GlobalRemapArray("udg_CONVERTED_DAMAGE_TYPE", function(damageType) return damageType end)
    
    if _USE_ROOT_TRACKING then
        remap("udg_DamageEventAOE",         function() return BlzGroupGetSize(Damage.root.targets) end)
        remap("udg_DamageEventLevel",       function() return Damage.root.level end)
        remap("udg_AOEDamageSource",        function() return Damage.root.instance.source end)
        remap("udg_EnhancedDamageTarget",   function() return Damage.root.instance.target end)
    end
    remap("udg_NextDamageType", nil, Damage.type)
    
    local currentEvent = Event.current
    
    ---Remap damageInstance types of variables (DamageEventSource/Target/Amount/etc)
    ---@param udgStr string
    ---@param luaStr string
    ---@param get? boolean
    ---@param set? boolean
    local function map(udgStr, luaStr, get, set)
        remap(udgStr, get and function() return currentEvent.data[luaStr] end, set and function(val) currentEvent.data[luaStr] = val end)
    end
    map("udg_DamageEventAmount",  "damage",     true, true)
    map("udg_DamageEventType",    "userData",   true, true)
    map("udg_DamageEventAttackT", "attackType", true, true)
    map("udg_DamageEventDamageT", "damageType", true, true)
    map("udg_DamageEventWeaponT", "weaponType", true, true)
    map("udg_LethalDamageHP",     "life",       true, true)
    if _USE_ARMOR_MOD then
        remap("udg_DamageEventArmorPierced", function() return currentEvent.data.armorPierced or 0 end, function(armor) currentEvent.data.armorPierced = armor end)
        map("udg_DamageEventArmorT",   "armorType",    true, true)
        map("udg_DamageEventDefenseT", "defenseType",  true, true)
    end
    map("udg_DamageEventSource",  "source",   true)
    map("udg_DamageEventTarget",  "target",   true)
    map("udg_DamageEventPrevAmt", "prevAmt",  true)
    map("udg_DamageEventUserAmt", "userAmt",  true)
    map("udg_IsDamageAttack",     "isAttack", true)
    map("udg_IsDamageCode",       "isCode",   true)
    map("udg_IsDamageSpell",      "isSpell",  true)
    if _USE_MELEE_RANGE then
        map("udg_IsDamageMelee",  "isMelee",  true)
        map("udg_IsDamageRanged", "isRanged", true)
    end
end
end, OnInit'end')
