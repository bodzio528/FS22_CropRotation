----------------------------------------------------------------------------------------------------
-- Queue
----------------------------------------------------------------------------------------------------
-- Purpose:  A queue
--
-- A FIFO queue.
-- Only supports objects. https://gist.github.com/BlackBulletIV/4084042
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

Queue = {}

local Queue_mt = Class(Queue)

function Queue:new()
    local self = setmetatable({}, Queue_mt)

    self.size = 0
    self.first = nil
    self.last = nil

    return self
end

function Queue:delete()
end

---Push an element to the queue (O(1))
function Queue:push(value)
    if self.last then
        self.last._next = value
        value._prev = self.last
        self.last = value
    else
        -- First node
        self.first = value
        self.last = value
    end

    self.size = self.size + 1
end

---Pop an element from the queue (O(1))
function Queue:pop()
    if not self.first then
        return
    end

    local value = self.first

    if value._next then
        value._next._prev = nil
        self.first = value._next
        value._next = nil
    else
        self.first = nil
        self.last = nil
    end

    self.size = self.size - 1

    return value
end

---Remove given element from the queue (O(n))
function Queue:remove(value)
    if value._next then
        if value._prev then
            value._next._prev = value._prev
            value._prev._next = value._next
        else
            value._next._prev = nil
            self.first = value._next
        end
    elseif value._prev then
        value._prev._next = nil
        self.last = value._prev
    else
        self.first = nil
        self.last = nil
    end

    -- Normally, this should be emptied
    -- However, the only place it is currently used is inside a loop
    -- of the iteratePushOrder. One can't mutate the list you iterate
    -- over, unless this is commented out
    if mutateIterating ~= true then
        value._next = nil
        value._prev = nil
    end

    self.size = self.size - 1
end

---Get whether the queue is empty (O(1))
function Queue:isEmpty()
    return self.first == nil
end

---Iterate over all items in the order they should be pushed to copy the queue. This is from first to last.
function Queue:iteratePushOrder(func)
    local i = 1
    local item = self.first

    while item ~= nil do
        if func(item, i) == true then
            break
        end

        i = i + 1
        item = item._next
    end
end

function Queue:iteratePopOrder(func)
    local i = 1
    local item = self.last

    while item ~= nil do
        if func(item, i) == true then
            break
        end

        i = i + 1
        item = item._prev
    end
end
