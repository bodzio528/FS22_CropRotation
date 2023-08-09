FS22_PATH = '/home/bchojnow/Projekty/FS22/fs22-1.10.1.1/?.lua'
MOD_PATH = '/home/bchojnow/Projekty/FS22/FS22_CropRotation/?.lua'

package.path = package.path .. ";".. FS22_PATH .. ";" .. MOD_PATH

function log(...)
    print(...)
end
function printCallstack() end

function addConsoleCommand(...) end
function removeConsoleCommand(...) end
function addModEventListener(...) end

Utils = {}
function Utils.prependedFunction(...) end
function Utils.appendedFunction(...) end

TypeManager = {}
ItemSystem = {}
Gui = {}
FSBaseMission = {}
HelpLineManager = {}

require 'dataS.scripts.shared.class'
require 'utils.Logger'

function source(path)
    -- print(string.format("[DBG] source %s", path))

    -- 1. strip .lua extension
    src = string.sub(path, 0, string.len(path)-4)

    -- 2. change `/` to `.`
    moduleName, _ = string.gsub(src, "/", '.')

    if DEBUG ~= nil then print(string.format('[DBG] require %s', moduleName)) end
    require(moduleName)
end

g_currentModName = 'FS22_CropRotation'
g_currentModDirectory = '.'

require 'CropRotation'

lu = require('luaunit')
g_cropRotation = CropRotation.new(nil)

TestCropRotation = {}
    function TestCropRotation:test_instantiate()
        local sut = CropRotation.new()
        lu.assertEquals(3, #sut.valueMaps)
        lu.assertEquals(3, #sut:getValueMaps())
        lu.assertEquals('crCoverMap', sut:getValueMap(1).name)
        lu.assertEquals('crYieldMap_n1', sut:getValueMap(2).name)
        lu.assertEquals('crYieldMap_n2', sut:getValueMap(3).name)
    end

os.exit(lu.LuaUnit.run())
