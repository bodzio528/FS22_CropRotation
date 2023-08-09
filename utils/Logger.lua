Logger = {}
Logger.__index = Logger

Logger.DEBUG = 1
Logger.INFO = 2
Logger.WARNING = 3
Logger.ERROR = 4
Logger.OFF = 1000

function Logger.create(name)
  local self = setmetatable({}, Logger) 
  
  self.name = name
  self.level = Logger.DEBUG
  return self
end

function Logger:setLevel(level)
  self.level = level
end

function Logger:print(level, text)  
  if level < self.level then
    return
  end

  local levelDesc = "ERROR"
  if level == Logger.WARNING then
    levelDesc = "WARN"
  elseif level == Logger.INFO then
    levelDesc = "INFO"
  elseif level == Logger.DEBUG then
    levelDesc = "DEBUG"
  end

  log("[" .. levelDesc .. "] " .. self.name .. ": " .. text)
end

function Logger:getLevel()
  return self.level
end

function Logger:error(text, ...)
  self:print(Logger.ERROR, string.format(text, ...))
end

function Logger:warn(text, ...)
  self:print(Logger.WARNING, string.format(text, ...))
end

function Logger:info(text, ...)
  self:print(Logger.INFO, string.format(text, ...))
end

function Logger:debug(text, ...)
  self:print(Logger.DEBUG, string.format(text, ...))
end

function Logger:dump(tbl, indent) 
  self:debug(string.rep("-", indent) .. " (" .. type(tbl) .. ")")

  if (type(tbl) == "table") then
    for k, v in pairs(tbl) do
      self:debug(string.rep("-", indent + 1) .. " " ..k .. " (" .. type(v) .. ")")
    end  
  end
end
