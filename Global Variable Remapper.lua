do--[[
--------------------------------------------------------------------------------------
Global Variable Remapper v1.2.0.1 by Bribe
--Requires Hook: https://www.hiveworkshop.com/threads/hook.339153
--Libraries which call this should use Global Initialization: https://www.hiveworkshop.com/threads/global-initialization.317099/

- Intended to empower the GUI user-base and those who design systems for them.

API:
    GlobalRemap(variableStr[, getterFunc, setterFunc])
    @variableStr is a string such as "udg_MyVariable"
    @getterFunc is a function that takes nothing but returns the expected value when
        "udg_MyVariable" is referenced.
    @setterFunc is a function that takes a single argument (the value that is being
        assigned) and allows you to do what you want when someone uses "Set MyVariable = SomeValue".
        The function doesn't need to do anything nor return anything. Enables read-only
        GUI variables for the first time in WarCraft 3 history.
    
    GlobalRemapArray(variableStr[, getterFunc, setterFunc])
    @variableStr is a string such as "udg_MyVariableArray"
    @getterFunc is a function that takes the index of the array and returns the
        expected value when "MyVariableArray" is referenced.
    @setterFunc is a function that takes two arguments: the index of the array and the
        value the user is trying to assign. The function doesn't return anything.
----------------------------------------------------------------------------------------]]

local getters, setters, skip

---Remap a non-array global variable
---@param var string
---@param getFunc? fun() ->value?
---@param setFunc? fun(value)
function GlobalRemap(var, getFunc, setFunc)
    if not skip then
        getters, setters, skip = {}, {}, DoNothing
        local oldGet, oldSet
        oldGet = AddHook("__index",
        function(tab, index)
            local func = getters[index]
            if func then
                return func()
            else
                return oldGet(tab, index)
            end
        end, nil, _G,
        function(a, b)
            return rawget(a, b)
        end, true)
        oldSet = AddHook("__newindex", 
        function(tab, index, val)
            local func = setters[index]
            if func then
                func(val)
            else
                oldSet(tab, index, val)
            end
        end, nil, _G,
        function(a, b, c)
            rawset(a, b, c)
        end, true)
    end
    _G[var] = nil                   --Delete the variable from the global table.
    getters[var] = getFunc or skip  --Assign a function that returns what should be returned when this variable is referenced.
    setters[var] = setFunc or skip  --Assign a function that captures the value the variable is attempting to be set to.
end

---Remap a global variable array
---@param var string
---@param getFunc? fun(index : any) -> any
---@param setFunc? fun(index : any, val : any)
function GlobalRemapArray(var, getFunc, setFunc) --will get inserted into GlobalRemap after testing.
    local tab = {}
    _G[var] = tab
    getFunc = getFunc or DoNothing
    setFunc = setFunc or DoNothing
    setmetatable(tab, {__index = function(_, index) return getFunc(index) end, __newindex = function(_, index, val) setFunc(index, val) end})
end
end
--End of Global Variable Remapper
