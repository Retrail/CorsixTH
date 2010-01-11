--[[ Copyright (c) 2010 Peter "Corsix" Cawley

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. --]]

local persist = require "persist"
local saved_permanents = {}

strict_declare_global "permanent"

function permanent(name, ...)
  if select('#', ...) == 0 then
    return function (...) return permanent(name, ...) end
  end
  local value = ...
  assert(value ~= nil)
  assert(saved_permanents[name] == nil)
  saved_permanents[name] = value
  return value
end

local function MakePermanentObjectsTable(inverted, ensure_safe)
  local return_val = {}
  local permanent
  if ensure_safe then
    permanent = {}
    if inverted then
      setmetatable(permanent, {__newindex = function(t, k, v)
        assert(return_val[v] == nil)
        assert(type(v) == "string")
        assert(type(k) ~= "string")
        rawset(return_val, v, k)
      end})
    else
      setmetatable(permanent, {__newindex = function(t, v, k)
        assert(return_val[k] == nil)
        assert(type(k) == "string")
        assert(type(v) ~= "string")
        rawset(return_val, v, k)
      end})
    end
  else
    permanent = return_val
    if inverted then
      setmetatable(permanent, {__newindex = function(t, k, v)
        rawset(t, v, k)
      end})
    end
  end
  
  -- Global functions
  for k, v in pairs(_G) do
    if type(v) == "function" then
      permanent[v] = k
    end
  end
   
  -- Lua class methods
  for name, class in pairs(_G) do repeat
    if type(class) ~= "table" then
      break -- continue
    end
    local class_mt = getmetatable(class)
    if not class_mt or class_mt.__class_name ~= name then
      break -- continue
    end
    permanent[class] = name .. ".1"
    permanent[class_mt] = name .. ".2"
    for k, v in pairs(class) do
      if type(v) == "function" then
        permanent[v] = name ..".".. k
      end
    end
  until true end
  
  -- C/class/library methods
  for name, lib in pairs(package.loaded) do
    permanent[lib] = name
    for k, v in pairs(lib) do
      local type = type(v)
      if type == "function" or type == "table" or type == "userdata" then
        permanent[v] = name ..".".. k
        if name == "TH" and type == "table" then
          -- C class metatables
          permanent[debug.getfenv(getmetatable(v).__call)] = name ..".".. k ..".<mt>"
        end
      end
    end
  end
  
  -- Bits of the app
  permanent[TheApp] = "TheApp"
  for _, key in ipairs{"config", "modes", "video", "strings", "audio"} do
    permanent[TheApp[key]] = "TheApp.".. key
  end
  for _, collection in ipairs{"walls", "objects", "rooms", "humanoid_actions", "diseases"} do
    for k, v in pairs(TheApp[collection]) do
      if type(k) == "string" then
        permanent[v] = "TheApp.".. collection ..".".. k
      end
    end
  end
  permanent[TheApp.ui.menu_bar] = "TheApp.ui.menu_bar"
  
  -- Graphics bits which are *always* loaded
  permanent[TheApp.gfx.cache.anims.V] = "TheApp.gfx.cache.anims.V"
  permanent[TheApp.gfx.cache.tabled["VBlk-0"]] = "TheApp.gfx.cache.tabled.VBlk-0"
  
  -- Things requested to be permanent by other bits of code
  for name, value in pairs(saved_permanents) do
    permanent[value] = name
  end
  
  return return_val
end

local function NameOf(obj) -- Debug aid
  local explored = {[_G] = true}
  local to_explore = {[_G] = "_G"}
  
  while true do
    local exploring, name = next(to_explore)
    if exploring == nil then
      break
    end
    to_explore[exploring] = nil
    if exploring == obj then
      return name
    end
    
    if type(exploring) == "table" then
      for key, val in pairs(exploring) do
        if not explored[val] then
          to_explore[val] = name .."."..tostring(key)
          explored[val] = true
        end
      end
    elseif type(exploring) == "function" then
      local i = 0
      while true do
        i = i + 1
        local name, val = debug.getupvalue(exploring, i)
        if not name then
          break
        end
        if val ~= nil and not explored[val] then
          to_explore[val] = name ..".<upvalue-"..i..tostring(name)..">"
          explored[val] = true
        end
      end
    end
    local mt = debug.getmetatable(exploring)
    if mt and not explored[mt] then
      to_explore[mt] = name ..".<metatable>"
      explored[mt] = true
    end
    mt = debug.getfenv(exploring)
    if mt and not explored[mt] then
      to_explore[mt] = name ..".<env>"
      explored[mt] = true
    end
  end
  
  return "<no name>"
end

strict_declare_global "SaveGame"
strict_declare_global "LoadGame"

function SaveGame()
  local state = {
    ui = TheApp.ui,
    world = TheApp.world,
    map = TheApp.map,
    gfx = TheApp.gfx,
    random = math.randomdump(),
  }
  --local status, res = xpcall(function()
  local result, err, obj = persist.dump(state, MakePermanentObjectsTable(false, true))
  if not result then
    print(obj, NameOf(obj)) -- for debugging
    error(err)
  else
    return result
  end
  --end, persist.errcatch)
end

function LoadGame(data)
  --local status, res = xpcall(function()
  local state = assert(persist.load(data, MakePermanentObjectsTable(true, true)))
  TheApp.ui = state.ui
  TheApp.world = state.world
  TheApp.map = state.map
  TheApp.gfx = state.gfx
  math.randomseed(state.random)
  --end, persist.errcatch)
end