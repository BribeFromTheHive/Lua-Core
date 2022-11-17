--[[
    Event v2.1

    Event is built for GUI support, event linking via coroutines, simple events (e.g. Heal Event),
    binary events (like Unit Indexer) or complex event systems like Spell Event, Damage Engine and Unit Event.

    Event.create
    ============
    Create an event that is recursion-proof by default, with easy syntax for GUI support.

    --In its most basic form:
    Event.create "MyEvent"          -> Create your event.
    Event.MyEvent.register(myFunc)  -> Global API for the user to call to register their callback function.
    Event.MyEvent()                 -> call this to execute the event (inherits this functionality from Hook).
    
    --If GUI has a variable by the same name, it hooks it internally (automating the udg_ portion) to allow this to work:
    Game - Value of MyEvent becomes Equal to 0.00

    NOTE - the value that MyEvent compares to is its priority in the event sequence, so events with higher numbers run first.

    --Enhanced event execution:
    Event.MyEvent.execute(extraValue:any, eventSucceeded:boolean, ...)
        - Run the event with special data attached (e.g. Spell Event uses the ability ID, Damage Engine uses limitops)
        - In most cases, eventSucceeded should be "true". However (for example) Attack Engine -> Damage Engine data transmission will use "false" to cover "missed" events.
        - Neither extraValue nor eventSucceeded are propogated as parameters to the callback functions.
    
    --Enhanced event registration:
    Event.SpellEffect.await(function() print "Medivh's Raven Form was used" end), 'Amrf', true)
        - This is an example of how Spell Event uses the ability ID to distinguish a special callback to this function.
        - The second parameter specifies the value that should be matched for the event to run.
        - The third value must be "true" if the event should be static (rather than called only once)
    
    --WaitForEvent functionality:
    Event.OnUnitIndexed.register(function()
        print"Unit Indexed" --runs for any unit.
        Event.OnUnitRemoval.await(function()
            print "Unit Deindexed" --runs only for the specific unit from the OnUnitIndexed event, and then automatically removes this one-off event once it runs.
        end)
    end)
]]
OnInit(function(require) --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Total_Initialization.lua

    local hook        = require "AddHook"                --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Hook.lua
    local remap       = require.lazily "GlobalRemap"     --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Global_Variable_Remapper.lua
    local sleep       = require.lazily "PreciseWait"     --https://github.com/BribeFromTheHive/Lua-Core/blob/main/PreciseWait.lua
    local wrapTrigger = require.lazily "GUI.wrapTrigger" --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Lua-Infused-GUI.lua

    local _PRIORITY   = 1000 --The hook priority assigned to the event executor.
    
    local allocate, continue
    local currentEvent, depth = {}, {}

    Event = {
        current = currentEvent,
        stop    = function() continue = false end
    }

    do
        local function addFunc(name, func, priority, hookIndex)
            assert(type(func)=="function")
            local funcData = {active = true}
            funcData.next,
            funcData.remove = hook(
                hookIndex or name,
                function(...)
                    if continue then
                        if funcData.active then
                            currentEvent.funcData = funcData
                            depth[funcData] = 0
                            func(...)
                        end
                        funcData.next(...)
                    end
                end,
                priority, (hookIndex and Event[name].promise) or Event, DoNothing, false
            )
            return funcData
        end

        ---@param name string        -- A unique name for the event. GUI trigger registration will check if "udg_".."ThisEventName" exists, so do not prefix it with udg_.
        ---@return table
        function Event.create(name)
            local event = allocate(name)
            
            ---Register a function to the event.
            ---@param userFunc      function
            ---@param priority?     number      defaults to 0.
            ---@param userTrig?     trigger     only exists if was called from TriggerRegisterVariableEvent, and only useful if this function is hooked.
            ---@param limitOp?      limitop     same as the above.
            ---@return table
            function event.register(userFunc, priority, userTrig, limitOp)
                return addFunc(name, userFunc, priority)
            end

            ---Calls userFunc when the event is run with the specified index.
            ---@param userFunc      function
            ---@param onValue       any         Defaults to currentEvent.data. This is the value that needs to match when the event runs.
            ---@param runOnce?      boolean     Defaults true. If true, will remove itself after being called the first time.
            ---@param priority?     number      defaults to 0
            ---@return table
            function event.await(userFunc, onValue, runOnce, priority)
                onValue = onValue or currentEvent.data
                runOnce = runOnce~=false
                return addFunc(name,
                    function(...)
                        userFunc(...)
                        if runOnce then
                            Event.current.funcData.remove()
                            if event.promise[onValue] == DoNothing then--no further events exist on this, so Hook has defaulted back to DoNothing
                                event.promise[onValue] = nil
                            end
                        end
                    end,
                    priority, onValue
                )
            end
            return event --return the event object. Not needed; the user can just access it via Event.MyEventName
        end
    end

    local createHook
    do
        local realID --Needed for GUI support to correctly detect Set WaitForEvent = SomeEvent.
        realID = {
            n = 0,
            name = {},
            create = function(name)
                realID.n = realID.n + 1
                realID.name[realID.n] = name
                return realID.n
            end
        }

        local function testGlobal(udgName) return globals[udgName] end
        function createHook(name)
            local udgName = "udg_"..name ---@type string|false
            local isGlobal = pcall(testGlobal, udgName)
            local destroy

            udgName = (isGlobal or _G[udgName]) and udgName
            if udgName then --only proceed with this block if this is a GUI-compatible string.
                if isGlobal then
                    globals[udgName] = realID.create(name) --WC3 will complain if this is assigned to a non-numerical value, hence have to generate one.
                else
                    _G[udgName] = name --do this as a failsafe in case the variable exists but didn't get declared in a GUI Variable Event.
                end
                destroy = select(2,
                    hook("TriggerRegisterVariableEvent", --PreciseWait is needed if triggers use WaitForEvent/SleepEvent.
                        function(userTrig, userStr, userOp, priority)
                            if udgName == userStr then
                                Event[name].register(
                                    wrapTrigger and wrapTrigger(userTrig) or
                                    function()
                                        if IsTriggerEnabled(userTrig) and TriggerEvaluate(userTrig) then
                                            TriggerExecute(userTrig)
                                        end
                                    end,
                                    priority, false, userTrig, userOp
                                )
                            else
                                return TriggerRegisterVariableEvent.actual(userTrig, userStr, userOp, priority)
                            end
                        end
                    )
                )
            end
            return function()
                if destroy then destroy() end
                Event[name] = nil
            end
        end

        if remap then
            if sleep then
                remap("udg_WaitForEvent", nil,
                    function(whichEvent)
                        if type(whichEvent) == "number" then
                            whichEvent = realID.name[whichEvent] --this is a real value (globals.udg_eventName) rather than simply _G.eventName (which stores the string).
                        end
                        assert(whichEvent)
                        local co = coroutine.running()
                        Event[whichEvent].await(function() coroutine.resume(co) end)
                        coroutine.yield()
                    end
                )
                remap("udg_SleepEvent", nil,
                    function(duration) --Yields the coroutine while preserving the event index for the user.
                        local funcData, data = currentEvent.funcData, currentEvent.data
                        PolledWait(duration)
                        currentEvent.funcData, currentEvent.data = funcData, data
                    end
                )
            end
            remap("udg_EventSuccess",
                function() return currentEvent.success end,
                function(value) currentEvent.success = value end
            )
            remap("udg_EventOverride",  nil, Event.stop)
            remap("udg_EventIndex",          function() return currentEvent.data end)
            remap("udg_EventRecursion", nil, function(maxDepth) currentEvent.funcData.maxDepth = maxDepth end)
        end
    end
    
    local createExecutor
    do
        local freeze
        freeze = { --this enables the same recursion mitigation as what was introduced in Damage Engine 5
            list = {},
            apply = function(funcData)
                funcData.active = false
                table.insert(freeze.list, funcData)
            end,
            release = function()
                if freeze.list[1] then
                    for _,funcData in ipairs(freeze.list) do
                        funcData.active = true
                    end
                    freeze.list = {}
                end
            end
        }
        function createExecutor(next, promise)
            local function runEvent(promiseID, success, eventID, ...)
                continue = true
                currentEvent.data = eventID
                currentEvent.success = success
                if promise and promiseID then
                    if promise[promiseID] then
                        promise[promiseID](eventID, ...)   --promises are run before normal events.
                    end
                    if promiseID~=eventID and promise[eventID] then --avoid calling duplicate promises.
                        promise[eventID](eventID, ...)
                    end
                end
                next(eventID, ...)
            end

            local runQueue
            return function(...)
                local funcData = currentEvent.funcData
                if funcData then --if another event is already running.
                    runQueue = runQueue or {}
                    table.insert(runQueue, table.pack(...)) --rather than going truly recursive, queue the event to be ran after the already queued event(s).
                    depth[funcData] = depth[funcData] + 1
                    if depth[funcData] > (funcData.maxDepth or 0) then --max recursion has been reached for this function.
                        freeze.apply(funcData)      --Pause it and let it be automatically unpaused at the end of the sequence.
                    end
                else
                    runEvent(...)
                    while runQueue do --This works similarly to the recursion processing introduced in Damage Engine 5.
                        local tempQueue = runQueue
                        runQueue = nil
                        for _,args in ipairs(tempQueue) do
                            runEvent(table.unpack(args, 1, args.n))
                        end
                    end
                    currentEvent.funcData = nil
                    freeze.release()
                end
            end
        end
    end

    ---@param name string
    ---@return table
    function allocate(name)
        assert(type(name)=="string")
        assert(not Event[name])
        local event
        local next = hook(
            name,
            function(eventIndex, ...)
                event.execute(eventIndex, true, eventIndex, ...) --normal Event("MyEvent",...) function call will have the promise ID matched to the event ID, and "success" as true.
            end,
            _PRIORITY, Event, DoNothing, false
        )
        event         = Event[name]
        event.promise = __jarray() --using a jarray allows Lua-Infused GUI to clean up expired promises.
        event.execute = createExecutor(next, event.promise)
        event.destroy = createHook(name)
        return event
    end
end)
