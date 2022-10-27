OnGlobalInit(function()

Require "AddHook"                            --https://www.hiveworkshop.com/threads/hook.339153/
local remap = Require.optional "GlobalRemap" --https://www.hiveworkshop.com/threads/global-variable-remapper.339308
local sleep = Require.optional "PreciseWait"

local _EVENT_PRIORITY = 1000 --The hook priority assigned to the event executor.

--[[
Event v1.4

Event is built for GUI support, event linking via coroutines, simple events (e.g. Heal Event),
binary events (like Unit Indexer) or complex event systems like Spell Event, Damage Engine and Unit Event.

There are three main functions to keep in mind for the global API:

Event.create
============
Create an event that is recursion-proof by default, with easy syntax for GUI support.

Due to optional parameters and return values, the API supports a very simple or very
complex environment - depending on how you choose to use it.
It is also easily extensible, so it can be used to support API for other event libraries.

--In its most basic form:
Event.create("MyEvent")     -> Create your event.
Event.MyEvent.register()    -> Global API for the user to call to register their callback function.
Event.MyEvent()             -> call this when it's time for the event to execute.

--If GUI has a variable by the same name, it hooks it internally (hiding the ugliness) to allow this to work:
Game - Value of MyEvent becomes Equal to 0.00

NOTE - the value is the priority used in the event sequence, so higher-registered numbers run first, down to lower numbers.

WaitForEvent
============
Useful for when events are linked together. Allows you to suspend your function until the designated event is called.

ControlEventRecursion
=====================
Useful only if wanting recursion for a specific function to be able to exceed a certain
point, but also useful for debugging (as it returns the current depth and max depth).
]]

local Event = {}
local eventStrs = {} --key, values formatted as ["eventName"] = eventID.
eventStrs.__index = function(_, string) return rawget(Event, rawget(eventStrs, string)) end
setmetatable(Event, eventStrs)

local globalRemapCalled, cachedTrigFuncs, globalEventIndex, createEventIndex, recycleEventIndex, globalFuncRef, runEvent, waitForEvent
local weakTable={__mode="k"}
local userFuncList=setmetatable({}, weakTable)

---@param eventStr?         string      - Name the event. Also useful for GUI trigger registration
---@param isLinkable?       boolean     - If true, will use event linking to bind events when possible.
---@param maxEventDepth?    integer     - Defaults to 1. If 0, events are forbidden to branch off of each other.
---@param customRegister?   fun(userFunc:function, continue?:fun(editedFunc:fun(), noHook:boolean), firstReg?:boolean, trigRef?:trigger, opCode?:limitop, priority?:number):function,function
---@return fun(userFunc:function, priority?:number, manualControl?:boolean):nextEvent:function, removeOrPause:fun(pause:boolean) registerEvent
---@return fun(...)         runEvent    - Run all functions registered to this event. The first parameter should be a unique index, and if the second parameter is a function, it will be executed as a "one time event", without being registered.
---@return function         removeEvent - Call this to remove the event completely.
function Event.create(eventStr, isLinkable, maxEventDepth, customRegister)
    local thisEvent   = createEventIndex()  -- each event needs a unique numerical index.
    Event[thisEvent]  = DoNothing           -- use a dummy function to enable Hook without having to use it as a default function.
    maxEventDepth     = maxEventDepth or 1  -- apply the default recusion depth allowance for when none is specified.
    --Declare top-level variables needed for use within this particular event.
    local unpauseList, trigRef, opCode
    local registerEvent=function(userFunc, priority, disablePausing, manualControl)
        local evaluator, wrapper, nextEvent, firstReg
        
        --all data is indexed by the user's function. So, for linked events, the user should pass the
        --same function to each of them, to ensure that they can be connected via one harmonious coroutine:
        local funcRef=userFuncList[userFunc]

        if isLinkable then
            local resumer=function(co, ...)
                globalFuncRef = funcRef
                coroutine.resume(co, ...)
                if not manualControl and coroutine.status(co)=="suspended" then
                    nextEvent(...)
                    return true
                end
            end
            if funcRef then
                wrapper=function(eventIndex, ...)
                    --completely change the user's function to load and resume a coroutine.
                    local thread=funcRef[eventIndex]
                    if thread and thread.waitFor==thisEvent then
                        return resumer(thread.co, eventIndex, ...)
                    end
                end
            else
                --It is imperitive that the eventIndex is a unique value for the event, in order to ensure that
                --coroutines can persist even with overlapping events that call the same function. A good example
                --is a Unit Index Event which runs when a unit is created, and once more when it is removed. The
                --Event Index can be a unit, and the "on index" coroutine can simply yield until the "on deindex"
                --runs for that exact unit. Another example is simply using a dynamic table for the eventIndex,
                --which is what systems like Damage Engine use.
                wrapper=function(eventIndex, ...)
                    --transform calling the user's function into a coroutine
                    return resumer(coroutine.create(userFunc), eventIndex, ...)
                end
                firstReg=true
            end
        else
            wrapper=userFunc
            if maxEventDepth > 0 then
                evaluator = function() globalFuncRef = funcRef end
            end
        end
        if not funcRef then
            funcRef=setmetatable({userFunc=userFunc, maxDepth=maxEventDepth}, weakTable)
            userFuncList[userFunc]=funcRef
        end
        local isPaused
        if not disablePausing then
            local old = evaluator or DoNothing
            evaluator = function() return isPaused or old() end
        end
        evaluator = evaluator or DoNothing
        if manualControl then
            local old = wrapper
            wrapper = function(...)
                if not evaluator() then
                    old(...)
                end
            end
        else
            local old = wrapper
            wrapper=function(...)
                if not evaluator() then
                    if (not old(...) or not isLinkable) then
                        nextEvent(...)
                    end
                end
            end
        end
        ---Call this function from the custom register to actually register the event.
        ---This also allows you access to the return values, because your custom register
        ---needs to return those two functions (wrapped, nilled or unspoiled).
        ---@param editedFunc? function
        ---@param noHook? boolean
        ---@return fun(args_should_match_the_original_function?: any):any nextEvent
        ---@return fun(pause:boolean, autoUnpause:boolean) removeOrPause
        local continue=function(editedFunc, noHook)
            local removeUserHook
            if noHook then
                nextEvent,removeUserHook=DoNothing,DoNothing
            else
                nextEvent,removeUserHook=AddHook(thisEvent, editedFunc, priority, Event)  --Hook the processed function to the event.
            end
            local enablerFunc
            enablerFunc=function(pause, autoUnpause)
                if pause==nil then
                    removeUserHook()
                    if firstReg and isLinkable then
                        userFuncList[userFunc]=nil --should the function ever be re-registered, this is key.
                    end
                else
                    isPaused=pause
                    if autoUnpause then
                        --this is the same as the pause/unpause mechanism of Damage Engine 5.
                        unpauseList=unpauseList or {}
                        table.insert(unpauseList, enablerFunc)
                    end
                end
            end
            funcRef.enabler=enablerFunc
            return nextEvent, enablerFunc --return the user's 2 control functions.
        end
        if customRegister then
            local a,b,clearRef=customRegister(wrapper, continue, firstReg, trigRef, opCode, priority)
            if clearRef then
                userFuncList[userFunc]=nil
            end
            return a,b
        else
            return continue(wrapper)
        end
    end
    local _,removeTRVE,parsedEventStr
    if eventStr then
        eventStrs[eventStr] = thisEvent
        if eventStr:sub(1,4) ~= "udg_" then
            parsedEventStr = "udg_"..eventStr
            if not _G[parsedEventStr] then
                parsedEventStr = nil
            end
        end
        if parsedEventStr then --only proceed with this block if this is a GUI-compatible string.
            if isLinkable then
                --Align the "global.X" syntax accordingly, so that it works properly with Set WaitForEvent = SomeEvent:
                pcall(function() globals[parsedEventStr]=thisEvent end) --Have to pcall this, as there is no safe "getter" function to check if the real is indexed to the global to begin with.
                
                if remap and not globalRemapCalled then
                    globalRemapCalled=true
                    if sleep then
                        remap("udg_WaitForEvent", nil, waitForEvent)
                        remap("udg_SleepEvent", nil, SleepEvent)
                    end
                    remap("udg_EventIndex", function() return globalEventIndex end)
                    remap("udg_EventRecusion", nil, function(maxDepth)
                        if globalFuncRef then
                            globalFuncRef.maxDepth=maxDepth
                        end
                    end)
                end
            end
            _,removeTRVE=AddHook("TriggerRegisterVariableEvent",
            function(userTrig, userStr, userOp, userVal)    --This hook runs whenever TriggerRegisterVariableEvent is called:
                if parsedEventStr==userStr then
                    local cachedTrigFunc
                    if cachedTrigFuncs then
                        cachedTrigFunc=cachedTrigFuncs[userTrig]
                    else
                        cachedTrigFuncs=setmetatable({},weakTable)--will only be called once per game.
                    end
                    if not cachedTrigFunc then
                        cachedTrigFunc=function()
                            if IsTriggerEnabled(userTrig) and TriggerEvaluate(userTrig) then
                                TriggerExecute(userTrig) --Needs PreciseWait if used with sleeping coroutines.
                            end
                        end
                        cachedTrigFuncs[userTrig]=cachedTrigFunc
                    end
                    trigRef,opCode=userTrig,userOp
                    registerEvent(cachedTrigFunc, userVal)
                    trigRef,opCode=nil,nil
                else
                    return TriggerRegisterVariableEvent.actual(userTrig, userStr, userOp, userVal)
                end
            end)
        end
    end
    local running, next
    local function execute(eventIndex, specialExec, ...)
        if running then
            --rather than going truly recursive, queue the event to be ran after the first event, and wrap up any events queued before this.
            local max = globalFuncRef.maxDepth or maxEventDepth
            if max>0 then
                if running==true then running={} end
                table.insert(running, table.pack(eventIndex, specialExec, ...))
                local depth = (globalFuncRef.depth or 0) + 1
                if depth >= max then
                    --max recursion has been reached for this function. Pause it and let it be automatically unpaused at the end of the sequence.
                    globalFuncRef.depth = 0
                    globalFuncRef.enabler(true, true)
                else
                    globalFuncRef.depth = depth
                end
            end
        else
            local oldIndex,oldList=globalEventIndex,globalFuncRef--cache so that different overlapping events don't have a conflict.
            running=true
            runEvent(next, eventIndex, specialExec, ...)
            while running~=true do
                --This is the same recursion processing introduced in Damage Engine 5.
                local runner=running; running=true
                for _,args in ipairs(runner) do
                    runEvent(next, table.unpack(args, 1, args.n))
                end
            end
            if unpauseList then
                --unpause users' functions that were set to be automatically unpaused.
                for func in ipairs(unpauseList) do func(false) end
                unpauseList=nil
            end
            running=nil
            globalEventIndex,globalFuncRef=oldIndex,oldList--retrieve so that overlapping events don't break.
        end
    end
    next = AddHook(thisEvent, execute, _EVENT_PRIORITY, Event)
    Event[thisEvent].register = registerEvent
    return registerEvent,
    --Second return value is a function that runs the event when called. Any number of paramters can be specified, but the first should be unique to the event instance you're running.
    Event[thisEvent],
    --Third return value is used to remove the event. Usually unused, as most events would be persistent.
    function()
        if thisEvent~=0 then
            if eventStr then
                eventStrs[eventStr] = nil
                if removeTRVE then
                    removeTRVE()
                end
            end
            recycleEventIndex(thisEvent)
            thisEvent        = 0
        end
    end
end
CreateEvent = Event.create -- I may eventually deprecate this function.
do
    local uniqueEventIndices=0
    local recycledEvents={}
    --works indentically to vJass struct index handling
    ---@return integer
    createEventIndex=function()
        if #recycledEvents>0 then
            return table.remove(recycledEvents, #recycledEvents)
        else
            uniqueEventIndices=uniqueEventIndices+1
            return uniqueEventIndices
        end
    end
    ---@param index integer
    recycleEventIndex=function(index)
        table.insert(recycledEvents, index)
        Event[index]=nil
    end
    runEvent = function(eventFunc, eventIndex, specialFunc, ...)
        globalEventIndex=eventIndex
        eventFunc(eventIndex, ...)
        if specialFunc and type(specialFunc)=="function" then
            --A special execution was necessary to enable SpellEvent's O(1) function execution based on ability ID.
            --Without it, all events would need to run, regardless of if the conditions matches.
            specialFunc(eventIndex, ...)
        end
    end
    ---@param whichEvent real
    waitForEvent = function(whichEvent)
        globalFuncRef[globalEventIndex]={co=coroutine.running(), waitFor=whichEvent}
        coroutine.yield()
    end
    ---@param whichEvent string
    function WaitForEvent(whichEvent)
        waitForEvent(eventStrs[whichEvent])
    end
    if sleep then
        ---Yields the coroutine while preserving the event index for the user.
        ---@param duration any
        function SleepEvent(duration)
            local index = globalEventIndex
            PolledWait(duration)
            globalEventIndex = index
        end
    end

    ---Raises or lowers the recursion tolerance for the running function.
    ---The return values are intended for debugging. I expect the automatic recursion handling to be sufficient for most cases.
    ---@param maxDepth? integer
    ---@return integer currentDepth
    ---@return integer maximumDepth
    function ControlEventRecursion(maxDepth)
        if globalFuncRef then
            if maxDepth then
                globalFuncRef.maxDepth = maxDepth
            end
            return globalFuncRef.depth or 0, globalFuncRef.maxDepth or 0
        end
        return 0, 0
    end
end
end)
