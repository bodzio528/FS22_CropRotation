--
-- FS22 - Crop Rotation mod
--
-- CropRotation.lua
--
-- @Author: Bodzio528
-- @Date: 03.08.2022
-- @Version: 1.0.0.0
--
-- Changelog:
-- 	v1.0.0.0 (03.08.2022):
--      - Initial release
--

CropRotation = {
    MOD_NAME = g_currentModName or "FS22_CropRotation",
    MOD_DIRECTORY = g_currentModDirectory
}

local CropRotation_mt = Class(CropRotation)

CropRotation.MAP_NUM_CHANNELS = 2 * 3 + 1 + 1 -- [n-2][n-1][f][h]
CropRotation.CATEGORIES = {
    FALLOW = 0,
    OILSEED = 1,
    CEREAL = 2,
    LEGUME = 3,
    ROOT = 4,
    NIGHTSHADE = 5,
    GRASS = 6
}
CropRotation.CATEGORIES_MAX = 6

CropRotation.PrecisionFarming = "FS22_precisionFarming"

CropRotation.COLORS = { -- TODO: rename to HUD_COLORS or sth like that
    [1] = {color = {0.0000, 0.4341, 0.0802, 1}, colorBlind={1.0000, 1.0000, 0.1000, 1}, text="cropRotation_hud_fieldInfo_perfect"}, -- perfect
    [2] = {color = {0.1329, 0.4735, 0.0296, 1}, colorBlind={0.8500, 0.8500, 0.1000, 1}, text="cropRotation_hud_fieldInfo_good"}, -- good
    [3] = {color = {0.3231, 0.4969, 0.0137, 1}, colorBlind={0.7500, 0.7500, 0.1000, 1}, text="cropRotation_hud_fieldInfo_ok"}, -- ok
    [4] = {color = {0.9910, 0.3231, 0.0000, 1}, colorBlind={0.4500, 0.4500, 0.1000, 1}, text="cropRotation_hud_fieldInfo_bad"} -- bad
}

CropRotation.debug = true -- false --

function overwrittenStaticFunction(object, funcName, newFunc)
    local oldFunc = object[funcName]
    object[funcName] = function (...)
        return newFunc(oldFunc, ...)
    end
end

function CropRotation:new(mission, messageCenter, fruitTypeManager, i18n, data, dms)
    local self = setmetatable({}, CropRotation_mt)

    self.isServer = mission:getIsServer()

    self.mission = mission
    self.messageCenter = messageCenter
    self.fruitTypeManager = fruitTypeManager
    self.i18n = i18n

    self.data = data

    self.densityMapScanner = dms

    overwrittenStaticFunction(FSDensityMapUtil, "updateSowingArea", CropRotation.inj_densityMapUtil_updateSowingArea)
    overwrittenStaticFunction(FSDensityMapUtil, "updateDirectSowingArea", CropRotation.inj_densityMapUtil_updateSowingArea)
    overwrittenStaticFunction(FSDensityMapUtil, "cutFruitArea", CropRotation.inj_densityMapUtil_cutFruitArea)

    addConsoleCommand("crInfo", "Get crop rotation info", "commandGetInfo", self)
    if g_addCheatCommands then -- cheats enabled
        addConsoleCommand("crFallowRun", "Run yearly fallow", "commandRunFallow", self)
        addConsoleCommand("crFallowSet", "Set fallow state", "commandSetFallow", self)
        addConsoleCommand("crFallowClear", "Clear fallow state", "commandClearFallow", self)
        addConsoleCommand("crHarvestSet", "Set harvest state", "commandSetHarvest", self)
        addConsoleCommand("crHarvestClear", "Clear harvest state", "commandClearHarvest", self)
    end

    return self
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
    print(string.format("CropRotation:loadMap(): called"))

    if self.mission:getIsServer() and self.mission.missionInfo.savegameDirectory ~= nil then
        local path = self.mission.missionInfo.savegameDirectory .. "/cropRotation.xml"

        if fileExists(path) then
            local xmlFile = loadXMLFile("CropRotationXML", path)
            print(string.format("CropRotation:loadMap(): CropRotationXML path = %s", path))

            if xmlFile ~= nil then
                print(string.format("CropRotation:loadMap(): CropRotationXML loading success"))
                self.densityMapScanner:loadFromSavegame(xmlFile)

                delete(xmlFile)
            end
        end
    end

    -- ok, we got loading, now add savegame event handler
    FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, CropRotation.saveSavegame)

    -- extend PlayerHUDUpdater with crop rotation info
    if g_modIsLoaded[CropRotation.PrecisionFarming] then
        print(string.format("CropRotation:loadMap(): Precision Farming mod is loaded!"))

        local l_precisionFarming = FS22_precisionFarming.g_precisionFarming
        if l_precisionFarming ~= nil then
            l_precisionFarming.fieldInfoDisplayExtension:addFieldInfo(g_i18n:getText("cropRotation_hud_fieldInfo_title"),
                                                                      self,
                                                                      self.updateFieldInfoDisplay,
                                                                      4, -- prio,
                                                                      self.yieldChangeFunc)
        end

        PlayerHUDUpdater.fieldAddFruit = Utils.appendedFunction(PlayerHUDUpdater.fieldAddFruit, function(updater, data, box)
            local cropRotation = g_cropRotation
            assert(cropRotation ~= nil)

            cropRotation.fruitTypeIndex = data.fruitTypeMax
        end)
    else
        -- simply add Crop Rotation Info to standard HUD
        print(string.format("CropRotation:loadMap(): append crop rotation to field info hud!"))
        PlayerHUDUpdater.fieldAddFruit = Utils.appendedFunction(PlayerHUDUpdater.fieldAddFruit, CropRotation.fieldAddFruit)
        -- PlayerHUDUpdater.updateFieldInfo = Utils.overwrittenFunction(PlayerHUDUpdater.updateFieldInfo, CropRotation.updateFieldInfo)

    end
end

---Called every frame update
function CropRotation:update(dt)
    if self.densityMapScanner ~= nil then
        self.densityMapScanner:update(dt)
    end

--     self:visualize()
end

------------------------------------------------
--- Player HUD Updater
------------------------------------------------

function CropRotation:updateFieldInfo(superFunc, posX, posZ, rotY)
    if self.requestedFieldData then
        return
    end

    superFunc(posX, posZ, rotY)

    local cropRotation = g_cropRotation


    self.cropRotationFieldInfo = {
        current = CropRotation.CATEGORIES.LEGUME,
        n1 = CropRotation.CATEGORIES.OILSEED,
        n2 = CropRotation.CATEGORIES.CEREAL
    }

-- 		local sizeX = 5
-- 		local sizeZ = 5
-- 		local distance = 2
-- 		local dirX, dirZ = MathUtil.getDirectionFromYRotation(rotY)
-- 		local sideX, _, sideZ = MathUtil.crossProduct(dirX, 0, dirZ, 0, 1, 0)
-- 		local startWorldX = posX - sideX * sizeX * 0.5 - dirX * distance
-- 		local startWorldZ = posZ - sideZ * sizeX * 0.5 - dirZ * distance
-- 		local widthWorldX = posX + sideX * sizeX * 0.5 - dirX * distance
-- 		local widthWorldZ = posZ + sideZ * sizeX * 0.5 - dirZ * distance
-- 		local heightWorldX = posX - sideX * sizeX * 0.5 - dirX * (distance + sizeZ)
-- 		local heightWorldZ = posZ - sideZ * sizeX * 0.5 - dirZ * (distance + sizeZ)
    local isColorBlindMode = g_gameSettings:getValue(GameSettings.SETTING.USE_COLORBLIND_MODE) or false

-- 		for i = 1, #self.fieldInfos do
-- 			local fieldInfo = self.fieldInfos[i]
-- 			fieldInfo.value, fieldInfo.color, fieldInfo.additionalText = fieldInfo.updateFunc(fieldInfo.object, fieldInfo, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, isColorBlindMode)
-- 		end
end


-- Show crop rotation info on player HUD without PRECISION FARMING (not tested yet)
function CropRotation:fieldAddFruit(data, box)
    print(string.format("CropRotation.fieldAddFruit(): data = %s, box = %s)", tostring(data), tostring(box)))

--     DebugUtil.printTableRecursively(data, "", 0, 0)

    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    local fruitTypeIndex = cropRotation.fruitTypeIndex
    self.cropRotationFieldInfo = {
        current = CropRotation.CATEGORIES.LEGUME,
        n1 = CropRotation.CATEGORIES.OILSEED,
        n2 = CropRotation.CATEGORIES.CEREAL
    }

    local crYieldMultiplier = cropRotation:getRotationYieldMultiplier(self.cropRotationFieldInfo.n2,
                                                                      self.cropRotationFieldInfo.n1,
                                                                      fruitTypeIndex)

    local level = 5 - math.min(4, math.max(1, math.floor(20*(crYieldMultiplier - 1.0)+4)))

    box:addLine(string.format("%s (%s)", g_i18n:getText("cropRotation_hud_fieldInfo_title"),
                                         g_i18n:getText(CropRotation.COLORS[level].text)),
                string.format("%d %s", math.floor(100 * crYieldMultiplier), "%"),
                true, -- use color
                CropRotation.COLORS[level].color)
    box:addLine(g_i18n:getText("cropRotation_hud_fieldInfo_previous"),
                string.format("%s | %s", g_cropRotation:getCategoryName(self.cropRotationFieldInfo.n1),
                                         g_cropRotation:getCategoryName(self.cropRotationFieldInfo.n2)))
end

-- PrecisionFarming Player HUD Updater
function CropRotation:yieldChangeFunc(fieldInfo)

    local crFactor = fieldInfo.crFactor or 1.00 -- default is 100%

    return math.max(-3, 10 * (crFactor - 1)), --factor in <-3;+2>
           0.20, --  proportion
           fieldInfo.yieldPotential or 1, -- _yieldPotential
           fieldInfo.yieldPotentialToHa or 0 --  _yieldPotentialToHa
end

function CropRotation:updateFieldInfoDisplay(fieldInfo, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, isColorBlindMode)
    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    if cropRotation.fruitTypeIndex == nil then return end

    -- Read CR data
    local n2, n1 = cropRotation:getInfoAtWorldCoords(startWorldX, startWorldZ)

    fieldInfo.crFactor = cropRotation:getRotationYieldMultiplier(n2, n1, cropRotation.fruitTypeIndex)

    local level = 4
    if fieldInfo.crFactor >= 1.00 then
        level = 1 -- perfect
    elseif fieldInfo.crFactor >= 0.90 then
        level = 2 -- good
    elseif fieldInfo.crFactor >= 0.80 then
        level = 3 -- ok
    end -- < 0.80  4 -- bad

    local value = string.format("%s | %s", cropRotation:getCategoryName(n1),
                                           cropRotation:getCategoryName(n2))

    local color = CropRotation.COLORS[level].color
    if isColorBlindMode then color = CropRotation.COLORS[level].colorBlind end

    local additionalText = string.format("%d %s", math.floor(fieldInfo.crFactor * 100), "%")

    return value, color, additionalText
end

------------------------------------------------
--- Save game
------------------------------------------------

-- cropRotation.xml is place where crop rotation planner will store their data
function CropRotation:saveSavegame()
    print(string.format("FS22_CropRotation:saveSavegame(): called on save game!"))

    local cropRotation = g_cropRotation
    assert(cropRotation ~= nil)

    if self.missionInfo.isValid then
        local xmlFile = createXMLFile("CropRotationXML", self.missionInfo.savegameDirectory .. "/cropRotation.xml", "cropRotation")
        if xmlFile ~= nil then
            cropRotation:saveToSavegame(xmlFile)

            saveXMLFile(xmlFile)
            delete(xmlFile)
        end
    end
end

function CropRotation:saveToSavegame(xmlFile)
    self.densityMapScanner:saveToSavegame(xmlFile)

    local mapFilePath = self.mission.missionInfo.savegameDirectory .. "/cropRotation.grle"
    if self.map ~= 0 then
        saveBitVectorMapToFile(self.map, mapFilePath)
    end
end

------------------------------------------------
--- Load game
------------------------------------------------

function CropRotation:load()
    print(string.format("CropRotation:load(): %s", "has been called afer mission loading has finished"))

    self:loadModifiers()

    local finalizer = function (target, parameters)
        print(string.format("CropRotation:UpdateFellow:Finalizer(): target = %s parameters = %s", tostring(target), tostring(parameters)))
    end

    self.densityMapScanner:registerCallback("UpdateFallow", self.dms_updateFallow, self, finalizer, false)

    self.messageCenter:subscribe(MessageType.YEAR_CHANGED, self.onYearChanged, self)
end

function CropRotation:onMapLoaded(mission, node)
    print(string.format("CropRotation:onMapLoaded(mission, node): %s", "has been called - NOOP"))
end

function CropRotation:onTerrainLoaded(mission, terrainId, mapFilename)
    print(string.format("CropRotation:onTerrainLoaded(): has been called with terrainId = %s", tostring(terrainId)))

    self.terrainSize = self.mission.terrainSize

    self:loadCropRotationMap()
    self:loadModifiers()
end

function CropRotation:loadCropRotationMap() -- loadCropRotationDensityMap
    print(string.format("CropRotation:loadCropRotationMap(): %s", "has been called"))

    self.map = createBitVectorMap("cropRotation")
    local success = false

    if self.mission.missionInfo.isValid then
        local path = self.mission.missionInfo.savegameDirectory .. "/cropRotation.grle"
        print(string.format("CropRotation:loadCropRotationMap(): load from file - %s", tostring(path)))

        if fileExists(path) then
            success = loadBitVectorMapFromFile(self.map, path, CropRotation.MAP_NUM_CHANNELS)
        end
    end

    if not success then
        print(string.format("CropRotation:loadCropRotationMap(): init new densityMap - mission: %s, tdId: %s", tostring(self.mission), tostring(self.mission.terrainDetailId)))
        local size = getDensityMapSize(self.mission.terrainDetailId)
        loadBitVectorMapNew(self.map, size, size, CropRotation.MAP_NUM_CHANNELS, false)
    end

    self.mapSize = getBitVectorMapSize(self.map)
    print(string.format("CropRotation:loadCropRotationMap(): self.mapSize = %s", tostring(self.mapSize)))
end

function CropRotation:onMissionLoaded()
    print(string.format("CropRotation:onMissionLoaded(mission, node): %s", "has been called - NOOP"))

    print(string.format("CropRotation:onMissionLoaded() precisionFarming = %s", tostring(g_precisionFarming)))
end

function CropRotation:loadModifiers()
    print(string.format("CropRotation:loadModifiers(): %s", "has been called 20"))

    local modifiers = {}

    modifiers.map = {}
    modifiers.map.modifier = DensityMapModifier.new(self.map, 0, CropRotation.MAP_NUM_CHANNELS)
    modifiers.map.modifier:setPolygonRoundingMode(DensityRoundingMode.INCLUSIVE)
    modifiers.map.filter = DensityMapFilter.new(modifiers.map.modifier)

    modifiers.map.modifierN2 = DensityMapModifier.new(self.map, 5, 3)
    modifiers.map.filterN2 = DensityMapFilter.new(modifiers.map.modifierN2)

    modifiers.map.modifierN1 = DensityMapModifier.new(self.map, 2, 3)
    modifiers.map.filterN1 = DensityMapFilter.new(modifiers.map.modifierN1)

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
    if newYear == nil then newYear = 0 end
    print(string.format("CropRotation:onYearChanged(year = %s): %s", tostring(newYear),"called!"))

    self.densityMapScanner:queueJob("UpdateFallow")
end

------------------------------------------------
--- Density Map updater callback (job)
------------------------------------------------

-- yearly fallow bit update on parallelogram(start, width, height)
function CropRotation:dms_updateFallow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local terrainSize = self.terrainSize
    local mapModifiers = self.modifiers.map

    mapModifiers.modifierN1:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                     startWorldZ / terrainSize + 0.5,
                                                     widthWorldX / terrainSize + 0.5,
                                                     widthWorldZ / terrainSize + 0.5,
                                                     heightWorldX / terrainSize + 0.5,
                                                     heightWorldZ / terrainSize + 0.5,
                                                     DensityCoordType.POINT_POINT_POINT)
    mapModifiers.modifierN2:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                     startWorldZ / terrainSize + 0.5,
                                                     widthWorldX / terrainSize + 0.5,
                                                     widthWorldZ / terrainSize + 0.5,
                                                     heightWorldX / terrainSize + 0.5,
                                                     heightWorldZ / terrainSize + 0.5,
                                                     DensityCoordType.POINT_POINT_POINT)

    for i = 0, 6 do
        mapModifiers.filterN1:setValueCompareParams(DensityValueCompareType.EQUAL, i)

        -- Set [n2]=[n1]
        mapModifiers.modifierN2:executeSet(i, mapModifiers.filterF, mapModifiers.filterN1)

        -- Set [n1]=fallow
        mapModifiers.modifierN1:executeSet(CropRotation.CATEGORIES.FALLOW, mapModifiers.filterF, mapModifiers.filterN1)
    end

    -- Reset fallow map
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
    -- Oilseed ignores crop rotation
    if true then -- TODO filter on crops that have crop rotation defined, eg. fruitId ~= FruitType.OILSEEDRADISH
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

---Update the rotation map on harvest (or forage... perhaps the foraging should be made more damaging to the soil...)
function CropRotation.inj_densityMapUtil_cutFruitArea(superFunc, fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, useMinForageState, excludedSprayType, setsWeeds, limitToField)
    local cropRotation = g_cropRotation -- make CR module local

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

    if fruitFilter == nil then
        print("CropRotation:cutFruitArea(): WARNING: empty fruitFilter cache! Initializing fruit profile.")
        fruitFilter = DensityMapFilter.new(desc.terrainDataPlaneId,
                                           desc.startStateChannel,
                                           desc.numStateChannels,
                                           g_currentMission.terrainRootNode)
    end

    -- override minimal growth state when foraging
    local minState = desc.minHarvestingGrowthState
    if useMinForageState then
        minState = desc.minForageGrowthState
    end

    -- Filter on fruit to limit bad hits like grass borders
    fruitFilter:setValueCompareParams(DensityValueCompareType.BETWEEN, minState, desc.maxHarvestingGrowthState)

    -- Read Crop Rotation data
    local n2, n1, mapModifier = cropRotation:readFromMap(startWorldX,
                                                         startWorldZ,
                                                         widthWorldX,
                                                         widthWorldZ,
                                                         heightWorldX,
                                                         heightWorldZ,
                                                         fruitFilter,
                                                         true, -- skipWhenHarvested
                                                         false) -- n1 only

    local yieldMultiplier = 1

    -- When there is nothing read, don't do anything. It will be wrong.
    if n2 ~= -1 or n1 ~= -1 then
        -- Calculate the multiplier
        yieldMultiplier = cropRotation:getRotationYieldMultiplier(n2, n1, fruitIndex)

        -- Then update the values. Set [n-2] = [n-1], [n-1] = current, [f] = 1
        n2 = n1
        n1 = desc.rotation.category
        f = 1
        h = 1

        local bits = cropRotation:composeValues(n2, n1, f, h)

        -- Modifications have to be done sparsely, so when the harvester covers the next area the old values are still available (including h=0)
        mapModifier:executeSet(bits, fruitFilter, cropRotation.modifiers.map.filterH)

        print(string.format("[1] n2: %d n1: %d CRM: %f", n2, n1, yieldMultiplier))
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

function CropRotation:extractValues(bits)
    -- [n2:3][n1:3][f:1][h:1]

    local n2 = bitShiftRight(bitAND(bits, 224), 5)
    local n1 = bitShiftRight(bitAND(bits, 28), 2)
    local f = bitShiftRight(bitAND(bits, 2), 1)
    local h = bitAND(bits, 1)

    return n2, n1, f, h
end

function CropRotation:composeValues(n2, n1, f, h)
    return bitShiftLeft(n2, 5) + bitShiftLeft(n1, 2) + bitShiftLeft(f, 1) + h
end

---Read the n1 and n2 from the map.
function CropRotation:readFromMap(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, filter, skipWhenHarvested, n1Only)
    local terrainSize = self.terrainSize
    local n2, n1 = -1, -1

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
    local mapHarvestFilter = mapModifiers.filterH

    if not n1Only then
        mapModifiers.modifierN2:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                         startWorldZ / terrainSize + 0.5,
                                                         widthWorldX / terrainSize + 0.5,
                                                         widthWorldZ / terrainSize + 0.5,
                                                         heightWorldX / terrainSize + 0.5,
                                                         heightWorldZ / terrainSize + 0.5,
                                                         DensityCoordType.POINT_POINT_POINT)
        local maxArea = 0
        for i = 0, 6 do -- iterate over categories
            mapModifiers.filterN2:setValueCompareParams(DensityValueCompareType.EQUAL, i)

            local area, totalArea
            if skipWhenHarvested then
                _, area, totalArea = mapModifiers.modifierN2:executeGet(filter, mapHarvestFilter, mapModifiers.filterN2)
            else
                _, area, totalArea = mapModifiers.modifierN2:executeGet(filter, mapModifiers.filterN2)
            end

            if area > maxArea then
                maxArea = area
                n2 = i
            end

            -- Can't find anything larger if we are already at majority
            if area >= totalArea * 0.5 then
                break
            end
        end
    end

    mapModifiers.modifierN1:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                     startWorldZ / terrainSize + 0.5,
                                                     widthWorldX / terrainSize + 0.5,
                                                     widthWorldZ / terrainSize + 0.5,
                                                     heightWorldX / terrainSize + 0.5,
                                                     heightWorldZ / terrainSize + 0.5,
                                                     DensityCoordType.POINT_POINT_POINT)
    local maxArea = 0
    for i = 0, 6 do  -- iterate over categories
        mapModifiers.filterN1:setValueCompareParams(DensityValueCompareType.EQUAL, i)

        local area, totalArea
        if skipWhenHarvested then
            _, area, totalArea = mapModifiers.modifierN1:executeGet(filter, mapHarvestFilter, mapModifiers.filterN1)
        else
            _, area, totalArea = mapModifiers.modifierN1:executeGet(filter, mapModifiers.filterN1)
        end

        if area > maxArea then
            maxArea = area
            n1 = i
        end

        -- Can't find anything larger if we are already at majority
        if area >= totalArea * 0.5 then
            break
        end
    end

    return n2, n1, mapModifier
end

-----------------------------------
-- Algorithms
-----------------------------------

---Calculate the yield multiplier based on the crop history, fallow state, and harvested fruit type
function CropRotation:getRotationYieldMultiplier(n2, n1, fruitType)
    local fruitDesc = self.fruitTypeManager:getFruitTypeByIndex(fruitType)
    local current = fruitDesc.rotation.category

    local returnPeriod = self:getRotationReturnPeriodMultiplier(n2, n1, current, fruitDesc)
    local rotationCategory = self:getRotationCategoryMultiplier(n2, n1, current)

    return returnPeriod * rotationCategory
end

function CropRotation:getRotationReturnPeriodMultiplier(n2, n1, current, fruitDesc)
    if fruitDesc.rotation.returnPeriod == 2 then
        -- monoculture
        if n2 == n1 and n2 == current and n1 == current then
            return 0.9
        -- same as last
        elseif n1 == current then
            return 0.95
        end
    elseif fruitDesc.rotation.returnPeriod == 3 then
        -- monoculture
        if n2 == n1 and n2 == current and n1 == current then
            return 0.85
        -- same as last
        elseif n1 == current then
            return 0.9
        -- 1 year between
        elseif n2 == current and n1 ~= current then
            return 0.95
        end
    end

    return 1
end

---Calculate the rotation multiplier based on the previous 2 categories and the current one
function CropRotation:getRotationCategoryMultiplier(n2, n1, current)
    local n2Value = self.data:getRotationCategoryValue(n2, current)
    local n1Value = self.data:getRotationCategoryValue(n1, current)

    local n2Factor = -0.05 * n2Value ^ 2 + 0.2 * n2Value + 0.8
    local n1Factor = -0.025 * n1Value ^ 2 + 0.275 * n1Value + 0.75

    return n2Factor * n1Factor
end

------------------------------------------------
-- Getting info
------------------------------------------------

---Get the categories for given position
function CropRotation:getInfoAtWorldCoords(x, z)
    local worldToDensityMap = self.mapSize / self.mission.terrainSize

    local xi = math.floor((x + self.mission.terrainSize * 0.5) * worldToDensityMap)
    local zi = math.floor((z + self.mission.terrainSize * 0.5) * worldToDensityMap)

    local v = getBitVectorMapPoint(self.map, xi, zi, 0, CropRotation.MAP_NUM_CHANNELS)
    local n2, n1, f, h = self:extractValues(v)

    return n2, n1, f, h
end

---Get the translated name of the given category
function CropRotation:getCategoryName(category)
    return self.i18n:getText(string.format("cropRotation_Category_%d", category))
end

function CropRotation:commandGetInfo()
    local x, _, z = getWorldTranslation(getCamera(0))

    local n2, n1, f, h = self:getInfoAtWorldCoords(x, z)

    log(string.format("crops: [last: %s] [previous: %s] perf: [index: %d] bits: [Fallow: %d] [Harvest: %d]",
                      self:getCategoryName(n1),
                      self:getCategoryName(n2),
                      self.data:getRotationCategoryValue(n2, n1),
                      f,
                      h))
end

------------------------------------------------
-- Debugging
------------------------------------------------

function CropRotation:commandRunFallow()
    self.densityMapScanner:queueJob("UpdateFallow")
end

function CropRotation:commandSetFallow()
    local x, _, z = getWorldTranslation(getCamera(0))

    local radius = 10
    local terrainSize = self.mission.terrainSize

    local mapModifiers = self.modifiers.map

    local startWorldX = math.max(-terrainSize/2, x - radius)
    local startWorldZ = math.max(-terrainSize/2, z - radius)

    local widthWorldX = math.min(terrainSize/2, x + radius)
    local widthWorldZ = startWorldZ

    local heightWorldX = startWorldX
    local heightWorldZ = math.min(terrainSize/2, z + radius)

    -- Reset fallow map
    mapModifiers.modifierF:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                    startWorldZ / terrainSize + 0.5,
                                                    widthWorldX / terrainSize + 0.5,
                                                    widthWorldZ / terrainSize + 0.5,
                                                    heightWorldX / terrainSize + 0.5,
                                                    heightWorldZ / terrainSize + 0.5,
                                                    DensityCoordType.POINT_POINT_POINT)
    mapModifiers.modifierF:executeSet(1)
end

function CropRotation:commandSetHarvest()
    local x, _, z = getWorldTranslation(getCamera(0))

    local radius = 10
    local terrainSize = self.mission.terrainSize

    local mapModifiers = self.modifiers.map

    local startWorldX = math.max(-terrainSize/2, x - radius)
    local startWorldZ = math.max(-terrainSize/2, z - radius)

    local widthWorldX = math.min(terrainSize/2, x + radius)
    local widthWorldZ = startWorldZ

    local heightWorldX = startWorldX
    local heightWorldZ = math.min(terrainSize/2, z + radius)

    -- Reset fallow map
    mapModifiers.modifierH:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                    startWorldZ / terrainSize + 0.5,
                                                    widthWorldX / terrainSize + 0.5,
                                                    widthWorldZ / terrainSize + 0.5,
                                                    heightWorldX / terrainSize + 0.5,
                                                    heightWorldZ / terrainSize + 0.5,
                                                    DensityCoordType.POINT_POINT_POINT)
    mapModifiers.modifierH:executeSet(1)
end

function CropRotation:commandClearHarvest()
    local x, _, z = getWorldTranslation(getCamera(0))

    local radius = 10
    local terrainSize = self.mission.terrainSize

    local mapModifiers = self.modifiers.map

    local startWorldX = math.max(-terrainSize/2, x - radius)
    local startWorldZ = math.max(-terrainSize/2, z - radius)

    local widthWorldX = math.min(terrainSize/2, x + radius)
    local widthWorldZ = startWorldZ

    local heightWorldX = startWorldX
    local heightWorldZ = math.min(terrainSize/2, z + radius)

    -- Set harvest bit on map
    mapModifiers.modifierH:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                    startWorldZ / terrainSize + 0.5,
                                                    widthWorldX / terrainSize + 0.5,
                                                    widthWorldZ / terrainSize + 0.5,
                                                    heightWorldX / terrainSize + 0.5,
                                                    heightWorldZ / terrainSize + 0.5,
                                                    DensityCoordType.POINT_POINT_POINT)
    mapModifiers.modifierH:executeSet(0)
end
function CropRotation:commandClearFallow()
    local x, _, z = getWorldTranslation(getCamera(0))

    local radius = 10
    local terrainSize = self.mission.terrainSize

    local mapModifiers = self.modifiers.map

    local startWorldX = math.max(-terrainSize/2, x - radius)
    local startWorldZ = math.max(-terrainSize/2, z - radius)

    local widthWorldX = math.min(terrainSize/2, x + radius)
    local widthWorldZ = startWorldZ

    local heightWorldX = startWorldX
    local heightWorldZ = math.min(terrainSize/2, z + radius)

    -- Clear harvest bit on map
    mapModifiers.modifierF:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                    startWorldZ / terrainSize + 0.5,
                                                    widthWorldX / terrainSize + 0.5,
                                                    widthWorldZ / terrainSize + 0.5,
                                                    heightWorldX / terrainSize + 0.5,
                                                    heightWorldZ / terrainSize + 0.5,
                                                    DensityCoordType.POINT_POINT_POINT)
    mapModifiers.modifierF:executeSet(0)
end

-- borrowed from FS19_RM_Seasons mod
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

                local n2, n1, f, h = self:extractValues(v)

                local r,g,b = 1, 0, h

                local text = string.format("%d,%d,%d,%d", n2, n1, f, h)
                Utils.renderTextAtWorldPosition(x, y, z, text, getCorrectTextSize(0.015), 0, {r, g, b, 1})
            end
        end
    end
end
