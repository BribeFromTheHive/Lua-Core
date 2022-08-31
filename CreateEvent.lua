OnLibraryInit({         --requires https://www.hiveworkshop.com/threads/global-initialization.317099/
    "AddHook"           --requires https://www.hiveworkshop.com/threads/hook.339153/
    --,"GlobalRemap"    --optional https://www.hiveworkshop.com/threads/global-variable-remapper.339308
}, function()
--[[
CreateEvent v0.3 (beta)

CreateEvent is built for GUI support, event linking via coroutines, simple events
(e.g. Heal Event) or complex event systems such as Spell Event and Damage Engine.

Due to optional parameters/return values, the API supports a very simple or very
complex environment, depending on how you choose to use it. It is also easily
extensible, so it can be used to support API for other event libraries.
]]
local events={}
local rootFuncList,eventStr2Num={},{}
local globalSuspendFunc, globalRemapCalled, cachedTrigFuncs, globalEventIndex, createEventIndex, recycleEventIndex
local weakTable={__mode="k"}

---@param eventStr?             string                          Reserved only for GUI trigger registration
---@param prevEventRef          integer|string                  If 0, will be first in a chain of events. If an existing event, will be added to that list.
---@param maxEventDepth?        integer                         defaults to 1 if nil. Only in very few cases should this be changed.
---@param funcSanitizer?        fun(userFunc:function):function takes the user's function and returns whatever you want (e.g. a wrapper func, or nil to prevent the registration).
---@return fun(userFunc:function, priority?:number, manualControl?:boolean):nextEvent:function,removeEvent:fun(pause:boolean),suspendFunc:fun(until_which_event:integer)|nil registerEvent
---@return fun(...)         runEvent        call this with any number of arguments to run all functions registered to this event.  
---@return function         removeEvent     call this to remove the event completely.
---@return integer|string   eventIndex      useful in multi-event-sequences to identify the previous event in a chain.
function CreateEvent(eventStr, prevEventRef, maxEventDepth, funcSanitizer)
    local thisEvent, registerEvent, running, removeEventHook, removeTRVE, unpauseList, userFuncList
    
    thisEvent=createEventIndex()--each event needs a unique numerical index.

    events[thisEvent]=DoNothing --use a dummy function to enable Hook without having to use it as a default function.

    if prevEventRef then        --a reference tracker is needed to link certain events to each other (like UnitIndexEvent/UnitDeindexEvent)
        if prevEventRef==0 then --no previous reference, but is designated as an event which WILL be used in a linked event sequence.
            userFuncList=setmetatable({}, weakTable)        --Tracks the user functions to detect already-linked functions, so it knows when to apply coroutines
            rootFuncList[thisEvent]=userFuncList                        --Index the func list to the root event.
        else
            if type(prevEventRef)=="string" then
                prevEventRef=eventStr2Num[prevEventRef] --extract the actual reference from the user-friendly string they provided.
            end
            userFuncList=rootFuncList[prevEventRef]     --recover the func list from the previous reference
            rootFuncList[thisEvent]=userFuncList        --link the func list to this new reference, so that it works correctly in any subsequent linked events.
        end
    end
    registerEvent=function(userFunc, priority, disablePausing, manualControl)
        local nextEvent, isPaused, removeUserHook, removeOrPauseFunc, userFuncBaseCaller, userFuncHandler, pauseFuncHandler, suspendFunc
        if prevEventRef then
            --all data is indexed by the user's function. So, for linked events, the user should pass the
            --same function to each of them, to ensure that they can be connected via one harmonious coroutine:
            local thisList=userFuncList[userFunc]
            if not thisList then
                thisList=setmetatable({}, weakTable)
                userFuncList[userFunc]=thisList

                --It is imperitive that the eventIndex is a unique value for the event, in order to ensure that
                --coroutines can persist even with overlapping events that call the same function. A good example
                --is a Unit Index Event which runs when a unit is created, and once more when it is removed. The
                --Event Index can be a unit, and the "on index" coroutine can simply yield until the "on deindex"
                --runs for that exact unit. Another example is simply using a dynamic table for the eventIndex,
                --which is what systems like Damage Engine use.
                local lastEventIndex
                userFuncBaseCaller=function(eventIndex, ...)
                    --transform calling the user's function into a coroutine
                    lastEventIndex=eventIndex
                    local co=coroutine.create(userFunc)
                    coroutine.resume(co, eventIndex, ...)
                    if not manualControl and coroutine.status(co)=="suspended" then
                        nextEvent(eventIndex, ...)
                        return true
                    end
                end
                --this function will be returned via the registration call:
                suspendFunc=function(suspendUntil)
                    local co=coroutine.running()
                    thisList[lastEventIndex]={co=co, waitFor=suspendUntil}

                    coroutine.yield(not manualControl) --if the coroutine yields, alert the "resume" function accordingly.
                end
                thisList.suspendFunc=suspendFunc
            else
                thisList=userFuncList[userFunc]
                userFuncBaseCaller=function(eventIndex, ...)
                    --completely change the user's function to load and resume a coroutine.
                    local thread=thisList[eventIndex]
                    if thread and thread.waitFor==thisEvent then
                        globalSuspendFunc=suspendFunc
                        globalEventIndex=eventIndex
                        local co=thread.co
                        coroutine.resume(co)
                        if not manualControl and coroutine.status(co)=="suspended" then
                            nextEvent(eventIndex, ...)
                            return true
                        end
                    end
                end
                suspendFunc=thisList.suspendFunc
            end
        else
            userFuncBaseCaller=userFunc
        end
        if disablePausing then
            pauseFuncHandler=userFuncBaseCaller
        else
            --wrap the user's function:
            pauseFuncHandler=function(...)
                if not isPaused then return userFuncBaseCaller(...) end
            end
        end
        if manualControl then
            userFuncHandler=pauseFuncHandler
        else
            --wrap the user's function again:
            userFuncHandler=function(...)
                if not pauseFuncHandler(...) or not prevEventRef then
                    nextEvent(...)
                end
            end
        end
        if funcSanitizer then
            --in case the user wants anything fancier than what's already given, they can add
            --some kind of conditional or data attachment/complete denial of the function.
            userFuncHandler=funcSanitizer(userFuncHandler)
            if userFuncHandler==nil then return end
        end
        --Now that the user's function has been processed, hook it to the event:
        nextEvent,removeUserHook=AddHook(thisEvent, userFuncHandler, priority, events)
        
        removeEventHook=removeEventHook or removeUserHook   --useful only if the entire event will ultimately be removed:

        --this incorporates the pause/unpause mechanism of Damage Engine 5, but with more emphasis on the user being in control:
        removeOrPauseFunc=function(pause, autoUnpause)
            if pause==nil then
                removeUserHook()
            else
                isPaused=pause
                if autoUnpause then
                    unpauseList=unpauseList or {}
                    table.insert(unpauseList, removeOrPauseFunc)
                end
            end
        end
        return nextEvent, removeOrPauseFunc, suspendFunc --return the user's 3 functions. suspendFunc will be nil unless there are linked events.
    end
    if eventStr then
        if prevEventRef then
            eventStr2Num[eventStr]=thisEvent    --Cache the event index to the string representation

            globals[eventStr]=thisEvent         --Align the "global.X" syntax accordingly, so that it works properly with Set WaitForEvent = SomeEvent.

            if not globalRemapCalled then
                globalRemapCalled=true
                GlobalRemap("udg_WaitForEvent", nil, function(val) print("suspending until: "..val);globalSuspendFunc(val) end)
                GlobalRemap("udg_EventIndex", function() return globalEventIndex end)
            end
        end
        local oldTRVE
        oldTRVE,removeTRVE=AddHook("TriggerRegisterVariableEvent",
        function(userTrig, userStr, userOp, userVal)    --This hook runs whenever TriggerRegisterVariableEvent is called:
            if eventStr==userStr then
                local cachedTrigFunc, suspendFunc
                if cachedTrigFuncs then
                    cachedTrigFunc=cachedTrigFuncs[userTrig]
                else
                    cachedTrigFuncs=setmetatable({},weakTable)
                end
                if not cachedTrigFunc then
                    cachedTrigFunc=function(eventIndex)
                        globalEventIndex=eventIndex
                        if IsTriggerEnabled(userTrig) and TriggerEvaluate(userTrig) then
                            globalSuspendFunc=suspendFunc
                            TriggerExecute(userTrig)
                        end
                    end
                    cachedTrigFuncs[userTrig]=cachedTrigFunc
                    _,_,suspendFunc=registerEvent(cachedTrigFunc, userVal)
                else
                    registerEvent(cachedTrigFunc, userVal)
                end
            else
                return oldTRVE(userTrig, userStr, userOp, userVal)
            end
        end)
    end
    return registerEvent,
    --This function runs the event.
    function(...)
        if running then
            --rather than going truly recursive, queue the event to be ran after the first event, and wrap up any events queued before this.
            if running==true then running={} end
            local args=table.pack(...)
            table.insert(running, function() events[thisEvent](table.unpack(args, 1, args.n)) end)
        else
            running=true
            events[thisEvent](...)
            local depth=0
            while running~=true and depth<maxEventDepth do
                --This is, at its core, the same recursion processing introduced in Damage Engine 5.
                local runner=running; running=true
                for func in ipairs(runner) do func() end
                depth=depth+1
            end
            if unpauseList then
                --unpause users' functions that were set to be automatically unpaused.
                for func in ipairs(unpauseList) do func(false) end
                unpauseList=nil
            end
            --un-comment the below if you want debugging. Mainly useful if you use a depth greater than 1.
            --if depth>=maxEventDepth then
            --    print("Infinite Recursion detected on event: "..(eventStr or thisEvent))
            --end
            running=nil
        end
    end,
    --This function destroys the event.
    function()
        if thisEvent then
            if removeEventHook and events[thisEvent]~=DoNothing then removeEventHook(true) end
            if removeTRVE then removeTRVE() end

            recycleEventIndex(thisEvent)
            thisEvent=nil
        end
    end,
    thisEvent --the event index. Useful for chaining events in a sequence that didn't get tagged to a GUI variable.
end
do
    local eventN=0
    local eventR={}
    --works indentically to vJass struct index handling
    ---@return integer
    createEventIndex=function()
        if #eventR>0 then
            return table.remove(eventR, #eventR)
        else
            eventN=eventN+1
            return eventN
        end
    end
    ---@param index integer
    recycleEventIndex=function(index)
        table.insert(eventR, index)
        events[index]=nil
    end
end
end)
