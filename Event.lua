--[[
    Event v2

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
    Event.MyEvent.execute(promiseID:any, promiseSucceeded:boolean, ...)
        - Run the event with special data attached (e.g. Spell Event uses the ability ID, Damage Engine uses limitops)
        - In most cases, promiseSucceeded should be "true". However (for example) Attack Engine -> Damage Engine data transmission will use "false" to cover "missed" events.

    --Enhanced event registration:
    Event.SpellEffect.registerOnValue('Amrf', function() print "Medivh's Raven Form was used" end))
        - This is an example of how Spell Event uses the ability ID to distinguish a special callback to this function.
]]
OnInit(function(require) --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Total_Initialization.lua

    local hook        = require "AddHook"                --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Hook.lua
    local remap       = require.lazily "GlobalRemap"     --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Global_Variable_Remapper.lua
    local sleep       = require.lazily "PreciseWait"     --https://github.com/BribeFromTheHive/Lua-Core/blob/main/PreciseWait.lua
    local wrapTrigger = require.lazily "GUI.wrapTrigger" --https://github.com/BribeFromTheHive/Lua-Core/blob/main/Lua-Infused-GUI.lua

    local _PRIORITY   = 1000 --The hook priority assigned to the event executor.
    
    Event = {current = {}}

    local allocate, addFunc

    ---@param name string        -- A unique name for the event. GUI trigger registration will check if "udg_".."ThisEventName" exists, so do not prefix it with udg_.
    ---@return table
    function Event.create(name)
        local event = allocate(name)
        
        ---Register a function to the event.
        ---@param userFunc      function
        ---@param priority?     number      defaults to 0.
        ---@param manualNext?   boolean     set to false if you want to control when the next function should be called (e.g. have code run after the next function).
        ---@param userTrig?     trigger     only exists if was called from TriggerRegisterVariableEvent, and only useful if this function is hooked.
        ---@param userOp?       limitop     same as the above.
        ---@return table
        function event.register(userFunc, priority, manualNext, userTrig, userOp)
            return addFunc(name, userFunc, priority, manualNext)
        end

        ---Similar to JavaScript's Promise object. Calls userFunc when the event is run with the specified index.
        ---@param onValue       any       the value that needs to match for when the event runs.
        ---@param userFunc      function
        ---@param runOnce?      boolean   if true, will remove itself after being called the first time.
        ---@param priority?     number    defaults to 0
        ---@param manualNext?   boolean
        ---@return table
        function event.registerOnValue(onValue, userFunc, runOnce, priority, manualNext)
            return addFunc(
                onValue,
                function(...)
                    userFunc(...)
                    if runOnce then
                        Event.current.funcData.remove()
                        if event.promise[onValue] == DoNothing then--no further events exist on this, so Hook has defaulted back to DoNothing
                            event.promise[onValue] = nil
                        end
                    end
                end,
                priority, manualNext,
                rawget(event, "promise") or rawget(rawset(event, "promise", __jarray()), "promise") --using a jarray allows Lua-Infused GUI to clean up expired promises.
            )
        end
        return event --return the event object. Alternatively, the user can simply access this same value via Event.MyEventName
    end

    local currentEvent = Event.current

    function addFunc(hookIndex, userFunc, priority, manualNext, hookTable)
        assert(type(userFunc)=="function")
        local funcData = {active = true}
        funcData.next,
        funcData.remove = hook(
            hookIndex,
            function(...)
                if funcData.active then
                    currentEvent.funcData = funcData
                    funcData.depth = 0
                    userFunc(...)
                    if manualNext then return end
                end
                funcData.next(...)
            end,
            priority, hookTable or Event, DoNothing, false
        )
        return funcData
    end

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
                    funcData.depth = 0
                end
                freeze.list = {}
            end
        end
    }

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
        
        event = Event[name]

        local udgName = "udg_"..name ---@type string|false
        local isGlobal = pcall(testGlobal, udgName)

        udgName = (isGlobal or _G[udgName]) and udgName
        if udgName then --only proceed with this block if this is a GUI-compatible string.
            if isGlobal then
                globals[udgName] = realID.create(name) --WC3 will complain if this is assigned to a non-numerical value, hence have to generate one.
            else
                _G[udgName] = name --do this as a failsafe in case the variable exists but didn't get declared in a GUI Variable Event.
            end
            event.destroy = select(2,
                hook(
                    "TriggerRegisterVariableEvent", --PreciseWait is needed if triggers use WaitForEvent/SleepEvent.
                    function(userTrig, userStr, userOp, priority)
                        if udgName == userStr then
                            event.register(
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
        else
            event.destroy = DoNothing
        end

        local function runEvent(promiseID, success, eventID, ...)
            local promise = rawget(event, "promise")
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

        function event.registerOnNext(userFunc)
            return event.registerOnValue(currentEvent.data, userFunc, true)
        end

        local runQueue
        function event.execute(...)
            local funcData = currentEvent.funcData
            if funcData then --if another event is already running.
                runQueue = runQueue or {}
                table.insert(runQueue, table.pack(...)) --rather than going truly recursive, queue the event to be ran after the already queued event(s).
                funcData.depth = funcData.depth + 1
                if funcData.depth >= (funcData.maxDepth and math.max(funcData.maxDepth, 1) or 1) then --max recursion has been reached for this function.
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

        return event
    end
    if remap then
        if sleep then
            remap("udg_WaitForEvent", nil, function(whichEvent)
                if type(whichEvent) == "number" then
                    whichEvent = realID.name[whichEvent] --this is a real value (globals.udg_eventName) rather than simply _G.eventName (which stores the string).
                end
                assert(whichEvent)
                local co = coroutine.running()
                Event[whichEvent].registerOnNext(function() coroutine.resume(co) end)
                coroutine.yield()
            end)
            remap("udg_SleepEvent", nil, function(duration)
                local funcData, data    = currentEvent.funcData, currentEvent.data

                PolledWait(duration)    --Yields the coroutine while preserving the event index for the user.
                currentEvent.funcData   = funcData
                currentEvent.data       = data
                funcData.depth          = 0
            end)
        end
        remap("udg_EventSuccess",
            function() return currentEvent.success end,
            function(value) currentEvent.success = value end
        )
        remap("udg_EventIndex", function() return currentEvent.data end)
        remap("udg_EventRecursion",
            function() return currentEvent.funcData.depth end,
            function(depth) currentEvent.funcData.maxDepth = depth end
        )
    end
end)
