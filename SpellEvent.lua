--Lua Spell Event v1.0
OnLibraryInit({
    "Timed",                        --https://www.hiveworkshop.com/threads/timed-call-and-echo.339222/
    "GlobalRemap",                  --https://www.hiveworkshop.com/threads/global-variable-remapper.339308
    "RegisterAnyPlayerUnitEvent",   --https://www.hiveworkshop.com/threads/collection-gui-repair-kit.317084/
    "CreateEvent"                   --https://www.hiveworkshop.com/threads/event-gui-friendly.339451/
    --PreciseWait*                  --https://www.hiveworkshop.com/threads/precise-wait-gui-friendly.316960/
},
function()
    SpellEvent={}

    local _AUTO_ORDER = "spellsteal" --If TriggerRegisterCommandEvent is called and this order is specified,
    --ignore the actual request and instead allow it to be treated as an aiblity to be registered by Spell System.
    --In GUI, this event looks like: Game - Button for ability Animate Dead and order Human Spellbreaker - Spell Steal pressed.
    --If you actually WANT to use this order with this event, you could assign this to a different order (e.g. "battleroar").
    --If you want to be using ALL of these, then I recommend waiting until OnGameStart to call your own TriggerRegisterCommandEvent.

    --[=========================================================================================[
    Required GUI:
    
    Events work differently, and it's now allowed to create a spell without being forced into using a separate Config trigger.
        real udg_OnSpellChannel
        real udg_OnSpellCast
        real udg_OnSpellEffect
        real udg_OnSpellFinish

    The below preserve the API from the vJass version:
        unit        udg_Spell__Caster           -> When set, will assign Spell__Index to whatever the last spell this unit cast was.
        player      udg_Spell__CasterOwner
        location    udg_Spell__CastPoint
        location    udg_Spell__TargetPoint
        unit        udg_Spell__Target
        integer     udg_Spell__Index            -> Now is a Lua table behind the scenes.
        integer     udg_Spell__Level
        real        udg_Spell__LevelMultiplier
        abilcode    udg_Spell__Ability
        boolean     udg_Spell__Completed
        boolean     udg_Spell__Channeling
        real        udg_Spell__Duration

    Thanks to Lua, the above variables are read-only, as intended.

    New to Lua:
        real            udg_Spell__wait         -> Replaces Spell__Time. Use this instead of a regular wait to preserve event data after the wait.
        integer         udg_Spell__whileChannel -> The loop will continue up until the point where the caster stops channeling the spell.
        integer         udg_Spell__forDuration  -> Set Spell__Duration before entering the loop, then the loop will continue for the duration.
        string          udg_Spell__abilcode     -> Useful for debugging purposes.

        All of the other variables will be deprecated; possibly at some future point split into separate systems.
    --]=========================================================================================]
    
    local eventSpells,trigAbilMap = {},{}
    local oldCommand
    SpellEvent.__index = function(_,unit) return eventSpells[unit] end
    
    local eventSpell
    SpellEvent.addProperty = function(name, getter, setter)
        getter = getter or function() return eventSpell[name] end
        GlobalRemap("udg_Spell__"..name, getter, setter)
    end
    SpellEvent.addProperty("Index", function() return eventSpell end)
    SpellEvent.addProperty("Caster", nil, function(unit) eventSpell = eventSpells[unit] end)
    SpellEvent.addProperty("Ability")
    SpellEvent.addProperty("Target")
    SpellEvent.addProperty("CasterOwner")
    SpellEvent.addProperty("Completed")
    SpellEvent.addProperty("Channeling")
    do
        local getLevel = function() return eventSpell.Level end
        SpellEvent.addProperty("Level", getLevel)
        SpellEvent.addProperty("LevelMultiplier", getLevel)
    end do
        local getUnitPoint = function(unit, point)
            MoveLocation(point, GetUnitX(unit), GetUnitY(unit))
            return point
        end
        local casterPoint = Location(0,0)
        SpellEvent.addProperty("CastPoint", function()
            return getUnitPoint(eventSpell.Caster, casterPoint)
        end)
        local targetPoint = Location(0,0)
        SpellEvent.addProperty("TargetPoint", function()
            if eventSpell.Target then
                return getUnitPoint(eventSpell.Target, targetPoint)
            end
            MoveLocation(targetPoint, eventSpell.x, eventSpell.y)
            return targetPoint
        end)
    end
    local durationTracker = {__mode="k"}
    setmetatable(durationTracker, durationTracker)
    GlobalRemap("udg_Spell__wait", nil, function(duration)
        local spell = eventSpell
        PolledWait(duration)
        eventSpell = spell --it's really this simple, thanks to PreciseWait and Global variable Remapper.
        local co = coroutine.running()
        if durationTracker[co] and durationTracker[co] > 0 then
            durationTracker[co] = durationTracker[co] - duration
        end
    end)
    GlobalRemap("udg_Spell__Duration", function() return durationTracker[coroutine.running()] end, function(val) durationTracker[coroutine.running()] = val end)
    GlobalRemap("udg_Spell__forDuration", function()
        local co = coroutine.running()
        return durationTracker[co] and durationTracker[co] > 0 and -1 or 1
    end)
    GlobalRemap("udg_Spell__whileChannel", function() return eventSpell.Channeling and -1 or 1 end)
    GlobalRemap("udg_Spell__abilcode", function()
        if not eventSpell then return"nil"end
        local value = eventSpell.Ability
        local result = ""
        for _=1,4 do
            result = string.char(value %% 256) .. result --crazy that World Editor needs double percentage symbols
            value = value // 256
        end
        return result
    end)

    local eventList         = {}
    local coreFunc          = function()
        local caster        = GetTriggerUnit()
        local ability       = GetSpellAbilityId()
        local whichEvent    = GetTriggerEventId()
        local cache         = eventSpell
        eventSpell          = eventSpells[caster]
        if not eventSpell or not eventSpell.Channeling then
            eventSpell      = {
                Caster      = caster,
                Ability     = ability,
                Level       = GetUnitAbilityLevel(caster, ability),
                CasterOwner = GetTriggerPlayer(),
                Target      = GetSpellTargetUnit(),
                x           = GetSpellTargetX(),
                y           = GetSpellTargetY(),
                Channeling  = true
            }
            eventSpells[caster] = eventSpell
            if whichEvent == EVENT_PLAYER_UNIT_SPELL_CHANNEL then
                eventList.onChannel(eventSpell)
            else --whichEvent == EVENT_PLAYER_UNIT_SPELL_EFFECT
                eventSpell.Channeling = false
                eventList.onEffect(eventSpell) --In the case of Charge Gold and Lumber, only an OnEffect event will run.
            end
        elseif whichEvent == EVENT_PLAYER_UNIT_SPELL_CAST then
            eventList.onCast(eventSpell)
        elseif whichEvent == EVENT_PLAYER_UNIT_SPELL_EFFECT then
            eventList.onEffect(eventSpell)
        elseif whichEvent == EVENT_PLAYER_UNIT_SPELL_FINISH then
            eventSpell.Completed    = true
        else --whichEvent == EVENT_PLAYER_UNIT_SPELL_ENDCAST
            eventSpell.Channeling   = false
            eventList.onFinish(eventSpell)
        end
        eventSpell=cache
    end

    --Fairly complicated, but if a user registers multiple abilities to one event AND any of them were
    --already registered by another trigger, we have to do this.
    local valid
    local getCompare = function(func, abil)
        valid = valid or {}
        local check = valid[func]
        if not check then
            check = {}
            valid[func] = check
            local old = func
            func = function(spell)
                if check[spell.Ability] then
                    old(spell)
                end
            end
        end
        check[abil] = true
        return func
    end
    local makeAPI   = function(name)
        local reg, run, cachedAbil
        local abils = {}
        reg, run    = CreateEvent("udg_OnSpell"..name, true, 1, function(func, continue, firstReg, trigRef)
            local exit
            if firstReg then
                if trigRef then
                    for i=#trigAbilMap, 1, -1 do
                        local map = trigAbilMap[i]
                        if map[1]==trigRef then
                            local abil = map[2]
                            if abils[abil] then
                                --Multiple functions want access to the same spell. Shouldn't happen very often, but if it does,
                                --any subsequent registration will simply check the spell ID as a condition.
                                func = getCompare(func, abil)
                            else
                                exit=true
                                abils[abil]=func
                            end
                        else
                            trigAbilMap={}
                            break
                        end
                    end
                elseif cachedAbil then
                    if abils[cachedAbil] then
                        func = getCompare(func, cachedAbil)
                    else
                        abils[cachedAbil] = func
                        exit = true
                    end
                    cachedAbil=nil
                end
            end
            return continue(func, exit)
        end)
        SpellEvent["on"..name] = function(abil, ...)
            cachedAbil=abil
            reg(...)
            cachedAbil=nil
        end
        eventList["on"..name] = function(spell)
            --print("running "..name)
            run(spell, abils[spell.Ability])
        end
    end

    local spellStrs  = {"Channel","Cast","Effect","Finish","Endcast"}
    for _,name in ipairs(spellStrs) do
        if name~="Endcast" then
            makeAPI(name)
        end
        RegisterAnyPlayerUnitEvent(_G["EVENT_PLAYER_UNIT_SPELL_"..string.upper(name)], coreFunc)
    end
    oldCommand, remove = AddHook("TriggerRegisterCommandEvent", function(whichTrig, whichAbil, whichOrder)
        if whichOrder==_AUTO_ORDER then
            if trigAbilMap[1] and whichTrig ~= trigAbilMap[1][1] then
                trigAbilMap={}
            end
            table.insert(trigAbilMap, {whichTrig, whichAbil})
        else
            oldCommand(whichTrig, whichAbil, whichOrder) --normal use of this event has been requested.
        end
    end)
    OnMapInit(remove) --remove the hook once the map initialization triggers have run.
    
    setmetatable(SpellEvent, SpellEvent)
end)
