--
-- FS22 Crop Rotation mod
--
-- CropRotation.lua
--
-- @Author: Bodzio528
-- @Version: 2.0.0.0

-- Changelog:
--  v2.0.0.0 (05.09.2022):
--      - code rewrite
-- 	v1.0.0.0 (03.08.2022):
--      - Initial release

CropRotation = {
    MOD_NAME = g_currentModName or "FS22_PF_CropRotation",
    MOD_DIRECTORY = g_currentModDirectory,
    MAP_VERSION = 2,
    MAP_NUM_CHANNELS = 12 -- [R2:5][R1:5][F:1][H:1]
}

local CropRotation_mt = Class(CropRotation)

CropRotation.PrecisionFarming = "FS22_precisionFarming"

-- TODO: read colors from configuration XML
CropRotation.COLORS = {
    [0] = { color = {0.0000, 0.4341, 0.0802, 1}, colorBlind = {1.0000, 1.0000, 0.1000, 1}, text = "cropRotation_hud_fieldInfo_perfect" },
    [1] = { color = {0.0331, 0.4564, 0.0513, 1}, colorBlind = {0.9250, 0.9250, 0.1000, 1}, text = "cropRotation_hud_fieldInfo_good" },
    [2] = { color = {0.1329, 0.4735, 0.0296, 1}, colorBlind = {0.8500, 0.8500, 0.1000, 1}, text = "cropRotation_hud_fieldInfo_good" },
    [3] = { color = {0.3231, 0.4969, 0.0137, 1}, colorBlind = {0.7500, 0.7500, 0.1000, 1}, text = "cropRotation_hud_fieldInfo_ok" },
    [4] = { color = {0.6105, 0.5149, 0.0048, 1}, colorBlind = {0.6500, 0.6500, 0.1000, 1}, text = "cropRotation_hud_fieldInfo_ok" },
    [5] = { color = {0.9910, 0.3231, 0.0000, 1}, colorBlind = {0.4500, 0.4500, 0.1000, 1}, text = "cropRotation_hud_fieldInfo_bad" },
    [6] = { color = {0.9911, 0.0742, 0.0000, 1}, colorBlind = {0.2500, 0.2500, 0.1000, 1}, text = "cropRotation_hud_fieldInfo_bad" },
    [7] = { color = {0.9910, 0.0000, 0.0000, 1}, colorBlind = {0.1000, 0.1000, 0.1000, 1}, text = "cropRotation_hud_fieldInfo_bad" }
}

CropRotation.debug = false -- true --

function overwrittenStaticFunction(object, funcName, newFunc)
    local oldFunc = object[funcName]
    object[funcName] = function (...)
        return newFunc(oldFunc, ...)
    end
end

function CropRotation:new(mission, modDirectory, messageCenter, fruitTypeManager, i18n, data, densityMapUpdater)
    local self = setmetatable({}, CropRotation_mt)

    self.isServer = mission:getIsServer()

    self.mission = mission
    self.modDirectory = modDirectory
    self.messageCenter = messageCenter
    self.fruitTypeManager = fruitTypeManager
    self.i18n = i18n

    self.data = data

    self.mapName = "cropRotation"
    self.mapFilePath = self.mission.missionInfo.savegameDirectory .. "/cropRotation.grle"

    self.xmlName = "CropRotationXML"
    self.xmlFilePath = self.mission.missionInfo.savegameDirectory .. "/cropRotation.xml"
    self.xmlRootElement = "cropRotation"

    self.densityMapUpdater = densityMapUpdater

    self.numFruits = math.min(31, #self.fruitTypeManager:getFruitTypes())
    self.isVisualizeEnabled = false

    self.isNewSavegame = false

    overwrittenStaticFunction(FSDensityMapUtil, "updateSowingArea", CropRotation.inj_densityMapUtil_updateSowingArea)
    overwrittenStaticFunction(FSDensityMapUtil, "updateDirectSowingArea", CropRotation.inj_densityMapUtil_updateSowingArea)
    overwrittenStaticFunction(FSDensityMapUtil, "cutFruitArea", CropRotation.inj_densityMapUtil_cutFruitArea)

    addConsoleCommand("crInfo", "Get crop rotation info", "commandGetInfo", self)
    addConsoleCommand("crPlanner", "Perform planner function with specified crops", "commandPlanner", self)

    if CropRotation.debug then
        addConsoleCommand("crVisualizeToggle", "Toggle Crop Rotation visualization", "commandToggleVisualize", self)
    end

    if CropRotation.debug or g_addCheatCommands then -- cheats enabled
        addConsoleCommand("crFallowRun", "Run yearly fallow", "commandRunFallow", self)
        addConsoleCommand("crFallowSet", "Set fallow state", "commandSetFallow", self)
        addConsoleCommand("crFallowClear", "Clear fallow state", "commandClearFallow", self)
        addConsoleCommand("crHarvestSet", "Set harvest state", "commandSetHarvest", self)
        addConsoleCommand("crHarvestClear", "Clear harvest state", "commandClearHarvest", self)
    end

    self:initCache()

    return self
end

-- fill function cache to speedup execution
function CropRotation:initCache()
    self.cache = {}
    self.cache.fieldInfoDisplay = {}
    self.cache.fieldInfoDisplay.title = self.i18n:getText("cropRotation_hud_fieldInfo_title")
    self.cache.fieldInfoDisplay.previousTitle = self.i18n:getText("cropRotation_hud_fieldInfo_previous")
    self.cache.fieldInfoDisplay.previousFallow = self.i18n:getText("cropRotation_fallow")

    self.cache.fieldInfoDisplay.currentTypeIndex = FruitType.UNKNOWN
    self.cache.fieldInfoDisplay.currentFruitState = 0

    -- crop rotation fieldInfoDisplay level color and text
    local isColorBlindMode = g_gameSettings:getValue(GameSettings.SETTING.USE_COLORBLIND_MODE) or false

    self.cache.fieldInfoDisplay.levels = {}
    for level=0,7 do
        local color = CropRotation.COLORS[level].color
        if isColorBlindMode then color = CropRotation.COLORS[level].colorBlind end

        local text = self.i18n:getText(CropRotation.COLORS[level].text)

        self.cache.fieldInfoDisplay.levels[level] = { color=color, text=text }
    end

    -- readFromMap smart cache
    self.cache.readFromMap = {}
    self.cache.readFromMap.previousCrop = FruitType.UNKNOWN -- R2
    self.cache.readFromMap.lastCrop = FruitType.UNKNOWN -- R1
end

function CropRotation:delete()
    self.densityMapUpdater:unregisterCallback("UpdateFallow")

    if self.densityMapUpdater ~= nil then
        self.densityMapUpdater = nil
    end

    self.cache = nil

    removeConsoleCommand("crInfo")
    removeConsoleCommand("crPlanner")

    if CropRotation.debug then
        removeConsoleCommand("crVisualizeToggle", self)
    end

    if  CropRotation.debug or g_addCheatCommands then
        removeConsoleCommand("crFallowRun")
        removeConsoleCommand("crFallowSet")
        removeConsoleCommand("crFallowClear")
        removeConsoleCommand("crHarvestSet")
        removeConsoleCommand("crHarvestClear")
    end

    self.messageCenter:unsubscribeAll(self)
end

-- this function will add synchronization between all clients in MP game...
-- ...hopefully
function CropRotation:addDensityMapSyncer(densityMapSyncer)
    if self.map ~= nil then
        densityMapSyncer:addDensityMap(self.map)
    end
end

------------------------------------------------
--- Events from mod event handling
------------------------------------------------

function CropRotation:loadMap()
    self:loadSavegame()

    FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, CropRotation.saveSavegame)

    if g_modIsLoaded[CropRotation.PrecisionFarming] then -- extend PlayerHUDUpdater with crop rotation info
        local l_precisionFarming = FS22_precisionFarming.g_precisionFarming
        if l_precisionFarming ~= nil then
            l_precisionFarming.fieldInfoDisplayExtension:addFieldInfo(self.cache.fieldInfoDisplay.title,
                                                                      self,
                                                                      self.updateFieldInfoDisplay,
                                                                      4, -- prio,
                                                                      self.yieldChangeFunc)

            l_precisionFarming.fieldInfoDisplayExtension:addFieldInfo(self.i18n:getText("cropRotation_hud_fieldInfo_previous"),
                                                                      self,
                                                                      self.updateFieldInfoDisplayPreviousCrops,
                                                                      5, -- prio,
                                                                      nil)
        end

        PlayerHUDUpdater.fieldAddFruit = Utils.appendedFunction(PlayerHUDUpdater.fieldAddFruit, function(updater, data, box)
            -- capture fruit type that player is currently gazing
            local cropRotation = g_cropRotation
            assert(cropRotation ~= nil)

            cropRotation.cache.fieldInfoDisplay.currentTypeIndex = data.fruitTypeMax or FruitType.UNKNOWN
            cropRotation.cache.fieldInfoDisplay.currentFruitState = data.fruitStateMax or 0
        end)
    else -- OR simply add Crop Rotation Info to standard HUD
        PlayerHUDUpdater.fieldAddFruit = Utils.appendedFunction(PlayerHUDUpdater.fieldAddFruit, CropRotation.fieldAddFruit)
        PlayerHUDUpdater.updateFieldInfo = Utils.prependedFunction(PlayerHUDUpdater.updateFieldInfo, CropRotation.updateFieldInfo)
    end
end

---Called every frame update
function CropRotation:update(dt)
    if self.densityMapUpdater ~= nil then
        self.densityMapUpdater:update(dt)
    end

    if CropRotation.debug and self.isVisualizeEnabled then
        self:visualize()
    end
end

------------------------------------------------
--- Player HUD Updater
------------------------------------------------

function CropRotation.getLevelByCrFactor(factor)
    -- factor -- min = 0.7x  -- max = 1.15x
    if factor > 1.10 then return 0 end
    if factor > 1.05 then return 1 end
    if factor > 1.00 then return 2 end
    if factor > 0.95 then return 3 end
    if factor > 0.90 then return 4 end
    if factor > 0.85 then return 5 end
    if factor > 0.80 then return 6 end
    return 7
end

function CropRotation:getFruitTitle(index)
    if index ~= FruitType.UNKNOWN then
        return self.fruitTypeManager:getFruitTypeByIndex(index).fillType.title
    end

    return self.cache.fieldInfoDisplay.previousFallow
end

function CropRotation:updateFieldInfo(posX, posZ, rotY)
    if self.requestedFieldData then
        return
    end

    if g_farmlandManager:getOwnerIdAtWorldPosition(posX, posZ) ~= g_currentMission.player.farmId then
        return
    end

    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = CropRotation.getParallellogramFromXZrotY(posX, posZ, rotY)
    local prev, last = cropRotation:getInfoAtWorldParallelogram(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)

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
                local crYieldMultiplier = cropRotation:getRotationYieldMultiplier(cropRotation.cache.fieldInfoDisplay.rotation.prev,
                                                                                  cropRotation.cache.fieldInfoDisplay.rotation.last,
                                                                                  data.fruitTypeMax)
                local level = CropRotation.getLevelByCrFactor(crYieldMultiplier)
                local text = cropRotation.cache.fieldInfoDisplay.levels[level].text
                box:addLine(string.format("%s (%s)", cropRotation.cache.fieldInfoDisplay.title, text),
                            string.format("%d %%", math.ceil(100.0 * crYieldMultiplier)),
                            true, -- use color
                            cropRotation.cache.fieldInfoDisplay.levels[level].color)
            end
        end

        box:addLine(cropRotation.cache.fieldInfoDisplay.previousTitle,
                    string.format("%s | %s", cropRotation:getFruitTitle(cropRotation.cache.fieldInfoDisplay.rotation.last),
                                             cropRotation:getFruitTitle(cropRotation.cache.fieldInfoDisplay.rotation.prev)))
    end
end

------------------------------------------------
--- PrecisionFarming DLC Player HUD Updater
------------------------------------------------
function CropRotation:yieldChangeFunc(fieldInfo)
    local crFactor = fieldInfo.crFactor or 1.00 -- default is 100%

    return 10.0 * (crFactor-1.0),
           0.20,
           fieldInfo.yieldPotential,
           fieldInfo.yieldPotentialToHa
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

    local crFactor = cropRotation:getRotationYieldMultiplier(prevIndex, lastIndex, currentIndex)

    local value = string.format("%d %%",  math.ceil(100.0 * crFactor))

    local level = CropRotation.getLevelByCrFactor(crFactor) -- level 3 is neutral (multiplier = 1.00)
    local color = cropRotation.cache.fieldInfoDisplay.levels[level].color
    local text = cropRotation.cache.fieldInfoDisplay.levels[level].text

    fieldInfo.crFactor = crFactor -- update for PF's yieldChangeFunc (above)

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
--- Load/Save handlers
------------------------------------------------

function CropRotation:saveSavegame()
    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    if self.missionInfo.isValid then
        local xmlFile = createXMLFile(cropRotation.xmlName, cropRotation.xmlFilePath, cropRotation.xmlRootElement)
        if xmlFile ~= nil then
            cropRotation:saveToSavegame(xmlFile)

            saveXMLFile(xmlFile)
            delete(xmlFile)
        end
    end
end

function CropRotation:saveToSavegame(xmlFile)
    setXMLInt(xmlFile, "cropRotation.mapVersion", CropRotation.MAP_VERSION)

    if self.map ~= 0 then
        saveBitVectorMapToFile(self.map, self.mapFilePath)
    end

    -- TODO: self.planner:saveToSavegame(xmlFile)
end

function CropRotation:loadSavegame()
    if self.mission:getIsServer() and self.mission.missionInfo.savegameDirectory ~= nil then
        if fileExists(self.xmlFilePath) then
            local xmlFile = loadXMLFile(self.xmlName, self.xmlFilePath)
            if xmlFile ~= nil then
                self:loadFromSavegame(xmlFile)
                -- TODO: self.planner:loadFromSavegame(xmlFile)

                delete(xmlFile)
            end
        end
    end
end

function CropRotation:loadFromSavegame(xmlFile)
    local mapVersionKey = "cropRotation.mapVersion"
    if not hasXMLProperty(xmlFile, mapVersionKey) then
        self.isNewSavegame = true

        log("CropRotation:loadMap(): WARNING old version of mod was in use! Discarding crop rotation history.")
        return
    end

    local mapVersionLoaded = getXMLInt(xmlFile, mapVersionKey)
    if mapVersionLoaded and mapVersionLoaded < CropRotation.MAP_VERSION then
        self.isNewSavegame = true
        self.convertMapFromVersion = mapVersionLoaded

        log("CropRotation:loadMap(): INFO found old version of crop rotation map! Converting...")
    end
end

------------------------------------------------
--- Game initializing
------------------------------------------------

function CropRotation:load()
    self.data:load()

    self:loadCropRotationMap() --
    self:loadModifiers()

    local finalizer = function (target)
        if CropRotation.debug then
            log("CropRotation:finalizer(): job finished successfully!")
        end
    end

    self.densityMapUpdater:registerCallback("UpdateFallow", self.job_updateFallow, self, finalizer)
    self.densityMapUpdater:registerCallback("UpdateRegrow", self.job_updateRegrow, self, finalizer)

    self.messageCenter:subscribe(MessageType.YEAR_CHANGED, self.onYearChanged, self)
    self.messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
end

function CropRotation:onTerrainLoaded(mission, terrainId, mapFilename)
    self.terrainSize = self.mission.terrainSize
end

function CropRotation:loadCropRotationMap()
    self.map = createBitVectorMap(self.mapName)
    local success = false

    if self.mission.missionInfo.isValid then
        if fileExists(self.mapFilePath) and not self.isNewSavegame then
            success = loadBitVectorMapFromFile(self.map, self.mapFilePath, CropRotation.MAP_NUM_CHANNELS)
        end
    end

    if not success then
        local size = getDensityMapSize(self.mission.terrainDetailId)
        loadBitVectorMapNew(self.map, size, size, CropRotation.MAP_NUM_CHANNELS, false)
    end

    self.mapSize = getBitVectorMapSize(self.map)
end

function CropRotation:loadModifiers()
    -- M:12 = [R2:5][R1:5][F:1][H:1]
    local modifiers = {}

    modifiers.map = {}
    modifiers.map.modifier = DensityMapModifier.new(self.map, 0, CropRotation.MAP_NUM_CHANNELS)
    modifiers.map.modifier:setPolygonRoundingMode(DensityRoundingMode.INCLUSIVE)
    modifiers.map.filter = DensityMapFilter.new(modifiers.map.modifier)

    modifiers.map.modifierR2 = DensityMapModifier.new(self.map, 7, 5)
    modifiers.map.filterR2 = DensityMapFilter.new(modifiers.map.modifierR2)

    modifiers.map.modifierR1 = DensityMapModifier.new(self.map, 2, 5)
    modifiers.map.filterR1 = DensityMapFilter.new(modifiers.map.modifierR1)

    modifiers.map.modifierF = DensityMapModifier.new(self.map, 1, 1)
    modifiers.map.filterF = DensityMapFilter.new(modifiers.map.modifierF)
    modifiers.map.filterF:setValueCompareParams(DensityValueCompareType.EQUAL, 0)

    modifiers.map.modifierH = DensityMapModifier.new(self.map, 0, 1)
    modifiers.map.filterH = DensityMapFilter.new(modifiers.map.modifierH)
    modifiers.map.filterH:setValueCompareParams(DensityValueCompareType.EQUAL, 0)

    self.modifiers = modifiers
end

------------------------------------------------
--- Message Center Event handlers
------------------------------------------------

function CropRotation:onYearChanged(newYear)
    self.densityMapUpdater:schedule("UpdateFallow")
end

function CropRotation:onPeriodChanged(newPeriod)
    log("CropRotation:onPeriodChanged(): newPeriod =", newPeriod)
    -- TODO run it quaterly
    self.densityMapUpdater:schedule("UpdateRegrow")
end

------------------------------------------------
--- Density Map Updater periodic job
------------------------------------------------

-- yearly fallow bit update on parallelogram(start, width, height)
function CropRotation:job_updateFallow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local terrainSize = self.terrainSize
    local mapModifiers = self.modifiers.map

    mapModifiers.modifierR1:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                     startWorldZ / terrainSize + 0.5,
                                                     widthWorldX / terrainSize + 0.5,
                                                     widthWorldZ / terrainSize + 0.5,
                                                     heightWorldX / terrainSize + 0.5,
                                                     heightWorldZ / terrainSize + 0.5,
                                                     DensityCoordType.POINT_POINT_POINT)
    mapModifiers.modifierR2:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                     startWorldZ / terrainSize + 0.5,
                                                     widthWorldX / terrainSize + 0.5,
                                                     widthWorldZ / terrainSize + 0.5,
                                                     heightWorldX / terrainSize + 0.5,
                                                     heightWorldZ / terrainSize + 0.5,
                                                     DensityCoordType.POINT_POINT_POINT)

    for i = 0, self.numFruits do
        mapModifiers.filterR1:setValueCompareParams(DensityValueCompareType.EQUAL, i)
        mapModifiers.modifierR2:executeSet(i, mapModifiers.filterF, mapModifiers.filterR1)
        mapModifiers.modifierR1:executeSet(FruitType.UNKNOWN, mapModifiers.filterF, mapModifiers.filterR1)
    end

    mapModifiers.modifierF:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                    startWorldZ / terrainSize + 0.5,
                                                    widthWorldX / terrainSize + 0.5,
                                                    widthWorldZ / terrainSize + 0.5,
                                                    heightWorldX / terrainSize + 0.5,
                                                    heightWorldZ / terrainSize + 0.5,
                                                    DensityCoordType.POINT_POINT_POINT)
    mapModifiers.modifierF:executeSet(0)
end

function CropRotation:job_updateRegrow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local terrainSize = self.terrainSize
    local mapModifiers = self.modifiers.map

    for i, desc in pairs(self.fruitTypeManager:getFruitTypes()) do
        if desc.regrows then
            mapModifiers.filterR1:setValueCompareParams(DensityValueCompareType.EQUAL, i)
            mapModifiers.modifierH:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                            startWorldZ / terrainSize + 0.5,
                                                            widthWorldX / terrainSize + 0.5,
                                                            widthWorldZ / terrainSize + 0.5,
                                                            heightWorldX / terrainSize + 0.5,
                                                            heightWorldZ / terrainSize + 0.5,
                                                            DensityCoordType.POINT_POINT_POINT)
            mapModifiers.modifierH:executeSet(0, mapModifiers.filterR1)
        end
    end
end

------------------------------------------------
-- Injections to core game functions
------------------------------------------------

function CropRotation.inj_densityMapUtil_updateSowingArea(superFunc, fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, fieldGroundType, angle, growthState, blockedSprayTypeIndex)
    local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
    if fruitDesc and fruitDesc.rotation.enabled then -- TODO filter out crops that don't have crop rotation defined
        local cropRotation = g_cropRotation
        local modifiers = cropRotation.modifiers

        local terrainSize = cropRotation.terrainSize
        modifiers.map.modifierH:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                         startWorldZ / terrainSize + 0.5,
                                                         widthWorldX / terrainSize + 0.5,
                                                         widthWorldZ / terrainSize + 0.5,
                                                         heightWorldX / terrainSize + 0.5,
                                                         heightWorldZ / terrainSize + 0.5,
                                                         DensityCoordType.POINT_POINT_POINT)
        modifiers.map.modifierH:executeSet(0)
    end

    return superFunc(fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, fieldGroundType, angle, growthState, blockedSprayTypeIndex)
end

function CropRotation.inj_densityMapUtil_cutFruitArea(superFunc, fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, useMinForageState, excludedSprayType, setsWeeds, limitToField)
    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

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
        if CropRotation.debug then
            log(string.format("CropRotation:cutFruitArea(): WARNING: function cache missed for fruit index %d", fruitIndex))
        end

        fruitFilter = DensityMapFilter.new(desc.terrainDataPlaneId,
                                           desc.startStateChannel,
                                           desc.numStateChannels,
                                           g_currentMission.terrainRootNode)
        if functionData ~= nil and functionData.fruitFilters ~= nil then
            functionData.fruitFilters[fruitIndex] = fruitFilter
        end
    end

    local minState = desc.minHarvestingGrowthState
    if useMinForageState then
        minState = desc.minForageGrowthState
    end

    fruitFilter:setValueCompareParams(DensityValueCompareType.BETWEEN, minState, desc.maxHarvestingGrowthState)

    local prev, last, mapModifier = cropRotation:readFromMap(startWorldX, startWorldZ,
                                                             widthWorldX, widthWorldZ,
                                                             heightWorldX, heightWorldZ,
                                                             fruitFilter,
                                                             true) -- skipWhenHarvested
    local yieldMultiplier = 1
    if prev ~= -1 or last ~= -1 then
        -- Calculate the multiplier
        yieldMultiplier = cropRotation:getRotationYieldMultiplier(prev, last, fruitIndex)

        prev = last
        last = fruitIndex

        local fallow = 1
        local harvest = 1

        local bits = cropRotation:encode(prev, last, fallow, harvest)
        mapModifier:executeSet(bits, fruitFilter, cropRotation.modifiers.map.filterH)
    end

    local numPixels, totalNumPixels, sprayFactor, plowFactor, limeFactor, weedFactor, stubbleFactor, rollerFactor, beeFactor, growthState, maxArea, terrainDetailPixelsSum =
        superFunc(fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, useMinForageState, excludedSprayType, setsWeeds, limitToField)

    -- Update yield with CR multiplier
    return numPixels * yieldMultiplier,
           totalNumPixels, sprayFactor, plowFactor, limeFactor, weedFactor, stubbleFactor, rollerFactor, beeFactor, growthState, maxArea, terrainDetailPixelsSum
end

------------------------------------------------
-- Reading and writing
------------------------------------------------
-- [R2:5][R1:5][F:1][H:1]

function CropRotation:decode(bits)
    local previous = bitShiftRight(bitAND(bits, 3968), 7)
    local last = bitShiftRight(bitAND(bits, 124), 2)
    local fallow = bitShiftRight(bitAND(bits, 2), 1)
    local harvest = bitAND(bits, 1)

    return previous, last, fallow, harvest
end

function CropRotation:encode(previous, last, fallow, harvest)
    return bitShiftLeft(previous, 7) + bitShiftLeft(last, 2) + bitShiftLeft(fallow, 1) + harvest
end

---Read the forecrops and aftercrops from the map.
function CropRotation:readFromMap(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, filter, skipWhenHarvested)
    local terrainSize = self.terrainSize
    local r2, r1 = -1, -1

    local mapModifiers = self.modifiers.map

    -- Read value from CR map
    local mapModifier = mapModifiers.modifier
    mapModifier:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                         startWorldZ / terrainSize + 0.5,
                                         widthWorldX / terrainSize + 0.5,
                                         widthWorldZ / terrainSize + 0.5,
                                         heightWorldX / terrainSize + 0.5,
                                         heightWorldZ / terrainSize + 0.5,
                                         DensityCoordType.POINT_POINT_POINT)

    mapModifiers.modifierR2:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                     startWorldZ / terrainSize + 0.5,
                                                     widthWorldX / terrainSize + 0.5,
                                                     widthWorldZ / terrainSize + 0.5,
                                                     heightWorldX / terrainSize + 0.5,
                                                     heightWorldZ / terrainSize + 0.5,
                                                     DensityCoordType.POINT_POINT_POINT)

    -- OPTIMIZATION: g_cropRotation.cache.readFromMap.previousCrop = PREVIOUS_CROP_RECENTLY_FOUND or UNKNOWN
    -- if area(cache.previousCrop) >= 1/2 proceed, else: do search, update cache
    mapModifiers.filterR2:setValueCompareParams(DensityValueCompareType.EQUAL, self.cache.readFromMap.previousCrop)

    local area, totalArea

    if skipWhenHarvested then
        _, area, totalArea = mapModifiers.modifierR2:executeGet(filter, mapModifiers.filterH, mapModifiers.filterR2)
    else
        _, area, totalArea = mapModifiers.modifierR2:executeGet(filter, mapModifiers.filterR2)
    end

    if area >= totalArea * 0.5 then
        r2 = self.cache.readFromMap.previousCrop
    else
        local maxArea = 0
        for i = 0, self.numFruits do
            mapModifiers.filterR2:setValueCompareParams(DensityValueCompareType.EQUAL, i)

            local area, totalArea
            if skipWhenHarvested then
                acc, area, totalArea = mapModifiers.modifierR2:executeGet(filter, mapModifiers.filterH, mapModifiers.filterR2)
            else
                acc, area, totalArea = mapModifiers.modifierR2:executeGet(filter, mapModifiers.filterR2)
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

    mapModifiers.modifierR1:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                     startWorldZ / terrainSize + 0.5,
                                                     widthWorldX / terrainSize + 0.5,
                                                     widthWorldZ / terrainSize + 0.5,
                                                     heightWorldX / terrainSize + 0.5,
                                                     heightWorldZ / terrainSize + 0.5,
                                                     DensityCoordType.POINT_POINT_POINT)

    -- OPTIMIZATION: g_cropRotation.cache.readFromMap.lastCrop = PREVIOUS_CROP_RECENTLY_FOUND or UNKNOWN
    mapModifiers.filterR1:setValueCompareParams(DensityValueCompareType.EQUAL, self.cache.readFromMap.lastCrop)

    local area, totalArea
    if skipWhenHarvested then
        _, area, totalArea = mapModifiers.modifierR1:executeGet(filter, mapModifiers.filterH, mapModifiers.filterR1)
    else
        _, area, totalArea = mapModifiers.modifierR1:executeGet(filter, mapModifiers.filterR1)
    end

    if area >= totalArea * 0.5 then
        r1 = self.cache.readFromMap.lastCrop
    else
        local maxArea = 0
        for i = 0, self.numFruits do
            mapModifiers.filterR1:setValueCompareParams(DensityValueCompareType.EQUAL, i)

            local area, totalArea
            if skipWhenHarvested then
                acc, area, totalArea = mapModifiers.modifierR1:executeGet(filter, mapModifiers.filterH, mapModifiers.filterR1)
            else
                acc, area, totalArea = mapModifiers.modifierR1:executeGet(filter, mapModifiers.filterR1)
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

    return r2, r1, mapModifier
end

-----------------------------------
-- Algorithms
-----------------------------------

function CropRotation:getRotationYieldMultiplier(prevIndex, lastIndex, currentIndex)
    local currentDesc = self.fruitTypeManager:getFruitTypeByIndex(currentIndex)

    local returnPeriod = self:getRotationReturnPeriodMultiplier(prevIndex, lastIndex, currentDesc)
	local forecrops = self:getRotationForecropMultiplier(prevIndex, lastIndex, currentIndex)

    return returnPeriod * forecrops
end

function CropRotation:getRotationReturnPeriodMultiplier(prev, last, current)
    local returnPeriod = current.rotation.returnPeriod

    if returnPeriod == 3 then
        return 1 - (current.index == last and 0.1 or 0) - (current.index == prev and 0.05 or 0)
    end

    if returnPeriod == 2 then
        return  1 - ((current.index == last) and 0.05 or 0) - (current.index == prev and 0.05 or 0)
    end

    return 1.0
end

function CropRotation:getRotationForecropMultiplier(prevIndex, lastIndex, currentIndex)
    local prevValue = self.data:getRotationForecropValue(prevIndex, currentIndex)
    local lastValue = self.data:getRotationForecropValue(lastIndex, currentIndex)

    local prevFactor = -0.025 * prevValue ^ 2 + 0.125 * prevValue -- <0.0 ; 0.15>
    local lastFactor = -0.05 * lastValue ^ 2 + 0.25 * lastValue -- <0.0 ; 0.30>

    return 0.7 + (prevFactor + lastFactor) -- <0.7 ; 1.15>
end

-- input: list of crop indices: {11, 2, 3}
-- output: list of multipliers: {1.15, 1.1, 1.0}
function CropRotation:getRotationPlannerYieldMultipliers(input)
    if #input < 1 then return {} end

    result = {}
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
    local groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels = g_currentMission.fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)
    local groundFilter = DensityMapFilter.new(groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels)
    groundFilter:setValueCompareParams(DensityValueCompareType.GREATER, 0)

    local prev, last = self:readFromMap(startWorldX, startWorldZ,
                                                widthWorldX, widthWorldZ,
                                                heightWorldX, heightWorldZ,
                                                groundFilter,
                                                false)
    return prev, last
end

function CropRotation:getInfoAtWorldCoords(x, z)
    local worldToDensityMap = self.mapSize / self.mission.terrainSize

    local xi = math.floor((x + self.mission.terrainSize * 0.5) * worldToDensityMap)
    local zi = math.floor((z + self.mission.terrainSize * 0.5) * worldToDensityMap)

    local v = getBitVectorMapPoint(self.map, xi, zi, 0, CropRotation.MAP_NUM_CHANNELS)

    return self:decode(v) -- cropPrev, cropLast, fallowBit, harvestBit
end

function CropRotation:commandGetInfo()
    local x, _, z = getWorldTranslation(getCamera(0))

    local prev, last, f, h = self:getInfoAtWorldCoords(x, z)

    local getName = function (fruitIndex)
        if fruitIndex ~= FruitType.UNKNOWN then return g_fruitTypeManager:getFruitTypeByIndex(last).fillType.title end
        return g_i18n:getText("cropRotation_fallow")
    end

    log(string.format("crops: [last: %s(%d)] [previous: %s(%d)] bits: [Fallow: %d] [Harvest: %d]",
                      getName(last), last,
                      getName(prev), prev,
                      f,
                      h))
end

function CropRotation:commandPlanner(...)
    cropIndices = {}
    for i, name in pairs({...}) do
        crop = self.fruitTypeManager:getFruitTypeByName(name:upper()) or FruitType.UNKNOWN
        table.insert(cropIndices, crop.index)
    end

    result = self:getRotationPlannerYieldMultipliers(cropIndices)

    -- format the response
    for i, cropIndex in pairs(cropIndices) do
        if cropIndex == FruitType.UNKNOWN then
            log("FALLOW", "-")
        else
            crop = self.fruitTypeManager:getFruitTypeByIndex(cropIndex)
            log(string.format("%-20s %1.2f", crop.name, math.ceil(100*result[i])/100))
        end
    end
end

------------------------------------------------
-- Debugging
------------------------------------------------

function CropRotation:commandToggleVisualize()
    self.isVisualizeEnabled = not self.isVisualizeEnabled
end

function CropRotation:commandRunFallow()
    self.densityMapUpdater:schedule("UpdateFallow")
end

function CropRotation:commandSetFallow()
    local radius = 10

    local x, _, z = getWorldTranslation(getCamera(0))
    self:setFallow(x, z, radius, 1)
end

function CropRotation:commandClearFallow()
    local radius = 10

    local x, _, z = getWorldTranslation(getCamera(0))
    self:setFallow(x, z, radius, 0)
end

function CropRotation:commandSetHarvest()
    local radius = 10

    local x, _, z = getWorldTranslation(getCamera(0))
    self:setHarvest(x, z, radius, 1)
end

function CropRotation:commandClearHarvest()
    local radius = 10

    local x, _, z = getWorldTranslation(getCamera(0))
    self:setHarvest(x, z, radius, 0)
end

function CropRotation:setFallow(x, z, radius, bit)
    local terrainSize = self.mission.terrainSize
    local startWorldX = math.max(-terrainSize/2, x - radius)
    local startWorldZ = math.max(-terrainSize/2, z - radius)
    local widthWorldX = math.min(terrainSize/2, x + radius)
    local widthWorldZ = startWorldZ
    local heightWorldX = startWorldX
    local heightWorldZ = math.min(terrainSize/2, z + radius)

    local mapModifiers = self.modifiers.map
    mapModifiers.modifierF:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                    startWorldZ / terrainSize + 0.5,
                                                    widthWorldX / terrainSize + 0.5,
                                                    widthWorldZ / terrainSize + 0.5,
                                                    heightWorldX / terrainSize + 0.5,
                                                    heightWorldZ / terrainSize + 0.5,
                                                    DensityCoordType.POINT_POINT_POINT)
    mapModifiers.modifierF:executeSet(bit)
end

function CropRotation:setHarvest(x, z, radius, bit)
    local terrainSize = self.mission.terrainSize
    local startWorldX = math.max(-terrainSize/2, x - radius)
    local startWorldZ = math.max(-terrainSize/2, z - radius)
    local widthWorldX = math.min(terrainSize/2, x + radius)
    local widthWorldZ = startWorldZ
    local heightWorldX = startWorldX
    local heightWorldZ = math.min(terrainSize/2, z + radius)

    local mapModifiers = self.modifiers.map
    mapModifiers.modifierH:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                    startWorldZ / terrainSize + 0.5,
                                                    widthWorldX / terrainSize + 0.5,
                                                    widthWorldZ / terrainSize + 0.5,
                                                    heightWorldX / terrainSize + 0.5,
                                                    heightWorldZ / terrainSize + 0.5,
                                                    DensityCoordType.POINT_POINT_POINT)
    mapModifiers.modifierH:executeSet(bit)
end

function CropRotation:visualize()
    local mapSize = getBitVectorMapSize(self.map)
    local terrainSize = self.mission.terrainSize

    local worldToDensityMap = mapSize / terrainSize
    local densityToWorldMap = terrainSize / mapSize

    if self.map ~= 0 then
        local x,y,z = getWorldTranslation(getCamera(0))

        if self.mission.controlledVehicle ~= nil then
            local object = self.mission.controlledVehicle

            if self.mission.controlledVehicle.selectedImplement ~= nil then
                object = self.mission.controlledVehicle.selectedImplement.object
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
                local v = getBitVectorMapPoint(self.map, xi, zi, 0, CropRotation.MAP_NUM_CHANNELS)

                local x = (xi * densityToWorldMap) - terrainHalfSize
                local z = (zi * densityToWorldMap) - terrainHalfSize
                local y = getTerrainHeightAtWorldPos(self.mission.terrainRootNode, x,0,z) + 0.05

                local r2, r1, f, h = self:decode(v)

                local r,g,b = 1, f, h

                local text = string.format("%d,%d,%d,%d", r2, r1, f, h)
                Utils.renderTextAtWorldPosition(x, y, z, text, getCorrectTextSize(0.015), 0, {r, g, b, 1})
            end
        end
    end
end
