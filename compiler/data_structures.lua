--[[--------------------------------------------------------------------

  Gazelle: a system for building fast, reusable parsers

  data_structures.lua

  Implementations of useful data structures that we use often.
  Most of these are just useful interfaces around Lua's tables.

  Copyright (c) 2007 Joshua Haberman.  See LICENSE for details.

--------------------------------------------------------------------]]--

require "misc"

-- Queue
Queue = {name="Queue"}
  function Queue:new(init)
    local obj = newobject(self)
    obj.first = 0
    obj.last  = -1
    if init then obj:enqueue(init) end
    return obj
  end

  function Queue:enqueue(val)
    self.last = self.last + 1
    self[self.last] = val
  end

  function Queue:dequeue()
    if self:isempty() then error("Tried to dequeue an empty queue") end
    local val = self[self.first]
    self[self.first] = nil
    self.first = self.first + 1
    return val
  end

  function Queue:isempty()
    return self.first > self.last
  end
-- class Queue


-- Stack
Stack = {name="Stack"}
  function Stack:new(init)
    local obj = newobject(self)
    obj.stack = {}
    return obj
  end

  function Stack:push(val)
    table.insert(self.stack, val)
  end

  function Stack:pop()
    return table.remove(self.stack)
  end

  function Stack:top()
    return self.stack[#self.stack]
  end

  function Stack:contains(elem)
    for e in each(self.stack) do
      if elem == e then
        return true
      end
    end
    return false
  end

  function Stack:to_array()
    local arr = {}
    for i, val in ipairs(self.stack) do
      table.insert(arr, val)
    end
    return arr
  end
-- class Stack


-- Set
Set = {name="Set"}
  function Set:new(init)
    local obj = newobject(self)
    obj.elements = {}
    if init then
      obj:add_collection(init)
    end
    return obj
  end

  function Set:contains(x)
    return self.elements[x] ~= nil
  end

  function Set:add(x)
    self.elements[x] = true
  end

  function Set:remove(x)
    self.elements[x] = nil
  end

  function Set:add_collection(arr)
    for elem in each(arr) do
      self:add(elem)
    end
  end

  function Set:each()
    return pairs(self.elements)
  end

  function Set:to_array()
    local arr = {}
    for elem in self:each() do
      table.insert(arr, elem)
    end
    return arr
  end

  function Set:isempty()
    return self:count() == 0
  end

  function Set:count()
    local i = 0
    for elem in self:each() do
      i = i + 1
    end
    return i
  end

  function Set:hash_key()
    local arr = self:to_array()
    for i=1,#arr do
      arr[i] = tostring(arr[i])
    end

    table.sort(arr)

    str = "" for elem in each(arr) do str = str .. elem end
    return str
  end
-- class Set

-- Range
-- The Range is *inclusive* at both ends.
Range = {name="Range"}
  function Range:new(low, high)
    assert(low <= high)

    local obj = newobject(self)
    obj.low = low
    obj.high = high
    return obj
  end

  function Range.union(a, b)
    if math.max(a.low, b.low) <= (math.min(a.high, b.high)+1) then
      return Range:new(math.min(a.low, b.low), math.max(a.high, b.high))
    else
      return nil
    end
  end

  function Range:contains(int)
    return (self.low <= int) and (self.high >= int)
  end

  function Range:tostring(display_val_func)
    if self.low == self.high then
      return display_val_func(self.low)
    else
      return display_val_func(self.low) .. "-" .. display_val_func(self.high)
    end
  end
-- class Range


-- IntSet
-- None of the ranges may overlap.
IntSet = {name="IntSet"}
  function IntSet:new()
    local obj = newobject(self)
    obj.list = {}
    obj.negated = false
    return obj
  end

  function IntSet:add(new_range)
    local newlist = {}
    for range in each(self.list) do
      local union = new_range:union(range)
      if union then
        new_range = union
      else
        table.insert(newlist, range)
      end
    end

    table.insert(newlist, new_range)
    self.list = newlist
  end

  function IntSet:get_non_negated()
    if self.negated then
      return self:invert()
    else
      return self
    end
  end

  -- This is O(n^2) right now, and can probably
  -- be made O(n lg n) with a little thought, but n's
  -- are so small right now that I won't worry.
  function IntSet:add_intset(intset)
    for range in each(intset.list) do
      self:add(range)
    end
  end

  function IntSet:contains(int)
    local obj = self:get_non_negated()
    for range in each(obj.list) do
      if range:contains(int) then return true end
    end
    return false
  end

  function IntSet:sampleint()
    local obj = self:get_non_negated()

    if #obj.list == 0 then
      return nil
    else
      return obj.list[1].low
    end
  end

  function IntSet:invert()
    local new_intset = IntSet:new()
    new_intset.negated = not self.negated

    table.sort(self.list, function (a, b) return a.low < b.low end)
    local offset = 0

    for range in each(self.list) do
      if offset <= range.low-1 then
        new_intset:add(Range:new(offset, range.low-1))
      end
      offset = range.high+1
    end

    if offset ~= math.huge then
      new_intset:add(Range:new(offset, math.huge))
    end

    return new_intset
  end

  function IntSet:each_range()
    return each(self:get_non_negated().list)
  end

  function IntSet:isunbounded()
    for range in each(self.list) do
      if range.high == math.huge then
        return true
      end
    end
    return false
  end

  function IntSet:tostring(display_val_func)
    local str = ""
    if self.negated then str = "^" end

    table.sort(self.list, function (a, b) return a.low < b.low end)
    local first = true
    for range in each(self.list) do
      if first then
        first = false
      else
        str = str .. ","
      end

      str = str .. range:tostring(display_val_func)
    end

    return str
  end

  function IntSet:toasciistring()
    local convert_func = function (x)
      if x == math.huge then
        return "del"
      elseif x < 33 then
        return string.format("\\%03o", x)
      else
        return string.char(x)
      end
    end
    return self:tostring(convert_func)
  end

  function IntSet:tointstring()
    return self:tostring(function (x) return tostring(x) end)
  end
-- class IntSet

ShallowTable = {name="ShallowTable"}
function ShallowTable:new(val)
  if val == nil then return nil end

  if not self.cache then
    self.cache = {}
    --setmetatable(self.cache, {__mode = "v"})  -- make values weak
  end

  local str = ""
  local keys = {}
  for key in pairs(val) do table.insert(keys, key) end
  table.sort(keys)
  for key in each(keys) do
    if type(val[key]) == "table" and val[key].class == fa.NonTerm then
      str = str .. "|" .. key .. ":NONTERM" .. tostring(val[key].name)
    else
      str = str .. "|" .. key .. ":" .. tostring(val[key])
    end
  end

  if not self.cache[str] then
    self.cache[str] = newobject(self)
    for k,v in pairs(val) do
      self.cache[str][k] = v
    end
  end

  return self.cache[str]
end

-- vim:et:sts=2:sw=2
