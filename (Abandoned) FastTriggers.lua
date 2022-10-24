if Hook then --https://www.hiveworkshop.com/threads/hook.339153

    --Lua Fast Triggers v1.4.1.0
    --Completely overwrites the BJ "ConditionalTriggerExecute" rather than hooking it, due to performance reasons.
    
    local _PRIORITY = -1 --Specify the hook priority for TriggerAddAction and TriggerAddCondition
    
    local cMap = {}
    local aMap = {}
    local lastCondFunc
    local waitFunc
    
    --hook.args = {1:code}
    Hook.add("Condition",
    function(hook)
        lastCondFunc = hook.args[1]
    end)
    
    --hook.args = {1:trigger, 2:boolexpr}
    Hook.add("TriggerAddCondition",
    function(hook)
        if lastCondFunc then
            local trig = hook.args[1]
            local cond = lastCondFunc
            cMap[trig] = cond --map the condition function to the trigger.
            aMap[trig] = aMap[trig] or DoNothing
            lastCondFunc = nil
            
            hook.args[2] = Filter(
            function()
                if cond() then --Call the triggerconditions manually.
                    waitFunc = aMap[trig]
                    waitFunc() --If this was caused by an event, call the trigger actions manually.
                end --always return nil to prevent WC3 from executing any trigger actions.
            end)
        end
    end, _PRIORITY)
    
    --hook.args = {1:trigger, 2:code}
    Hook.add("TriggerAddAction",
    function(hook)
        local act = hook.args[2]
        aMap[hook.args[1]] = act
        
        hook.args[2] = 
        function()
            waitFunc = act
            waitFunc() --If this was caused by an event, call the trigger actions manually.
        end
    end, _PRIORITY)
    
    --hook.args = {1:trigger}
    Hook.add("TriggerExecute",
    function(hook)
        waitFunc = aMap[hook.args[1]]
        hook.skip = true
        waitFunc()
    end)
    
    local skipNext
    function EnableWaits()
        if skipNext then
            skipNext = nil
        else
            skipNext = true
            coroutine.resume(coroutine.create(function()
                waitFunc()
            end))
            return true
        end
    end
    
    function ConditionalTriggerExecute(trig)
        local c = cMap[trig]
        if c and not c() then return end
        local a = aMap[trig]
        if a then a() end
    end
    
    function GetTriggerActionFunc(trig)
        return aMap[trig]
    end
    
    function GetTriggerConditionFunc(trig)
        return cMap[trig]
    end
end
