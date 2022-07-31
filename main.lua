--
-- FS22 - Crop Rotation mod
--
-- main.lua - mod loader script
--
-- @Author: Bodzio528
-- @Date: 22.07.2022
-- @Version: 1.0.0.0
--
-- Changelog:
-- 	v1.0.0.0 (22.07.2022):
--      - Initial release
--

local modDirectory = g_currentModDirectory

source(modDirectory .. "CropRotation.lua")
source(modDirectory .. "CropRotationData.lua")
source(modDirectory .. "misc/DensityMapScanner.lua")
source(modDirectory .. "misc/Queue.lua")

local cropRotation = nil -- localize
local cropRotationData = nil -- crops.xml parser and content loader


-- Active test: needed for console version where the code is always sourced.
function isActive()
--[[
    if GS_IS_CONSOLE_VERSION and not g_isDevelopmentConsoleScriptModTesting then
        return g_modIsLoaded["FS22_CropRotation_console"]
    end
--]]

    -- Normally this code never runs if mod was not active. However, in development mode this might not always hold true.
    return g_modIsLoaded[CropRotation.MOD_NAME]
end

---Initialize the mod. This code is run once for the lifetime of the program.
function init()
    print(string.format("FS22_CropRotation:init(): %s", "mod initialized, yay"))

    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, cr_unload)
    FSBaseMission.initTerrain = Utils.appendedFunction(FSBaseMission.initTerrain, cr_initTerrain)
    FSBaseMission.loadMapFinished = Utils.prependedFunction(FSBaseMission.loadMapFinished, cr_loadMapFinished)

    Mission00.load = Utils.prependedFunction(Mission00.load, cr_loadMission)
    Mission00.loadMission00Finished = Utils.overwrittenFunction(Mission00.loadMission00Finished, cr_loadMissionFinished)

    HelpLineManager.loadMapData = Utils.overwrittenFunction(HelpLineManager.loadMapData, HelpLineManager.loadCropRotationHelpLine)
end

function cr_unload()
    print(string.format("FS22_CropRotation:cr_unload(): %s, isActive = %s", "mission unloaded, yay", tostring(isActive())))

    if not isActive() then return end

    removeModEventListener(cropRotation)

    if cropRotation ~= nil then
        cropRotation:delete()
        cropRotation = nil -- Allows garbage collecting
        getfenv(0)["g_cropRotation"] = nil
    end
end

--sets terrain root node.set lod, culling, audio culing, creates fruit updaters, sets fruit types to menu, installs weed, DM syncing
function cr_initTerrain(mission, terrainId, filename)
    print(string.format("FS22_CropRotation:cr_initTerrain(): %s, isActive = %s", "terrain initialized", tostring(isActive())))

    if not isActive() then return end

    g_cropRotation:onTerrainLoaded(mission, terrainId, filename)

	local isMultiplayer = mission.missionDynamicInfo.isMultiplayer
    if isMultiplayer then
        cropRotation:addDensityMapSyncer(mission.densityMapSyncer)
    end
end

-- Map object is loaded but not configured into the game
function cr_loadMapFinished(mission, node)
    print(string.format("FS22_CropRotation:cr_loadMapFinished(): %s, isActive = %s", "loadMapFinished, yay", tostring(isActive())))

    if not isActive() then return end

    if node ~= 0 then
        cropRotation:onMapLoaded(mission, node)
    end
end

function cr_loadMission(mission)
    print(string.format("FS22_CropRotation:cr_load(mission): %s, isActive = %s", "mission loaded, yay", tostring(isActive())))

    if not isActive() then return end
    assert(g_cropRotation == nil)

    cropRotationData = CropRotationData:new(mission, g_fruitTypeManager)
    densityMapScanner = SeasonsDensityMapScanner:new(mission, g_sleepManager, g_dedicatedServer ~= nil)

    cropRotation = CropRotation:new(mission, g_messageCenter, g_fruitTypeManager, g_i18n, cropRotationData, densityMapScanner)

    -- Available at this point:
    -- modDirectory, g_densityMapHeightManager, g_fillTypeManager,
    -- g_modManager, g_gui, g_gui.inputManager,
    -- g_specializationManager, g_vehicleTypeManager, g_onCreateUtil, g_treePlantManager, g_farmManager,
    -- g_missionManager, g_sprayTypeManager, g_gameplayHintManager, g_helpLineManager, g_soundManager,
    -- g_animalManager, g_animalFoodManager, g_workAreaTypeManager, g_dedicatedServerInfo, g_sleepManager,
    -- g_settingsScreen.settingsModel, g_ambientSoundManager, g_depthOfFieldManager, g_server, g_fieldManager,
    -- g_particleSystemManager, g_baleTypeManager, g_npcManager, g_farmlandManager

    getfenv(0)["g_cropRotation"] = cropRotation -- globalize

    addModEventListener(cropRotation)
end

function cr_loadMissionFinished(mission, superFunc, node)
    print(string.format("FS22_CropRotation:cr_loadMissionFinished(): %s, isActive = %s", "mission loaded called", tostring(isActive())))

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

----------------------
-- Help menu appendix
----------------------
function HelpLineManager:loadCropRotationHelpLine(superFunc, ...)
	local ret = superFunc(self, ...)
	if ret then
		self:loadFromXML(Utils.getFilename("gui/helpLine.xml", modDirectory))
		return true
	end
	return false
end

init()
