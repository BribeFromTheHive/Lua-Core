if  Timed                   --https://www.hiveworkshop.com/threads/timed-call-and-echo.339222/
and GlobalRemap             --https://www.hiveworkshop.com/threads/global-variable-remapper.339308
and AnyPlayerUnitEvent      --https://www.hiveworkshop.com/threads/collection-gui-repair-kit.317084/
and Event then              --https://www.hiveworkshop.com/threads/event-gui-friendly.339451/

OnGlobalInit(1, function()
    local _USER_DATA    = true --Whether to use SetUnitUserData to map the unit's handle Id to its userdata (true) or just use GetHandleId(false)
    
    local _REMOVE_ABIL      --= FourCC('A001')
    local _TRANSFORM_ABIL   --= FourCC('A002') --un-comment these and assign them to the respective abilities if you prefer not to initialize via GUI
    
    local _USE_ACTIVITY = true --adds a small overhead if true and you don't use the "active/inactive" events
    
    UnitEvent = { --Lua Unit Event 1.0.0.0
        onIndex         = Event.create("udg_OnUnitIndex", EQUAL),
        onCreate        = Event.create("udg_OnUnitCreate"),                     --counterpart: onRemoval
        onRemoval       = Event.create("udg_OnUnitIndex", NOT_EQUAL),

        onDeath         = Event.create("udg_OnUnitDeath", EQUAL),
        onReincarnate   = Event.create("udg_OnUnitReincarnate"),                --counterpart: onRevival
        onRevival       = Event.create("udg_OnUnitDeath", NOT_EQUAL),
        
        onLoaded        = Event.create("udg_OnUnitLoaded", EQUAL),
        onUnloaded      = Event.create("udg_OnUnitLoaded", NOT_EQUAL),

        onActive        = Event.create("udg_OnUnitActiveEvent", EQUAL),
        onInactive      = Event.create("udg_OnUnitActiveEvent", NOT_EQUAL),

        onTransform     = Event.create("udg_OnUnitTransform")  --counterpart: none
    }
    ---@class UnitEvent : table
    ---@field cargo group
    ---@field transporter unit
    ---@field summoner unit
    ---@field private new boolean
    ---@field private alive boolean
    ---@field unit unit
    ---@field preplaced boolean
    ---@field reincarnating boolean
    ---@field private unloading boolean

    local lastUnit  = nil
    local lastId    = 0
    local unitIndices = {}    ---@type UnitEvent[]

    --The below two functions are useful for GUI when _USER_DATA is set to "false". To use them:
    --Set UnitIndexUnit = (Triggering unit)
    -- OR 
    --Set UnitIndexId = (Index that belongs to said unit)
    --Once either of those were set, you can reference "UnitIndexUnit" and "UnitIndexId" as a unit and integer, respectively.
    --For GUI, it is obviously easier to just use (Custom value of Unit) so in such cases I just recommend setting _USER_DATA to "true"
    GlobalRemap("udg_UnitIndexUnit", function() return lastUnit end, function(whichUnit) lastUnit = whichUnit; lastId = GetHandleId(whichUnit) end)
    GlobalRemap("udg_UnitIndexId", function() return lastId end, function(whichId) lastUnit = unitIndices[whichId].unit; lastId = whichId end)

    GlobalRemap("udg_UDex", function() return Event.args[1].id end)
    
    local function map(arrStr, valStr)
        GlobalRemapArray(arrStr, function(id) return unitIndices[id][valStr] end)
    end
    
    map("udg_UDexUnits", "unit")
    map("udg_IsUnitPreplaced", "preplaced")
    map("udg_UnitTypeOf", "unitType")
    map("udg_IsUnitNew", "new")
    map("udg_IsUnitAlive", "alive")
    map("udg_IsUnitReincarnating", "reincarnating")
    map("udg_CargoTransportUnit", "transporter")
    map("udg_SummonerOfUnit", "summoner")
    
    do
        local cargo = udg_CargoTransportGroup
        if cargo then
            DestroyGroup(cargo[0])
            DestroyGroup(cargo[1])
            map("udg_CargoTransportGroup", "cargo")
        end
    end
    
    if _USE_ACTIVITY then
        local function setActive(unitTable)
            if unitTable and not unitTable.active and UnitAlive(unitTable.unit) then
                unitTable.active = true
                UnitEvent.onActive:run(unitTable)
            end
        end
        local function setInactive(unitTable)
            if unitTable and unitTable.active then
                unitTable.active = nil
                UnitEvent.onInactive:run(unitTable)
            end
        end
        
        UnitEvent.onCreate(setActive)
        UnitEvent.onRevival(setActive)
        UnitEvent.onUnloaded(setActive)
        
        UnitEvent.onDeath(setInactive)
        UnitEvent.onRemoval(setInactive)
        UnitEvent.onLoaded(setInactive)
        UnitEvent.onReincarnate(setInactive)
    end
    
    --UnitEvent.onIndex:register(function(id) print(id.id) end)
    
    OnTrigInit(function()
        local func = Trig_Unit_Event_Config_Actions
        if func then
            func()
            _REMOVE_ABIL    = udg_DetectRemoveAbility or _REMOVE_ABIL
            _TRANSFORM_ABIL = udg_DetectTransformAbility or _TRANSFORM_ABIL
        end
        
        local function checkAfter(unitTable)
            if not unitTable.checking then
                unitTable.checking = true
                Timed.call(function()
                    unitTable.checking = nil
                    if unitTable.new then
                        unitTable.new = nil
                        UnitEvent.onCreate:run(unitTable) --thanks to Spellbound for the idea
                    elseif unitTable.transforming then
                       UnitEvent.onTransform:run(unitTable)
                       unitTable.unitType = GetUnitTypeId(unitTable.unit) --Set this afterward to give the user extra reference
                       unitTable.transforming = nil
                       UnitAddAbility(unitTable.unit, _TRANSFORM_ABIL)
                    elseif unitTable.alive then
                        unitTable.reincarnating = true
                        unitTable.alive = false
                        UnitEvent.onReincarnate:run(unitTable)
                    end
                end)
            end
        end
    
        local re = CreateRegion()
        local r = GetWorldBounds()
        local maxX, maxY = GetRectMaxX(r), GetRectMaxY(r)
        RegionAddRect(re, r); RemoveRect(r)
        
        local function unload(unitTable)
            GroupRemoveUnit(unitIndices[GetHandleId(unitTable.transporter)].cargo, unitTable.unit)
            unitTable.unloading = true
            UnitEvent.onUnloaded:run(unitTable)
            unitTable.unloading = nil
            if not IsUnitLoaded(unitTable.unit) or not UnitAlive(unitTable.transporter) or GetUnitTypeId(unitTable.transporter) == 0 then
                unitTable.transporter = nil
            end
        end
        
        local preplaced = true
        local onEnter = Filter(
        function()
            local u = GetFilterUnit()
            local id = GetHandleId(u)
            local unitTable = unitIndices[id]
            if not unitTable then
                unitTable = {
                    unit    = u,
                    id      = id,
                    new     = true,
                    alive   = true,
                    unitType= GetUnitTypeId(u)
                }
                
                UnitAddAbility(u, _REMOVE_ABIL)
                UnitMakeAbilityPermanent(u, true, _REMOVE_ABIL)
                UnitAddAbility(u, _TRANSFORM_ABIL)

                unitIndices[id] = unitTable
                
                --print(GetUnitName(u) .. " has been indexed to " .. id)

                if _USER_DATA then SetUnitUserData(u, id) end

                unitTable.preplaced = preplaced
                UnitEvent.onIndex:run(unitTable)
                
                checkAfter(unitTable)
            elseif unitTable.transporter and not IsUnitLoaded(u) then
                --the unit was dead, but has re-entered the map (unloaded from meat wagon)
                unload(unitTable)
            end
        end)
        TriggerRegisterEnterRegion(CreateTrigger(), re, onEnter)
        
        AnyPlayerUnitEvent.add(EVENT_PLAYER_UNIT_LOADED,
        function()
            local u = GetTriggerUnit()
            local unitTable = unitIndices[GetHandleId(u)]
            if unitTable then
                if unitTable.transporter then
                    unload(unitTable)
                end
                --Loaded corpses do not issue an order when unloaded, therefore must
                --use the enter-region event method taken from Jesus4Lyf's Transport.
                if not unitTable.alive then
                    SetUnitX(u, maxX)
                    SetUnitY(u, maxY)
                end
               
                unitTable.transporter = GetTransportUnit()
                if not unitTable.transporter.cargo then
                    unitTable.transporter.cargo = CreateGroup()
                end
                GroupAddUnit(unitTable.transporter.cargo, u)
                
                UnitEvent.onLoaded:run(unitTable)
            end
        end)
        
        AnyPlayerUnitEvent.add(EVENT_PLAYER_UNIT_DEATH,
        function()
            local unitTable = unitIndices[GetTriggerUnit()]
            if unitTable then
                unitTable.alive = false
                UnitEvent.onDeath:run(unitTable)
                if unitTable.transporter then
                    unload(unitTable)
                end
            end
        end)
        
        AnyPlayerUnitEvent.add(EVENT_PLAYER_UNIT_SUMMON,
        function()
            local unitTable = GetHandleId(GetTriggerUnit())
            if unitTable.new then
                unitTable.summoner = GetSummoningUnit()
            end
        end)
        
        local orderB = Filter(
        function()
            local u = GetFilterUnit()
            local unitTable = unitIndices[GetHandleId(u)]
            if unitTable then
                if GetUnitAbilityLevel(u, _REMOVE_ABIL) == 0 then
                    unitTable[GetHandleId(u)] = nil

                    if unitTable.cargo then DestroyGroup(unitTable.cargo) end
                    
                    UnitEvent.onRemoval:run(unitTable)
                    
                elseif not unitTable.alive then
                    if UnitAlive(u) then
                        unitTable.alive = true
                        UnitEvent.onRevival:run(unitTable)
                        unitTable.reincarnating = nil
                    end
                elseif not UnitAlive(u) then
                    if unitTable.new then
                        --This unit was created as a corpse.
                        unitTable.alive = nil
                        UnitEvent.onDeath:run(unitTable)

                    elseif unitTable.transporter or not IsUnitType(u, UNIT_TYPE_HERO) then
                        --The unit may have just started reincarnating.
                        checkAfter(unitTable)
                    end
                elseif GetUnitAbilityLevel(u, _TRANSFORM_ABIL) == 0 and not unitTable.transforming then
                    unitTable.transforming = true
                    checkAfter(unitTable)
                end
                if unitTable.transporter and not unitTable.unloading and (not IsUnitLoaded(u) or not UnitAlive(u)) then
                    unload(unitTable)
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
end