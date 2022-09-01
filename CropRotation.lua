--
-- FS22 Crop Rotation mod
--
-- CropRotation.lua
--
-- @Author: Bodzio528
-- @Version: 2.0.0.0

-- Changelog:
--  v2.0.0.0 (30.08.2022):
--      - code rewrite
-- 	v1.0.0.0 (03.08.2022):
--      - Initial release

-- TODO: check if this little piece of code is loaded properly
-- TODO: make it FS22_SoilCare mod
PF_ValueMap = FS22_precisionFarming.ValueMap

BiomassMap = {
    MAP_NUM_CHANNELS = 3
}

BiomassMap_mt = Class(BiomassMap, PF_ValueMap)

function BiomassMap.new(pfModule, customMt)
    local self = PF_ValueMap.new(pfModule, customMt or BiomassMap_mt)

    return self
end

CropRotation = {
    MOD_NAME = g_currentModName or "FS22_PF_CropRotation",
    MOD_DIRECTORY = g_currentModDirectory,
    MAP_NUM_CHANNELS = 12 -- [R2:5][R1:5][F:1][H:1]

    --[[
    [D:1] lvl-up due to liquid manure/digestate
    [M:1] lvl-up due to manure
    [L:1] lvl-up due to green biomass (harvest leftovers)

    BIT MAPPING
    [R2:5] crop that was growing two harvests ago
    [R1:5] crop that was growing before current crop
    [F:1] fallow bit
    [H:1] harvest bit
    ]]--
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

CropRotation.debug = true -- false --

function overwrittenStaticFunction(object, funcName, newFunc)
    local oldFunc = object[funcName]
    object[funcName] = function (...)
        return newFunc(oldFunc, ...)
    end
end

function CropRotation:new(mission, modDirectory, messageCenter, fruitTypeManager, i18n, data, dms)
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

    self.densityMapScanner = dms

    self.numFruits = math.min(31, #self.fruitTypeManager:getFruitTypes())
    self.isVisualizeEnabled = false

    overwrittenStaticFunction(FSDensityMapUtil, "updateSowingArea", CropRotation.inj_densityMapUtil_updateSowingArea)
    overwrittenStaticFunction(FSDensityMapUtil, "updateDirectSowingArea", CropRotation.inj_densityMapUtil_updateSowingArea)
    overwrittenStaticFunction(FSDensityMapUtil, "cutFruitArea", CropRotation.inj_densityMapUtil_cutFruitArea)

    addConsoleCommand("crInfo", "Get crop rotation info", "commandGetInfo", self)

    if CropRotation.debug then
        addConsoleCommand("crVisualizeToggle", "Toggle Crop Rotation visualization", "commandToggleVisualize", self)
    end

    if g_addCheatCommands then -- cheats enabled
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
    self.cache.fieldInfoDisplay.fruitNone = "-" -- "Żaden, Nic"

    self.cache.fieldInfoDisplay.currentTypeIndex = FruitType.UNKNOWN -- 0

    -- crop rotation fieldInfoDisplay level color and text
    local isColorBlindMode = g_gameSettings:getValue(GameSettings.SETTING.USE_COLORBLIND_MODE) or false

    self.cache.fieldInfoDisplay.levels = {}
    for level=0, 7 do
        local color = CropRotation.COLORS[level].color
        if isColorBlindMode then color = CropRotation.COLORS[level].colorBlind end

        local text = self.i18n:getText(CropRotation.COLORS[level].text)

        self.cache.fieldInfoDisplay.levels[level] = { color=color, text=text }
    end

    -- readFromMap smart cache
    self.cache.previousCrop = FruitType.UNKNOWN -- R2
    self.cache.lastCrop = FruitType.UNKNOWN -- R1
end

function CropRotation:delete()
    if self.map ~= 0 then
        delete(self.map)
    end

    self.densityMapScanner:unregisterCallback("UpdateFallow")

    if self.densityMapScanner ~= nil then
        delete(self.densityMapScanner)
        self.densityMapScanner = nil
    end

    removeConsoleCommand("crInfo")
    if g_addCheatCommands then
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

-- called on map loaded, eg. from savegame
function CropRotation:loadMap()
    if self.mission:getIsServer() and self.mission.missionInfo.savegameDirectory ~= nil then
        if fileExists(self.xmlFilePath) then
            local xmlFile = loadXMLFile(self.xmlName, self.xmlFilePath)
            if xmlFile ~= nil then
                delete(xmlFile)
            end
        end
    end

    -- ok, we got loading, now add savegame event handler
    FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, CropRotation.saveSavegame)

    -- extend PlayerHUDUpdater with crop rotation info
    if g_modIsLoaded[CropRotation.PrecisionFarming] then
        local l_precisionFarming = FS22_precisionFarming.g_precisionFarming
        if l_precisionFarming ~= nil then
            -- TODO: occupy two rows:
            -- 1st: forecrop and pre-forecrop
            -- 2nd: overall crop rotation performance
            l_precisionFarming.fieldInfoDisplayExtension:addFieldInfo(self.cache.fieldInfoDisplay.title,
                                                                      self,
                                                                      self.updateFieldInfoDisplay,
                                                                      4, -- prio,
                                                                      self.yieldChangeFunc)
        end

        PlayerHUDUpdater.fieldAddFruit = Utils.appendedFunction(PlayerHUDUpdater.fieldAddFruit, function(updater, data, box)
            -- capture fruit type that player is currently gazing at
            local cropRotation = g_cropRotation
            assert(cropRotation ~= nil)

            cropRotation.cache.fieldInfoDisplay.currentTypeIndex = data.fruitTypeMax or FruitType.UNKNOWN
        end)
    else -- simply add Crop Rotation Info to standard HUD
        PlayerHUDUpdater.fieldAddFruit = Utils.appendedFunction(PlayerHUDUpdater.fieldAddFruit, CropRotation.fieldAddFruit)
        PlayerHUDUpdater.updateFieldInfo = Utils.prependedFunction(PlayerHUDUpdater.updateFieldInfo, CropRotation.updateFieldInfo)
    end
end

---Called every frame update
function CropRotation:update(dt)
    if self.densityMapScanner ~= nil then
        self.densityMapScanner:update(dt)
    end

    if self.isVisualizeEnabled then
        self:visualize()
    end
end

------------------------------------------------
--- Player HUD Updater
------------------------------------------------

function CropRotation:updateFieldInfo(posX, posZ, rotY)
    if self.requestedFieldData then
        return
    end

    local cropRotation = g_cropRotation

--[[ -- TODO: replace with farmland owner filter
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
    local isColorBlindMode = g_gameSettings:getValue(GameSettings.SETTING.USE_COLORBLIND_MODE) or false

    local filter = GROUND_TYPE_FILTER - ground
    local n2, n1, _ = cropRotation:readFromMap(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ,
                                               filter,
                                               true,
                                               false)
--]]
    local prev, last = cropRotation:getInfoAtWorldCoords(posX, posZ)

    cropRotation.crFieldInfo = {
        prev = prev,
        last = last
    }

end

function CropRotation:fieldAddFruit(data, box)
    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    if cropRotation.crFieldInfo ~= nil then
        local crYieldMultiplier = cropRotation:getRotationYieldMultiplier(cropRotation.crFieldInfo.previous,
                                                                          cropRotation.crFieldInfo.last,
                                                                          data.fruitTypeMax)
        local level = CropRotation.getLevelByMultiplier(crYieldMultiplier)

        local color, text = cropRotation.cache.fieldInfoDisplay.levels[level]
        local title = cropRotation.cache.fieldInfoDisplay.title

        box:addLine(string.format("%s (%s)", title, text),
                    string.format("%d %%", math.floor(100 * crYieldMultiplier)),
                    true, -- use color
                    color)
        box:addLine(g_i18n:getText("cropRotation_hud_fieldInfo_previous"),
                    string.format("%s | %s", cropRotation:getCategoryName(cropRotation.crFieldInfo.last),
                                             cropRotation:getCategoryName(cropRotation.crFieldInfo.previous)))
    end
end

------------------------------------------------
--- PrecisionFarming Player HUD Updater
------------------------------------------------
function CropRotation:yieldChangeFunc(fieldInfo)
    local crFactor = fieldInfo.crFactor or 1.00 -- default is 100%

    -- crFactor is between 1.15 and 0.80

    return 10.0 * (crFactor-1.0), -- factor here should be in <-3;+2> range
           0.20, --  proportion -> (-30% | +20%)
           fieldInfo.yieldPotential or 1, -- _yieldPotential
           fieldInfo.yieldPotentialToHa or 0 --  _yieldPotentialToHa
end

function CropRotation:updateFieldInfoDisplay(fieldInfo, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, isColorBlindMode)
    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    -- Read CR data
    local prevIndex, lastIndex, f, harvestBit = cropRotation:getInfoAtWorldCoords(startWorldX, startWorldZ) -- TODO: change to ReadFromMap(sx,sz,wx,wz,hx,hz)

    local getFruitTitle = function(index)
        if index ~= FruitType.UNKNOWN then
            return g_fruitTypeManager:getFruitTypeByIndex(lastIndex).fillType.title
        end
        return cropRotation.cache.fieldInfoDisplay.fruitNone
    end

    local value = string.format("%s | %s", getFruitTitle(lastIndex), getFruitTitle(prevIndex))

    local currentIndex = cropRotation.cache.fieldInfoDisplay.currentTypeIndex
    if currentIndex == FruitType.UNKNOWN or harvestBit then
        return value, nil, nil
    end

    fieldInfo.crFactor = cropRotation:getRotationYieldMultiplier(prevIndex, lastIndex, currentIndex)
    -- TODO: * cropRotation:getSoilConditionYieldMultiplier()
    -- TODO: read BiomassMap for level!

    local level = cropRotation:getLevelByCrFactor(fieldInfo.crFactor) -- level 3 is neutral (multiplier = 1.00)
    local color = cropRotation.cache.fieldInfoDisplay.levels[level].color

    --local text = cropRotation.cache.fieldInfoDisplay.levels[level].text

    return value, color, string.format("%d %%", math.floor(crFactor*100))
end

function CropRotation:getLevelByCrFactor(factor)
    if factor > 1.10 then return 0 end
    if factor > 1.05 then return 1 end
    if factor > 1.00 then return 2 end
    if factor > 0.95 then return 3 end
    if factor > 0.90 then return 4 end
    if factor > 0.85 then return 5 end
    if factor > 0.80 then return 6 end
    return 7
end

------------------------------------------------
--- Save game
------------------------------------------------

-- cropRotation.xml is place where crop rotation planner (TODO) will store its data
-- this function is injected
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
    if self.map ~= 0 then
        saveBitVectorMapToFile(self.map, self.mapFilePath)
    end
end

------------------------------------------------
--- Load game
------------------------------------------------

function CropRotation:load()
    self.data:load()

    self:loadModifiers()

    local fallowFinalizer = function (target, parameters)
        if CropRotation.debug then
            log("CropRotation:finalizer(Fallow): job finished successfully!")
        end
    end

    self.densityMapScanner:registerCallback("UpdateFallow", self.dms_updateFallow, self, fallowFinalizer, false)

    self.messageCenter:subscribe(MessageType.YEAR_CHANGED, self.onYearChanged, self)
    self.messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
end

function CropRotation:onTerrainLoaded(mission, terrainId, mapFilename)
    self.terrainSize = self.mission.terrainSize

    self:loadCropRotationMap()
    self:loadModifiers()
end

function CropRotation:loadCropRotationMap()
    self.map = createBitVectorMap(self.mapName)
    local success = false

    if self.mission.missionInfo.isValid then
        if fileExists(self.mapFilePath) then
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

-- periodic event handlers (subscribed in constructor)
function CropRotation:onYearChanged(newYear)
    log(string.format("CropRotation:onYearChanged(): year = %d", newYear))
    self.densityMapScanner:schedule("UpdateFallow")
end

function CropRotation:onPeriodChanged(newPeriod)
    log(string.format("CropRotation:onPeriodChanged(): period = %d", newPeriod))
end

function CropRotation:onDayChanged(newDay)
    log(string.format("CropRotation:onDayChanged(): month = %d", newDay))
end

------------------------------------------------
--- Density Map Updater callback (job)
------------------------------------------------

-- yearly fallow bit update on parallelogram(start, width, height)
function CropRotation:dms_updateFallow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
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

------------------------------------------------
-- Injections to core game functions
------------------------------------------------

---Reset harvest bit on sowing
function CropRotation.inj_densityMapUtil_updateSowingArea(superFunc, fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, fieldGroundType, angle, growthState, blockedSprayTypeIndex)
    if true or fruitIndex.rotation ~= nil then -- TODO filter out crops that don't have crop rotation defined
        local cropRotation = g_cropRotation
        local modifiers = cropRotation.modifiers

        -- Set harvest bit to 0
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

    -- Do the actual sowing
    return superFunc(fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, fieldGroundType, angle, growthState, blockedSprayTypeIndex)
end

---Update the rotation map on harvest
function CropRotation.inj_densityMapUtil_cutFruitArea(superFunc, fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, useMinForageState, excludedSprayType, setsWeeds, limitToField)
    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    -- Get fruit info
    local desc = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
    if desc.terrainDataPlaneId == nil then
        return 0
    end

    local fruitFilter = nil

    -- get the function cache
    local functionData = FSDensityMapUtil.functionCache.cutFruitArea
    if functionData ~= nil and functionData.fruitFilters ~= nil then
        fruitFilter = functionData.fruitFilters[fruitIndex]
    end

    -- we have missed the cache - create filter manually and store inside cache for future use
    if fruitFilter == nil then
        if CropRotation.debug then
            log(string.format("CropRotation:cutFruitArea() WARNING: function cache missed for fruit index %d", fruitIndex))
        end

        fruitFilter = DensityMapFilter.new(desc.terrainDataPlaneId,
                                           desc.startStateChannel,
                                           desc.numStateChannels,
                                           g_currentMission.terrainRootNode)
        if functionData ~= nil and functionData.fruitFilters ~= nil then
            functionData.fruitFilters[fruitIndex] = fruitFilter
        end
    end

    -- override minimum harvesting growth state when foraging
    local minState = desc.minHarvestingGrowthState
    if useMinForageState then
        minState = desc.minForageGrowthState
    end

    -- Filter on fruit to limit bad hits like grass borders
    fruitFilter:setValueCompareParams(DensityValueCompareType.BETWEEN, minState, desc.maxHarvestingGrowthState)

    -- Read Crop Rotation data
    local r2, r1, mapModifier = cropRotation:readFromMap(startWorldX,
                                                         startWorldZ,
                                                         widthWorldX,
                                                         widthWorldZ,
                                                         heightWorldX,
                                                         heightWorldZ,
                                                         fruitFilter,
                                                         true, -- skipWhenHarvested
                                                         false) -- r1 only
                                                         -- OPTIMIZATION: pass-in self(vehicle/cutter).cache.cropRotation object

    local yieldMultiplier = 1

    if r2 ~= -1 or r1 ~= -1 then
        -- Calculate the multiplier
        yieldMultiplier = cropRotation:getRotationYieldMultiplier(r2, r1, fruitIndex)

        if CropRotation.debug then
            log(string.format("CropRotation:cutFruitArea(): yieldMultiplier = %f", yieldMultiplier))
        end

        -- Then update the values: [previous] = [last], [last] = current, [fallow] = 1
        r2 = r1
        r1 = fruitIndex
        f = 1
        h = 1

        local bits = cropRotation:encode(r2, r1, f, h)
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

function CropRotation:decode(bits)
    -- [R2:5][R1:5][F:1][H:1]
    local previous = bitShiftRight(bitAND(bits, 3968), 7)
    local last = bitShiftRight(bitAND(bits, 124), 2)
    local fallow = bitShiftRight(bitAND(bits, 2), 1)
    local harvest = bitAND(bits, 1)

    return previous, last, fallow, harvest
end

function CropRotation:encode(previous, last, fallow, harvest)
    -- [R2:5][R1:5][F:1][H:1]
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

    -- OPTIMIZATION: g_cropRotation.cache.previousCrop = PREVIOUS_CROP_RECENTLY_FOUND or UNKNOWN
    -- if area(cache.previousCrop) >= 1/2 proceed, else: do search, update cache
    mapModifiers.filterR2:setValueCompareParams(DensityValueCompareType.EQUAL, self.cache.previousCrop)

    local area, totalArea

    if skipWhenHarvested then
        _, area, totalArea = mapModifiers.modifierR2:executeGet(filter, mapModifiers.filterH, mapModifiers.filterR2)
    else
        _, area, totalArea = mapModifiers.modifierR2:executeGet(filter, mapModifiers.filterR2)
    end

    if area >= totalArea * 0.5 then
        r2 = self.cache.previousCrop
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
                self.cache.previousCrop = i -- update function cache
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

    -- OPTIMIZATION: g_cropRotation.cache.lastCrop = PREVIOUS_CROP_RECENTLY_FOUND or UNKNOWN
    mapModifiers.filterR1:setValueCompareParams(DensityValueCompareType.EQUAL, self.cache.lastCrop)

    local area, totalArea
    if skipWhenHarvested then
        _, area, totalArea = mapModifiers.modifierR1:executeGet(filter, mapModifiers.filterH, mapModifiers.filterR1)
    else
        _, area, totalArea = mapModifiers.modifierR1:executeGet(filter, mapModifiers.filterR1)
    end

    if area >= totalArea * 0.5 then
        r1 = self.cache.lastCrop
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
                self.cache.lastCrop = i -- update function cache
                break
            end
        end
    end

    return r2, r1, mapModifier
end

-----------------------------------
-- Algorithms
-----------------------------------

---Calculate the yield multiplier based on the soil condition
-- TODO: move to BiomassMap
function CropRotation:getSoilConditionYieldMultiplier(v)
    --[[
    F(v) = v^3/500 - v^2/50 - v/125 + 1.15

    F(perfect) = 1.15
    F(good_2) = 1.125
    F(good_1) = 1.07
    F(ok_2) = 1.0
    F(ok_1) = 0.93
    F(bad_3) = 0.86
    F(bad_2) = 0.815
    F(bad_1) = 0.8
    --]]
    return 0.002 * v ^ 3 - 0.02 * v ^ 2 - 0.008 * v + 1.15
end

---Calculate the yield multiplier based on the crop history, fallow state, and harvested fruit type
function CropRotation:getRotationYieldMultiplier(prevIndex, lastIndex, currentIndex)
    local fruitDesc = self.fruitTypeManager:getFruitTypeByIndex(currentIndex)

    log(string.format("CropRotation:getRotationYieldMultiplier(): prevIndex = %d, lastIndex = %d, currentIndex = %d", prevIndex, lastIndex, currentIndex))

    return 1.2 -- TODO: make it work

    --[[
	local current = fruitDesc.rotation

	local returnPeriod = self:getRotationReturnPeriodMultiplier(prevIndex, lastIndex, currentIndex, fruitDesc)
	local rotationCategory = self:getRotationForecropMultiplier(prevIndex, lastIndex, currentIndex)

	return returnPeriod * rotationCategory
    --]]
end
function CropRotation:getRotationReturnPeriodMultiplier(prevIndex, lastIndex, currentIndex, fruitDesc)
    local returnPeriod = 3 -- fruitDesc.rotation.returnPeriod

    if returnPeriod == 2 then
        -- monoculture
        if prevIndex == lastIndex and lastIndex == currentIndex then
            return 0.9
        -- same as last
        elseif lastIndex == currentIndex then
            return 0.95
        end
    elseif returnPeriod == 3 then
        -- monoculture
        if prevIndex == lastIndex and lastIndex == currentIndex then
            return 0.85
        -- same as last
        elseif lastIndex == currentIndex then
            return 0.9
        -- 1 year gap
        elseif prevIndex == currentIndex and lastIndex ~= currentIndex then
            return 0.95
        end
    end

    return 1.0
end

---Calculate the rotation multiplier based on the previous 2 categories and the current one
function CropRotation:getRotationForecropMultiplier(prevIndex, lastIndex, currentIndex)
    local prevValue = self.data:getRotationForecropValue(prevIndex, currentIndex)
    local lastValue = self.data:getRotationForecropValue(lastIndex, currentIndex)

    local prevFactor = -0.02 * prevValue ^ 2 + 0.10 * prevValue + 0.92
    local lastFactor = -0.05 * lastValue ^ 2 + 0.25 * lastValue + 0.80

    return prevFactor * lastFactor
end

------------------------------------------------
-- Getting info
------------------------------------------------

--- Read map at given position
function CropRotation:getInfoAtWorldCoords(x, z)
    local worldToDensityMap = self.mapSize / self.mission.terrainSize

    local xi = math.floor((x + self.mission.terrainSize * 0.5) * worldToDensityMap)
    local zi = math.floor((z + self.mission.terrainSize * 0.5) * worldToDensityMap)

    local v = getBitVectorMapPoint(self.map, xi, zi, 0, CropRotation.MAP_NUM_CHANNELS)

    local cropPrev, cropLast, fallowBit, harvestBit = self:decode(v)

    return cropPrev, cropLast, fallowBit, harvestBit
end

function CropRotation:commandGetInfo()
    local x, _, z = getWorldTranslation(getCamera(0))

    local prev, last, f, h = self:getInfoAtWorldCoords(x, z)

    local getName = function (fruitIndex)
        if fruitIndex ~= FruitType.UNKNOWN then return g_fruitTypeManager:getFruitTypeByIndex(last).fillType.title end
        return "UNKNOWN" -- g_i18n:getText("FillType: None")
    end

    log(string.format("crops: [last: %s(%d)] [previous: %s(%d)] bits: [Fallow: %d] [Harvest: %d]",
                      getName(last), last,
                      getName(prev), prev,
                      f,
                      h))
end

------------------------------------------------
-- Debugging
------------------------------------------------

function CropRotation:commandRunFallow()
    self.densityMapScanner:schedule("UpdateFallow")
end

function CropRotation:commandSetFallow()
    local x, _, z = getWorldTranslation(getCamera(0))
    self:setFallow(x, z, 1)
end

function CropRotation:commandClearFallow()
    local x, _, z = getWorldTranslation(getCamera(0))
    self:setFallow(x, z, 0)
end

function CropRotation:commandSetHarvest()
    local x, _, z = getWorldTranslation(getCamera(0))
    self:setHarvest(x, z, 1)
end

function CropRotation:commandClearHarvest()
    local x, _, z = getWorldTranslation(getCamera(0))
    self:setHarvest(x, z, 0)
end

function CropRotation:commandToggleVisualize()
    self.isVisualizeEnabled = not self.isVisualizeEnabled
end

function CropRotation:setFallow(x, z, bit)
    local radius = 10
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

function CropRotation:setHarvest(x, z, bit)
    local radius = 10
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

                local r,g,b = 1, 0, h

                local text = string.format("%d,%d,%d,%d", r2, r1, f, h)
                Utils.renderTextAtWorldPosition(x, y, z, text, getCorrectTextSize(0.015), 0, {r, g, b, 1})
            end
        end
    end
end
