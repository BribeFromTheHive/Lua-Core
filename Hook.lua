if Debug then Debug.beginFile "Hook" end
--[[
--------------------------------------------------------------------
Hook version 6
Created by:   Bribe
Contributors: Jampion and Eikonium
--------------------------------------------------------------------
"Hook" allows dynamic function overriding and cascading hook callbacks in Lua, empowering systems such as
Global Variable Remapper and CreateEvent (which, in turn, empower systems such as Damage Engine and Spell Event).

"Classic" way of hooking in Lua is shown below:
    BJDebugMsg = print

The below is the most simple translation within the AddHook system:
    Hook.BJDebugMsg = print

A showcase of what you can do with the API to implement a simple timer recycling system:

    local recycledTimers = {}
    function Hook.CreateTimer()
        if recycledTimers[1] then
            return table.remove(recycledTimers, #recycledTimers)
        else
            return Hook.CreateTimer() --Call the CreateTimer native and return its timer
        end
    end
    function Hook.DestroyTimer(whichTimer)
        if #recycledTimers < 100 then
            table.insert(recycledTimers, whichTimer)
        else
            Hook.DestroyTimer(whichTimer) --This will not trigger recursively (but calling "DestroyTimer" without the preceding "Hook." will cause recursion).
        end
    end

When more complex scenarios are needed, Hook can be also be treated as a function (details in the script below).
------------------------------------------------------------------]]
do
    local _G, hostMT = _G, { __mode="v" }
    
    local hosts = setmetatable({ [_G] = setmetatable({}, hostMT) }, hostMT)

    local function removeHook(host, key, index)
        local hooks = hosts[host][key]
        if hooks then
            if not index or (index == 1 and #hooks == 1) then
                rawset(host, key, hooks[0][1]) --Restore the native from index [0][1]
                hosts[host][key] = nil
            else
                table.remove(hooks, index)
                for i=index, #hooks do hooks[i].reindex(i) end --Remap any subsequent indices
            end
        end
    end
    local function callNext(hooks, index, ...)
        hooks.current = index
        local results = hooks[index][1](...)
        hooks.current = nil
        return results
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
            hooks = { [0] = { rawget(host, key) or default or (host ~= _G or type(key)~=string) and DoNothing or error("No value found for key: "..key) } } --Store the native to index [0][1].
            hosts [host][key] = hooks
            rawset(host, key, function(...) return callNext(hooks, #hooks, ...) end)
        end
        table.insert(hooks, index, { callback, priority = priority, reindex = function(i) index = i end })
        for i=(index + 1), #hooks do hooks[i].reindex(i) end
        return function(...) return callNext(hooks, index - 1, ...) end, function(removeAll) removeHook(host, key, not removeAll and index) end
    end

    Hook =
    {   __call = function(_, ...) return AddHook(...) end
    ,   __index = function(hooks, key)
            hooks = hosts[_G][key]
            if hooks then                    --Behaves the same way that BJDebugMsg.old(s) did in 5.1, but the API has been changed to Hook.BJDebugMsg(s)
                if hooks.current then
                    hooks.current = hooks.current - 1
                    return hooks[hooks.current][1]
                end
                return hooks[0][1]
            end
            return _G[key]  --safety net in case the item isn't actually hooked.
        end
    ,   __newindex = function(_, key, callback)
            if callback then
                AddHook(key, callback) --Syntactical sugar. If you need the return values, use AddHook directly.
            elseif hosts[_G][key] then
                removeHook(_G, key, hosts[_G][key].current)  --Hook.BJDebugMsg = nil removes all hooks when called from outside of a currently-running hook callback.
            end
        end
    }
    setmetatable(Hook, Hook)
end
if Debug then Debug.endFile() end
