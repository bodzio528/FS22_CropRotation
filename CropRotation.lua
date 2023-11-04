--
-- FS22 Crop Rotation mod
--
-- CropRotation.lua
--

CropRotation = {
    MOD_NAME = g_currentModName,
    MOD_DIRECTORY = g_currentModDirectory,
    PrecisionFarming = "FS22_precisionFarming",
    DEBUG = false,
    EXPERIMENTAL = {
        NEW_PLANNER = false
    }
}

source(CropRotation.MOD_DIRECTORY .. "CropRotationData.lua")
source(CropRotation.MOD_DIRECTORY .. "CropRotationPlanner.lua")
source(CropRotation.MOD_DIRECTORY .. "CropRotationSettings.lua")

source(CropRotation.MOD_DIRECTORY .. "maps/ValueMap.lua")
source(CropRotation.MOD_DIRECTORY .. "maps/CoverMap.lua") -- TODO: cover fallow and harvest bits here (write converter)
source(CropRotation.MOD_DIRECTORY .. "maps/YieldMap.lua") -- TODO: two instances for R-1 and R-2


if CropRotation.EXPERIMENTAL.NEW_PLANNER then
    source(CropRotation.MOD_DIRECTORY .. "gui/CropRotationGUI.lua")
    source(CropRotation.MOD_DIRECTORY .. "gui/InGameMenuCRFrame.lua")
    source(CropRotation.MOD_DIRECTORY .. "gui/InGameMenuExtension.lua")
end

-- doomed code:
source(CropRotation.MOD_DIRECTORY .. "gui/InGameMenuCropRotationPlanner.lua")

source(CropRotation.MOD_DIRECTORY .. "utils/DensityMapUpdater.lua")
source(CropRotation.MOD_DIRECTORY .. "utils/Queue.lua")
source(CropRotation.MOD_DIRECTORY .. "utils/Logger.lua")

local CropRotation_mt = Class(CropRotation)

function CropRotation.new(customMt)
    local self = setmetatable({}, customMt or CropRotation_mt)

    self.log = Logger.create(CropRotation.MOD_NAME)
    self.log:setLevel(Logger.INFO)
    if CropRotation.DEBUG then
        self.log:setLevel(Logger.DEBUG)
    end

    self.log:debug("CropRotation:new()")

    self.overwrittenGameFunctions = {}
    self.valueMaps = {}
    self.visualizationOverlays = {}
    self.cropRotationSettings = CropRotationSettings.new(self)

    self:registerValueMap(CoverMap.new(self))
    self:registerValueMap(YieldMap.new(self, 'n1'))
    self:registerValueMap(YieldMap.new(self, 'n2'))

    self.firstTimeRun = false
    self.firstTimeRunDelay = 2000
    -- self.isNewSavegame = true

    if CropRotation.EXPERIMENTAL.NEW_PLANNER then
       self.inGameMenuExtension = InGameMenuExtension.new()
    end

    self.data = CropRotationData:new(self) -- static and dynamic crop data
    self.planner = CropRotationPlanner:new(self) -- planner data storage

    return self
end

function CropRotation:initialize()
    self.log:debug("CropRotation:initialize()")

    self:initCache()

    self.data:initialize()
    self.planner:initialize()

    for i = 1, #self.valueMaps do
        self.valueMaps[i]:initialize(self)
        self.valueMaps[i]:overwriteGameFunctions(self)
    end

    if CropRotation.EXPERIMENTAL.NEW_PLANNER then
        self.inGameMenuExtension:overwriteGameFunctions(self)
    end

    addConsoleCommand("crInfo", "Get crop rotation info", "commandGetInfo", self)
    addConsoleCommand("crPlanner", "Perform planner function with crops specified", "commandPlanner", self)

    if CropRotation.DEBUG or g_addCheatCommands then -- cheats enabled
        addConsoleCommand("crTaskFallow", "Run yearly fallow", "commandRunFallow", self)
        addConsoleCommand("crTaskRegrow", "Run monthly regrow", "commandRunRegrow", self)

        addConsoleCommand("crCover", "Set cover bit", "commandSetCover", self)
        addConsoleCommand("crFallow", "Set fallow bit", "commandSetFallow", self)
        addConsoleCommand("crHarvest", "Set harvest bit", "commandSetHarvest", self)
        addConsoleCommand("crLast", "Set last crop", "commandSetLast", self)
        addConsoleCommand("crPrev", "Set previous crop", "commandSetPrev", self)

        self.isVisualizeEnabled = false
        addConsoleCommand("crVisualize", "Toggle Crop Rotation visualization", "commandToggleVisualize", self)
    end
end

-- fill function cache to speedup execution
function CropRotation:initCache()
    self.cache = {}
    self.cache.fieldInfoDisplay = {}
    self.cache.fieldInfoDisplay.title = g_i18n:getText("cropRotation_hud_fieldInfo_title")
    self.cache.fieldInfoDisplay.previousTitle = g_i18n:getText("cropRotation_hud_fieldInfo_previous")
    self.cache.fieldInfoDisplay.previousFallow = g_i18n:getText("cropRotation_fallow")

    self.cache.fieldInfoDisplay.currentTypeIndex = FruitType.UNKNOWN
    self.cache.fieldInfoDisplay.currentFruitState = 0

    -- readFromMap smart cache
    self.cache.readFromMap = {}
    self.cache.readFromMap.previousCrop = FruitType.UNKNOWN -- R2
    self.cache.readFromMap.lastCrop = FruitType.UNKNOWN -- R1
end

function CropRotation:loadMap(filename)
    self.log:debug("[MOD EVENT] CropRotation:loadMap("..filename.."): loading static data from mod directory")

    if g_modIsLoaded[CropRotation.MOD_NAME] then
        if not Utils.getNoNil(getXMLBool(g_savegameXML, "gameSettings.cropRotation#initialized"), false) then
            self.firstTimeRun = true

            setXMLBool(g_savegameXML, "gameSettings.cropRotation#initialized", true)
            g_gameSettings:saveToXMLFile(g_savegameXML)
        end

        self.mapFilename = filename

        self.cropsFileName = Utils.getFilename("data/crops.xml", CropRotation.MOD_DIRECTORY)
        local cropsXmlFile = loadXMLFile("CropsXML", self.cropsFileName)

        self.data:loadFromXML(cropsXmlFile, "crops", CropRotation.MOD_DIRECTORY, self.cropsFileName, self.mapFilename)
        self.data:postLoad()

        delete(cropsXmlFile)

        self.configFileName = Utils.getFilename("CropRotation.xml", CropRotation.MOD_DIRECTORY)
        local xmlFile = loadXMLFile("ConfigXML", self.configFileName)

        for i = 1, #self.valueMaps do
            self.valueMaps[i]:loadFromXML(xmlFile, "cropRotation", CropRotation.MOD_DIRECTORY, self.configFileName, self.mapFilename)
        end

        for i = 1, #self.valueMaps do
            self.valueMaps[i]:postLoad(xmlFile, "cropRotation", CropRotation.MOD_DIRECTORY, self.configFileName, self.mapFilename)
        end

        -- load color and description for per level
        local colors = {}

        local colorsKey = 'cropRotation.colors'
        local i = 0
        while true do
            local colorKey = string.format(colorsKey..'.color(%d)', i)
            if not hasXMLProperty(xmlFile, colorKey) then break end

            local level = getXMLInt(xmlFile, colorKey..'#level') or i
            colors[level] = {
                color = string.getVectorN(getXMLString(xmlFile, colorKey .. "#color"), 4) or {0, 0, 0, 0},
                colorBlind = string.getVectorN(getXMLString(xmlFile, colorKey .. "#colorBlind"), 4) or {0, 0, 0, 0},
                text = g_i18n:getText(getXMLString(xmlFile, colorKey .. "#text"))
            }
            i = i + 1
        end
        CropRotation.COLORS = colors

        delete(xmlFile)
    end

    self:loadModifiers()

    self.densityMapUpdater = DensityMapUpdater:new(g_currentMission, g_sleepManager, g_dedicatedServer ~= nil)

    local finalizer = function(target)
        g_cropRotation.log:info("DensityMapUpdater: job finished!")
    end

    self.densityMapUpdater:register("UpdateFallow", self.task_updateFallow, self, finalizer)
    self.densityMapUpdater:register("UpdateRegrow", self.task_updateRegrow, self, finalizer)

    g_messageCenter:subscribe(MessageType.YEAR_CHANGED, self.onYearChanged, self)
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)

    if g_modIsLoaded[CropRotation.PrecisionFarming] then -- extend PlayerHUDUpdater with crop rotation info
        local pfModule = FS22_precisionFarming.g_precisionFarming
        if pfModule ~= nil then
            pfModule.fieldInfoDisplayExtension:addFieldInfo(
                self.cache.fieldInfoDisplay.title,
                self,
                self.updateFieldInfoDisplay,
                4, -- prio
                self.yieldChangeFunc)

            pfModule.fieldInfoDisplayExtension:addFieldInfo(
                g_i18n:getText("cropRotation_hud_fieldInfo_previous"),
                self,
                self.updateFieldInfoDisplayPreviousCrops,
                5, -- prio
                nil) -- no yield change
        end

        PlayerHUDUpdater.fieldAddFruit =
            Utils.appendedFunction(
            PlayerHUDUpdater.fieldAddFruit,
            function(updater, data, box)
                local cropRotation = g_cropRotation
                assert(cropRotation ~= nil)

                cropRotation.cache.fieldInfoDisplay.currentTypeIndex = data.fruitTypeMax or FruitType.UNKNOWN
                cropRotation.cache.fieldInfoDisplay.currentFruitState = data.fruitStateMax or 0
            end
        )
    else -- OR simply add Crop Rotation Info to standard HUD
        PlayerHUDUpdater.fieldAddFruit = Utils.appendedFunction(PlayerHUDUpdater.fieldAddFruit, CropRotation.fieldAddFruit)
        PlayerHUDUpdater.updateFieldInfo = Utils.prependedFunction(PlayerHUDUpdater.updateFieldInfo, CropRotation.updateFieldInfo)
    end

end

function CropRotation:loadModifiers()
    self.log:debug("CropRotation:loadModifiers()")

    -- CFH= [C:1][F:1][H:1]
    -- R1 = [R1:5]
    -- R2 = [R2:5]
    local modifiers = self.crCoverMap.modifiers

    modifiers.r1 = self.crYieldMap_n1.modifiers
    modifiers.r2 = self.crYieldMap_n2.modifiers

    self.modifiers = modifiers
end

function CropRotation:unloadMapData()
    self.log:debug("CropRotation:unloadMapData()")

    if CropRotation.EXPERIMENTAL.NEW_PLANNER then
        self.inGameMenuExtension:unloadMapData()
    end
end

function CropRotation:initTerrain(mission, terrainId, filename)
    self.log:debug("CropRotation:initTerrain("..filename..")")

    for i = 1, #self.valueMaps do
        self.valueMaps[i]:initTerrain(mission, terrainId, filename)
    end
end

function CropRotation:deleteMap()
    self.log:debug("[MOD EVENT] CropRotation:deleteMap()")

    if g_modIsLoaded[CropRotation.MOD_NAME] then
        for i = #self.visualizationOverlays, 1, -1 do
            resetDensityMapVisualizationOverlay(self.visualizationOverlays[i])

            self.visualizationOverlays[i] = nil
        end

        for i = 1, #self.valueMaps do
            self.valueMaps[i]:delete()
        end

        if CropRotation.EXPERIMENTAL.NEW_PLANNER then
            self.inGameMenuExtension:delete()
        end

        for i = #self.overwrittenGameFunctions, 1, -1 do
            local reference = self.overwrittenGameFunctions[i]
            reference.object[reference.funcName] = reference.oldFunc
            self.overwrittenGameFunctions[i] = nil
        end

        removeConsoleCommand("crInfo")
        removeConsoleCommand("crPlanner")

        if CropRotation.DEBUG or g_addCheatCommands then
            removeConsoleCommand("crTaskFallow")
            removeConsoleCommand("crTaskRegrow")

            removeConsoleCommand("crFallowSet")
            removeConsoleCommand("crFallowClear")
            removeConsoleCommand("crHarvestSet")
            removeConsoleCommand("crHarvestClear")

            removeConsoleCommand("crVisualizeToggle")
        end

        self.densityMapUpdater:unregister("UpdateFallow")
        self.densityMapUpdater:unregister("UpdateRegrow")

        g_messageCenter:unsubscribeAll(self)
    end
end

function CropRotation:loadFromItemsXML(xmlFile, key)
    self.log:debug("CropRotation:loadFromItemsXML(xmlFile="..tostring(xmlFile)..", key="..key.."): loading planner data")

    self.planner:loadFromItemsXML(xmlFile, key)

    for i = #self.valueMaps, 1, -1 do
        self.valueMaps[i]:loadFromItemsXML(xmlFile, key)
    end

    -- self.farmlandStatistics:loadFromItemsXML(xmlFile, key)
    -- self.additionalFieldBuyInfo:loadFromItemsXML(xmlFile, key)
    -- self.environmentalScore:loadFromItemsXML(xmlFile, key)
end

function CropRotation:saveToXMLFile(xmlFile, key, usedModNames)
    self.log:debug("CropRotation:saveToXMLFile(key="..key.."): save planner data")

    self.planner:saveToXMLFile(xmlFile, key)

    for i = 1, #self.valueMaps do
        self.valueMaps[i]:saveToXMLFile(xmlFile, key, usedModNames)
    end

    -- self.farmlandStatistics:saveToXMLFile(xmlFile, key, usedModNames)
    -- self.additionalFieldBuyInfo:saveToXMLFile(xmlFile, key, usedModNames)
    -- self.environmentalScore:saveToXMLFile(xmlFile, key, usedModNames)
end

function CropRotation:addSetting(...)
    self.cropRotationSettings:addSetting(...)
end

function CropRotation:registerVisualizationOverlay(overlay)
    self.log:debug("CropRotation:registerVisualizationOverlay("..tostring(overlay)..")")
    table.insert(self.visualizationOverlays, overlay)
end

function CropRotation:update(dt)
    -- [MOD EVENT] CropRotation:update(dt)

    if g_modIsLoaded[CropRotation.MOD_NAME] then
        for i = 1, #self.valueMaps do
            self.valueMaps[i]:update(dt)
        end

        if CropRotation.EXPERIMENTAL.NEW_PLANNER then
            self.inGameMenuExtension:update(dt)
        end

        if self.firstTimeRun then
            self.firstTimeRunDelay = math.max(self.firstTimeRunDelay - dt, 0)

            if self.firstTimeRunDelay == 0 --[[and self.helplineExtension:getAllowFirstTimeEvent()]] then
                -- self.helplineExtension:onFirstTimeRun()

                self.firstTimeRun = false
            end
        end

        if CropRotation.DEBUG and self.isVisualizeEnabled then
            self:visualize()
        end

        if self.densityMapUpdater ~= nil then
            self.densityMapUpdater:update(dt)
        end
    end
end

function CropRotation:draw()
    -- [MOD EVENT] CropRotation:draw()
    if g_modIsLoaded[CropRotation.MOD_NAME] then
        -- self.harvestExtension:draw()
    end
end

function CropRotation:onPostInit()
    -- [MOD EVENT] CropRotation:onPostInit()
    self.log:debug("[MOD EVENT] CropRotation:onPostInit()")
end

function CropRotation:mouseEvent(posX, posY, isDown, isUp, button)
    -- [MOD EVENT] CropRotation:mouseEvent(posX, posY, isDown, isUp, button)
end

function CropRotation:registerValueMap(object)
    self.log:debug("CropRotation:registerValueMap("..tostring(object.name)..")")

    table.insert(self.valueMaps, object)

    self[object.name] = object
    object.valueMapIndex = #self.valueMaps
end

function CropRotation:getValueMaps()
    return self.valueMaps
end

function CropRotation:getValueMap(index)
    return self.valueMaps[index]
end

function CropRotation:updateCropRotationOverlays()
    self.log:debug("CropRotation:updateCropRotationOverlays() - called, NOOP")

    if CropRotation.EXPERIMENTAL.NEW_PLANNER then
        self.inGameMenuExtension:updateCropRotationOverlays()
    end
end

function CropRotation:onValueMapSelectionChanged(valueMap)
    self.log:debug("CropRotation:onValueMapSelectionChanged() - called, NOOP")
    -- self.yieldMap:onValueMapSelectionChanged(valueMap)
    -- ???
end

function CropRotation:onFarmlandSelectionChanged(farmlandId, fieldNumber, fieldArea)
    self.log:debug("CropRotation:onFarmlandSelectionChanged() - called, NOOP")
    -- self.yieldMap:onFarmlandSelectionChanged(farmlandId, fieldNumber, fieldArea)
    -- per-field planner???
end

function CropRotation:getFarmlandFieldInfo(farmlandId)
    self.log:debug("CropRotation:getFarmlandFieldInfo("..tostring(farmlandId)..")")

    local fieldNumber = 0
    local fieldArea = 0
    local farmland = g_farmlandManager.farmlands[farmlandId]

    if farmland ~= nil then
        fieldArea = farmland.totalFieldArea or 0
    end

    local fields = g_fieldManager:getFields()

    if fields ~= nil then
        for _, field in pairs(fields) do
            if field.farmland ~= nil and field.farmland.id == farmlandId then
                fieldNumber = field.fieldId

                break
            end
        end
    end

    return fieldNumber, fieldArea
end

------------------------------------------------
--- Game initializing
------------------------------------------------

-- populate map fields with random crops
function CropRotation:randomInit()
    self.log:debug("CropRotation:randomInit()")

    local terrainSize = g_currentMission.terrainSize or 1024

    -- initialize random forecrop generator
    local keys = {}
    for key, forecrops in pairs(self.data.matrix) do
        if #forecrops > 0 then
            table.insert(keys, key)
        end
    end
    self.log:debug("Crop indices enabled for rotation: "..table.concat(keys, " | "))
    local r2, r1 = 0

    local modifierR1 = self.modifiers.r1.modifier
    local modifierR2 = self.modifiers.r2.modifier
    for i, field in pairs(g_fieldManager:getFields()) do
        if field.fieldGrassMission then
            r2 = FruitType.GRASS
            r1 = FruitType.GRASS
        else
            r2 = keys[math.random(#keys)]
            r1 = keys[math.random(#keys)]
        end

        -- local bits = self:encode(r2, r1, 0, 0)
        for index = 1, table.getn(field.maxFieldStatusPartitions) do
            local partition = field.maxFieldStatusPartitions[index]

            local x = partition.x0 / terrainSize + 0.5
            local z = partition.z0 / terrainSize + 0.5
            local widthX = partition.widthX / terrainSize
            local widthZ = partition.widthZ / terrainSize
            local heightX = partition.heightX / terrainSize
            local heightZ = partition.heightZ / terrainSize

            modifierR1:setParallelogramUVCoords(x, z, widthX, widthZ, heightX, heightZ, DensityCoordType.POINT_VECTOR_VECTOR)
            modifierR1:executeSet(r1)
            modifierR2:setParallelogramUVCoords(x, z, widthX, widthZ, heightX, heightZ, DensityCoordType.POINT_VECTOR_VECTOR)
            modifierR2:executeSet(r2)
        end

        self.log:debug(string.format("CropRotation:randomInit(): Field %d: R2: %s R1 %s (grass: %s)",
                              field.fieldId,
                              g_fruitTypeManager:getFruitTypeByIndex(r2).name,
                              g_fruitTypeManager:getFruitTypeByIndex(r1).name,
                              field.fieldGrassMission))
    end
end

function CropRotation:onNewSavegame()
    self.log:debug("CropRotation:onNewSavegame(): start")
    self.log:debug("  isServer: "..tostring(g_currentMission.getIsServer()))
    self.log:debug("  isClient: "..tostring(g_currentMission.getIsClient()))
    self.log:debug("  isMultiplayer: "..tostring(g_currentMission.missionDynamicInfo.isMultiplayer))
    self.log:debug("  isDedicatedServer: "..tostring(g_dedicatedServer ~= nil))

    if g_currentMission:getIsServer() then
        self:randomInit()
    end

    local spGame = {
        missionDynamicInfo = {
            isMultiplayer = false,
            mods = {"FS22_CropRotation", "FS22_precisionFarming"}
        },
        isServer = true,
        isClient = true,
        isDedicatedServer = false
    }
    local mpGameDedicatedServer = {
        missionDynamicInfo = {
            isMultiplayer = true,
            mods = {"FS22_CropRotation", "FS22_precisionFarming"}
        },
        isServer = true,
        isClient = true,
        isDedicatedServer = true
    }

    self.log:debug("CropRotation:onNewSavegame(): done")
end

function CropRotation:overwriteGameFunction(object, funcName, newFunc)
    self.log:debug("CropRotation:overwriteGameFunction("..tostring(funcName)..")")

    if object == nil then
        self.log:error("Failed to overwrite '%s'", funcName)
        printCallstack()

        return
    end

    local oldFunc = object[funcName]

    if oldFunc ~= nil then
        object[funcName] = function (...)
            return newFunc(oldFunc, ...)
        end
    end

    local reference = {
        object = object,
        funcName = funcName,
        oldFunc = oldFunc
    }

    table.insert(self.overwrittenGameFunctions, reference)
end

g_cropRotation = CropRotation.new()
addModEventListener(g_cropRotation)

local function validateTypes(self)
    g_cropRotation.log:debug("validateTypes("..tostring(self.typeName)..")")

    if self.typeName == "vehicle" and g_modIsLoaded[CropRotation.MOD_NAME] and g_iconGenerator == nil then
        g_cropRotation:initialize()
    end
end

TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, validateTypes)

local function save(itemsSystem, xmlFilename, usedModNames)
    g_cropRotation.log:debug("save("..tostring(xmlFilename)..")")

    if g_modIsLoaded[CropRotation.MOD_NAME] then
        local xmlFilename = g_currentMission.missionInfo.savegameDirectory .. "/cropRotation.xml"
        local xmlFile = XMLFile.create("cropRotationXML", xmlFilename, "cropRotation")

        if xmlFile ~= nil then
            g_cropRotation:saveToXMLFile(xmlFile, "cropRotation", usedModNames)
            xmlFile:save()
            xmlFile:delete()
        end
    end
end

ItemSystem.save = Utils.prependedFunction(ItemSystem.save, save)

local function loadItems(itemsSystem, xmlFilename, ...)
    g_cropRotation.log:debug("loadItems() items file="..tostring(xmlFilename))

    if g_modIsLoaded[CropRotation.MOD_NAME] then
        local savegameDirectory = g_currentMission.missionInfo.savegameDirectory
        g_cropRotation.log:debug("loadItems() savegame dir="..tostring(savegameDirectory))

        if savegameDirectory ~= nil then
            local xmlFilename = g_currentMission.missionInfo.savegameDirectory .. "/cropRotation.xml"
            g_cropRotation.log:debug("loadItems() xmlFilename="..tostring(xmlFilename))

            if fileExists(xmlFilename) then
                local xmlFile = XMLFile.load("cropRotationXML", xmlFilename)
                g_cropRotation.log:debug("loadItems() xmlFile="..tostring(xmlFile))

                if xmlFile ~= nil then
                    g_cropRotation:loadFromItemsXML(xmlFile, "cropRotation")
                    xmlFile:delete()
                end
            end
        else
            g_cropRotation:onNewSavegame()
        end
    end
   
    if not CropRotation.EXPERIMENTAL.NEW_PLANNER then
        cr_addOldPlannerToMenu() -- TODO: fixme
    end
end

ItemSystem.loadItems = Utils.prependedFunction(ItemSystem.loadItems, loadItems)

local function unloadMapData(mission, xmlFilename)
    g_cropRotation.log:debug("unloadMapData("..tostring(xmlFilename)..")")

    if g_modIsLoaded[CropRotation.MOD_NAME] then
        g_cropRotation:unloadMapData()
    end
end

Gui.unloadMapData = Utils.prependedFunction(Gui.unloadMapData, unloadMapData)

local function postInitTerrain(mission, terrainId, filename)
    g_cropRotation.log:debug("postInitTerrain("..tostring(filename)..")")

    if g_modIsLoaded[CropRotation.MOD_NAME] then
        g_cropRotation:initTerrain(mission, terrainId, filename)
    end
end

FSBaseMission.initTerrain = Utils.appendedFunction(FSBaseMission.initTerrain, postInitTerrain)

function CropRotation:loadMapDataHelpLineManager(superFunc, ...)
	local ret = superFunc(self, ...)
	if ret then
		self:loadFromXML(Utils.getFilename("gui/helpLine.xml", g_cropRotation.MOD_DIRECTORY))
		return true
	end
	return false
end

HelpLineManager.loadMapData = Utils.overwrittenFunction( HelpLineManager.loadMapData, CropRotation.loadMapDataHelpLineManager)

------------------------------------------------
--- Vanilla Player HUD Updater
-- TODO: move to fieldInfoExtension
------------------------------------------------

function CropRotation.getParallellogramFromXZrotY(posX, posZ, rotY)
    local sizeX = 5
    local sizeZ = 5
    local distance = 2
    local dirX, dirZ = MathUtil.getDirectionFromYRotation(rotY)
    local sideX, _, sideZ = MathUtil.crossProduct(dirX, 0, dirZ, 0, 1, 0)
    local startWorldX = posX - sideX * sizeX * 0.5 - dirX * distance
    local startWorldZ = posZ - sideZ * sizeX * 0.5 - dirZ * distance
    local widthWorldX = posX + sideX * sizeX * 0.5 - dirX * distance
    local widthWorldZ = posZ + sideZ * sizeX * 0.5 - dirZ * distance
    local heightWorldX = posX - sideX * sizeX * 0.5 - dirX * (distance + sizeZ)
    local heightWorldZ = posZ - sideZ * sizeX * 0.5 - dirZ * (distance + sizeZ)

    return startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ
end

function CropRotation:getInfoAtWorldParallelogram(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local mapId, firstChannel, numChannels = g_currentMission.fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)
    local groundFilter = DensityMapFilter.new(mapId, firstChannel, numChannels)
    groundFilter:setValueCompareParams(DensityValueCompareType.GREATER, 0)

    return self:readFromMap(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, groundFilter, false)
end

function CropRotation.getLevelByCrFactor(factor)
    -- factor -- min = 0.7x -- max = 1.15x
    if factor >= 1.10 then return 0 end
    if factor >= 1.05 then return 1 end
    if factor >= 1.00 then return 2 end
    if factor >= 0.95 then return 3 end
    if factor >= 0.90 then return 4 end
    if factor >= 0.80 then return 5 end
    if factor >= 0.70 then return 6 end
    return 7
end

function CropRotation:getFruitTitle(index)
    if not index or index == FruitType.UNKNOWN then
        return self.cache.fieldInfoDisplay.previousFallow
    end

    return g_fruitTypeManager:getFruitTypeByIndex(index).fillType.title
end

function CropRotation:updateFieldInfo(posX, posZ, rotY)
    -- self is PlayerHUDUpdater here!
    if self.requestedFieldData then
        return
    end

    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    if g_farmlandManager:getOwnerIdAtWorldPosition(posX, posZ) ~= g_currentMission.player.farmId then
        cropRotation.cache.fieldInfoDisplay.rotation = nil
        return
    end

    local prev, last = cropRotation:getInfoAtWorldParallelogram(CropRotation.getParallellogramFromXZrotY(posX, posZ, rotY))
    if prev == -1 or last == -1 then
        cropRotation.cache.fieldInfoDisplay.rotation = nil
    else
        cropRotation.cache.fieldInfoDisplay.rotation = {
            prev = prev,
            last = last
        }
    end
end

function CropRotation:fieldAddFruit(data, box)
    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    if cropRotation.cache.fieldInfoDisplay.rotation ~= nil then
        if data.fruitTypeMax and data.fruitTypeMax ~= FruitType.UNKNOWN then
            local fruitType = g_fruitTypeManager:getFruitTypeByIndex(data.fruitTypeMax)
            if fruitType.cutState ~= data.fruitStateMax then
                local crYieldMultiplier =
                    cropRotation:getRotationYieldMultiplier(
                    cropRotation.cache.fieldInfoDisplay.rotation.prev,
                    cropRotation.cache.fieldInfoDisplay.rotation.last,
                    data.fruitTypeMax
                )
                local level = CropRotation.getLevelByCrFactor(crYieldMultiplier)
                local text = CropRotation.COLORS[level].text
                local isColorBlindMode = g_gameSettings:getValue(GameSettings.SETTING.USE_COLORBLIND_MODE) or false

                box:addLine(
                    string.format("%s (%s)", cropRotation.cache.fieldInfoDisplay.title, text),
                    string.format("%d %%", math.floor(100.0 * crYieldMultiplier + 0.1)),
                    true, -- use color
                    isColorBlindMode and CropRotation.COLORS[level].colorBlind or CropRotation.COLORS[level].color
                )
            end
        end

        box:addLine(
            cropRotation.cache.fieldInfoDisplay.previousTitle,
            string.format(
                "%s | %s",
                cropRotation:getFruitTitle(cropRotation.cache.fieldInfoDisplay.rotation.last),
                cropRotation:getFruitTitle(cropRotation.cache.fieldInfoDisplay.rotation.prev)
            )
        )
    end
end

------------------------------------------------
--- PrecisionFarming DLC Player HUD Updater
------------------------------------------------

function CropRotation:yieldChangeFunc(fieldInfo)
    local crFactor = fieldInfo.crFactor or 1.00

    return 2.0 * (crFactor - 1.0), 1.0, fieldInfo.yieldPotential, fieldInfo.yieldPotentialToHa
end

function CropRotation:updateFieldInfoDisplay(fieldInfo, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, isColorBlindMode)
    if g_farmlandManager:getOwnerIdAtWorldPosition(startWorldX, startWorldZ) ~= g_currentMission.player.farmId then
        return nil
    end

    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    local prevIndex, lastIndex = cropRotation:getInfoAtWorldParallelogram(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)

    if prevIndex == -1 or lastIndex == -1 then
        return nil
    end

    local currentIndex = cropRotation.cache.fieldInfoDisplay.currentTypeIndex
    if FruitType.UNKNOWN == currentIndex then
        return nil
    end

    local fruitType = g_fruitTypeManager:getFruitTypeByIndex(currentIndex)
    if fruitType.cutState == cropRotation.cache.fieldInfoDisplay.currentFruitState then
        return nil
    end

    -- update for PF's yieldChangeFunc (above)
    fieldInfo.crFactor = cropRotation:getRotationYieldMultiplier(prevIndex, lastIndex, currentIndex)

    local value = string.format("%d %%", math.floor(100.0 * fieldInfo.crFactor + 0.1))
    local level = CropRotation.getLevelByCrFactor(fieldInfo.crFactor)
    local color = isColorBlindMode and CropRotation.COLORS[level].colorBlind or CropRotation.COLORS[level].color
    local text = CropRotation.COLORS[level].text

    color = {color[1], color[2], color[3], 1} -- RGB to RGBA

    return value, color, text
end

function CropRotation:updateFieldInfoDisplayPreviousCrops(fieldInfo, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, isColorBlindMode)
    if g_farmlandManager:getOwnerIdAtWorldPosition(startWorldX, startWorldZ) ~= g_currentMission.player.farmId then
        return nil
    end

    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    -- Read CR data
    local prev, last = cropRotation:getInfoAtWorldParallelogram(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)

    if prev == -1 or last == -1 then
        return nil
    end

    return string.format("%s | %s", cropRotation:getFruitTitle(last), cropRotation:getFruitTitle(prev))
end

------------------------------------------------
-- Injections to core game functions
-- TODO: move it to ValueMaps
------------------------------------------------

function CropRotation.inj_densityMapUtil_updateSowingArea(superFunc, fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, fieldGroundType, angle, growthState, blockedSprayTypeIndex)
    local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
    if fruitDesc and fruitDesc.rotation.enabled then
        local modifiers = g_cropRotation.modifiers

        local terrainSize = g_currentMission.terrainSize or 1024
        modifiers.harvest.modifier:setParallelogramUVCoords(
            startWorldX  / terrainSize + 0.5,
            startWorldZ  / terrainSize + 0.5,
            widthWorldX  / terrainSize + 0.5,
            widthWorldZ  / terrainSize + 0.5,
            heightWorldX / terrainSize + 0.5,
            heightWorldZ / terrainSize + 0.5,
            DensityCoordType.POINT_POINT_POINT
        )
        modifiers.harvest.modifier:executeSet(0)
    end

    return superFunc(fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, fieldGroundType, angle, growthState, blockedSprayTypeIndex)
end

function applyYieldMultiplier(multiplier, ...)
    if select('#', ...) > 0 then
        local arg = {...}
        arg[1] = multiplier * arg[1]
        return unpack(arg)
    end
    return nil
end

function CropRotation.inj_densityMapUtil_cutFruitArea(superFunc, fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, useMinForageState, excludedSprayType, setsWeeds, limitToField)
    if g_farmlandManager:getOwnerIdAtWorldPosition(0.5*(widthWorldX+heightWorldX), 0.5*(widthWorldZ+heightWorldZ)) ~= g_currentMission.player.farmId then
        -- no crop rotation bonus in NPC missions
        -- change to filtering on cover map
        return superFunc(fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, useMinForageState, excludedSprayType, setsWeeds, limitToField)
    end

    local desc = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
    if desc.terrainDataPlaneId == nil then
        return 0
    end

    local fruitFilter = nil

    local functionData = FSDensityMapUtil.functionCache.cutFruitArea
    if functionData ~= nil and functionData.fruitFilters ~= nil then
        fruitFilter = functionData.fruitFilters[fruitIndex]
    end

    if fruitFilter == nil then
        -- we have missed the cache - create new filter and store inside cache for future use
        g_cropRotation.log:debug(string.format("CropRotation.cutFruitArea(): function cache missed for fruit index %d", fruitIndex))

        fruitFilter = DensityMapFilter.new(desc.terrainDataPlaneId, desc.startStateChannel, desc.numStateChannels, g_currentMission.terrainRootNode)
        if functionData ~= nil and functionData.fruitFilters ~= nil then
            functionData.fruitFilters[fruitIndex] = fruitFilter
        end
    end

    local minState = desc.minHarvestingGrowthState
    if useMinForageState then
        minState = desc.minForageGrowthState
    end

    fruitFilter:setValueCompareParams(DensityValueCompareType.BETWEEN, minState, desc.maxHarvestingGrowthState)

    local cropRotation = g_cropRotation

    local prev, last = g_cropRotation:readFromMap(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX,heightWorldZ, fruitFilter, true)

    local yieldMultiplier = 1.0
    if prev ~= -1 or last ~= -1 then
        yieldMultiplier = cropRotation:getRotationYieldMultiplier(prev, last, fruitIndex)
        -- mapModifier:executeSet(
        --     cropRotation:encode(last, fruitIndex, 1, 1),
        --     fruitFilter,
        --     cropRotation.modifiers.map.filterH
        -- )

        local terrainSize = g_currentMission.terrainSize
        cropRotation.modifiers.harvest.modifier:setParallelogramUVCoords(
            startWorldX  / terrainSize + 0.5,
            startWorldZ  / terrainSize + 0.5,
            widthWorldX  / terrainSize + 0.5,
            widthWorldZ  / terrainSize + 0.5,
            heightWorldX / terrainSize + 0.5,
            heightWorldZ / terrainSize + 0.5,
            DensityCoordType.POINT_POINT_POINT)
        cropRotation.modifiers.fallow.modifier:setParallelogramUVCoords(
            startWorldX  / terrainSize + 0.5,
            startWorldZ  / terrainSize + 0.5,
            widthWorldX  / terrainSize + 0.5,
            widthWorldZ  / terrainSize + 0.5,
            heightWorldX / terrainSize + 0.5,
            heightWorldZ / terrainSize + 0.5,
            DensityCoordType.POINT_POINT_POINT)

        local filterH = cropRotation.modifiers.harvest.filter
        cropRotation.modifiers.r2.modifier:executeSet(last, fruitFilter, filterH)
        cropRotation.modifiers.r1.modifier:executeSet(fruitIndex, fruitFilter, filterH) -- current
        cropRotation.modifiers.fallow.modifier:executeSet(1, fruitFilter, filterH)
        cropRotation.modifiers.harvest.modifier:executeSet(1, fruitFilter, filterH)
    end

    return applyYieldMultiplier(
        yieldMultiplier,
        superFunc(
            fruitIndex,
            startWorldX,
            startWorldZ,
            widthWorldX,
            widthWorldZ,
            heightWorldX,
            heightWorldZ,
            destroySpray,
            useMinForageState,
            excludedSprayType,
            setsWeeds,
            limitToField
        )
    )
end

g_cropRotation:overwriteGameFunction(FSDensityMapUtil, "updateSowingArea", CropRotation.inj_densityMapUtil_updateSowingArea)
g_cropRotation:overwriteGameFunction(FSDensityMapUtil, "updateDirectSowingArea", CropRotation.inj_densityMapUtil_updateSowingArea)
g_cropRotation:overwriteGameFunction(FSDensityMapUtil, "cutFruitArea", CropRotation.inj_densityMapUtil_cutFruitArea)

------------------------------------------------
-- Reading and writing
-- TODO: move it to ValueMap methods
------------------------------------------------

---Read the forecrops and aftercrops from the map.
function CropRotation:readFromMap(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, filter, skipWhenHarvested)
    local terrainSize = g_currentMission.terrainSize
    local r2, r1 = -1, -1

    local modifiers = self.modifiers

    modifiers.r2.modifier:setParallelogramUVCoords(
        startWorldX  / terrainSize + 0.5,
        startWorldZ  / terrainSize + 0.5,
        widthWorldX  / terrainSize + 0.5,
        widthWorldZ  / terrainSize + 0.5,
        heightWorldX / terrainSize + 0.5,
        heightWorldZ / terrainSize + 0.5,
        DensityCoordType.POINT_POINT_POINT)
    modifiers.r2.filter:setValueCompareParams(DensityValueCompareType.EQUAL, self.cache.readFromMap.previousCrop)

    local area, totalArea

    if skipWhenHarvested then
        _, area, totalArea = modifiers.r2.modifier:executeGet(filter, modifiers.harvest.filter, modifiers.r2.filter)
    else
        _, area, totalArea = modifiers.r2.modifier:executeGet(filter, modifiers.r2.filter)
    end

    if area >= totalArea * 0.5 then
        r2 = self.cache.readFromMap.previousCrop
    else
        local maxArea = 0
        for i = 0, #g_fruitTypeManager:getFruitTypes() do
            modifiers.r2.filter:setValueCompareParams(DensityValueCompareType.EQUAL, i)

            local area, totalArea
            if skipWhenHarvested then
                acc, area, totalArea = modifiers.r2.modifier:executeGet(filter, modifiers.harvest.filter, modifiers.r2.filter)
            else
                acc, area, totalArea = modifiers.r2.modifier:executeGet(filter, modifiers.r2.filter)
            end

            if area > maxArea then
                maxArea = area
                r2 = i
            end

            if area >= totalArea * 0.5 then
                self.cache.readFromMap.previousCrop = i -- update function cache
                break
            end
        end
    end

    modifiers.r1.modifier:setParallelogramUVCoords(
        startWorldX / terrainSize + 0.5,
        startWorldZ / terrainSize + 0.5,
        widthWorldX / terrainSize + 0.5,
        widthWorldZ / terrainSize + 0.5,
        heightWorldX / terrainSize + 0.5,
        heightWorldZ / terrainSize + 0.5,
        DensityCoordType.POINT_POINT_POINT)
    modifiers.r1.filter:setValueCompareParams(DensityValueCompareType.EQUAL, self.cache.readFromMap.lastCrop)

    local area, totalArea
    if skipWhenHarvested then
        _, area, totalArea = modifiers.r1.modifier:executeGet(filter, modifiers.harvest.filter, modifiers.r1.filter)
    else
        _, area, totalArea = modifiers.r1.modifier:executeGet(filter, modifiers.r1.filter)
    end

    if area >= totalArea * 0.5 then
        r1 = self.cache.readFromMap.lastCrop
    else
        local maxArea = 0
        for i = 0, #g_fruitTypeManager:getFruitTypes() do
            modifiers.r1.filter:setValueCompareParams(DensityValueCompareType.EQUAL, i)

            local area, totalArea
            if skipWhenHarvested then
                acc, area, totalArea = modifiers.r1.modifier:executeGet(filter, modifiers.harvest.filter, modifiers.r1.filter)
            else
                acc, area, totalArea = modifiers.r1.modifier:executeGet(filter, modifiers.r1.filter)
            end

            if area > maxArea then
                maxArea = area
                r1 = i
            end

            if area >= totalArea * 0.5 then
                self.cache.readFromMap.lastCrop = i -- update function cache
                break
            end
        end
    end

    return r2, r1
end

-----------------------------------
-- Algorithms
-----------------------------------

function CropRotation:getRotationYieldMultiplier(prevIndex, lastIndex, currentIndex)
    local currentDesc = g_fruitTypeManager:getFruitTypeByIndex(currentIndex)

    local returnPeriod = self:getRotationReturnPeriodMultiplier(prevIndex, lastIndex, currentDesc)
    local forecrops = self:getRotationForecropMultiplier(prevIndex, lastIndex, currentIndex)

    return forecrops + returnPeriod
end

function CropRotation:getRotationReturnPeriodMultiplier(prev, last, current)
    local returnPeriod = current.rotation.returnPeriod

    -- monoculture
    local result = 0.0 - ((current.index == last and current.index == prev) and 0.05 or 0)

    if returnPeriod == 3 then
        return result - (current.index == last and 0.1 or 0) - (current.index == prev and 0.05 or 0)
    end

    if returnPeriod == 2 then
        return result - (current.index == last and 0.05 or 0)
    end

    return result
end

function CropRotation:getRotationForecropMultiplier(prevIndex, lastIndex, currentIndex)
    local prevValue = self.data:getRotationForecropValue(prevIndex, currentIndex)
    local lastValue = self.data:getRotationForecropValue(lastIndex, currentIndex)

    local prevFactor = -0.025 * prevValue ^ 2 + 0.125 * prevValue -- <0.0 ; 0.15>
    local lastFactor = -0.05 * lastValue ^ 2 + 0.25 * lastValue -- <0.0 ; 0.30>

    return 0.7 + (prevFactor + lastFactor) -- <0.7 ; 1.15>
end

-- input: list of crop indices: { 11, 2, 3 }
-- output: list of multipliers: { 1.15, 1.1, 1.0 }
function CropRotation:getRotationPlannerYieldMultipliers(input)
    if #input < 1 then
        return {}
    end

    local result = {}
    for pos, current in pairs(input) do
        if current and current ~= FruitType.UNKNOWN then
            lastPos = 1 + math.fmod((pos + #input - 1) - 1, #input)
            prevPos = 1 + math.fmod((pos + #input - 1) - 2, #input)

            table.insert(result, self:getRotationYieldMultiplier(input[prevPos], input[lastPos], current))
        else
            table.insert(result, 0.0)
        end
    end

    return result
end

------------------------------------------------
-- Getting info
------------------------------------------------

function CropRotation:commandPlanner(...)
    -- prepare request
    local cropIndices = {}
    for i, name in pairs({...}) do
        local crop = g_fruitTypeManager:getFruitTypeByName(name:upper())
        if crop ~= nil then
            table.insert(cropIndices, crop.index)
        else
            table.insert(cropIndices, FruitType.UNKNOWN)
        end
    end

    local result = self:getRotationPlannerYieldMultipliers(cropIndices)

    -- format the response
    for i, cropIndex in pairs(cropIndices) do
        if cropIndex == FruitType.UNKNOWN then
            print(string.format("%-20s -.--", "FALLOW"))
        else
            local crop = g_fruitTypeManager:getFruitTypeByIndex(cropIndex)
            print(string.format("%-20s %1.2f", crop.name, math.floor(100 * result[i] + 0.1) / 100))
        end
    end
end

function CropRotation:getInfoAtWorldCoords(x, z)
    local mapSize = getBitVectorMapSize(self.crCoverMap.bitVectorMap)
    local terrainSize = g_currentMission.terrainSize

    local worldToDensityMap = mapSize / terrainSize
    local densityToWorldMap = terrainSize / mapSize

    local terrainHalfSize = terrainSize * 0.5
    local xi = math.floor((x + terrainHalfSize) * worldToDensityMap)
    local zi = math.floor((z + terrainHalfSize) * worldToDensityMap)

    local prev = getBitVectorMapPoint(self.crYieldMap_n2.bitVectorMap, xi, zi, 0, self.crYieldMap_n2.numChannels)
    local last = getBitVectorMapPoint(self.crYieldMap_n1.bitVectorMap, xi, zi, 0, self.crYieldMap_n1.numChannels)
    local harvest = getBitVectorMapPoint(self.crCoverMap.bitVectorMap, xi, zi, self.crCoverMap.harvestChannel, 1)
    local fallow = getBitVectorMapPoint(self.crCoverMap.bitVectorMap, xi, zi, self.crCoverMap.fallowChannel, 1)
    local cover =  getBitVectorMapPoint(self.crCoverMap.bitVectorMap, xi, zi, self.crCoverMap.lockChannel, 1)

    return prev, last, harvest, fallow, cover
end

function CropRotation:commandGetInfo()
    local x, _, z = getWorldTranslation(getCamera(0))

    local prev, last, harvest, fallow, cover = self:getInfoAtWorldCoords(x, z)

    local getName = function(fruitIndex)
        if fruitIndex ~= FruitType.UNKNOWN then
            return g_fruitTypeManager:getFruitTypeByIndex(fruitIndex).fillType.title
        end
        return g_i18n:getText("cropRotation_fallow")
    end

    self.log:info(string.format("crops: [last(%d): %s] [previous(%d): %s] bits: [harvest: %d] [fallow: %d] [cover: %d]",
        last, getName(last),
        prev, getName(prev),
        harvest,
        fallow,
        cover)
    )
end

------------------------------------------------
-- Debugging
------------------------------------------------

function CropRotation:commandRunFallow()
    self.densityMapUpdater:schedule("UpdateFallow")
end

function CropRotation:commandRunRegrow()
    self.densityMapUpdater:schedule("UpdateRegrow")
end

function CropRotation:commandSetCover(bit)
    local radius = 10
    local x, _, z = getWorldTranslation(getCamera(0))
    if g_currentMission.controlledVehicle ~= nil then
        local object = g_currentMission.controlledVehicle
        if g_currentMission.controlledVehicle.selectedImplement ~= nil then
            object = g_currentMission.controlledVehicle.selectedImplement.object
        end
        x, _, z = getWorldTranslation(object.components[1].node)
    end

    self:setCover(x, z, radius, tonumber(bit and 1 or 0))
end

function CropRotation:commandSetFallow(bit)
    local radius = 10
    local x, _, z = getWorldTranslation(getCamera(0))
    if g_currentMission.controlledVehicle ~= nil then
        local object = g_currentMission.controlledVehicle
        if g_currentMission.controlledVehicle.selectedImplement ~= nil then
            object = g_currentMission.controlledVehicle.selectedImplement.object
        end
        x, _, z = getWorldTranslation(object.components[1].node)
    end

    self:setFallow(x, z, radius, tonumber(bit and 1 or 0))
end

function CropRotation:commandSetHarvest(bit)
    local radius = 10
    local x, _, z = getWorldTranslation(getCamera(0))
    if g_currentMission.controlledVehicle ~= nil then
        local object = g_currentMission.controlledVehicle
        if g_currentMission.controlledVehicle.selectedImplement ~= nil then
            object = g_currentMission.controlledVehicle.selectedImplement.object
        end
        x, _, z = getWorldTranslation(object.components[1].node)
    end

    self:setHarvest(x, z, radius, tonumber(bit and 1 or 0))
end

function CropRotation:setCover(x, z, radius, bit)
    local terrainSize = g_currentMission.terrainSize
    local startWorldX = math.max(-terrainSize / 2, x - radius)
    local startWorldZ = math.max(-terrainSize / 2, z - radius)
    local widthWorldX = math.min(terrainSize / 2, x + radius)
    local widthWorldZ = startWorldZ
    local heightWorldX = startWorldX
    local heightWorldZ = math.min(terrainSize / 2, z + radius)

    local modifier = self.modifiers.cover.modifier
    modifier:setParallelogramUVCoords(
        startWorldX  / terrainSize + 0.5,
        startWorldZ  / terrainSize + 0.5,
        widthWorldX  / terrainSize + 0.5,
        widthWorldZ  / terrainSize + 0.5,
        heightWorldX / terrainSize + 0.5,
        heightWorldZ / terrainSize + 0.5,
        DensityCoordType.POINT_POINT_POINT
    )
    modifier:executeSet(bit)
end

function CropRotation:setFallow(x, z, radius, bit)
    local terrainSize = g_currentMission.terrainSize
    local startWorldX = math.max(-terrainSize / 2, x - radius)
    local startWorldZ = math.max(-terrainSize / 2, z - radius)
    local widthWorldX = math.min(terrainSize / 2, x + radius)
    local widthWorldZ = startWorldZ
    local heightWorldX = startWorldX
    local heightWorldZ = math.min(terrainSize / 2, z + radius)

    local modifier = self.modifiers.fallow.modifier
    modifier:setParallelogramUVCoords(
        startWorldX  / terrainSize + 0.5,
        startWorldZ  / terrainSize + 0.5,
        widthWorldX  / terrainSize + 0.5,
        widthWorldZ  / terrainSize + 0.5,
        heightWorldX / terrainSize + 0.5,
        heightWorldZ / terrainSize + 0.5,
        DensityCoordType.POINT_POINT_POINT
    )
    modifier:executeSet(bit)
end

function CropRotation:setHarvest(x, z, radius, bit)
    local terrainSize = g_currentMission.terrainSize
    local startWorldX = math.max(-terrainSize / 2, x - radius)
    local startWorldZ = math.max(-terrainSize / 2, z - radius)
    local widthWorldX = math.min(terrainSize / 2, x + radius)
    local widthWorldZ = startWorldZ
    local heightWorldX = startWorldX
    local heightWorldZ = math.min(terrainSize / 2, z + radius)

    local modifier = self.modifiers.harvest.modifier
    modifier:setParallelogramUVCoords(
        startWorldX  / terrainSize + 0.5,
        startWorldZ  / terrainSize + 0.5,
        widthWorldX  / terrainSize + 0.5,
        widthWorldZ  / terrainSize + 0.5,
        heightWorldX / terrainSize + 0.5,
        heightWorldZ / terrainSize + 0.5,
        DensityCoordType.POINT_POINT_POINT
    )
    modifier:executeSet(bit)
end

function CropRotation:commandSetLast(name)
    local radius = 10
    local x, _, z = getWorldTranslation(getCamera(0))

    local crop = g_fruitTypeManager:getFruitTypeByName(name:upper())
    self:setLast(x, z, radius, crop and crop.index or 0)  
end

function CropRotation:setLast(x,z,radius,index)
    local terrainSize = g_currentMission.terrainSize
    local startWorldX = math.max(-terrainSize / 2, x - radius)
    local startWorldZ = math.max(-terrainSize / 2, z - radius)
    local widthWorldX = math.min(terrainSize / 2, x + radius)
    local widthWorldZ = startWorldZ
    local heightWorldX = startWorldX
    local heightWorldZ = math.min(terrainSize / 2, z + radius)

    local modifier = self.modifiers.r1.modifier
    modifier:setParallelogramUVCoords(
        startWorldX  / terrainSize + 0.5,
        startWorldZ  / terrainSize + 0.5,
        widthWorldX  / terrainSize + 0.5,
        widthWorldZ  / terrainSize + 0.5,
        heightWorldX / terrainSize + 0.5,
        heightWorldZ / terrainSize + 0.5,
        DensityCoordType.POINT_POINT_POINT
    )
    modifier:executeSet(index)
end

function CropRotation:commandSetPrev(name) 
    local radius = 10
    local x, _, z = getWorldTranslation(getCamera(0))

    local crop = g_fruitTypeManager:getFruitTypeByName(name:upper())
    self:setPrev(x, z, radius, crop and crop.index or 0)
end

function CropRotation:setPrev(x,z,radius,index)
    local terrainSize = g_currentMission.terrainSize
    local startWorldX = math.max(-terrainSize / 2, x - radius)
    local startWorldZ = math.max(-terrainSize / 2, z - radius)
    local widthWorldX = math.min(terrainSize / 2, x + radius)
    local widthWorldZ = startWorldZ
    local heightWorldX = startWorldX
    local heightWorldZ = math.min(terrainSize / 2, z + radius)

    local modifier = self.modifiers.r2.modifier
    modifier:setParallelogramUVCoords(
        startWorldX  / terrainSize + 0.5,
        startWorldZ  / terrainSize + 0.5,
        widthWorldX  / terrainSize + 0.5,
        widthWorldZ  / terrainSize + 0.5,
        heightWorldX / terrainSize + 0.5,
        heightWorldZ / terrainSize + 0.5,
        DensityCoordType.POINT_POINT_POINT
    )
    modifier:executeSet(index)
end

function CropRotation:commandToggleVisualize()
    if CropRotation.DEBUG then
        self.isVisualizeEnabled = not self.isVisualizeEnabled
    end
end


function CropRotation:visualize()
    local mapSize = getBitVectorMapSize(self.crCoverMap.bitVectorMap)
    local terrainSize = g_currentMission.terrainSize

    local worldToDensityMap = mapSize / terrainSize
    local densityToWorldMap = terrainSize / mapSize

    if self.crCoverMap ~= 0 then
        local x, y, z = getWorldTranslation(getCamera(0))

        if g_currentMission.controlledVehicle ~= nil then
            local object = g_currentMission.controlledVehicle

            if g_currentMission.controlledVehicle.selectedImplement ~= nil then
                object = g_currentMission.controlledVehicle.selectedImplement.object
            end

            x, y, z = getWorldTranslation(object.components[1].node)
        end

        local terrainHalfSize = terrainSize * 0.5
        local xi = math.floor((x + terrainHalfSize) * worldToDensityMap)
        local zi = math.floor((z + terrainHalfSize) * worldToDensityMap)

        local minXi = math.max(xi - 20, 0)
        local minZi = math.max(zi - 20, 0)
        local maxXi = math.min(xi + 20, mapSize - 1)
        local maxZi = math.min(zi + 20, mapSize - 1)

        for zi = minZi, maxZi do
            for xi = minXi, maxXi do
                local cfh = getBitVectorMapPoint(self.crCoverMap.bitVectorMap,   xi, zi, 0, self.crCoverMap.numChannels)

                local h = bitShiftRight(bitAND(cfh, 4), 2)
                local f = bitShiftRight(bitAND(cfh, 2), 1)
                local c = bitAND(cfh, 1)

                local r1 = getBitVectorMapPoint(self.crYieldMap_n1.bitVectorMap, xi, zi, 0, self.crYieldMap_n1.numChannels)
                local r2 = getBitVectorMapPoint(self.crYieldMap_n2.bitVectorMap, xi, zi, 0, self.crYieldMap_n2.numChannels)

                local x = (xi * densityToWorldMap) - terrainHalfSize
                local z = (zi * densityToWorldMap) - terrainHalfSize
                local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 0.05

                local r, g, b = (0.5+c/2), f, h

                local text = string.format("%d,%d,%d,%d", r2, r1, f, h)
                Utils.renderTextAtWorldPosition(x, y, z, text, getCorrectTextSize(0.015), 0, {r, g, b, 1})
            end
        end
    end
end

------------------------------------------------
--- Message Center Event handlers
------------------------------------------------

function CropRotation:onYearChanged(newYear)
    self.log:debug("CropRotation:onYearChanged(year="..tostring(newYear)..")")
    
    self.densityMapUpdater:schedule("UpdateFallow")
end

function CropRotation:onPeriodChanged(newPeriod)
    self.log:debug("CropRotation:onPeriodChanged(month="..tostring(newPeriod)..")")

    self.densityMapUpdater:schedule("UpdateRegrow")
end

------------------------------------------------
--- Density Map Updater periodic task definitions
------------------------------------------------

-- yearly fallow bit update on parallelogram(start, width, height)
function CropRotation:task_updateFallow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local terrainSize = g_currentMission.terrainSize or 1024
    local modifiers = self.modifiers

    modifiers.r1.modifier:setParallelogramUVCoords(
        startWorldX  / terrainSize + 0.5,
        startWorldZ  / terrainSize + 0.5,
        widthWorldX  / terrainSize + 0.5,
        widthWorldZ  / terrainSize + 0.5,
        heightWorldX / terrainSize + 0.5,
        heightWorldZ / terrainSize + 0.5,
        DensityCoordType.POINT_POINT_POINT
    )
    modifiers.r2.modifier:setParallelogramUVCoords(
        startWorldX  / terrainSize + 0.5,
        startWorldZ  / terrainSize + 0.5,
        widthWorldX  / terrainSize + 0.5,
        widthWorldZ  / terrainSize + 0.5,
        heightWorldX / terrainSize + 0.5,
        heightWorldZ / terrainSize + 0.5,
        DensityCoordType.POINT_POINT_POINT
    )

    for i = 0, #g_fruitTypeManager:getFruitTypes() do
        modifiers.r1.filter:setValueCompareParams(DensityValueCompareType.EQUAL, i)
        modifiers.r2.modifier:executeSet(i, modifiers.fallow.filter, modifiers.r1.filter)
        modifiers.r1.modifier:executeSet(FruitType.UNKNOWN, modifiers.fallow.filter, modifiers.r1.filter)
    end

    modifiers.fallow.modifier:setParallelogramUVCoords(
        startWorldX  / terrainSize + 0.5,
        startWorldZ  / terrainSize + 0.5,
        widthWorldX  / terrainSize + 0.5,
        widthWorldZ  / terrainSize + 0.5,
        heightWorldX / terrainSize + 0.5,
        heightWorldZ / terrainSize + 0.5,
        DensityCoordType.POINT_POINT_POINT
    )
    modifiers.fallow.modifier:executeSet(0)
end

function CropRotation:task_updateRegrow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local terrainSize = g_currentMission.terrainSize or 1024
    local modifiers = self.modifiers

    for i, desc in pairs(g_fruitTypeManager:getFruitTypes()) do
        if desc.regrows then
            modifiers.r1.filter:setValueCompareParams(DensityValueCompareType.EQUAL, i)
            modifiers.harvest.modifier:setParallelogramUVCoords(
                startWorldX  / terrainSize + 0.5,
                startWorldZ  / terrainSize + 0.5,
                widthWorldX  / terrainSize + 0.5,
                widthWorldZ  / terrainSize + 0.5,
                heightWorldX / terrainSize + 0.5,
                heightWorldZ / terrainSize + 0.5,
                DensityCoordType.POINT_POINT_POINT
            )
            modifiers.harvest.modifier:executeSet(0, modifiers.r1.filter)
        end
    end
end

------------------------------------------------
-- Install OLD STYLE Crop Rotation Planner Menu
-- All code below is going to be removed
------------------------------------------------

function cr_addOldPlannerToMenu()
    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    g_gui:loadProfiles(CropRotation.MOD_DIRECTORY .. "gui/guiProfiles.xml")

    local ingameMenuCropRotationPlanner = InGameMenuCropRotationPlanner.new(g_i18n, cropRotation, cropRotation.planner)
    local pathToGuiXml = CropRotation.MOD_DIRECTORY .. "gui/InGameMenuCropRotationPlanner.xml"
    g_gui:loadGui(pathToGuiXml,
                  "ingameMenuCropRotationPlanner",
                  ingameMenuCropRotationPlanner,
                  true)

    fixInGameMenu(ingameMenuCropRotationPlanner,
                  "ingameMenuCropRotationPlanner",
                  {0, 0, 1024, 1024},
                  4)
end

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
    local iconFileName = Utils.getFilename('gui/menuIcon.dds', CropRotation.MOD_DIRECTORY)
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
