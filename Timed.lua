OnLibraryInit("LinkedList", --https://www.hiveworkshop.com/threads/definitive-doubly-linked-list.339392
--[[--------------------------------------------------------------------------------------
    Timed Call and Echo v1.2.4.0, code structure credit to Eikonium and Jesus4Lyf
    
    Timed.call([delay, ]userFunc)
    -> Call userFunc after 'delay' seconds. Delay defaults to 0 seconds.
    
    Timed.echo(userFunc[, timeout])
    -> Returns a new TimedNode.
    -> calls userFunc every "timeout" seconds until userFunc returns true.
    
    Node API (for the tables returned by Timed.echo):
        node.elapsed -> the number of seconds that 'node' has been iterating for.
----------------------------------------------------------------------------------------]]
function()
    local _TIMEOUT = 0.03125 --default echo timeout
    
    ---@class Timed : LinkedListHead
    ---@field loop fun() -> TimedNode
    Timed = {}
    ---@class TimedNode : LinkedListNode
    ---@field elapsed number
    ---@field func fun() -> boolean
    
--[[--------------------------------------------------------------------------------------
    Internal
----------------------------------------------------------------------------------------]]
    
    local zeroList, _ZERO_TIMER
    
--[[--------------------------------------------------------------------------------------
    Name: Timed.call
    Args: [delay, ]userFunc
    Desc: After "delay" seconds, call "userFunc".
----------------------------------------------------------------------------------------]]
    
    ---Core function by Eikonium; zero-second expiration is a simple list by Bribe
    ---@param delay number|function
    ---@param userFunc? function|number
    function Timed.call(delay, userFunc)
        if not userFunc or delay == 0.00 then
            if not zeroList then
                zeroList = {}
                _ZERO_TIMER = _ZERO_TIMER or CreateTimer()
                TimerStart(_ZERO_TIMER, 0.00, false,
                function()
                    local tempList = zeroList
                    zeroList = nil
                    for _, func in ipairs(tempList) do func() end
                end)
            end
            zeroList[#zeroList + 1] = userFunc or delay
        else
            local t = CreateTimer()
            TimerStart(t, delay, false,
            function()
                DestroyTimer(t)
                userFunc()
            end)
        end
    end
 
    local lists = {} ---@type Timed[]
 
--[[--------------------------------------------------------------------------------------
    Timed.echo is reminiscent of Jesus4Lyf's Timer32 module. It borrows from it with the
    LinkedList syntax and "exitwhen true" nature of the original T32 module.

    Desc: Calls userFunc every timeout seconds (by default, every 0.03125 seconds). If
        your own node should be specified but you want to use the default timeout, you
        can use Timed.echo(yourFunc, nil, myTable).
    Warn: This merges all timeouts of the same value together, so large numbers can cause
        expirations to occur too early on.
----------------------------------------------------------------------------------------]]
    ---@param userFunc fun(node:TimedNode) -> boolean -- if true, echo will stop
    ---@param timeout? number
    ---@return TimedNode new_node
    function Timed.echo(userFunc, timeout)
        timeout = timeout or _TIMEOUT
        local list = lists[timeout]
        local elapsed = 0.00
        if list then
            local r = TimerGetRemaining(list.timer)
            if r < timeout * 0.50 then --the merge uses rounding to determine if
                local q = list.queue   --the first expiration should be skipped
                if not q then
                    q = LinkedList.create()
                    list.queue = q
                end
                elapsed = r       --add the remaining timeout to the elapsed time for this node.
                list = q
            else
                elapsed = r - timeout --the instance will be called on the next tick, despite not being around for the full tick.
            end
        else
            list = LinkedList.create() ---@type Timed
            lists[timeout] = list
            local t = CreateTimer()       --one timer per timeout interval
            list.timer = t
            TimerStart(t, timeout, true,
            function()
                for tNode in list:loop() do
                    tNode.elapsed = tNode.elapsed + timeout
                    if tNode:func() then --function can return true to remove itself from the list.
                        tNode:remove()
                    end
                end
                -- delayed add to list
                local q = list.queue
                if q then
                    q:merge(list)
                    list.queue = nil
                end
                --
                if list.n == 0 then --list is empty; delete it.
                    lists[timeout] = nil
                    PauseTimer(t)
                    DestroyTimer(t)
                end
            end)
        end
        local newNode = list:insert()
        newNode.func = userFunc
        newNode.elapsed = elapsed
        return newNode
    end
end)
