FS22_PATH = '/home/bchojnow/Projekty/FS22/fs22-1.10.1.1/?.lua'
FS22_PATH = 'E:\\Users\\Bodzio\\FS22-scripts\\fs22-1.11.0.0\\?.lua'
MOD_PATH = '/home/bchojnow/Projekty/FS22/FS22_CropRotation/?.lua'
MOD_PATH = 'D:\\Users\\Bodzio\\Documents\\GitHub\\FS22_CropRotation\\?.lua'
MOD_PATH = 'D:\\Users\\Bodzio\\Documents\\My Games\\FarmingSimulator2022\\mods\\FS22_CropRotation\\?.lua'
package.path = package.path .. ";".. FS22_PATH .. ";" .. MOD_PATH

if DEBUG ~= nil then print(string.format("[DBG] package.path = %s", package.path)) end

function source(path)
    -- print(string.format("[DBG] source %s", path))

    -- 1. strip .lua extension
    src = string.sub(path, 0, string.len(path)-4)

    -- 2. change `/` to `.`
    moduleName, _ = string.gsub(src, "/", '.')

    if DEBUG ~= nil then print(string.format('[DBG] require %s', moduleName)) end
    require(moduleName)
end

-- emulate GIANTS Editor
function getSelection()
    return true
end

function getNumDlcPaths() return 0 end

require 'dataS.scripts.shared.class'

DensityMapModifier = {}
local DensityMapModifier_mt = Class(DensityMapModifier)

function DensityMapModifier.new(mapId, firstChannel, numChannels)
    local self = setmetatable({}, DensityMapModifier)

    return self
end
require 'dataS.scripts.std'
require 'dataS.scripts.platform.Platform'
require 'dataS.scripts.mods'
require 'dataS.scripts.utils.Utils'
require 'dataS.scripts.xml.XMLManager'
require 'dataS.scripts.missions.ItemSystem'
require 'dataS.scripts.network.EventIds'
require 'dataS.scripts.FSBaseMission'
require 'dataS.scripts.specialization.TypeManager'




function printCallstack()
    print("<LUA Call Stack>")
end

require 'dataS.scripts.misc.Logging'

Gui = {profiles = {}}
Gui_mt = Class(Gui)

function Gui:new()
    local self = setmetatable({}, Gui_mt) 
    return self 
end
function Gui:loadProfiles(...) return {} end

g_gui = Gui.new()
GuiElement = {}
TabbedMenuFrameElement = {}
    function TabbedMenuFrameElement:new() 
        return {}
    end


g_currentModDirectory = ''
g_currentModName = 'FS22_CropRotation'

g_modIsLoaded = {}
g_modIsLoaded["FS22_CropRotation"] = true
g_modIsLoaded["FS22_CropRotation_update"] = false
