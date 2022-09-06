OnLibraryInit({
    "Timed",                        --https://www.hiveworkshop.com/threads/timed-call-and-echo.339222/
    "GlobalRemap",                  --https://www.hiveworkshop.com/threads/global-variable-remapper.339308
    "RegisterAnyPlayerUnitEvent",   --https://www.hiveworkshop.com/threads/collection-gui-repair-kit.317084/
    "CreateEvent"                   --https://www.hiveworkshop.com/threads/event-gui-friendly.339451/
},
--[[
Lua Unit Event 1.0

Supports linked events that allow your trigger to Wait until another event runs!

Variable names have been completely changed from all prior Unit Event incarnations.
> All real variable event names are now prefixed with OnUnit...
> All array references (unit properties) are now prefixed with UnitEvent_
> Lua users can access a unit's properties via UnitEvent[unit].property (e.g. reincarnating/cargo)
> Lua users can easily add a GUI property to a unit via UnitEvent.addProperty("udg_PropertyName", "luaPropertyName")
>>> The first parameter is accessed via GUI, the second is accessed via UnitEvent[unit].luaPropertyName
> UnitUserData (custom value of unit) has been completely removed. This is the first unit indexer to not use UnitUserData nor hashtables.
>>> UnitEvent_unit is the subject unit of the event.
>>> UnitEvent_index is an integer in GUI, but points to a the unit.
>>> UnitEvent_setKey lets you assign a unit to the key.
>>> UnitEvent_getKey is an integer in GUI, but points to the unit you assigned as the key.
>>>>> Lua doesn't care about array max sizes, nor the type of information used as an index in that array (because it uses tables and not arrays).
>>>>> GUI is over 20 years old and can easily be fooled. As long as the variable is defined with the correct type, it doesn't care what happens to that variable behind the scenes.
--]]
function() UnitEvent={}

    local _REMOVE_ABIL      = FourCC('A001')
    local _TRANSFORM_ABIL   = FourCC('A002') --be sure to assign these to their respective abilities if you prefer not to initialize via GUI
    
--[[
    Full list of GUI variables:
    real    udg_OnUnitIndexed
    real    udg_OnUnitCreation
    real    udg_OnUnitRemoval
    real    udg_OnUnitReincarnating
    real    udg_OnUnitRevival
    real    udg_OnUnitLoaded
    real    udg_OnUnitUnloaded
    real    udg_OnUnitTransform
    real    udg_OnUnitDeath
    real    udg_OnUnitActive
    real    udg_OnUnitPassive

    ability udg_DetectRemoveAbility
    ability udg_DetectTransformAbility

    unit    udg_UnitEvent_unit
    integer udg_UnitEvent_index

    unit    udg_UnitEvent_setKey
    integer udg_UnitEvent_getKey

    boolean   array udg_UnitEvent_preplaced
    unit      array udg_UnitEvent_summoner
    unittype  array udg_UnitEvent_unitType
    boolean   array udg_UnitEvent_reincarnating
    unit      array udg_UnitEvent_transporter
    unitgroup array udg_UnitEvent_cargo
--]]

    local eventList={}
    local makeAPI = function(luaName, ...)
        local register, run = CreateEvent(...)
        eventList[luaName]  = run
        UnitEvent[luaName]  = register
    end
    local unitIndices={} ---@type UnitEventTable[]

    --onIndexed and onCreation occur at roughly the same time, but the unit's creation should be used instead as it will have more data.
    --Combined, they are the counterparts to onRemoval.
    makeAPI("onIndexed",  "udg_OnUnitIndexed", 0)
    makeAPI("onCreation", "udg_OnUnitCreation", "udg_OnUnitIndexed")
    makeAPI("onRemoval",  "udg_OnUnitRemoval",  "udg_OnUnitCreation")

    --counterparts (though revival doesn't only come from reincarnation):
    makeAPI("onReincarnating", "udg_OnUnitReincarnating", "udg_OnUnitCreation")
    makeAPI("onRevival",       "udg_OnUnitRevival",       "udg_OnUnitReincarnating")
    
    --perfect counterparts:
    makeAPI("onLoaded",   "udg_OnUnitLoaded",   "udg_OnUnitCreation")
    makeAPI("onUnloaded", "udg_OnUnitUnloaded", "udg_OnUnitLoaded")
    
    --stand-alone events:
    makeAPI("onTransform", "udg_OnUnitTransform", "udg_OnUnitCreation")
    makeAPI("onDeath",     "udg_OnUnitDeath",     "udg_OnUnitIndexed")
    
    --perfect counterparts:
    makeAPI("onActive",  "udg_OnUnitActive", 0)
    makeAPI("onPassive", "udg_OnUnitPassive", "udg_OnUnitActiveEvent")

    ---@param unit unit
    ---@return UnitEventTable
    UnitEvent.__index = function(_, unit) return unitIndices[unit] end
    
    ---@param udgName string
    ---@param luaName string
    UnitEvent.addProperty = function(udgName, luaName)
        GlobalRemapArray(udgName, function(unit) return unitIndices[unit][luaName] end)
    end

    ---@class UnitEventTable : table
    ---@field unit          unit
    ---@field preplaced     boolean
    ---@field summoner      unit
    ---@field transporter   unit
    ---@field cargo         group
    ---@field reincarnating boolean
    ---@field private new boolean
    ---@field private alive boolean
    ---@field private unloading boolean
    
    --The below two variables are intended for GUI typecasting, because you can't use a unit as an array index.
    --What it does is bend the rules of GUI (which is still bound by strict JASS types) by transforming those
    --variables with Global Variable Remapper (which isn't restricted by any types).
    --"setKey" is write-only (assigns the key to a unit)
    --"getKey" is read-only (retrieves the key and tells GUI that it's an integer, allowing it to be used as an array index)
    local lastUnit
    GlobalRemap("udg_UnitEvent_setKey", nil, function(unit)lastUnit=unit end) --assign to a unit to unlock the getKey variable.
    GlobalRemap("udg_UnitEvent_getKey",      function() return lastUnit  end) --type is "integer" in GUI but remains a unit in Lua.
    
    local runEvent
    do
        local eventUnit
        local getEventUnit  = function() return eventUnit end
        runEvent            = function(event, unitTable)
            local cached    = eventUnit
            eventUnit       = unitTable.unit
            eventList[event](unitTable)
            eventUnit       = cached
        end
        GlobalRemap("udg_UnitEvent_unit",  getEventUnit) --the subject unit for the event.
        GlobalRemap("udg_UnitEvent_index", getEventUnit) --fools GUI into thinking unit is an integer
    end
    --add a bunch of read-only arrays to access GUI data. I've removed the "IsUnitAlive" array as the GUI living checks are fixed with the GUI Enhancer Colleciton.
    UnitEvent.addProperty("udg_UnitEvent_preplaced",    "preplaced")
    UnitEvent.addProperty("udg_UnitEvent_unitType",     "unitType")
    UnitEvent.addProperty("udg_UnitEvent_reincarnating","reincarnating")
    UnitEvent.addProperty("udg_UnitEvent_transporter",  "transporter")
    UnitEvent.addProperty("udg_UnitEvent_summoner",     "summoner")
    
    do
        local cargo = udg_UnitEvent_cargo
        if cargo then
            DestroyGroup(cargo[0])
            DestroyGroup(cargo[1])
            UnitEvent.addProperty("udg_UnitEvent_cargo", "cargo")
        end
    end
    
    --Flag a unit as being able to move or attack on its own:
    local function setActive(unitTable)
        if unitTable and not unitTable.active and UnitAlive(unitTable.unit) then --be sure not to run the event when corpses are created/unloaded.
            unitTable.active = true
            runEvent("onActive", unitTable)
        end
    end
    ---Flag a unit as NOT being able to move or attack on its own:
    local function setPassive(unitTable)
        if unitTable and unitTable.active then
            unitTable.active = nil
            runEvent("onPassive", unitTable)
        end
    end
    
    UnitEvent.onCreation(setActive, 2, true)
    UnitEvent.onUnloaded(setActive, 2, true)
    UnitEvent.onRevival(setActive, 2, true)
    
    UnitEvent.onLoaded(setPassive, 2, true)
    UnitEvent.onReincarnating(setPassive, 2, true)
    UnitEvent.onDeath(setPassive, 2, true)
    UnitEvent.onRemoval(setPassive, 2, true)
    
    --UnitEvent.onIndex(function(dex) print(tostring(dex.unit).."/"..GetUnitName(dex.unit).." has been indexed.") end)
    
    setmetatable(UnitEvent, UnitEvent)

    --Wait until GUI triggers and events have been initialized. 
    OnTrigInit(function()
        if Trig_Unit_Event_Config_Actions then
            Trig_Unit_Event_Config_Actions()
            _REMOVE_ABIL    = udg_DetectRemoveAbility    or _REMOVE_ABIL
            _TRANSFORM_ABIL = udg_DetectTransformAbility or _TRANSFORM_ABIL
        end
        local function checkAfter(unitTable)
            if not unitTable.checking then
                unitTable.checking              = true
                Timed.call(function()
                    unitTable.checking          = nil
                    if unitTable.new then
                        unitTable.new           = nil
                        runEvent("onCreation", unitTable) --thanks to Spellbound for the idea
                    elseif unitTable.transforming then
                        local unit = unitTable.unit
                        runEvent("onTransform", unitTable)
                        unitTable.unitType = GetUnitTypeId(unit) --Set this afterward to give the user extra reference

                        --Reset the transforming flags so that subsequent transformations can be detected.
                        unitTable.transforming  = nil
                        UnitAddAbility(unit, _TRANSFORM_ABIL)
                    elseif unitTable.alive then
                        unitTable.reincarnating = true
                        unitTable.alive         = false
                        runEvent("onReincarnating", unitTable)
                    end
                end)
            end
        end
    
        local re = CreateRegion()
        local r = GetWorldBounds()
        local maxX, maxY = GetRectMaxX(r), GetRectMaxY(r)
        RegionAddRect(re, r); RemoveRect(r)
        
        local function unloadUnit(unitTable)
            local unit, transport       = unitTable.unit, unitTable.transporter
            GroupRemoveUnit(unitIndices[transport].cargo, unit)
            unitTable.unloading         = true
            runEvent("onUnloaded", unitTable)
            unitTable.unloading         = nil
            if not IsUnitLoaded(unit) or not UnitAlive(transport) or GetUnitTypeId(transport) == 0 then
                unitTable.transporter   = nil
            end
        end
        
        local preplaced = true
        local onEnter = Filter(
        function()
            local unit = GetFilterUnit()
            local unitTable = unitIndices[unit]
            if not unitTable then
                unitTable = {
                    unit    = unit,
                    new     = true,
                    alive   = true,
                    unitType= GetUnitTypeId(unit)
                }
                UnitAddAbility(unit, _REMOVE_ABIL)
                UnitMakeAbilityPermanent(unit, true, _REMOVE_ABIL)
                UnitAddAbility(unit, _TRANSFORM_ABIL)

                unitIndices[unit] = unitTable

                unitTable.preplaced = preplaced
                runEvent("onIndexed", unitTable)
                
                checkAfter(unitTable)
            elseif unitTable.transporter and not IsUnitLoaded(unit) then
                --the unit was dead, but has re-entered the map (e.g. unloaded from meat wagon)
                unloadUnit(unitTable)
            end
        end)
        TriggerRegisterEnterRegion(CreateTrigger(), re, onEnter)
        
        RegisterAnyPlayerUnitEvent(EVENT_PLAYER_UNIT_LOADED,
        function()
            local unit = GetTriggerUnit()
            local unitTable = unitIndices[unit]
            if unitTable then
                if unitTable.transporter then
                    unloadUnit(unitTable)
                end
                --Loaded corpses do not issue an order when unloaded, therefore must
                --use the enter-region event method taken from Jesus4Lyf's Transport: https://www.thehelper.net/threads/transport-enter-leave-detection.126051/
                if not unitTable.alive then
                    SetUnitX(unit, maxX)
                    SetUnitY(unit, maxY)
                end
                local transporter = GetTransportUnit()
                unitTable.transporter = transporter
                if not unitIndices[transporter].cargo then
                    unitIndices[transporter].cargo = CreateGroup()
                end
                GroupAddUnit(unitIndices[transporter].cargo, unit)
                
                runEvent("onLoaded", unitTable)
            end
        end)
        
        RegisterAnyPlayerUnitEvent(EVENT_PLAYER_UNIT_DEATH,
        function()
            local unitTable = unitIndices[GetTriggerUnit()]
            if unitTable then
                unitTable.alive = false
                runEvent("onDeath", unitTable)
                if unitTable.transporter then
                    unloadUnit(unitTable)
                end
            end
        end)
        
        RegisterAnyPlayerUnitEvent(EVENT_PLAYER_UNIT_SUMMON,
        function()
            local unitTable = unitIndices[GetTriggerUnit()]
            if unitTable.new then
                unitTable.summoner = GetSummoningUnit()
            end
        end)
        
        local orderB = Filter(
        function()
            local unit = GetFilterUnit()
            local unitTable = unitIndices[unit]
            if unitTable then
                if GetUnitAbilityLevel(unit, _REMOVE_ABIL) == 0 then

                    runEvent("onRemoval", unitTable)
                    unitIndices[unit] = nil
                    if unitTable.cargo then
                        DestroyGroup(unitTable.cargo)
                    end
                elseif not unitTable.alive then
                    if UnitAlive(unit) then
                        unitTable.alive = true
                        runEvent("onRevival", unitTable)
                        unitTable.reincarnating = nil
                    end
                elseif not UnitAlive(unit) then
                    if unitTable.new then
                        --This unit was created as a corpse.
                        unitTable.alive = nil
                        runEvent("onDeath", unitTable)

                    elseif unitTable.transporter or not IsUnitType(unit, UNIT_TYPE_HERO) then
                        --The unit may have just started reincarnating.
                        checkAfter(unitTable)
                    end
                elseif GetUnitAbilityLevel(unit, _TRANSFORM_ABIL) == 0 and not unitTable.transforming then
                    unitTable.transforming = true
                    checkAfter(unitTable)
                end
                if unitTable.transporter and not unitTable.unloading and not (IsUnitLoaded(unit) and UnitAlive(unit)) then
                    unloadUnit(unitTable)
                end
            end
        end)
        
        local p
        local order = CreateTrigger()
        for i = 0, bj_MAX_PLAYER_SLOTS - 1 do
            p = Player(i)
            GroupEnumUnitsOfPlayer(bj_lastCreatedGroup, p, onEnter)
            SetPlayerAbilityAvailable(p, _REMOVE_ABIL, false)
            SetPlayerAbilityAvailable(p, _TRANSFORM_ABIL, false)
            TriggerRegisterPlayerUnitEvent(order, p, EVENT_PLAYER_UNIT_ISSUED_ORDER, orderB)
        end
        preplaced = nil
    end)
end)
