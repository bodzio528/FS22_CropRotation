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
local modName = g_currentModName

source(modDirectory .. "CropRotation.lua")

local cropRotation = nil -- localize
--local version = 1


-- Active test: needed for console version where the code is always sourced.
function isActive()
--[[
    if GS_IS_CONSOLE_VERSION and not g_isDevelopmentConsoleScriptModTesting then
        return g_modIsLoaded["FS22_CropRotation_console"]
    end
--]]

    -- Normally this code never runs if mod was not active. However, in development mode this might not always hold true.
    return g_modIsLoaded["FS22_CropRotation"]
end


---Initialize the mod. This code is run once for the lifetime of the program.
function init()
	print(string.format("FS22_CropRotation:init(): %s", "mod initialized, yay"))
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, cr_unload)
    FSBaseMission.initTerrain = Utils.appendedFunction(FSBaseMission.initTerrain, cr_initTerrain)
    FSBaseMission.loadMapFinished = Utils.prependedFunction(FSBaseMission.loadMapFinished, cr_loadMapFinished)
	
	FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, cr_saveToXMLFile)

	Mission00.load = Utils.prependedFunction(Mission00.load, cr_loadMission)
    Mission00.loadMission00Finished = Utils.overwrittenFunction(Mission00.loadMission00Finished, cr_loadMissionFinished)
end

function cr_loadMission(mission)
	print(string.format("FS22_CropRotation:cr_load(mission): %s, isActive = %s", "mission loaded, yay", tostring(isActive())))
	
    if not isActive() then return end
    assert(g_seasons == nil)
	
    cropRotation = CropRotation:new(mission, g_messageCenter) --, g_i18n, modDirectory, modName, g_densityMapHeightManager, g_fillTypeManager, g_modManager, g_deferredLoadingManager, g_gui, g_gui.inputManager, g_fruitTypeManager, g_specializationManager, g_vehicleTypeManager, g_onCreateUtil, g_treePlantManager, g_farmManager, g_missionManager, g_sprayTypeManager, g_gameplayHintManager, g_helpLineManager, g_soundManager, g_animalManager, g_animalFoodManager, g_workAreaTypeManager, g_dedicatedServerInfo, g_sleepManager, g_settingsScreen.settingsModel, g_ambientSoundManager, g_depthOfFieldManager, g_server, g_fieldManager, g_particleSystemManager, g_baleTypeManager, g_npcManager, g_farmlandManager)
    --cropRotation.version = version

    getfenv(0)["g_cropRotation"] = cropRotation

    addModEventListener(cropRotation)

    --[[ HACKS
    if not g_addTestCommands then
        addConsoleCommand("gsToggleDebugFieldStatus", "Shows field status", "consoleCommandToggleDebugFieldStatus", mission)
        addConsoleCommand("gsTakeEnvProbes", "Takes env. probes from current camera position", "consoleCommandTakeEnvProbes", mission)
    end
	--]]
end

-- Map object is loaded but not configured into the game
function cr_loadMapFinished(mission, node) -- loadedMap
	print(string.format("FS22_CropRotation:cr_loadMapFinished(): %s, isActive = %s", "loadMapFinished, yay", tostring(isActive())))
	
	if not isActive() then return end
	
    if node ~= 0 then
        cropRotation:onMapLoaded(mission, node)
    end
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

    cropRotation:onTerrainLoaded(mission, terrainId, filename)
end


-- called after the map is async loaded from :load. has :loadMapData calls. NOTE: self.xmlFile is also deleted here. (Is map.xml)
function cr_loadMissionFinished(mission, superFunc, node) -- loadedMission
	print(string.format("FS22_CropRotation:cr_loadMissionFinished(): %s, isActive = %s", "mission loaded called", tostring(isActive())))


    if not isActive() then
        return superFunc(mission, node)
    end
	
	cropRotation:load()
	
--[[
    local function callSeasons()
        seasons:onMissionLoading(mission)

        if mission:getIsServer() and mission.missionInfo.savegameDirectory ~= nil and fileExists(mission.missionInfo.savegameDirectory .. "/seasons.xml") then
            local xmlFile = loadXMLFile("SeasonsXML", mission.missionInfo.savegameDirectory .. "/seasons.xml")
            if xmlFile ~= nil then
                seasons:onMissionLoadFromSavegame(mission, xmlFile)
                delete(xmlFile)
            end
        end
    end

    -- The function called for loading vehicles and items depends on the map setup and savegame setup
    -- We want to get a call out before they are called so we need to overwrite the correct one.
    if mission.missionInfo.vehiclesXMLLoad ~= nil then
        local old = mission.loadVehicles
        mission.loadVehicles = function (...)
            callSeasons()
            old(...)
        end
    elseif mission.missionInfo.itemsXMLLoad ~= nil then
        local old = mission.loadItems
        mission.loadItems = function (...)
            callSeasons()
            old(...)
        end
    else
        local old = mission.loadItemsFinished
        mission.loadItemsFinished = function (...)
            callSeasons()
            old(...)
        end
    end
--]]
    superFunc(mission, node)

    if mission.cancelLoading then
        return
    end

--[[
    g_deferredLoadingManager:addTask(function()
        cropRotation:onMissionLoaded(mission)
    end)
--]]
    return
end

-- Calling saveToXML (after saving)
-- cropRotation.xml is place where crop rotation planner will store their data
function cr_saveToXMLFile(missionInfo)
	print(string.format("FS22_CropRotation:saveToXMLFile(): %s, isActive = %s", "called on save to XML", tostring(isActive())))

    if not isActive() then return end

    if missionInfo.isValid then
        local xmlFile = createXMLFile("CropRotationXML", missionInfo.savegameDirectory .. "/cropRotation.xml", "cropRotation")
        if xmlFile ~= nil then
            cropRotation:onMissionSaveToSavegame(g_currentMission, xmlFile)

            saveXMLFile(xmlFile)
            delete(xmlFile)
        end
    end
end

init()

