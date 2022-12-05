OnInit("Damage Engine", function()                        --https://www.hiveworkshop.com/threads/global-initialization.317099/
--Lua Version 3 preview
--Author: Bribe
    
    Require "Event"                                       --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Event.lua
    
    local onEvent = Require "RegisterAnyPlayerUnitEvent"  --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Lua-Infused-GUI.lua

    local remap   = Require.lazily "GlobalRemap"          --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Global_Variable_Remapper.lua

    --Configurable variables are listed below
    local _USE_GUI           = remap    --GUI only works if Global Variable Remapper is included.
    local _USE_LEVEL_AND_AOE = true     --If you don't use DamageEventLevel/DamageEventAOE/SourceDamageEvent, set this to false
    local _USE_LEGACY_API    = true     --Whether to support classic Damage Engine API (DamageModifierEvent, DamageEvent and AOEDamageEvent)
    local _USE_ARMOR_MOD     = true     --If you do not modify nor detect armor/defense types, set this to false
    local _USE_MELEE_RANGE   = true     --If you do not detect melee nor ranged damage, set this to false
    local _USE_LETHAL        = true     --If false, LethalDamageEvent and explosive damage will be disabled.
    
    ---@class Damage
    ---@field public life number
    ---@field public nextType integer
    ---@field protected nextMelee boolean
    ---@field protected nextRanged boolean
    Damage = {
        DEATH_VAL   = 0.405,    --In case M$ ever change this, it'll be a quick fix here.
        CODE        = 1,        --Must be the same as udg_DamageTypeCode, or 0 if you prefer to disable the automatic flag.
        PURE        = 2         --Must be the same as udg_DamageTypePure
    }
    local Damage = Damage

    ---@class damageInstance
    ---@field source        unit
    ---@field target        unit
    ---@field damage        number
    ---@field prevAmt       number
    ---@field isAttack      boolean
    ---@field isRanged      boolean
    ---@field isMelee       boolean
    ---@field attackType    attacktype
    ---@field damageType    damagetype
    ---@field weaponType    weapontype
    ---@field isCode        boolean
    ---@field isSpell       boolean
    ---@field userType      integer
    ---@field armorPierced  number
    ---@field prevArmorT    integer
    ---@field armorType     integer
    ---@field prevDefenseT  integer
    ---@field defenseType   integer
    local currentInstance, triggeringInstance
    
    ---@diagnostic disable: undefined-global, lowercase-global, cast-local-type, param-type-mismatch, undefined-field

    --further reading on these following types: https://www.hiveworkshop.com/threads/spell-ability-damage-types-and-what-they-mean.316271
    local attacksImmune = {
        [ATTACK_TYPE_MELEE]         = true,
        [ATTACK_TYPE_PIERCE]        = true,
        [ATTACK_TYPE_SIEGE]         = true,
        [ATTACK_TYPE_CHAOS]         = true,
        [ATTACK_TYPE_HERO]          = true
    }
    local damagesImmune = {
        [DAMAGE_TYPE_UNKNOWN]       = true,
        [DAMAGE_TYPE_NORMAL]        = true,
        [DAMAGE_TYPE_ENHANCED]      = true,
        [DAMAGE_TYPE_POISON]        = true,
        [DAMAGE_TYPE_DISEASE]       = true,
        [DAMAGE_TYPE_ACID]          = true,
        [DAMAGE_TYPE_DEMOLITION]    = true,
        [DAMAGE_TYPE_SLOW_POISON]   = true,
        [DAMAGE_TYPE_UNIVERSAL]     = true
    }
    local recursiveDamageType = {
        [DAMAGE_TYPE_PLANT]         = true,
        [DAMAGE_TYPE_DEFENSIVE]     = true,
        [DAMAGE_TYPE_SPIRIT_LINK]   = true
    }

    local readonly
    if _USE_LEVEL_AND_AOE then
        readonly = {
            reset = function()
                readonly.sourceAOE       = 1
                readonly.sourceStacks    = 1
                readonly.originalTarget  = 0
                readonly.originalSource  = 0
            end,
            targets = udg_DamageEventAOEGroup or CreateGroup(),
            onSourceDamage = function()
                Event.SourceDamageEvent(readonly)
                readonly.reset()
                GroupClear(readonly.targets)
            end
        }
        readonly.reset()
    end
    
    local setArmor
    if _USE_ARMOR_MOD then
        ---Handle any desired armor modification.
        ---@param d damageInstance
        ---@param reset? boolean
        function setArmor(d, reset)
            if d.armorPierced then
                BlzSetUnitArmor(d.target, BlzGetUnitArmor(d.target) + (reset and d.armorPierced or -d.armorPierced))
            end
            if d.prevArmorT   ~= d.armorType then
                BlzSetUnitIntegerField(d.target, UNIT_IF_ARMOR_TYPE,   reset and d.prevArmorT   or  d.armorType)
            end
            if d.prevDefenseT ~= d.defenseType then
                BlzSetUnitIntegerField(d.target, UNIT_IF_DEFENSE_TYPE, reset and d.prevDefenseT or  d.defenseType)
            end
        end
    else
        setArmor = DoNothing
    end
    
    local awaitDamagedEvent
    
    local function finish(keepFrozen)
        local d = currentInstance
        if d then
            if awaitDamagedEvent then
                awaitDamagedEvent = false
                setArmor(d, true)
            end
            if d.prevAmt ~= 0 then
                Event.AfterDamageEvent(d)
            end
            currentInstance = nil
        end
        if not keepFrozen then
            Event.freeze(false)
        end
    end
    local GetDamage         = GetEventDamage
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

        local timer;timer = {
            started = false,
            timer   = CreateTimer(),
            finish  = function()
                timer.started = false
                triggeringInstance = nil
                finish()
                if readonly then
                    readonly.onSourceDamage()
                end
                currentInstance = nil
                Event.freeze(false)
            end,
            start   = function(d)
                TimerStart(timer.timer, 0, false, timer.finish)
                timer.started = true
                Event.freeze(true)
                if readonly and not d.isCode then
                    readonly.originalSource  = d.source
                    readonly.originalTarget  = d.target
                end
            end
        }

        onEvent(EVENT_PLAYER_UNIT_DAMAGING, function()
            local amt = GetDamage()
            local d = { ---@type damageInstance
                source              = GetSource(),
                target              = GetTarget(),
                damage              = amt,
                isAttack            = GetIsAttack(),
                isRanged            = false,
                attackType          = GetAttackType(),
                damageType          = GetDamageType(),
                weaponType          = GetWeaponType(),
                prevAmt             = amt,
                userAmt             = amt
            }
            d.isSpell               = d.attackType == ATTACK_TYPE_NORMAL and not d.isAttack
            if Damage.nextType then
                d.userType          = Damage.nextType
                Damage.nextType     = nil
                d.isCode            = true
                if _USE_MELEE_RANGE and d.isAttack and not d.isSpell then
                    d.isMelee       = Damage.nextMelee
                    d.isRanged      = Damage.nextRanged
                end
            else
                d.userType          = 0
                if _USE_MELEE_RANGE and (d.damageType == DAMAGE_TYPE_NORMAL) and d.isAttack then
                    d.isMelee       = IsUnitType(d.source, UNIT_TYPE_MELEE_ATTACKER)
                    d.isRanged      = IsUnitType(d.source, UNIT_TYPE_RANGED_ATTACKER)
                    if d.isMelee and d.isRanged then
                        d.isMelee   = GetHandleId(d.weaponType) == 0 --Melee units play a sound when damaging; in naturally-occuring cases where a
                        d.isRanged  = not d.isMelee                  --unit is both ranged and melee, the ranged attack plays no sound.
                    end
                end
            end
            if timer.started then
                if awaitDamagedEvent and recursiveDamageType[d.damageType] then --WarCraft 3 didn't run the DAMAGED event despite running the DAMAGING event.
                    triggeringInstance = currentInstance
                else
                    finish() --wrap up any previous damage index
                    if readonly and not d.isCode then
                        if d.source ~= readonly.originalSource then
                            readonly.onSourceDamage()
                            readonly.originalSource = d.source
                            readonly.originalTarget = d.target
                        elseif d.target == readonly.originalTarget then
                            readonly.sourceStacks = readonly.sourceStacks + 1
                        elseif not IsUnitInGroup(d.target, readonly.targets) then
                            readonly.sourceAOE = readonly.sourceAOE + 1
                        end
                    end
                end
            else
                timer.start(d)
            end
            if readonly then
                GroupAddUnit(readonly.targets, d.target)
            end
            if _USE_ARMOR_MOD then
                d.armorType      = BlzGetUnitIntegerField(d.target, UNIT_IF_ARMOR_TYPE)
                d.defenseType    = BlzGetUnitIntegerField(d.target, UNIT_IF_DEFENSE_TYPE)
                d.prevArmorT     = d.armorType
                d.prevDefenseT   = d.defenseType
            end
            currentInstance      = d
            
            if amt == 0 then
                Event.ZeroDamageEvent(d)
            elseif d.damageType ~= DAMAGE_TYPE_UNKNOWN then
                Event.PreDamageEvent(d)
                SetAttackType(d.attackType)
                SetDamageType(d.damageType)
                SetWeaponType(d.weaponType)
                SetDamage(d.damage)
                setArmor(d, false)
            end
            awaitDamagedEvent = not triggeringInstance or attacksImmune[d.attackType] or damagesImmune[d.damageType] or not IsUnitType(d.target, UNIT_TYPE_MAGIC_IMMUNE)
        end)
    end
    do
        local GetUnitLife = GetWidgetLife
    
        onEvent(EVENT_PLAYER_UNIT_DAMAGED, function()
            local amt   = GetDamage()
            local d     = currentInstance ---@type damageInstance
            if d.prevAmt == 0 then
                finish()
                return
            elseif awaitDamagedEvent then awaitDamagedEvent = false --the normal scenario.
            else
                finish(true) --spirit link or defensive/thorns recursive damage have finished, and it's time to wrap them up and load the triggering damage data.
                d, currentInstance, triggeringInstance = triggeringInstance, triggeringInstance, nil
            end
            setArmor(d, true)
            d.userAmt = d.damage
            d.damage  = amt
            
            if amt > 0 then
                Event.ArmorDamageEvent(d)
                if _USE_LETHAL then
                    Damage.life = GetUnitLife(d.target) - d.damage
                    if Damage.life <= Damage.DEATH_VAL then
                        Event.LethalDamageEvent(d)
                        
                        d.damage = GetUnitLife(d.target) - Damage.life
                        if d.userType < 0 and Damage.life <= Damage.DEATH_VAL then
                            SetUnitExploded(d.target, true)
                        end
                    end
                end
            end
            if d.damageType ~= DAMAGE_TYPE_UNKNOWN then
                Event.OnDamageEvent(d)
            end
            amt = d.damage
            SetDamage(amt)
            if amt == 0 then
                finish()
            end
        end)
    end
    do
        local opConds = {
            [LESS_THAN]             = "Attack",
            [LESS_THAN_OR_EQUAL]    = "Melee",
            [GREATER_THAN_OR_EQUAL] = "Ranged",
            [GREATER_THAN]          = "Spell",
            [NOT_EQUAL]             = "Code"
        }
        local hideUnknown = "(d.damageType ~= DAMAGE_TYPE_UNKNOWN)"
        local eventConds = {
            PreDamageEvent    = "(d.userType ~= Damage.PURE) or "..hideUnknown,
            ArmorDamageEvent  = "(d.damage > 0)",
            OnDamageEvent     = hideUnknown,
            LethalDamageEvent = "(Damage.life <= Damage.DEATH_VAL)",
            AfterDamageEvent  = hideUnknown,
            AOEDamageEvent    = "(Damage.sourceAOE > 1)"
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
            return Event[name].oldRegister(func, priority)
        end
    end
    do
        local function createRegistry(name)
            Event[name].oldRegister = Event[name].register
            Event[name].register = function(func, priority, _, limitop)
                return Damage.register(name, func, priority, limitop)
            end
        end

        Event.PreDamageEvent        = Event.new(); createRegistry "PreDamageEvent"
        Event.ArmorDamageEvent      = Event.new(); createRegistry "ArmorDamageEvent"
        Event.ZeroDamageEvent       = Event.new(); createRegistry "ZeroDamageEvent"
        Event.OnDamageEvent         = Event.new(); createRegistry "OnDamageEvent"
        Event.AfterDamageEvent      = Event.new(); createRegistry "AfterDamageEvent"
        if _USE_LETHAL then
            Event.LethalDamageEvent = Event.new(); createRegistry "LethalDamageEvent"
        end
        if readonly then
            Event.SourceDamageEvent = Event.new(); createRegistry "SourceDamageEvent"
        end
        if _USE_LEGACY_API then
            if readonly then
                Event.AOEDamageEvent             = Event.new(); createRegistry "AOEDamageEvent"
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
                if _USE_MELEE_RANGE then
                    Damage.nextMelee  = ranged == false --ignore nil parameters
                    Damage.nextRanged = ranged
                end
                Damage.nextType       = Damage.nextType or Damage.CODE
                if attack == nil then
                    attack = (ranged ~= nil) or (damageType == DAMAGE_TYPE_NORMAL)
                end
                UDT(source, target, amount, attack, ranged, attackType, damageType, weaponType)
                finish()
            end)
        end
    end
    UnitDamageTarget = Damage.apply
    
    --[[--------------------------------------------------------------------------------------
        Set references to readonly variables for public use.
    ----------------------------------------------------------------------------------------]]
    Damage.__index = readonly
    function Damage:__newindex(key, val)
        assert(not readonly[key])
        rawset(self, key, val)
    end
    setmetatable(Damage, Damage)
    
    if _USE_GUI then
        udg_NextDamageWeaponT = WEAPON_TYPE_WHOKNOWS

        function UnitDamageTargetBJ(source, target, amount, attackType, damageType)
            local isAttack = udg_NextDamageIsAttack; udg_NextDamageIsAttack = false
            local weapon   = udg_NextDamageWeaponT;  udg_NextDamageWeaponT  = WEAPON_TYPE_WHOKNOWS
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
        ---@param ... string[]
        local function setTypes(debugStrs, varPrefix, ...)
            for _,suffix in ipairs{...} do
                local handle = _G[varPrefix..suffix]
                local debugStr
                if varPrefix =="ATTACK_TYPE_" then
                    --"Normal" in JASS2 used to be the melee unit attack type, but was also used used for Spells (both dealt flat damage in RoC).
                    --Their names in the editor were updated to align with the TFT naming convention, but the JASS2 variables were not.
                    if     suffix == "NORMAL" then suffix = "SPELLS"
                    elseif suffix == "MELEE"  then suffix = "NORMAL" end
                elseif suffix == "WHOKNOWS" then
                    suffix   = "NONE"
                    debugStr = "NONE"
                    goto preserveFormat
                elseif varPrefix == "WEAPON_TYPE_" then
                    debugStr = suffix
                    suffix   = suffix:gsub("_([A-Z]*)_", "_\x251_")     --METAL_LIGHT_SLICE -> METAL_L_SLICE        (var name only)
                    goto preserveDebug
                elseif suffix == "NONE" then
                    suffix = "UNARMORED" --"Unarmored" is what's displayed in-game and in the editor.
                end
                debugStr = suffix
                ::preserveDebug::
                debugStr = debugStr:gsub("_", " "):gsub("([A-Z]+)", CAPStoCap) --"METAL_LIGHT_SLICE" -> "Metal Light Slice"
                ::preserveFormat::
                debugStrs[handle] = debugStr
                _G["udg_"..varPrefix..suffix] = handle
            end
        end
        setTypes(udg_ArmorTypeDebugStr,   "ARMOR_TYPE_",   "FLESH",  "WOOD",   "METAL",  "ETHEREAL", "STONE", "WHOKNOWS") --Affects the sound that plays on-hit. "WHOKNOWS" is unselectable in Object Editor.
        setTypes(udg_DefenseTypeDebugStr, "DEFENSE_TYPE_", "NONE",   "LIGHT",  "MEDIUM", "LARGE",    "FORT",  "HERO", "DIVINE", "NORMAL")  --vulnerabilities to attack types. NORMAL takes 100% from all attack types, but was removed from ladder with balance changes introduced in The Frozen Throne expansion.
        setTypes(udg_AttackTypeDebugStr,  "ATTACK_TYPE_",            "PIERCE", "MELEE",  "MAGIC",    "SIEGE", "HERO", "CHAOS",  "NORMAL")  --"NORMAL" is used by all WC3 spells. Further reading: http://classic.battle.net/war3/basics/armorandweapontypes.shtml
        setTypes(udg_DamageTypeDebugStr,  "DAMAGE_TYPE_",
            "MAGIC",  "LIGHTNING", "DIVINE", "SONIC",   "COLD", "SHADOW_STRIKE", "DEFENSIVE",  "SPIRIT_LINK", "FORCE", "PLANT", "DEATH", "FIRE", "MIND",--Cannot affect spell immune units. "MIND" never occurs naturally in WC3.
            "NORMAL", "ENHANCED",  "POISON", "DISEASE", "ACID", "SLOW_POISON",   "DEMOLITION", "UNKNOWN",     "UNIVERSAL")                              --Can affect Spell Immune units. https://www.hiveworkshop.com/threads/spell-ability-damage-types-and-what-they-mean.316271/
        setTypes(udg_WeaponTypeDebugStr,  "WEAPON_TYPE_", "WHOKNOWS", --Affects the sound that plays on-hit.
            "METAL_LIGHT_CHOP",  "METAL_MEDIUM_CHOP",  "METAL_HEAVY_CHOP",   "AXE_MEDIUM_CHOP", --METAL & AXE CHOP
             "WOOD_LIGHT_BASH",   "WOOD_MEDIUM_BASH",   "WOOD_HEAVY_BASH", "METAL_MEDIUM_BASH", "METAL_HEAVY_BASH", "ROCK_HEAVY_BASH", --METAL, WOOD & ROCK BASH
            "METAL_LIGHT_SLICE", "METAL_MEDIUM_SLICE", "METAL_HEAVY_SLICE",  --METAL SLICE
            --None of the following can be selected in the Object Editor:
                "WOOD_LIGHT_SLICE",  "WOOD_MEDIUM_SLICE",  "WOOD_HEAVY_SLICE",  --WOOD SLICE
                "CLAW_LIGHT_SLICE",  "CLAW_MEDIUM_SLICE",  "CLAW_HEAVY_SLICE",  --CLAW SLICE
                "WOOD_LIGHT_STAB",   "WOOD_MEDIUM_STAB",                      "METAL_MEDIUM_STAB", "METAL_HEAVY_STAB") --WOOD & METAL STAB
        
        GlobalRemapArray("udg_CONVERTED_ATTACK_TYPE", function(attackType) return attackType end)
        GlobalRemapArray("udg_CONVERTED_DAMAGE_TYPE", function(damageType) return damageType end)
        
        if readonly then
            remap("udg_DamageEventAOE",         function() return readonly.sourceAOE end)
            remap("udg_DamageEventLevel",       function() return readonly.sourceStacks end)
            remap("udg_AOEDamageSource",        function() return readonly.originalSource end)
            remap("udg_EnhancedDamageTarget",   function() return readonly.originalTarget end)
        end
        remap("udg_LethalDamageHP",      function() return Damage.life end, function(var) Damage.life = var end)
        remap("udg_NextDamageType", nil, function(val) Damage.nextType = val end)

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
        map("udg_DamageEventType",    "userType",   true, true)
        map("udg_DamageEventAttackT", "attackType", true, true)
        map("udg_DamageEventDamageT", "damageType", true, true)
        map("udg_DamageEventWeaponT", "weaponType", true, true)
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
