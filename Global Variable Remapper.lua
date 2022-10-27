OnGlobalInit("GlobalRemap", function()

    Require "AddHook" --https://www.hiveworkshop.com/threads/hook.339153
--[[
--------------------------------------------------------------------------------------
Global Variable Remapper v1.3.1 by Bribe

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
local default = DoNothing
local getters,setters = {},{}
local oldGet, oldSet
oldGet = AddHook("__index", function(tab, index)
    if getters[index]~=nil then
        return getters[index]()
    else
        --print("Trying to read undeclared global: "..tostring(index))
        return oldGet(tab, index)
    end
end, 0, _G, default)

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
    local tab = {}
    _G[var] = tab
    getFunc = getFunc or default
    setFunc = setFunc or default
    setmetatable(tab, {
        __index = function(_, index)
            return getFunc(index)
        end,
        __newindex = function(_, index, val)
            --if index==nil then
            --    print("Attempt to index a nil value: "..GetStackTrace())
            --    return
            --end
            setFunc(index, val)
        end
    })
end
end)
