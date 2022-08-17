--[[
--------------------------------------------------------------------
Hook 5.0.2.0
--------------------------------------------------------------------
Provides a single function as its API: AddHook.
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
        print("returning nothing") --this function should return whatever the original function returns. BJDebugMsg returns nothing, but CreateUnit returns a unit.
    end)
]]------------------------------------------------------------------
---@param oldFunc               string      The name of the old function you wish to hook
---@param userFunc              function    The function you want to run when oldFunc is called. The args and return values would normally mimic the function that is hooked.
---@param priority?             number      Defaults to 0. Hooks are called in order of highest priority down to lowest priority.
---@param parentTable?          table       Defaults to _G, which is the table that stores all global variables.
---@param defaultOldFunc?       function    If the oldFunc does not exist in the parent table, use this default function instead.
---@param storeIntoMetatable?   boolean     Defaults to true if the "default" parameter is given.
---@return fun(args_should_match_the_original_function?):any    old_function_or_lower_priority_hooks
---@return fun(remove_all_hooks?:boolean)                       call_this_to_remove_hook
function AddHook(oldFunc, userFunc, priority, parentTable, defaultOldFunc, storeIntoMetatable)
    parentTable     = parentTable or _G
    priority        = priority or 0
    local hookStr   = "__hookHandler_"..oldFunc --You can change the prefix if you want (in case it conflicts with any other prefixes you use in the parentTable).
    
    if defaultOldFunc and storeIntoMetatable == nil or storeIntoMetatable then
        --Index the hook to the metatable instead of the user's given table.
        local mt = getmetatable(parentTable)
        if not mt then
            --Create a new metatable in case none existed.
            mt = {}
            setmetatable(parentTable, mt) 
        end
        parentTable = mt
    end
    local index     = 2 --The index defaults to 2 (index 1 is reserved for the original function that you're trying to hook)
    local hooks     = rawget(parentTable, hookStr)
    if hooks then
        local fin   = #hooks
        repeat
            --Search manually for an index based on the priority of all other hooks.
            if hooks[index][2] > priority then break end
            index = index + 1
        until index > fin
    else
        --create a table that stores all hooks that can be added to this function.
        --[1] either points to the native function, to the default function (if none existed).
        --[2] is a function that is a function called to update hook indices when a new hook is added or an old one is removed.
        hooks = {
            --hooks[1] serves as the root hook table.
            {
                --index[1]
                --Falls back to a junk function if no oldFunc nor default was provided.
                --Will throw an error in that case if you un-comment the block quote below.
                rawget(parentTable, oldFunc) or defaultOldFunc --[[or print("failed to hook "..oldFunc)]] or function() end
                ,
                --index[2]
                ---@param where integer
                ---@param instance? table [1]:function userFunc, [2]:integer priority, [3]:fun(index:integer)
                function(where, instance)
                    local n = #hooks
                    if where > n then
                        --this only occurs when this is the first hook.
                        hooks[where] = instance
                    elseif where == n and not instance then
                        --the top hook is being removed.
                        hooks[where] = nil
                        --assign the next function to the parent table
                        rawset(parentTable, oldFunc, hooks[where-1][1])
                    else
                        if instance then
                            --if an instance is provided, we add it
                            table.insert(hooks, where, instance)
                            where = where + 1
                            n = n + 1
                        else
                            --if no instance is provided, we remove the existing index. 
                            table.remove(hooks, where)
                            n = n - 1
                        end
                        --when an index is added or removed in the middle of the list, re-map the subsequent indices:
                        for i = where, n do
                            hooks[i][3](i)
                        end
                    end
                end
            }
        }
        rawset(parentTable, hookStr, hooks) --this would store the hook-table holding BJDebugMsg as _G["__hookHandler_BJDebugMsg"]
    end
    --call the stored function at root-hook-table[2] to assign indices.
    hooks[1][2](index, { --this table belongs specifically to this newly-added Hook instance.
        --index[1] is the function that needs to be called in place of the original function.
        userFunc
        ,
        --index[2] is the priority specified by the user, so it can be compared with future added hooks.
        priority
        ,
        --index[3] is the function that is used to inject an instruction to realign the instance's local index
        --Almost everything is processed in local scope via containers/closures.
        --This keeps the "oldFunc" recursive callbacks extremely performant.
        function(i) index = i end
    })
    if index == #hooks then
        --this is the highest-priority hook and should be called first.
        --Therefore, insert the user's function as the actual function that gets natively called.
        rawset(parentTable, oldFunc, userFunc)
    end
    --This is the first returned function (old_function_or_lower_priority_hooks):
    return function(...)
        return hooks[index-1][1](...)
    end,
    ---This is the second returned function (call_this_to_remove_hook):
    function(removeAll)
        if removeAll or #hooks == 2 then
            --Remove all hooks, clear memory and restore the original function to the parent table.
            rawset(parentTable, hookStr, nil)
            rawset(parentTable, oldFunc, hooks[1][1])
        else
            hooks[1][2](index) --remove just the single hook instance
        end
    end
end
