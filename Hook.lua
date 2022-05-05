if LinkedList then --https://www.hiveworkshop.com/threads/definitive-doubly-linked-list.339392/
--[[--------------------------------------------------------------------------------------
    Hook v4.1.2.0 by Bribe, with very special thanks to:
    Eikonium and Jampion for bug reports, feature improvements, teaching me new things.
    MyPad for teaching me new things
    Wrda and Eikonium for the better LinkedList approach
----------------------------------------------------------------------------------------]]
    Hook = {}
    
    local _LOW_PRIO     = -0.1          -- a number to represent what should be the lowest priority for a before-hook (lower values run first).
    local _HIGH_PRIO    = 9001          -- a number to represent what should be the lowest priority for an after-hook (lower values run first).
    local _SKIP_HOOK    = "skip hook"   -- when this is returned from a Hook.addSimple function, the hook will stop.
    
    local hookBefore    = {} ---@type Hook[]        --stores a list of functions that are called prior to a hooked function.
    local hookAfter     = {} ---@type Hook[]        --stores a list of functions that are called after a hooked function.
    local hookedFunc    = {} ---@type function[]    --stores a list of overriden functions
    
    ---@class Hook      :LinkedListHead
    ---@field add       function
    ---@field addSimple function
    ---@field flush     function
    ---@field func      function
    ---@field loop      fun(list) -> hookNode

    ---@class hookNode  :LinkedListNode
    ---@field priority  number
    ---@field head      Hook
    ---@field func      fun(hook:Hook)

    ---@class hookInstance:table
    ---@field args      table
    ---@field call      function    --original function that was hooked
    ---@field skip      boolean
    ---@field returned  table
--[[--------------------------------------------------------------------------------------
    Internal functions
----------------------------------------------------------------------------------------]]
    ---@param oldFunc string
    ---@param parent? table
    ---@return table
    ---@return table hookedFuncParent
    ---@return function? hooked_func_or_nil
    ---@return function hooked_func
    local function parseArgs(oldFunc, parent)
        parent = parent or _G
        local hfp = hookedFunc[parent]
        local hf = hfp and hfp[oldFunc]
        return parent, hfp, hf, hf or parent[oldFunc]
    end

--[[--------------------------------------------------------------------------------------
    Hook.add
    Args: string oldFunc, function userFunc[, number priority, table parent, function default]
          @ oldFunc is a string that represents the name of a function (e.g. "CreateUnit")
          @ userFunc is the function you want to be called when the original function is
            called*.
          @ priority is an optional parameter that determines whether your hook takes place
            "before" the original function is called, or after. Broken down like this:
            
            (a) if "priority" is "nil", "false" or a "negative number", it is treated as a
                "before hook". If "nil" or "false", "_LOW_PRIO" will be assigned as the priority.
            (b) if "priority" is "true", "0" or a "positive number", it is treated as an
                "after hook". If "true", it defaults to "_HIGH_PRIO".
            
          @ parent is an optional parameter for where the oldFunc is hosted. By default,
            it assumes a global (_G table) such as "BJDebugMsg".
          @ default is a function that you can inject into the table in case that variable
            is not found. If the variable is not found and a function is not passed as a
            default, the addition will fail.
    
    Returns two items:
        1. The original function you are hooking (if successful) or nil (if failed).
        2. A table to represent your hook registry. This is part of a linked list belonging
           to the function you hooked and aligned with whether it is a "before" or "after"
           hook. Its most relevant use would be to be passed to "Hook.remove(userHookTable)",
           as that is the way to remove a single hook in version 4.0.
    
    *The function you specify in Hook.add can take exactly one argument: a table. That
    table has the following properties within itself:
    
    args
    (table)
        Contains the original arguments passed during a hook. Useful for referencing in an
        "after hook". Can be modified by a "before hook".
    
    returned
    (table or nil)
        Contains a table of the return value(s) from "before" hooks and (if applicable) the
        original function. This is either "nil", or usually only holds a single index. To
        initialize this correctly, use table.pack(returnVal[, returnVal2, returnVal3, ...]).
    
    old
    (function)
        The original, native function that has been hooked (in case you want to call it).
    
    skip
    (boolean)
    Note: Set this to "true" from within a before-hook callback function to prevent the
          original function from being called. Users can check if this is set to true if
          they want to change the behavior of their own hooks accordingly.
----------------------------------------------------------------------------------------]]
    ---@param oldFunc string
    ---@param userFunc fun(hook:table)
    ---@param priority? number
    ---@param parent? table
    ---@param default? function
    ---@return function original_function
    ---@return hookNode newUserNode
    function Hook.add(oldFunc, userFunc, priority, parent, default)
        if type(oldFunc) ~= "string" or type(userFunc) ~= "function" then
            --print "Hook.add Error: The first argument must be a string, the second must be a function."
            return
        end
        local parent, hfp, hf, old = parseArgs(oldFunc, parent)
        
        if not old or type(old) ~= "function" then
            if default then
                old             = default
                parent[oldFunc] = default
            else
                --print("Hook.add Error: Tried to hook a function that doesn't exist: " .. oldFunc .. ".\nTry calling Hook.add from a Global Initialization function.")
                return
            end
        end
        if not hf then
            if not hfp then
                hfp                 = {}
                hookedFunc[parent]  = hfp
            end
            hfp[oldFunc]    = old ---@type function
            local hb        = LinkedList.create()   ---@type Hook
            hookBefore[old] = hb
            hb.func         = old
            local ha        = LinkedList.create()   ---@type Hook
            hookAfter[old]  = ha
            ha.func         = old
            parent[oldFunc] =
            function(...)
                local this = {args = table.pack(...), call = old, skip = false } ---@type hookInstance
                
                for userNode in hb:loop() do userNode.func(this, userNode) end
                
                local r
                if not this.skip then
                    r = table.pack(old(table.unpack(this.args, 1, this.args.n)))
                    if r.n > 0 then this.returned = r end
                end
                r = this.returned
                if not (r and type(r) == "table" and r.n and r.n > 0) then
                    r = nil; this.returned = nil
                --else
                    --print("Hook report: returning " .. r.n .. " values.")
                end
                
                for userNode in ha:loop() do userNode.func(this, userNode) end
                
                if r then return table.unpack(r, 1, r.n) end
            end
        end
        
        priority = priority or _LOW_PRIO
        if priority == true then priority = _HIGH_PRIO end
        
        --This creates and inserts newUserNode into the corresponding table with taking into consideration the priority of each item.
        local tab = priority < 0 and hookBefore[old] or hookAfter[old]
        local insertPoint = tab.head
        local newUserNode
        for node in tab:loop() do
            if node.priority > priority then insertPoint = node; break end
        end
        newUserNode = insertPoint:insert() ---@type hookNode
        newUserNode.func = userFunc
        newUserNode.priority = priority
        newUserNode.remove = Hook.remove
        
        --print("indexing")
        return old, newUserNode
    end
    
    ---Remove a registered hook by passing the node returned from the second
    ---return value of Hook.add.
    ---@param node hookNode
    ---@return integer number_of_hooks_remaining
    function Hook.remove(node)
        local r = 0
        local head = node.head
        if head then
            head:remove(node)
            r = hookBefore[head.func].n + hookAfter[head.func].n
            if r == 0 then
                Hook.flush(head.func)
            end
        end
        return r
    end
    
--[[--------------------------------------------------------------------------------------
    Hook.flush
    Args: string oldFunc[, table parent]
    Desc: Purges all hooks associated with the given function string and sets the original
          function back inside of the parent table.
----------------------------------------------------------------------------------------]]
    
    ---Hook.flush
    ---@param oldFunc string
    ---@param parent? table
    function Hook.flush(oldFunc, parent)
        local parent, hfp, hf, old = parseArgs(oldFunc, parent)
        if hf then
            parent[oldFunc] = old
            hookBefore[old] = nil
            hookAfter[old]  = nil
            hfp[oldFunc]    = nil
        end
    end
    
--[[--------------------------------------------------------------------------------------
    The user-function parameters and behavior are different from Hook.add. This uses
    the original format I wanted for hook-behavior, but it became clear that there
    were scenarios where the user should be able to do more.
    
    "Before hook" parameters are the arguments of the original function call. This is
    useful in a situation where you don't want to unpack the args yourself to see them in
    an intuitive way, and don't need the additional complexities of the table to determine
    what you want to do.
    
    Return: If anything other than "nil" is returned, it will prevent any additional
            "before" hooks with a lower priority from running, as well as prevent the
            original function from being called. If returning a value other than "nil"
            would break the expectations of the original function, return the string
            "stop hook" instead.
    
    "After hook"
    ------------
    Args: Takes the return value(s) as parameter(s), if there was any return value.
----------------------------------------------------------------------------------------]]
    ---@param oldFunc string
    ---@param userFunc function
    ---@param priority? number
    ---@param parent? table
    ---@param default? function
    ---@return function original_function
    ---@return hookNode newUserNode
    function Hook.addSimple(oldFunc, userFunc, priority, parent, default)
        return Hook.add(oldFunc,
        function(hook)
            local r = hook.returned
            if priority and (priority == true or priority >= 0) then
                if r then
                    userFunc(table.unpack(r, 1, r.n))
                else
                    userFunc()
                end
            elseif not hook.skip and not r then
                r = userFunc(table.unpack(hook.args, 1, hook.args.n))
                if r and #r > 0 then
                    if r[1] ~= _SKIP_HOOK then
                        hook.returned = table.pack(r)
                    end
                    hook.skip = true
                end
            end
        end, priority, parent, default)
    end
    
end --End of Hook library