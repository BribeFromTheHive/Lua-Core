if Hook then --https://www.hiveworkshop.com/threads/hook.339153
--[[--------------------------------------------------------------------------------------
    Global Variable Remapper v1.1.0.0 by Bribe
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
    
    Systems that use this should call GlobalRemap via Global Initialization or later:
    https://www.hiveworkshop.com/threads/global-initialization.317099/

----------------------------------------------------------------------------------------]]
 
    local getters, setters, skip
 
    ---Remap a non-array global variable
    ---@param var string
    ---@param getFunc? fun() ->value?
    ---@param setFunc? fun(value)
    function GlobalRemap(var, getFunc, setFunc)
        if not skip then
            getters, setters, skip = {}, {}, DoNothing
 
            local mt = getmetatable(_G)
            if not mt then
                mt = {}
                setmetatable(_G, mt) 
            end
            
            --hook.args = {1:table, 2:index}
            Hook.add("__index",
            function(hook)
                local func = getters[hook.args[2]]
                if func then
                    hook.skip = true
                    hook.returned = table.pack(func())
                end
            end, nil, mt,
            function(a, b)
                return rawget(a, b)
            end)

            --hook.args = {1:table, 2:index, 3:value}
            Hook.add("__newindex", 
            function(hook)
                local func = setters[hook.args[2]]
                if func then
                    hook.skip = true
                    func(hook.args[3])
                end
            end, nil, mt,
            function(a, b, c)
                rawset(a, b, c)
            end)
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