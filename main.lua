--
-- FS22 - Crop Rotation mod
--
-- main.lua - mod loader script
--
-- @Author: Bodzio528
-- @Date: 04.08.2022
-- @Version: 1.0.0.0
--
-- Changelog:
-- 	v1.0.0.0 (03.08.2022):
--      - Initial release
--

local modDirectory = g_currentModDirectory

source(modDirectory .. "CropRotation.lua")
source(modDirectory .. "CropRotationData.lua")
source(modDirectory .. "misc/DensityMapScanner.lua")
source(modDirectory .. "misc/Queue.lua")

local cropRotation = nil -- localize
local cropRotationData = nil -- crops.xml parser and content loader

function isActive()
    return g_modIsLoaded["FS22_CropRotation"]
end

---Initialize the mod. This code is run once for the lifetime of the program.
function init()
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, cr_unload)
    FSBaseMission.initTerrain = Utils.appendedFunction(FSBaseMission.initTerrain, cr_initTerrain)

    Mission00.load = Utils.prependedFunction(Mission00.load, cr_loadMission)
    Mission00.loadMission00Finished = Utils.overwrittenFunction(Mission00.loadMission00Finished, cr_loadMissionFinished)

    HelpLineManager.loadMapData = Utils.overwrittenFunction(HelpLineManager.loadMapData, HelpLineManager.loadCropRotationHelpLine)
end

function cr_unload()
    if not isActive() then return end

    removeModEventListener(cropRotation)

    if cropRotation ~= nil then
        cropRotation:delete()
        cropRotation = nil -- Allow garbage collecting
        getfenv(0)["g_cropRotation"] = nil
    end
end

--sets terrain root node.set lod, culling, audio culing, creates fruit updaters, sets fruit types to menu, installs weed, DM syncing
function cr_initTerrain(mission, terrainId, filename)
    if not isActive() then return end

    g_cropRotation:onTerrainLoaded(mission, terrainId, filename)

	local isMultiplayer = mission.missionDynamicInfo.isMultiplayer
    if isMultiplayer then
        cropRotation:addDensityMapSyncer(mission.densityMapSyncer)
    end
end

function cr_loadMission(mission)
    if not isActive() then return end
    assert(g_cropRotation == nil)

    cropRotationData = CropRotationData:new(mission, g_fruitTypeManager)
    densityMapScanner = SeasonsDensityMapScanner:new(mission, g_sleepManager, g_dedicatedServer ~= nil)

    cropRotation = CropRotation:new(mission,
                                    g_messageCenter,
                                    g_fruitTypeManager,
                                    g_i18n,
                                    cropRotationData,
                                    densityMapScanner)

    getfenv(0)["g_cropRotation"] = cropRotation -- globalize

    addModEventListener(cropRotation)
end

function cr_loadMissionFinished(mission, superFunc, node)
    if not isActive() then
        return superFunc(mission, node)
    end

    cropRotationData:setDataPaths(getDataPaths("crops.xml"))
    cropRotationData:load()

    cropRotation:load()

    superFunc(mission, node)

    if mission.cancelLoading then
        return
    end

    return
end

function getDataPaths(filename)
    local paths = {} -- self.thirdPartyMods:getDataPaths(filename) -- TODO(v.2): load custom crops.xml from GEOs

    -- First add base crops.xml from this mod, then override in 3rdparty
    local path = Utils.getFilename("data/" .. filename, modDirectory)
    if fileExists(path) then
        table.insert(paths, 1, { file = path, modDir = modDirectory })
    end

    return paths
end

------------------------------------------------
-- InGame Help Menu chapter loading
------------------------------------------------
function HelpLineManager:loadCropRotationHelpLine(superFunc, ...)
    local ret = superFunc(self, ...)
    if ret then
        self:loadFromXML(Utils.getFilename("gui/helpLine.xml", modDirectory))
        return true
    end
    return false
end

init()
