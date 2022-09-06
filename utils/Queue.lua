--
-- FS22 - Crop Rotation mod
--
-- Queue.lua - wrapper around lua to model FIFO container, as described in
-- Knuth, Donald The Art of Computer Programming, Volume 1: Fundamental Algorithms
--

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

-- Push an element to the queue (O(1))
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

-- Pop an element from the queue (O(1))
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
