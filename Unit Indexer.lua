OnInit(function(require)
    require "GlobalRemap" --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Global_Variable_Remapper.lua
    require "Event"       --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Event.lua
    
    Event.create("OnUnitIndexed", true)
    Event.create("OnUnitRemoval", true)
    
    local unitRef = setmetatable({}, {__mode = "k"})
    local eventUnit
    local collector = {__gc = function(unit)
        eventUnit = unit[1]
        unitRef[eventUnit] = nil
        Event.OnUnitRemoval(eventUnit)
    end}

    GetUnitUserData = function(unit) return unit end
    
    GlobalRemap("udg_UDex",  function() return eventUnit end) --fools GUI into thinking unit is an integer
    GlobalRemapArray("udg_UDexUnits", function(unit) return unit end)

    local preplaced = true

    OnTrigInit(function()
        local re = CreateRegion()
        local r = GetWorldBounds()
        RegionAddRect(re, r); RemoveRect(r)
        local b = Filter(
        function()
            local u = GetFilterUnit()
            if not unitRef[u] then
                unitRef[u] = {u}
                setmetatable(unitRef[u], collector)
                if rawget(_G, "udg_IsUnitPreplaced") then
                    udg_IsUnitPreplaced[u] = preplaced
                end
                eventUnit = u
                Event.OnUnitIndexed(u)
            end
        end)
        TriggerRegisterEnterRegion(CreateTrigger(), re, b)
        for i = 0, bj_MAX_PLAYER_SLOTS -1 do
            GroupEnumUnitsOfPlayer(bj_lastCreatedGroup, Player(i), b)
        end
        preplaced = nil
    end)
end)
