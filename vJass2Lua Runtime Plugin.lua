do vJass, Struct = {}, {} --vJass2Lua runtime plugin, version 2.1.1.0 by Bribe
    
    --Requires optional Global Initialization: https://www.hiveworkshop.com/threads/global-initialization.317099/
    --Requires optional Global Variable Remapper: https://www.hiveworkshop.com/threads/global-variable-remapper-the-future-of-gui.339308/

    local rawget = rawget
    local rawset = rawset
    local getmetatable = getmetatable
    local setmetatable = setmetatable

    --In case vJass2Lua misses any string concatenation, this metatable hook will pick it up and correct it.
    getmetatable("").__add = function(obj, obj2) return obj .. obj2 end

    --Extract the globals declarations from the "globals" block so we can remap them via Global Variable Remapper to use globals.var = blah syntax.
    --Although quite a bit of a hack, it gets the job done without the parser knowing which variables need to be processed like this.
    do
        local oldGlobals = globals
        function globals(func)
            local t = {}
            func(t)
            for _,v in pairs(t) do
                GlobalRemap(v, function() return globals[v] end, function(val) globals[v] = val end)
            end
            oldGlobals(func)
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
                -- Need to use double percentages in World Editor, but a single percentage on each should be used when testing code outside of World Editor.
                load(macro:gsub("%%$([%%w_]+)%%$", function(arg)
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
            if not mt then
                mt = {
                    __index = function(self, key)
                        local new = {}
                        rawset(self, key, new)
                        return new
                    end
                }
            end
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
                old(...)
            end)
        else
            old = _G[funcName]
            _G[funcName] = function(...)
                userFunc(...)
                old(...)
            end
        end
    end

    vJass.struct = Struct --just for naming consistency with the above vJass-prefixed methods.

    local mt = {
        __index = function(self, key)
            local get = rawget(self, "_getindex") --declaring a _getindex function in your struct enables it to act as method operator []
            return get and get(self, key) or rawget(Struct, key) --however, it doesn't extend to child structs.
        end
        ,
        __newindex = function(self, key, val)
            local set = rawget(self, "_setindex") --declaring a _setindex function in your struct enables it to act as method operator []=
            if set then set(self, key, val) else rawset(self, key, val) end
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
    mt.__newindex = environment.struct
    
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
            local mt = getmetatable(struct)
            if not mt then mt = {} ; setmetatable(struct, mt) end
            struct.__getterFuncs = {}
            struct.__setterFuncs = {}
            mt.__index = function(self, var)
                local call = self.__getterFuncs[var]
                if call then return call(self)
                elseif not self.__setterFuncs[var] then
                    return rawget(rawget(self, "parent") or Struct, var)
                end
            end
            mt.__newindex = function(self, var, val)
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
    
    if OnGlobalInit then
        OnGlobalInit(function()
            for init in ipairs(moduleQueue) do pcall(init) end

            for struct in ipairs(structQueue) do
                local init = rawget(struct, "onInit")
                if init then pcall(init) end
            end
            moduleQueue, structQueue = nil, nil
        end)
    end
end --end of Struct library
