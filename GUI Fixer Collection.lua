function TriggerRegisterDestDeathInRegionEvent(trig, r)
    --Removes the limit on the number of destructables that can be registered.
    EnumDestructablesInRect(r, nil, function() TriggerRegisterDeathEvent(trig, GetEnumDestructable()) end)
end
function IsUnitDeadBJ(u) return not UnitAlive(u) end --uses the reliable native instead of the life check

function IsUnitAliveBJ(u) return UnitAlive(u) end --uses the reliable native instead of the life check

function SetUnitPropWindowBJ(whichUnit, propWindow)
    --Allows the Prop Window to be set to zero to allow unit movement to be suspended.
    SetUnitPropWindow(whichUnit, propWindow*bj_DEGTORAD)
end
    
do
    --[[-----------------------------------------------------------------------------------------
  
    __jarray compactor 1.0 by Bribe
  
    This small snippet will cut the number of tables produced by __jarray almost by 50%. The
    regular __jarray function currently produces two tables per initialization due to the
    setmetatable call, however this will instead cache the metatables with the same default
    return value and recycle them.

    -------------------------------------------------------------------------------------------]]
    local mts = {}
    __jarray = function(default)
        if default then
            local mt = mts[default]
            if not mt then
                mt = {__index = function() return default end}
                mts[default] = mt
            end
            return setmetatable({}, mt)
        end
        return {}
    end
end

do AnyPlayerUnitEvent = {}
--[[---------------------------------------------------------------------------------------------
  
    AnyPlayerUnitEvent v1.0.1.0 by Bribe
    
    I designed the original JASS system RegisterAnyPlayerUnitEvent to help to cut down on handles
    that are generated for events, but this has the benefit of using raw function calls (for Lua
    users), plus potentially benefiting from Lua Fast Triggers for GUI purposes.
    
-----------------------------------------------------------------------------------------------]]

    local fStack = {}
    local tStack = {}
    local bj = TriggerRegisterAnyUnitEventBJ

    function AnyPlayerUnitEvent.add(event, userFunc)
        local r, funcs = 0, fStack[event]
        if funcs then
            r = #funcs
            if r == 0 then EnableTrigger(tStack[event]) end
        else
            funcs = {}
            fStack[event] = funcs
            local t = CreateTrigger()
            tStack[event] = t
            bj(t, event)
            TriggerAddCondition(t, Filter(
            function()
                for _, func in ipairs(funcs) do func() end
            end))
        end
        funcs[r + 1] = userFunc
        return userFunc
    end

    function AnyPlayerUnitEvent.remove(event, userFunc)
        local r, funcs = -1, fStack[event]
        if funcs then
            for i, func in ipairs(funcs) do
                if func == userFunc then r = i break end
            end
            if r > 0 then
                local i = r
                r = #funcs
                if r > 1 then
                    funcs[i] = funcs[r]
                else
                    DisableTrigger(tStack[event])
                end
                funcs[r] = nil
                r = r - 1
            end
        end
        return r
    end
    
    function TriggerRegisterAnyUnitEventBJ(trig, event)
        return AnyPlayerUnitEvent.add(event, function() if IsTriggerEnabled(trig) then ConditionalTriggerExecute(trig) end end)
    end

end