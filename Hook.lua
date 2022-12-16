if Debug then Debug.beginFile "Hook" end
--[[
--------------------------------------------------------------------
Hook version 6.1
Created by:   Bribe
Contributors: Jampion and Eikonium
--------------------------------------------------------------------
"Hook" allows dynamic function overriding and cascading hook callbacks in Lua, empowering systems such as
Global Variable Remapper and CreateEvent (which, in turn, empower systems such as Damage Engine and Spell Event).
------------------------------------------------------------------]]
do
    local doNothing = function()end --not using the actual DoNothing so as to be sure when a function should indeed be set to nil.
    local hosts, hostMT

    local function reindex(hooks, from)
        for i=from, #hooks do
            hooks[i].index = i
            hooks[i].next = hooks[i - 1].callback
        end
    end

    local function removeHook(host, key, index)
        local hooks = hosts[host][key]
        if hooks then
            if not index or (index == 1 and #hooks == 1) then
                local native = hooks[0].callback
                if native == doNothing then native = nil end
                rawset(host, key, native)
                hosts[host][key] = nil
            else
                table.remove(hooks, index)
                reindex(hooks, index)
            end
        end
    end

    local function addHook(key, callback, priority, host, default, metatable)
        host = host  or _G
        if metatable or (default and metatable == nil) then
            --Index the hook to the metatable instead of the user's given table.
            host = getmetatable(host) or getmetatable(setmetatable(host, {})) --Create a new metatable in case none existed.
        end
        priority    = priority    or 0
        hosts[host] = hosts[host] or setmetatable({}, hostMT)
        local hooks = hosts[host][key]
        local index = 1
        if hooks then
            local exit = #hooks
            repeat
                if priority <= hooks[index].priority then break end
                index=index + 1
            until index > exit
        else
            hooks = { [0] = { callback = rawget(host, key) or default or (host ~= _G or type(key)~=string) and doNothing or error("No value found for key: "..key) } } --Store the native to index [0]["callback"].
            hosts [host][key] = hooks
            rawset(host, key, function(...)
                hooks.current = #hooks
                local results = hooks[hooks.current].callback(...)
                hooks.current = nil
                return results
            end)
        end
        ---@class hookInstance
        ---@field callback  function
        ---@field index     integer
        ---@field priority  number
        ---@field next      function
        ---@field remove    function
        local self; self = { callback = callback, priority = priority, index = index, remove = function(removeAll) removeHook(host, key, not removeAll and self.index) end }
        table.insert(hooks, index, self)
        reindex(hooks, index)
        return self
    end

    ---@param key        any           Usually a string (the name of the old function you wish to hook)
    ---@param callback   function      The function you want to run when the native is called. The args and return values would normally mimic the function that is hooked.
    ---@param priority?  number        Defaults to 0. Hooks are called in order of highest priority down to lowest priority. The native itself has the lowest priority.
    ---@param host?      table         Defaults to _G (the table that stores all global variables).
    ---@param default?   function      If the native does not exist in the host table, use this default instead.
    ---@param metatable? boolean       Whether to store into the host's metatable instead. Defaults to true if the "default" parameter is given.
    ---@return fun(...):any callNext   Calls the next (lower-priority) hook. The args and return values should normally align with the original native.
    ---@return fun(boolean) removeHook Remove the hook. Pass the boolean "true" to remove all hooks.
    function AddHook(key, callback, priority, host, default, metatable)
        local self = addHook(key, callback, priority, host, default, metatable)
        return function(...) return self.next(...) end, self.remove
    end

    hostMT = { __mode="v" }
    hosts = setmetatable({}, hostMT)

    local createHook
    function createHook(fromHost)
        local hostData = hosts[fromHost] or setmetatable({}, hostMT)
        hosts[fromHost] = hostData
        local host =
        {   __call = function(_, k, c, p, h, ...)
                if c then
                    return addHook(k, c, p, h or fromHost, ...) --As of v6.1, this returns a table which stores all the required information.
                end
                assert(type(k)=="table")
                return createHook(k) --Enables 'myHook = Hook(myTable)' syntax to allow 'myHook' to behave identically to "Hook", but with your own custom table instead of _G.
            end
        ,   __index = function(hooks, key)
                hooks = hostData[key]
                if hooks then                    --Behaves the same way that BJDebugMsg.old(s) did in 5.1, but the API has been changed to Hook.BJDebugMsg(s)
                    if hooks.current then
                        hooks.current = hooks.current - 1
                        return hooks[hooks.current].callback
                    end
                    return hooks[0].callback
                end
                return fromHost[key]  --safety net in case the item isn't actually hooked.
            end
        ,   __newindex = function(_, key, callback)
                if callback then
                    addHook(key, callback, 0, fromHost) --Syntactical sugar. If you need the return value or a custom host-table, then call Hook directly.
                elseif hostData[key] then
                    removeHook(fromHost, key, hostData[key].current)  --Hook.BJDebugMsg = nil removes all hooks when called from outside of a currently-running hook callback.
                end
            end
        }
        return setmetatable(host, host)
    end
    Hook = createHook(_G)
end
if Debug then Debug.endFile() end
