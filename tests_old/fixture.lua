-- DEBUG = true

FS22_PATH = '/home/bchojnow/Projekty/FS22/fs22-1.10.1.1/?.lua'
FS22_PATH = 'E:\\Users\\Bodzio\\FS22-scripts\\fs22-1.11.0.0\\?.lua'
MOD_PATH = '/home/bchojnow/Projekty/FS22/FS22_CropRotation/?.lua'
MOD_PATH = 'D:\\Users\\Bodzio\\Documents\\GitHub\\FS22_CropRotation\\?.lua'
package.path = package.path .. ";".. FS22_PATH .. ";" .. MOD_PATH

if DEBUG ~= nil then print(string.format("[DBG] package.path = %s", package.path)) end

require 'dataS.scripts.shared.class'

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

g_currentModDirectory = ''

g_modIsLoaded = {}
g_modIsLoaded["FS22_CropRotation"] = true
g_modIsLoaded["FS22_CropRotation_update"] = false
