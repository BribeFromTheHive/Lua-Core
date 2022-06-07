--[[
    Hook 5.0 - better speed, features, code length, intuitive and has no requirements.

    Core API has been reduced from Hook.add, Hook.addSimple, Hook.remove, Hook.flush to just AddHook
    Secondary API has been reduced from hook.args, hook.returned, hook.old, hook.skip to just old(...)
    AddHook returns two functions: 1) old function* and 2) function to call to remove the hook.**
    
    *The old function will point to either the originally-hooked function, or it will point to the next-lower priority
        "AddHook" function a user requested. Not calling "oldFunc" means that any lower-priority callbacks will not
        execute. It is therefore key to make sure to prioritize correctly: higher numbers are called before lower ones.

"Classic" way of hooking in Lua is shown below, but doesn't allow other hooks to take a higher priority, nor can it be removed safely.
    local oldFunc = BJDebugMsg
    BJDebugMsg = print

The below allows other hooks to coexist with it, based on a certain priority, and can be removed:
    local oldFunc, removeFunc = AddHook("BJDebugMsg", print)

A small showcase of what you can do with the API:
    
    local oldFunc, removeFunc --remember to declare locals before any function that uses them
   
    oldFunc, removeFunc = AddHook("BJDebugMsg", function(s)
        if want_to_display_to_all_players then
            oldFunc(s) --this either calls the native function, or allows lower-priority hooks to run.
        elseif want_to_remove_hook then
            removeFunc() --removes just this hook from BJDebugMsg
        elseif want_to_remove_all_hooks then
            removeFunc(true) --removes all hooks on BJDebugMsg
        else
            print(s) --not calling the native function means that lower-priority hooks will be skipped.
        end
    end)

Version 5.0 also introduces a "metatable" boolean as the last parameter, which will get or create a new metatable
for the parentTable parameter, and assign the "oldFunc" within the metatable (or "default" if no oldFunc exists).
This is envisioned to be useful for hooking __index and __newindex on the _G table, such as with Global Variable
Remapper.
]]--
---@param oldFunc string
---@param userFunc function
---@param priority? number
---@param parentTable? table
---@param default? function
---@param metatable? boolean
---@return function old_function
---@return function call_this_to_remove
function AddHook(oldFunc, userFunc, priority, parentTable, default, metatable)
    parentTable = parentTable or _G
    if default and metatable then
        metatable = getmetatable(parentTable)
        if not metatable then
            metatable = {}
            setmetatable(parentTable, metatable)
        end
        parentTable = metatable
    end
    local index     = 2
    local hookStr   = "_hooked_"..oldFunc --You can change the prefix if you want.
    local hooks     = rawget(parentTable, hookStr)
    priority        = priority or 0
    if hooks then
        local fin   = #hooks
        repeat
            if hooks[index][2] > priority then break end
            index = index + 1
        until index > fin
    else
        hooks = {{
            rawget(parentTable, oldFunc) or default,
            function(where, instance)
                local n = #hooks
                if where > n then
                    hooks[where] = instance
                elseif where == n and not instance then
                    hooks[where] = nil
                    rawset(parentTable, oldFunc, hooks[where-1][1])
                else
                    if instance then
                        table.insert(hooks, where, instance)
                        where = where + 1
                    else
                        table.remove(hooks, where)
                    end
                    for i = where, n do
                        hooks[i][3](i) --when an index is added or removed in the middle of the list, re-map the subsequent indices.
                    end
                end
            end
        }}
        rawset(parentTable, hookStr, hooks)
    end
    hooks[1][2](index, {
        userFunc,
        priority,
        function(i) index = i end
    })
    if index == #hooks then
        rawset(parentTable, oldFunc, userFunc)
    end
    return function(...)
        return hooks[index-1][1](...) --this is the "old" function, and allows "..." without packing/unpacking.
    end, function(removeAll)
        local fin = #hooks
        if removeAll or fin == 2 then
            rawset(parentTable, hookStr, nil)
            rawset(parentTable, oldFunc, hooks[1][1])
        else
            hooks[1][2](index)
        end
    end
end
