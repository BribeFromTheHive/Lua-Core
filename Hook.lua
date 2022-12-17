if Debug then Debug.beginFile "Hook" end do local addHook --[[
——————————————————————————————————————————————————————————————
    Hook version 7
    Created by:   Bribe
    Contributors: Jampion and Eikonium
————————————————————————————————————————————————————————————]]
---@param key        any        Usually a string (the name of the old function you wish to hook)
---@param callback   function   The function you want to run when the native is called. The args and return values would normally mimic the function that is hooked.
---@param priority?  number     Defaults to 0. Hooks are called in order of highest priority down to lowest priority. The native itself has the lowest priority.
---@param host?      table      Defaults to _G (the table that stores all global variables).
---@param default?   function   If the native does not exist in the host table, use this default instead.
---@param metatable? boolean    Whether to store into the host's metatable instead. Defaults to true if the "default" parameter is given.
---@return fun(...):any old     Calls the next (lower-priority) hook or the native function. The args and return values align.
---@return fun(boolean) remove  Remove the hook. Pass the boolean "true" to remove all hooks.
function AddHook(key, callback, priority, host, default, metatable)
    local self = addHook(nil, key, function(_, ...) return callback(...) end, priority, host, default, metatable)
    return self.old, self.remove
end

local doNothing,     hostMT,         _G, rawset, setmetatable, hosts =
      function()end, { __mode="v" }, _G, rawset, setmetatable, nil

local function reindex(hooks, from)
    for i=from, #hooks do
        hooks[i].index = i
        hooks[i].old   = hooks[i - 1]
    end
end

local function remove(hooks, host, key, index)
    if not index or (index == 1 and #hooks == 1) then
        rawset(host, key, hooks[0] ~= doNothing and hooks[0] or nil)
        hosts[host][key] = nil
    else
        table.remove(hooks, index)
        reindex(hooks, index)
    end
end

function addHook(_, key, callback, priority, host, default, metatable)
    host = host  or _G
    if metatable or (default and metatable == nil) then
        host = getmetatable(host) or getmetatable(setmetatable(host, {}))
    end
    priority    = priority    or 0
    hosts[host] = hosts[host] or setmetatable({}, hostMT)
    local hooks = hosts[host][key]
    local index = 1
    if hooks then
        local exit = #hooks
        repeat if priority <= hooks[index].priority then break end
        index=index + 1 until index > exit
    else
        hooks = { [0] = rawget(host, key) or default or (host ~= _G or type(key)~=string) and doNothing or error("No value found for key: "..key) }
        hosts [host][key] = hooks
        rawset(host, key, function(...) return hooks[#hooks](...) end)
    end
    local self; self = { __call=callback, priority=priority, remove = function(removeAll) remove(hooks, host, key, not removeAll and self.index) end }
    table.insert(hooks, index, setmetatable(self, self))
    reindex(hooks, index)
    return self, hooks
end
hosts     = setmetatable({}, hostMT)
hosts[_G] = setmetatable({}, hostMT)
Hook      = { __call = addHook, __newindex = addHook }
setmetatable(Hook, Hook)
end
--———————————————————————————————
if Debug then Debug.endFile() end
