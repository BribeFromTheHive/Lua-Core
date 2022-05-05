if  GlobalRemap             --https://www.hiveworkshop.com/threads/global-variable-remapper.339308
and Event then              --

OnGlobalInit(1, function()
    local _MAX_WASTED   = 16    --Every _MAX_WASTED units created after map initialization, run the "garbage collector"
    local _USER_DATA    = false --Whether to use SetUnitUserData to map the unit's handle Id to its userdata (true) or just use GetHandleId(false)
    
    local indexed   = LinkedList.create() ---@type unitIndex
    ---@class unitIndex:LinkedListNode
    ---@field id integer
    ---@field unit unit
    ---@field loop fun() -> unitIndex
 
    local lastUnit  = nil
    local lastId    = 0
    local unitIndex = {}    ---@type unitIndex[]
 
    --The below two functions are useful for GUI when _USER_DATA is set to "false". To use them:
    --Set UnitIndexUnit = (Triggering unit)
    -- OR
    --Set UnitIndexId = (Index that belongs to said unit)
    --Once either of those were set, you can reference "UnitIndexUnit" and "UnitIndexId" as a unit and integer, respectively.
    --For GUI, it is obviously easier to just use (Custom value of Unit) so in such cases I just recommend setting _USER_DATA to "true"
    GlobalRemap("udg_UnitIndexUnit", function() return lastUnit end, function(whichUnit) lastUnit = whichUnit; lastId = GetHandleId(whichUnit) end)
    GlobalRemap("udg_UnitIndexId", function() return lastId end, function(whichId) lastUnit = unitIndex[whichId].unit; lastId = whichId end)
 
    GlobalRemap("udg_UDex", function() return Event.args[2] end)
    GlobalRemapArray("udg_UDexUnits", function(id) return unitIndex[id].unit end)
 
    ---Run an index or deindex event and factor in recursion
    ---@param eventFunc function
    ---@param unitTable unitIndex
    local function runEvent(eventFunc, unitTable)
       eventFunc:run(unitTable, unitTable.id)
    end
    
    Event.onUnitIndex = Event.create("UnitIndexEvent", EQUAL)
    Event.onUnitDeindex = Event.create("UnitIndexEvent", NOT_EQUAL)

    --Event.onUnitIndex(function() print(Event.args[2]) end)

    local wasted = 0
    local preplaced = true

    OnTrigInit(function()
        local re = CreateRegion()
        local r = GetWorldBounds()
        RegionAddRect(re, r); RemoveRect(r)
        local b = Filter(
        function()
            local u = GetFilterUnit()
            local id = GetHandleId(u)
            local unitTable = unitIndex[id]
            if not unitTable then
                if not preplaced then -- No need to check for removed units during the beginning of the game sequence
                    wasted = wasted + 1
                    if wasted > _MAX_WASTED then
                        for node in indexed:loop() do
                            if GetUnitTypeId(node.unit) == 0 then
                                runEvent(Event.onUnitDeindex, node) -- Run the deindex event
                                udg_IsUnitPreplaced[node.id] = nil
                                node:remove()
                            end
                        end
                        wasted = 0
                    end
                end
                unitTable = {unit=u, id=id}
                indexed:insert(unitTable)

                unitIndex[id] = unitTable
                
                --print(GetUnitName(u) .. " has been indexed to " .. id)

                if _USER_DATA then SetUnitUserData(u, id) end

                udg_IsUnitPreplaced[id] = preplaced
                runEvent(Event.onUnitIndex, unitTable) -- Run the index event
            end
        end)
        TriggerRegisterEnterRegion(CreateTrigger(), re, b)
        for i = bj_MAX_PLAYER_SLOTS - 1, 0, -1 do
            GroupEnumUnitsOfPlayer(bj_lastCreatedGroup, Player(i), b)
        end
        preplaced = nil
    end)
end)
end