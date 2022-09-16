--
-- FS22 - Crop Rotation mod
--
-- main.lua - mod loader script
--

local modDirectory = g_currentModDirectory

source(modDirectory .. "CropRotation.lua")
source(modDirectory .. "CropRotationData.lua")
source(modDirectory .. "CropRotationPlanner.lua")
source(modDirectory .. "utils/DensityMapUpdater.lua")
source(modDirectory .. "utils/Queue.lua")

source(modDirectory .. "gui/InGameMenuCropRotationPlanner.lua")


local cropRotation = nil -- localize

function isActive()
    return g_modIsLoaded["FS22_CropRotation"] or g_modIsLoaded["FS22_CropRotation_update"]
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

    local cropRotationPlanner = CropRotationPlanner:new(g_fruitTypeManager) -- storage - load & save planner as xml

    cropRotation = CropRotation:new(mission,
                                    modDirectory,
                                    g_messageCenter,
                                    g_fruitTypeManager,
                                    g_i18n,
                                    CropRotationData:new(mission, modDirectory, g_fruitTypeManager),
                                    DensityMapUpdater:new(mission, g_sleepManager, g_dedicatedServer ~= nil),
                                    cropRotationPlanner)

    g_gui:loadProfiles(modDirectory .. "gui/guiProfiles.xml")

	local ingameMenuCropRotationPlanner = InGameMenuCropRotationPlanner.new(g_i18n, cropRotation, cropRotationPlanner)

    local pathToGuiXml = modDirectory .. "gui/InGameMenuCropRotationPlanner.xml"
	g_gui:loadGui(pathToGuiXml,
                  "ingameMenuCropRotationPlanner",
                  ingameMenuCropRotationPlanner,
                  true)

	fixInGameMenu(ingameMenuCropRotationPlanner,
                  "ingameMenuCropRotationPlanner",
                  {0, 0, 1024, 1024},
                  4)


    getfenv(0)["g_cropRotation"] = cropRotation -- globalize

    addModEventListener(cropRotation)
end

function cr_loadMissionFinished(mission, superFunc, node)
    if not isActive() then
        return superFunc(mission, node)
    end

    cropRotation:load()

    superFunc(mission, node)
end

----------------------
-- Install Crop Rotation Planner Menu
----------------------
function fixInGameMenu(frame, pageName, uvs, position)
	local inGameMenu = g_gui.screenControllers[InGameMenu]

	for k, v in pairs({pageName}) do
		inGameMenu.controlIDs[v] = nil
	end

	inGameMenu:registerControls({pageName})

	inGameMenu[pageName] = frame
	inGameMenu.pagingElement:addElement(inGameMenu[pageName])

	inGameMenu:exposeControlsAsFields(pageName)

	for i = 1, #inGameMenu.pagingElement.elements do
		local child = inGameMenu.pagingElement.elements[i]
		if child == inGameMenu[pageName] then
			table.remove(inGameMenu.pagingElement.elements, i)
			table.insert(inGameMenu.pagingElement.elements, position, child)
			break
		end
	end

	for i = 1, #inGameMenu.pagingElement.pages do
		local child = inGameMenu.pagingElement.pages[i]
		if child.element == inGameMenu[pageName] then
			table.remove(inGameMenu.pagingElement.pages, i)
			table.insert(inGameMenu.pagingElement.pages, position, child)
			break
		end
	end

	inGameMenu.pagingElement:updateAbsolutePosition()
	inGameMenu.pagingElement:updatePageMapping()

	inGameMenu:registerPage(inGameMenu[pageName], position, function() return true end)
	local iconFileName = Utils.getFilename('gui/menuIcon.dds', modDirectory)
	inGameMenu:addPageTab(inGameMenu[pageName],iconFileName, GuiUtils.getUVs(uvs))
	inGameMenu[pageName]:applyScreenAlignment()
	inGameMenu[pageName]:updateAbsolutePosition()

	for i = 1, #inGameMenu.pageFrames do
		local child = inGameMenu.pageFrames[i]
		if child == inGameMenu[pageName] then
			table.remove(inGameMenu.pageFrames, i)
			table.insert(inGameMenu.pageFrames, position, child)
			break
		end
	end

	inGameMenu:rebuildTabList()

    frame:initialize()
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
