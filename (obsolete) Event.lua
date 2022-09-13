if LinkedList then --https://www.hiveworkshop.com/threads/definitive-doubly-linked-list.339392/
--[[
    Event version 1.3.0.1 by Bribe

Barebones API that doesn't incorporate GUI events:
    myEvent = Event.create()
    myEvent(function() print "myEvent is running" end)
    myEvent:run()
    myEvent:destroy()

Simple API that extends to enable GUI events (provided MyRealVariable was created in Variable Editor):
    Event.create("udg_MyRealVariable")
    ...in a trigger:
    Game - Value of MyRealVariable becomes Equal to 1.00*

Advanced API for GUI (in case you want to avoid creating too many GUI variables for similar events):
    Event.create("udg_MyRealVariable", NOT_EQUAL)
    ...in a trigger:
    Game - Value of MyRealVariable becomes Not Equal to 1.00*

*The real value at the end dictates the priority that the event will run in. Smaller numbers run first.
]]
---@class Event : LinkedList
---@field public    run         fun(...)
---@field public    args        table       --Retrieve the arguments via a variable event callback
---@field private   execute     function
---@field private   varStr      string
---@field private   opCode      limitop
---@field public    loop        fun() ->Event

---@class EventReg : Event
---@field public    userFunc    fun(...)
---@field private   priority    number
Event = {}
Event.__index = Event

Event.loop = LinkedList.loop        ---@type fun()->Event
Event.insert = LinkedList.insert
Event.remove = LinkedList.remove

local _LOW_PRIO = 9001

local events ---@type Event[]

---Create a new event with optional GUI real variable string, limitop and numerical value 
---to coincide with a real variable event registry.
---@param varStr? string
---@param opCode? limitop
---@return Event
function Event.create(varStr, opCode)
    local event = LinkedList.create() ---@type Event
    setmetatable(event, Event)

    if varStr and Hook then --https://www.hiveworkshop.com/threads/hook.339153
        if not events then
            events = {}
            Hook.add("TriggerRegisterVariableEvent",    --add a hook for GUI trigger registry
            function(hook)
                local str = hook.args[2]
                local onReg = events[str]              --check if the variable is indexed to Event
                if not onReg then
                    onReg = events[str .. GetHandleId(hook.args[3])] --check if the event's limitop is a match.
                    if not onReg then return end
                end
                local trig = hook.args[1]                   --map the trigger to the event.
                onReg( function() if IsTriggerEnabled(trig) then ConditionalTriggerExecute(trig) end end, hook.args[4])
                hook.skip = true                            --prevent the variable event from being created.
            end)
        end
        event.varStr = opCode and varStr .. GetHandleId(opCode) or varStr
        events[event.varStr] = event
    end
    return event
end

---Execute all functions registered to this event
---optional arguments are optional.
function Event:run(...)
    if self.varStr then
        local args = Event.args --need to be able to access args publicly for registered triggers.
        Event.args = table.pack(...)
        for node in self:loop() do node.userFunc(...) end
        Event.args = args
    else
        for node in self:loop() do node.userFunc(...) end
    end
end

if GlobalRemapArray then --https://www.hiveworkshop.com/threads/global-variable-remapper.339308
    GlobalRemapArray("udg_Event__Data", function(index) return Event.args[index] end) --enable GUI to access Event args via Event__Data
end

---Enables yourEvent(yourFunc) syntax to register to an event.
---@param event Event
---@param userFunc fun(...)
---@param priority? number
---@return Event eventReg
Event.__call = function(event, userFunc, priority)
    priority            = priority or _LOW_PRIO
    local insertPoint   = event
    for node in event:loop() do
        if node.priority > priority then insertPoint = node; break end
    end
    local eventReg      = insertPoint:insert() ---@type EventReg
    eventReg.userFunc   = userFunc
    eventReg.priority   = priority
    return eventReg
end

---Destroy the given Event
function Event:destroy()
    events[self.varStr] = nil
end
    
end --End of Event library
    
