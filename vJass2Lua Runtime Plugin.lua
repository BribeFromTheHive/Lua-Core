OnInit("vJass2Lua", function(uses) --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Total_Initialization.lua
    
    local remap = uses.optionally "GlobalRemap" --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Global_Variable_Remapper.lua
    
    vJass, Struct = {}, {} --vJass2Lua runtime plugin, version 2.3 by Bribe

    local rawget = rawget
    local rawset = rawset
    local getmetatable = getmetatable
    local setmetatable = setmetatable

    --In case vJass2Lua misses any string concatenation, this metatable hook will pick it up and correct it.
    getmetatable("").__add = function(obj, obj2) return obj .. obj2 end

    --Extract the globals declarations from the "globals" block so we can remap them via Global Variable Remapper to use globals.var = blah syntax.
    --Although quite a bit of a hack, it gets the job done without the parser knowing which variables need to be processed like this.
    if remap then
        local oldGlobals = globals
        function globals(func)
            oldGlobals(func)
            local t = {}
            func(t)
            for _,v in ipairs(t) do
                remap(v, function() return oldGlobals[v] end, function(val) oldGlobals[v] = val end)
            end
        end
    end
    ---@class vJass : table
    ---@field interface function
    ---@field module function
    ---@field implement function
    ---@field textmacro function
    ---@field runtextmacro function
    ---@field struct Struct

    ---Constructor: vJass.struct([optional_parent_struct]) or just Struct()
    ---@class Struct : table
    ---@field allocate fun(from_struct)
    ---@field deallocate fun(struct_instance)
    ---@field create fun(from_struct)
    ---@field destroy fun(struct_instance)
    ---@field onDestroy fun(struct_instance)
    ---@field onCreate fun(struct_instance)
    ---@field extends fun(other_struct_or_table)
    ---@field private inception fun(child_struct)
    ---@field super Struct
    ---@field isType fun(struct_to_compare, other_struct)
    ---@field environment fun(struct_to_iterate)
    ---@field _operatorset fun(your_struct, var_name, your_func)
    ---@field _operatorget fun(your_struct, var_name, your_func)
    ---@field _getindex fun(your_struct, index)
    ---@field _setindex fun(your_struct, index, value)
    
    local macros = {}

    ---@param macroName string
    ---@param args? table string[] --a table containing any number of strings
    ---@param macro string|function --the code that is to be "inserted"
    function vJass.textmacro(macroName, args, macro, ...)
        macros[macroName] = {macro, args}
    end --index this macro as a table and store its name and arguments.

    ---@param macroName string
    ---@param ... string string1,string2,string3,etc.
    function vJass.runtextmacro(macroName, ...)
        local storedMacro = macros[macroName]
        if storedMacro then
            local macro = storedMacro[1] --get the macro string
            if type(macro) == "function" then
                macro(...)
                return
            end
            local macroargs = storedMacro[2] --get the args of textmacro (pointers)
            
            if macroargs then
                local args = {...} --get the args of runtextmacro (values)
                local n = #macroargs

                -- the below string pattern checks for $word_with_or_without_underscores$.
                load(macro:gsub("[$]([A-Za-z_.]+)[$]", function(arg)
                    for i = 1, n do -- search all of the textmacro's registered arguments to find out which of the pointers match
                        if arg == macroargs[i] then
                            return args[i] --substitute the runtextmacro arg string at the matching pointer position
                        end
                    end
                end))()
            else
                load(macro)()
            end
        end
    end

    ---Create a new module that can be implemented by any struct.
    local modules = {}
    local moduleQueue = {}
    
    ---@param moduleName string
    ---@param privacy? string private
    ---@param scope? string SCOPE_PREFIX
    ---@param moduleFunc fun(module : table, struct : Struct)
    function vJass.module(moduleName, privacy, scope, moduleFunc)
        local module, init = {}, {}
        if type(privacy) == "string" and privacy ~= "" and scope then
            modules[scope..moduleName] = module
        else
            if type(privacy) == "function" then
                moduleFunc = privacy
            end
            modules[moduleName] = module
        end
        module.implement = function(struct)
            if not init[struct] then
                init[struct] = true
                local private = {}
                moduleFunc(private, struct)
                if private.onInit then
                    moduleQueue[#moduleQueue+1] = private.onInit
                end
            end
        end
    end
    
    ---Implement a module by name
    ---@param moduleName string
    ---@param struct Struct
    function vJass.implement(moduleName, scope, struct)
        local module = modules[scope..moduleName]
        if not module then
            module = modules[moduleName]
        end
        if module then
            module.implement(struct)
        end
    end
    
    local interface, defaults
    
    --Does its best to automatically handle the vJass "interface" concept.
    ---@param default any
    ---@return table
    function vJass.interface(default)
        interface = interface or {
            __index = function(tab, key)
                local dflt = rawget(Struct, key)
                if not dflt then
                    return defaults[tab]
                end
                return dflt
            end
        }
        local new = setmetatable({}, interface)
        defaults = defaults or {}
        defaults[new] = default and function() return default end or DoNothing
        return new
    end

    do
        local mt
        local getMt = function()
            mt = mt or {__index = function(self, key)
                return rawget(rawset(self, key, {}), key)
            end}
            return mt
        end
        vJass.array2D = function(w, h)
            return setmetatable({width = w, height = h, size=w*h}, getMt())
        end
        vJass.dynamicArray = function(w,h)
            local newArray = Struct()
            h = h or 1
            newArray.width = w
            newArray.height = h
            newArray.size = w*h
            newArray._getindex = getMt().__index
            return newArray
        end
    end

    vJass.hook = function(funcName, userFunc)
        local old
        if AddHook then
            old = AddHook(funcName, function(...)
                userFunc(...)
                return old(...)
            end)
        else
            old = _G[funcName]
            _G[funcName] = function(...)
                userFunc(...)
                return old(...)
            end
        end
    end

    do
        local keys = 0
        vJass.key = function()
            keys = keys + 1
            return keys
        end
    end

    --takes myFunction.name syntax, generates a string in the _G table to reference the function.
    --the function could be local or part of a struct, neither of which will work with ExecuteFunc.
    do
        local vJassStringPrefix = "vJass2LuaNamePrefix"
        local funcRef = {}
        vJass.name = function(func)
            local prefix = funcRef[func]
            if prefix then
                return prefix
            end
            prefix = vJassStringPrefix..vJass.key()
            funcRef[func] = prefix
            _G[prefix] = func
        end
    end

    do
        local trig
        local args
        local lastFunc

        local function proxyCallFunc(how, func, ...)
            if not trig then
                trig = CreateTrigger() --only use one trigger for all evals/execs instead of one for each.
                local function proxyCaller()
                    return lastFunc(table.unpack(args))
                end
                TriggerAddCondition(trig, Filter(proxyCaller))
                TriggerAddAction(trig, proxyCaller)
            end
            lastFunc = func
            args = table.pack(...)
            return how(trig)
        end

        vJass.evaluate = function(func, ...)
            return proxyCallFunc(TriggerEvaluate, func, ...)
        end
        vJass.execute = function(func, ...)
            proxyCallFunc(TriggerExecute, func, ...)
        end
    end

    vJass.struct = Struct --just for naming consistency with the above vJass-prefixed methods.

    local mt = {
        __index = function(self, key)
            local getter = rawget(self, "_getindex") --declaring a _getindex function in your struct enables it to act as method operator []
            if getter then
                return getter(self, key)
            end
            return rawget(Struct, key) --however, it doesn't extend to child structs.
        end,
        __newindex = function(self, key, val)
            local setter = rawget(self, "_setindex") --declaring a _setindex function in your struct enables it to act as method operator []=
            if setter then
                setter(self, key, val)
            else
                rawset(self, key, val)
            end
        end
    }
    setmetatable(Struct, mt)
    
    --Loop function to iterate all of the structs from the child to the parent.
    function Struct:inception()
        local skip = true
        return function()
            if skip then
                skip = nil
            else
                self = self.super
            end
            return self
        end
    end
    
    ---Allocate, call the stub method onCreate and return a new struct instance via myStruct:create().
    ---@return Struct new_instance
    function Struct:allocate()
        local newInstance = {}
        setmetatable(newInstance, {__index = self})
        for struct in self:inception() do
            struct.onCreate(newInstance)
        end
        return newInstance
    end
    
    Struct.destroyed = {__mode = "k"}
    
    ---Deallocate and call the stub method onDestroy via myStructInstance:destroy().
    function Struct.deallocate(self)
        for struct in self:inception() do
            struct.onDestroy(self)
        end
        setmetatable(self, Struct.destroyed)
    end
    
    local structQueue = {}

    ---Acquire another struct's keys via myStruct:extends(otherStruct)
    ---@param parent Struct
    function Struct:extends(parent)
        for key, val in pairs(parent) do
            if self[key] == nil then
                self[key] = val
            end
        end
    end
     
    ---Create a new "vJass"-style struct with myStruct = Struct([parentStruct]).
    ---@param parent? Struct
    ---@return Struct new_struct
    function mt:__call(parent)
        if self == Struct then
            local struct
            if parent then
                struct = setmetatable({super = parent, allocate = parent.create, deallocate = parent.destroy}, {__index = parent})
            else
                struct = setmetatable({}, {__index = self})
            end
            structQueue[#structQueue+1] = struct
            return struct
        end
        return parent --vJass typecasting... shouldn't be used in Lua, but there could be cases where this will work without the user having to change anything.
    end
    
    --stub methods:
    Struct.create = Struct.allocate
    Struct.destroy = Struct.deallocate
    Struct.onCreate = DoNothing
    Struct.onDestroy = DoNothing
    
    ---Check if a child struct belongs to a particular parent struct.
    ---@param parent Struct
    ---@return boolean
    function Struct:isType(parent)
        for struct in parent:inception() do
            if struct == self then return true end
        end
    end

    mt = {}
    local environment = setmetatable({}, mt)
    environment.struct = environment
    local getter = function(key)
        local super = rawget(environment.struct, "super")
        while super do
            local get = rawget(super, key)
            if get ~= nil then
                return get
            else
                super = rawget(super, "super")
            end
        end
    end
    mt.__index = function(_, key)
        --first check the initial struct, then check extended structs (if any), then check the main Struct library, or finally check if it's a global
        return rawget(environment.struct, key) or getter(key) or rawget(Struct, key) or rawget(_G, key)
    end
    mt.__newindex = function(_,key,val) rawset(environment.struct, key, val) end
    
    ---Complicated, but allows invisible encapsulation via:
    ---do local _ENV = myStruct:environment()
    ---    x = 10
    ---    y = 100 --assigns myStruct.x to 10 and myStruct.y to 100.
    ---end
    ---@param self Struct
    ---@return table
    function Struct:environment()
        environment.struct = self
        return environment
    end
    
    local function InitOperators(struct)
        if not struct.__getterFuncs then
            local smt = getmetatable(struct) or getmetatable(setmetatable(struct, {}))
            struct.__getterFuncs = {}
            struct.__setterFuncs = {}
            smt.__index = function(self, var)
                local call = self.__getterFuncs[var]
                if call then return call(self)
                elseif not self.__setterFuncs[var] then
                    return rawget(rawget(self, "parent") or Struct, var)
                end
            end
            smt.__newindex = function(self, var, val)
                local call = rawget(self, "__setterFuncs")
                call = call[var]
                if call then call(self, val)
                elseif not self.__getterFuncs[var] then
                    rawset(self, var, val)
                end
            end
        end
    end
    
    ---Create a new method operator with myStruct:_operatorset("x", function(val) SetUnitX(u, val) end)
    ---@param var string
    ---@param func fun(val)
    function Struct:_operatorset(var, func) --treat the var-string as a "write-only" variable
        InitOperators(self)
        self.__setterFuncs[var] = func
    end

    ---Create a new method operator with myStruct:_operatorget("x", function() return GetUnitX(u) end)
    ---@param var string
    ---@param func fun()->any
    function Struct:_operatorget(var, func) --treat the var-string as a "read-only" variable
        InitOperators(self)
        self.__getterFuncs[var] = func
    end
    
    OnInit "Init vJass Modules and Structs"

    local call = try or pcall

    for _,init in ipairs(moduleQueue) do call(init) end

    for _,struct in ipairs(structQueue) do
        local init = rawget(struct, "onInit")
        if init then call(init) end
    end
    moduleQueue, structQueue = nil, nil

    OnInit "Init vJass Libraries"
    OnInit "Init vJass Scopes"
end)
