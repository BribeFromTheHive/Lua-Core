--[[
--------------------------------------------------------------------
AddHook version 5.1.1
 Author: Bribe
 Special Thanks: Jampion and Eikonium
--------------------------------------------------------------------
"AddHook" allows dynamic function overriding and cascading hook callbacks in Lua, empowering systems such as
Global Variable Remapper and CreateEvent (which, in turn, empower systems such as Damage Engine and Spell Event).

AddHook is a function which returns two functions:
    1) The next hook callback or original native
    2) A function to call to remove the hook.

As of version 5.1, the hooked function is turned into a table, which allows syntax like "CreateTimer.old", which
calls the next hooked function (or the native function, if no other hooked functions exist). The name of this
extension can be anything you want - "native, oldFunc, original", whatever you find to be the most fitting for you.

"Classic" way of hooking in Lua is shown below:
    BJDebugMsg = print

The below is the most simple translation within the AddHook system:
    AddHook("BJDebugMsg", print)

A small showcase of what you can do with the API:
    
    AddHook("CreateTimer", function()
        if recycleTimer then
            return recycleStack.pop()
        elseif newTimer then
            return CreateTimer.original()
        end
    end)
    AddHook("DestroyTimer", function(whichTimer)
        if recycleTimer then
            recycleStack.insert(whichTimer)
        elseif destroyTimer then
            DestroyTimer.old(whichTimer)
        end
    end)

    *Note that the names "original" and "old" are just fluff. As long as you are using them from within the callback function,
    you can give them any name to call the original function (or next hook).
    
    If you are outside of the callback function, then denoting a property like "native" or "oldFunction" or such will always
    call the native function (rather than trigger any hooked callbacks). However, this will fail if the native isn't hooked.
]]------------------------------------------------------------------
do
    local max = math.max
    local funcProxyTable = {}
    local tableMetatable = {
        __call = function(self, ...) --the new way of calling hooks, introduced in 5.1
            self.current = #self
            local result = self[self.current][1](...)
            self.current = 0
            return result
        end,
        __index = function(self) --Using the __index method means that non-indexed names will default to accessing the next/orignal function.
            self.current = max(self.current - 1, 0)
            return self[self.current][1]
        end
    }
    ---Insert or remove a hook callback
    ---@param hooks table
    ---@param index integer
    ---@param value? table
    local function editList(hooks, index, value)
        local top = #hooks
        if index > top then
            hooks[index] = value --simply add the index to the top of the stack
        else
            if value then
                table.insert(hooks, index, value)
                index = index + 1
                top = top + 1
            else
                table.remove(hooks, index)
                top = top - 1
            end
            for i = index, top do
                hooks[i].setIndex(i) --Remap subsequent indices
            end
        end
    end
    local function createHookTable(native, current)
        return setmetatable({[0]={native}, current=current}, tableMetatable)
    end

    ---@param nativeKey        any         Usually a string (the name of the old function you wish to hook)
    ---@param callback         function    The function you want to run when the native is called. The args and return values would normally mimic the function that is hooked.
    ---@param priority?        number      Defaults to 0. Hooks are called in order of highest priority down to lowest priority.
    ---@param hostTable?       table       Defaults to _G, which is the table that stores all global variables.
    ---@param default?         function    If the native does not exist in the host table, use this default instead.
    ---@param usesMetatable?   boolean     Defaults to true if the "default" parameter is given.
    ---@return fun(params_of_native?:any):any callNative
    ---@return fun(remove_all_hooks?:boolean) callRemoveHook
    function AddHook(nativeKey, callback, priority, hostTable, default, usesMetatable)
        priority  = priority  or 0
        hostTable = hostTable or _G
        
        local function getNative()
            return rawget(hostTable, nativeKey) or default or error("Nothing could be hooked at: "..nativeKey)
        end
        
        local proxy
        if usesMetatable or (default and usesMetatable == nil) then
            --Index the hook to the metatable instead of the user's given table. Create a new metatable in case none existed.
            hostTable                            = getmetatable(hostTable)              or getmetatable(setmetatable(hostTable, {}))
            funcProxyTable[hostTable]            = funcProxyTable[hostTable]            or {}
            proxy                                = funcProxyTable[hostTable][nativeKey] or createHookTable(getNative())
            funcProxyTable[hostTable][nativeKey] = proxy
        end
        local index  = 1
        local hooks  = proxy or getNative()
        local typeOf = type(hooks)
        if proxy and #proxy == 0 then
            rawset(hostTable, nativeKey, function(...) --metatable methods like __index cannot be impersonated by a table that uses metamethods such as __call.
                return proxy[#proxy][1](...)           --I learned this the hard way when trying to find out why my hooks weren't working on GlobalRemap after Hook 5.1.
            end)
        elseif typeOf == "table" then
            local exitwhen = #hooks
            repeat
                if hooks[index].priority > priority then break end --Search manually for an index based on the priority of all other hooks.
                index = index + 1
            until index > exitwhen
        elseif typeOf == "function" then
            hooks = createHookTable(hooks, 0)
            rawset(hostTable, nativeKey, hooks)
        else
            error("Tried to hook an incorrect type: "..typeOf)
        end
        editList(hooks, index, {callback, priority = priority, setIndex = function(val) index = val end})
        return proxy and function(...)
            return hooks[index - 1][1](...) --used for metatables (no need to track the current position)
        end or function(...)
            hooks.current = index - 1
            return hooks[index - 1][1](...) --used for native tables (tracks the current position)
        end,
        function(removeAll)
            if removeAll or index == 1 and #hooks == 1 then
                rawset(hostTable, nativeKey, hooks[0][1]) --Remove all hooks by restoring the original function to the host table. The native is stored at index [0][1]
            else
                editList(hooks, index)
            end
        end
    end
end
