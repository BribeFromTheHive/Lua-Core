OnInit("GlobalRemap", function(needs)

    needs "AddHook" --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Hook.lua
--[[
--------------------------------------------------------------------------------------
Global Variable Remapper v1.3.2 by Bribe

- Turns normal GUI variable references into function calls that integrate seamlessly
  with a Lua framework.

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
local default = DoNothing
local getters,setters = {},{}
local oldGet, oldSet
oldGet = AddHook("__index", function(tab, index)
    if getters[index]~=nil then
        return getters[index]()
    end
    return oldGet(tab, index)
end, 0, _G, rawget)

oldSet = AddHook("__newindex", function(tab, index, val)
    if setters[index]~=nil then
        setters[index](val)
    else
        oldSet(tab, index, val)
    end
end, 0, _G, rawset)

---Remap a non-array global variable
---@param var string
---@param getFunc? fun():any
---@param setFunc? fun(value:any)
function GlobalRemap(var, getFunc, setFunc)
    _G[var] = nil                       --Delete the variable from the global table.
    getters[var] = getFunc or default   --Assign a function that returns what should be returned when this variable is referenced.
    setters[var] = setFunc or default   --Assign a function that captures the value the variable is attempting to be set to.
end

---Remap a global variable array
---@param var string
---@param getFunc? fun(index : any): any
---@param setFunc? fun(index : any, val : any)
function GlobalRemapArray(var, getFunc, setFunc) --will get inserted into GlobalRemap after testing.
    getFunc = getFunc or default
    setFunc = setFunc or default
    _G[var] = setmetatable({}, {
        __index = function(_, index) return getFunc(index) end,
        __newindex = function(_, index, val) setFunc(index, val) end
    })
end
end)
