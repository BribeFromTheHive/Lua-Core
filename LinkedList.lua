--[[
    Doubly-Linked List v1.4.2.1 by Wrda, Eikonium and Bribe
    ------------------------------------------------------------------------------
    A script that enables linking objects together with "previous" and "next"
    syntax.
    ------------------------------------------------------------------------------
API:
    LinkedList.create() -> LinkedListHead
    - Creates a new LinkedList head that can have nodes inserted to itself.

    list:insert([value : any, after : boolean]) -> LinkedListNode
    - Inserts *before* the given head/node unless "after" is true.
    - If a value is passed, the system will attach it as a generic "value"
    - Returns the inserted node that was added to the list (if addition was successful).

    list:remove(node : LinkedListNode)
    - Removes a node from whatever list it is a part of.

    for node in list:loop([backwards : boolean]) do [stuff] end
    - Shows how to iterate over all nodes in "list".
    
    fromList:merge(intoList : LinkedList[, mergeBefore : boolean])
    - Removes all nodes of list "fromList" and adds them to the end of list "intoList" (or
      at the beginning, if "mergeBefore" is true).
      "fromList" needs to be the linked list head, but "into" can be anywhere in that list.
]]
---@class LinkedList     : table
---@field head LinkedListHead
---@field next LinkedList
---@field prev LinkedList

---@class LinkedListNode : LinkedList
---@field value any

---@class LinkedListHead : LinkedList
---@field n integer

LinkedList = {}
LinkedList.__index = LinkedList

---Creates a new LinkedList head node.
---@return LinkedListHead
function LinkedList.create()
    local head = {}
    setmetatable(head, LinkedList)

    head.next = head
    head.prev = head
    head.head = head
    head.n = 0
    return head
end

---Inserts *before* the given head/node, unless "backward" is true.
---@param value? any
---@param insertAfter? boolean
---@return LinkedListNode node that was added to the list (if addition was successful)
function LinkedList:insert(value, insertAfter)
    local node = {}   ---@type LinkedListNode
    setmetatable(node, LinkedList)

    local from = insertAfter and self.next or self
    from.prev.next = node
    node.prev = from.prev
    from.prev = node
    node.next = from
    
    node.value = value

    local head = from.head
    node.head = head
    head.n = head.n + 1
    return node
end

---Removes a node from whatever list it is a part of. A node cannot be a part of
---more than one list at a time, so there is no need to pass the containing list as
---an argument.
---@param node LinkedListNode
---@return boolean wasRemoved
function LinkedList:remove(node)
    node.prev.next = node.next
    node.next.prev = node.prev
    self.n = self.n - 1
end

---Merges LinkedListHead "from" to a LinkedList "into"
---@param from LinkedListHead
---@param into LinkedList
---@param mergeBefore boolean
function LinkedList.merge(from, into, mergeBefore)
    local head = into.head
    into = mergeBefore and into.next or into
    from.n = 0
    for node in from:loop() do node.head = head end
    
    from.next.prev = into.prev
    into.prev.next = from.next
    into.prev = from.prev
    from.prev.next = into
end

---Enables the generic for-loop for LinkedLists.
---Syntax: "for node in LinkedList.loop(list) do print(node) end"
---Alternative Syntax: "for node in list:loop() do print(node) end"
---@param list LinkedList
---@param backward? boolean
function LinkedList.loop(list, backward)
    list = list.head        ---@type LinkedListHead
    local loopNode = list   ---@type LinkedListNode
    local direction = backward and "prev" or "next"
    return function()
        loopNode = loopNode[direction]
        return loopNode ~= list and loopNode or nil
    end
end --End of LinkedList library
