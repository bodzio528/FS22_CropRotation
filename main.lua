--
-- FS22 - Crop Rotation mod
--
-- main.lua - mod loader script
--
-- @Author: Bodzio528
-- @Version: 2.0.0.0

-- Changelog:
--  v2.0.0.0 (30.08.2022):
--      - code rewrite
-- 	v1.0.0.0 (03.08.2022):
--      - Initial release

local modDirectory = g_currentModDirectory

source(modDirectory .. "CropRotation.lua")
source(modDirectory .. "CropRotationData.lua")
source(modDirectory .. "utils/DensityMapUpdater.lua")
source(modDirectory .. "utils/Queue.lua")

local cropRotation = nil -- localize

function isActive()
    return g_modIsLoaded["FS22_PF_CropRotation"]
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

    cropRotation = CropRotation:new(mission,
                                    modDirectory,
                                    g_messageCenter,
                                    g_fruitTypeManager,
                                    g_i18n,
                                    CropRotationData:new(mission, g_fruitTypeManager),
                                    SeasonsDensityMapScanner:new(mission, g_sleepManager, g_dedicatedServer ~= nil))

    getfenv(0)["g_cropRotation"] = cropRotation -- globalize

    addModEventListener(cropRotation)
end

function cr_loadMissionFinished(mission, superFunc, node)
    if not isActive() then
        return superFunc(mission, node)
    end

    cropRotation:load()

    superFunc(mission, node)

    if mission.cancelLoading then
        return
    end

    return
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
