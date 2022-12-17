if Debug then Debug.beginFile "Hook" end
--——————————————————————————————————————
-- Hook version 7.0.1
-- Created by: Bribe
-- Contributors: Jampion, Eikonium, MyPad, Wrda
--—————————————————————————————————————————————
do
    local addHook
    
    ---@param key        any        Usually a string (the name of the native you wish to hook)
    ---@param callback   function   The function you want to run when the native is called. The args and return values would normally mimic the function that is hooked.
    ---@param priority?  number     Defaults to 0. Hooks are called in order of highest priority down to lowest priority. The native itself has the lowest priority.
    ---@param host?      table      Defaults to _G (the table that stores all global variables).
    ---@param default?   function   If the native does not exist in the host table, use this default instead.
    ---@param metatable? boolean    Whether to store into the host's metatable instead. Defaults to true if the "default" parameter is given.
    ---@return fun(...):any old     Calls the next (lower-priority) hook or the native function. The args and return values match.
    ---@return fun(all?) remove     Remove the hook. Pass the boolean "true" to remove all hooks.
    function AddHook(key, callback, priority, host, default, metatable)
        local self = addHook(nil, key, function(_, ...) return callback(...) end, priority, host, default, metatable)
        return self.old
        ,   function(all) self:remove(all) end
    end
    
    local function reindex(hooks, from)
        for i=from, #hooks do
            hooks[i].index = i
            hooks[i].old = hooks[i - 1]
        end
    end
    
    local mode_v = {__mode="v"}
    local hosts = setmetatable({ [_G] = setmetatable({}, mode_v) }, mode_v)

    local function remove(h, all)
        local hooks = h.hooks
        if all or (#hooks == 1) then
            rawset(hooks.host, hooks.key, hooks[0] ~= DoNothing and hooks[0] or nil)
            hosts[hooks.host][hooks.key] = nil
        else
            table.remove(hooks, h.index)
            reindex(hooks, h.index)
        end
    end
    
    function addHook(_, key, callback, priority, host, default, metatable)
        host=host or _G
        priority=priority or 0
        if metatable or (default and metatable==nil) then
            host = getmetatable(host) or getmetatable(setmetatable(host, {}))
        end
        hosts[host]=hosts[host] or setmetatable({}, mode_v)
        local index, hooks = 1, hosts[host][key]
        if hooks then
            local exit = #hooks
            repeat if priority <= hooks[index].priority then break end
            index=index + 1 until index > exit
        else
            hooks = { host=host, key=key, [0] = rawget(host, key) or default or (host ~= _G or type(key)~=string) and DoNothing or error("No value found for key: "..key) }
            hosts[host][key] = hooks
            rawset(host, key, function(...) return hooks[#hooks](...) end)
        end
        table.insert(hooks, index, setmetatable({ priority=priority, hooks=hooks, remove=remove }, {__call=callback}))
        reindex(hooks, index)
        return hooks[index]
    end

    Hook = setmetatable({}, { __call = addHook, __newindex = addHook })
end
if Debug then Debug.endFile() end
