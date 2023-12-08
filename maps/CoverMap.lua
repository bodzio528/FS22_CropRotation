CoverMap = {
    MOD_NAME = g_currentModName
}

local CoverMap_mt = Class(CoverMap, ValueMap)

function CoverMap.new(crModule, customMt)
    local self = ValueMap.new(crModule, customMt or CoverMap_mt)

    self.name = "crCoverMap"
    self.filename = "cropRotation_coverMap.grle"

    addConsoleCommand("crUncoverField", "Uncovers given field", "debugUncoverField", self)
    addConsoleCommand("crUncoverAll", "Uncovers all fields", "debugUncoverAll", self)
    -- addConsoleCommand("crReduceCoverState", "Reduces cover State for given field", "debugReduceCoverStateField", self)
    -- addConsoleCommand("crReduceCoverStateAll", "Reduces cover State for all fields", "debugReduceCoverStateAll", self)
    addConsoleCommand("crPrepareField", "Set last and prev harvest for field", "debugPrepareField", self)

    self.crModule.log:debug(string.format("New map (%s): %s", self.name, self.filename))

    return self
end

function CoverMap:initialize()
    CoverMap:superClass().initialize(self)

    self.crModule.log:debug("CoverMap:initialize()")

    self.modifiers = {}

    --[[
    self.densityMapModifiersAnalyse = {}
    self.densityMapModifiersUncover = {}
    self.densityMapModifiersUncoverFarmland = {}
    self.densityMapModifiersFarmlandState = {}
    self.densityMapModifiersUpdate = {}
    self.densityMapModifiersResetLock = {}
    ]]
end

function CoverMap:delete()
    self.crModule.log:debug("CoverMap:delete() name:", self.name)

    removeConsoleCommand("crUncoverField")
    removeConsoleCommand("crUncoverAll")
    -- removeConsoleCommand("crReduceCoverState")
    -- removeConsoleCommand("crReduceCoverStateAll")
    removeConsoleCommand("crPrepareField")

    CoverMap:superClass().delete(self)
end

function CoverMap:loadFromXML(xmlFile, key, baseDirectory, configFileName, mapFilename)
    key = key .. ".coverMap"
    self.sizeX = getXMLInt(xmlFile, key .. "#sizeX") or ValueMap.DEFAULT_MAP_SIZE
    self.sizeY = getXMLInt(xmlFile, key .. "#sizeY") or ValueMap.DEFAULT_MAP_SIZE
    self.lockChannel = getXMLInt(xmlFile, key .. "#lockChannel") or 0
    self.fallowChannel = getXMLInt(xmlFile, key .. "#fallowChannel") or 1
    self.harvestChannel = getXMLInt(xmlFile, key .. "#harvestChannel") or 2
    self.numChannels = 3
    -- self.maxValue = 2^self.numChannels - 1
    -- self.maxValue = getXMLInt(xmlFile, key .. "#maxValue") or self.maxValue
    -- self.sampledValue = self.maxValue + 1
    self.bitVectorMap = self:loadSavedBitVectorMap(self.name, self.filename, self.numChannels, self.sizeX)

    self:addBitVectorMapToSync(self.bitVectorMap)
    self:addBitVectorMapToSave(self.bitVectorMap, self.filename)
    self:addBitVectorMapToDelete(self.bitVectorMap)

    -- self.bitVectorMapSoilSampleFarmId = self:loadSavedBitVectorMap("soilSampleFarmIdMap", "cropRotation_soilSampleFarmIdMap.grle", 4, self.sizeX)

    -- self:addBitVectorMapToSave(self.bitVectorMapSoilSampleFarmId, "precisionFarming_soilSampleFarmIdMap.grle")
    -- self:addBitVectorMapToDelete(self.bitVectorMapSoilSampleFarmId)

    -- self.bitVectorMapTempHarvestLock = self:loadSavedBitVectorMap("bitVectorMapTempHarvestLock", "bitVectorMapTempHarvestLock.grle", 1, self.sizeX)

    -- self:addBitVectorMapToDelete(self.bitVectorMapTempHarvestLock)

    -- self.soilMap = g_cropRotation.soilMap

    local modifiers = {}

    modifiers.cover = {}
    modifiers.cover.modifier = DensityMapModifier.new(self.bitVectorMap, self.lockChannel, 1)
    modifiers.cover.modifier:setPolygonRoundingMode(DensityRoundingMode.INCLUSIVE)
    modifiers.cover.filter = DensityMapFilter.new(modifiers.cover.modifier)
    modifiers.cover.filter:setValueCompareParams(DensityValueCompareType.EQUAL, 0)

    modifiers.fallow = {}
    modifiers.fallow.modifier = DensityMapModifier.new(self.bitVectorMap, self.fallowChannel, 1)
    modifiers.fallow.modifier:setPolygonRoundingMode(DensityRoundingMode.INCLUSIVE)
    modifiers.fallow.filter = DensityMapFilter.new(modifiers.fallow.modifier)
    modifiers.fallow.filter:setValueCompareParams(DensityValueCompareType.EQUAL, 0)

    modifiers.harvest = {}
    modifiers.harvest.modifier = DensityMapModifier.new(self.bitVectorMap, self.harvestChannel, 1)
    modifiers.harvest.modifier:setPolygonRoundingMode(DensityRoundingMode.INCLUSIVE)
    modifiers.harvest.filter = DensityMapFilter.new(modifiers.harvest.modifier)
    modifiers.harvest.filter:setValueCompareParams(DensityValueCompareType.EQUAL, 0)

    self.modifiers = modifiers

    return true
end

local function worldCoordsToLocalCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, size, terrainSize)
    return size * (startWorldX  + terrainSize * 0.5) / terrainSize,
           size * (startWorldZ  + terrainSize * 0.5) / terrainSize,
           size * (widthWorldX  + terrainSize * 0.5) / terrainSize,
           size * (widthWorldZ  + terrainSize * 0.5) / terrainSize,
           size * (heightWorldX + terrainSize * 0.5) / terrainSize,
           size * (heightWorldZ + terrainSize * 0.5) / terrainSize
end

function CoverMap:overwriteGameFunctions(crModule)
    CoverMap:superClass().overwriteGameFunctions(self, crModule)
end

function CoverMap:getShowInMenu()
    return false
end

function CoverMap:uncoverFarmlandArea(farmlandId)
    local modifier = self.densityMapModifiersUncoverFarmland.modifier
    local maskFilter = self.densityMapModifiersUncoverFarmland.maskFilter
    local fieldFilter = self.densityMapModifiersUncoverFarmland.fieldFilter

    if modifier == nil or maskFilter == nil or fieldFilter == nil then
        self.densityMapModifiersUncoverFarmland.modifier = DensityMapModifier.new(self.bitVectorMap, self.firstChannel, self.numChannels)
        modifier = self.densityMapModifiersUncoverFarmland.modifier

        modifier:setParallelogramDensityMapCoords(0, 0, 0, self.sizeY, self.sizeX, 0, DensityCoordType.POINT_POINT_POINT)

        local farmlandManager = g_farmlandManager
        self.densityMapModifiersUncoverFarmland.maskFilter = DensityMapFilter.new(farmlandManager.localMap, 0, farmlandManager.numberOfBits)
        maskFilter = self.densityMapModifiersUncoverFarmland.maskFilter

        maskFilter:setValueCompareParams(DensityValueCompareType.EQUAL, farmlandId)

        local fieldGroundSystem = g_currentMission.fieldGroundSystem
        local groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels = fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)
        self.densityMapModifiersAnalyse.fieldFilter = DensityMapFilter.new(groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels)
        fieldFilter = self.densityMapModifiersAnalyse.fieldFilter

        fieldFilter:setValueCompareParams(DensityValueCompareType.GREATER, 0)
    end

    maskFilter:setValueCompareParams(DensityValueCompareType.EQUAL, farmlandId)
    self.soilMap:onUncoverArea(maskFilter, fieldFilter, nil)
    modifier:executeSet(self.maxValue, maskFilter, fieldFilter)
end

function CoverMap:updateCoverArea(fruitTypes, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, useMinForageState)
    local modifier = self.densityMapModifiersUpdate.modifier
    local lockModifier = self.densityMapModifiersUpdate.lockModifier
    local lockFilter = self.densityMapModifiersUpdate.lockFilter
    local fruitFilter = self.densityMapModifiersUpdate.fruitFilter
    local lockChannelFilter = self.densityMapModifiersUpdate.lockChannelFilter
    local coverStateFilter = self.densityMapModifiersUpdate.coverStateFilter

    if modifier == nil or lockModifier == nil or lockFilter == nil or fruitFilter == nil or lockChannelFilter == nil or coverStateFilter == nil then
        self.densityMapModifiersUpdate.modifier = DensityMapModifier.new(self.bitVectorMap, self.firstChannel, self.numChannels)
        modifier = self.densityMapModifiersUpdate.modifier

        modifier:setPolygonRoundingMode(DensityRoundingMode.INCLUSIVE)

        self.densityMapModifiersUpdate.lockModifier = DensityMapModifier.new(self.bitVectorMapTempHarvestLock, 0, 1)
        lockModifier = self.densityMapModifiersUpdate.lockModifier

        lockModifier:setPolygonRoundingMode(DensityRoundingMode.INCLUSIVE)

        self.densityMapModifiersUpdate.lockFilter = DensityMapFilter.new(self.bitVectorMapTempHarvestLock, 0, 1)
        lockFilter = self.densityMapModifiersUpdate.lockFilter
        self.densityMapModifiersUpdate.fruitFilter = DensityMapFilter.new(modifier)
        fruitFilter = self.densityMapModifiersUpdate.fruitFilter
        self.densityMapModifiersUpdate.lockChannelFilter = DensityMapFilter.new(self.bitVectorMap, self.lockChannel, 1)
        lockChannelFilter = self.densityMapModifiersUpdate.lockChannelFilter

        lockChannelFilter:setValueCompareParams(DensityValueCompareType.EQUAL, 0)

        self.densityMapModifiersUpdate.coverStateFilter = DensityMapFilter.new(self.bitVectorMap, self.firstChannel, self.numChannels)
        coverStateFilter = self.densityMapModifiersUpdate.coverStateFilter

        coverStateFilter:setValueCompareParams(DensityValueCompareType.BETWEEN, 2, self.maxValue)
    end

    local widthDirX, widthDirY = MathUtil.vector2Normalize(startWorldX - widthWorldX, startWorldZ - widthWorldZ)
    local heightDirX, heightDirY = MathUtil.vector2Normalize(startWorldX - heightWorldX, startWorldZ - heightWorldZ)
    local extensionLength = g_currentMission.terrainSize / self.sizeX * 2
    local extendedStartWorldX = startWorldX + widthDirX * extensionLength + heightDirX * extensionLength
    local extendedStartWorldZ = startWorldZ + widthDirY * extensionLength + heightDirY * extensionLength
    local extendedWidthWorldX = widthWorldX - widthDirX * extensionLength + heightDirX * extensionLength
    local extendedWidthWorldZ = widthWorldZ - widthDirY * extensionLength + heightDirY * extensionLength
    local extendedHeightWorldX = heightWorldX - heightDirX * extensionLength + widthDirX * extensionLength
    local extendedHeightWorldZ = heightWorldZ - heightDirY * extensionLength + widthDirY * extensionLength
    startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = worldCoordsToLocalCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, self.sizeX, g_currentMission.terrainSize)
    extendedStartWorldX, extendedStartWorldZ, extendedWidthWorldX, extendedWidthWorldZ, extendedHeightWorldX, extendedHeightWorldZ = worldCoordsToLocalCoords(extendedStartWorldX, extendedStartWorldZ, extendedWidthWorldX, extendedWidthWorldZ, extendedHeightWorldX, extendedHeightWorldZ, self.sizeX, g_currentMission.terrainSize)

    modifier:setParallelogramDensityMapCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, DensityCoordType.POINT_POINT_POINT)
    lockModifier:setParallelogramDensityMapCoords(extendedStartWorldX, extendedStartWorldZ, extendedWidthWorldX, extendedWidthWorldZ, extendedHeightWorldX, extendedHeightWorldZ, DensityCoordType.POINT_POINT_POINT)
    lockModifier:executeSet(1)

    local usedFruitIndex = nil
    local numFruitTypes = 0

    for _, fruitIndex in pairs(fruitTypes) do
        local desc = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)

        if desc ~= nil and desc.terrainDataPlaneId ~= nil then
            fruitFilter:resetDensityMapAndChannels(desc.terrainDataPlaneId, desc.startStateChannel, desc.numStateChannels)
            fruitFilter:setValueCompareParams(DensityValueCompareType.EQUAL, desc.cutState)

            local _, numPixels = lockModifier:executeSet(0, fruitFilter)

            if numPixels > 0 then
                usedFruitIndex = fruitIndex
            end
        end

        numFruitTypes = numFruitTypes + 1
    end

    if numFruitTypes == 0 then
        lockModifier:executeSet(0)
    end

    modifier:setParallelogramDensityMapCoords(extendedStartWorldX, extendedStartWorldZ, extendedWidthWorldX, extendedWidthWorldZ, extendedHeightWorldX, extendedHeightWorldZ, DensityCoordType.POINT_POINT_POINT)
    modifier:setDensityMapChannels(self.lockChannel, 1)
    lockFilter:setValueCompareParams(DensityValueCompareType.EQUAL, 1)
    modifier:executeSet(0, lockFilter)
    -- update state channels
    modifier:setParallelogramDensityMapCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, DensityCoordType.POINT_POINT_POINT)
    modifier:setDensityMapChannels(self.firstChannel, self.numChannels)
    lockFilter:setValueCompareParams(DensityValueCompareType.EQUAL, 0)
    modifier:executeAdd(-1, lockFilter, lockChannelFilter, coverStateFilter)

    local _, pixelsToLock = modifier:executeGet(lockFilter, lockChannelFilter)

    -- todo: this is moment for update L/P/H/F bits
    local phMapUpdated = false
    local nMapUpdated = false
--[[
    if usedFruitIndex ~= nil then
        if self.pfModule.pHMap ~= nil then
            phMapUpdated = self.pfModule.pHMap:onHarvestCoverUpdate(lockFilter, lockChannelFilter, usedFruitIndex, pixelsToLock > 0, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, useMinForageState)
        end

        if self.pfModule.phosphagenMap ~= nil then
            nMapUpdated = self.pfModule.phosphagenMap:onHarvestCoverUpdate(lockFilter, lockChannelFilter, usedFruitIndex, pixelsToLock > 0, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, useMinForageState)
        end

        if self.pfModule.seedRateMap ~= nil then
            self.pfModule.seedRateMap:onHarvestCoverUpdate(lockFilter, lockChannelFilter, usedFruitIndex, pixelsToLock > 0, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, useMinForageState)
        end
    end
--]]
    modifier:setDensityMapChannels(self.lockChannel, 1)
    modifier:executeSet(1, lockFilter, lockChannelFilter)

    return phMapUpdated, nMapUpdated
end

function CoverMap:resetCoverLock(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    self.crModule.log:debug("CoverMap:resetCoverLock")
    local modifier = self.densityMapModifiersResetLock.modifier

    if modifier == nil then
        self.densityMapModifiersResetLock.modifier = DensityMapModifier.new(self.bitVectorMap, self.lockChannel, 1)
        modifier = self.densityMapModifiersResetLock.modifier
    end

    startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = worldCoordsToLocalCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, self.sizeX, g_currentMission.terrainSize)

    modifier:setParallelogramDensityMapCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, DensityCoordType.POINT_POINT_POINT)
    modifier:executeSet(0)
end

function CoverMap:getNumCoverOverlays()
    return self.maxValue - 1
end

function CoverMap:buildCoverStateOverlay(overlay, index)
    -- nie bedzie potrzebne
    local numOverlays = self:getNumCoverOverlays()

    resetDensityMapVisualizationOverlay(overlay)

    local alpha = (numOverlays - (index - 1)) / numOverlays

    setOverlayColor(overlay, 1, 1, 1, alpha)
    setDensityMapVisualizationOverlayStateColor(overlay, self.bitVectorMap, 0, 0, self.firstChannel, self.numChannels, index, 0, 0, 0)
end

function CoverMap:getIsUncoveredAtBitVectorPos(x, z, isWorldPos)
    if isWorldPos == true then
        x = (x + g_currentMission.terrainSize * 0.5) / g_currentMission.terrainSize * self.sizeX
        z = (z + g_currentMission.terrainSize * 0.5) / g_currentMission.terrainSize * self.sizeY
    end

    local coverValue = getBitVectorMapPoint(self.bitVectorMap, x, z, self.firstChannel, self.numChannels)

    if coverValue > 1 and coverValue <= self.maxValue then
        return true
    end

    return false
end

-- function CoverMap:debugReduceCoverStateField(fieldIndex)
--     local field = g_fieldManager:getFieldByIndex(tonumber(fieldIndex))

--     if field ~= nil and field.fieldDimensions ~= nil then
--         local numDimensions = getNumOfChildren(field.fieldDimensions)

--         for i = 1, numDimensions do
--             local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = self:getCoordsFromFieldDimensions(field.fieldDimensions, i - 1)

--             self:updateCoverArea({}, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, true)
--         end

--         for i = 1, numDimensions do
--             local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = self:getCoordsFromFieldDimensions(field.fieldDimensions, i - 1)

--             self:resetCoverLock(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
--         end
--     end

--     self.crModule:updateCropRotationOverlays() -- NOOP
-- end

-- function CoverMap:debugReduceCoverStateAll()
--     for i = 1, #g_fieldManager.fields do
--         self:debugReduceCoverStateField(i)
--     end
-- end

function CoverMap:debugPrepareField(fieldIndex, lastCropName, prevCropName, harvestBit, fallowBit)
    -- crPrepareField <field_id> <last_crop> <previous_crop> <harvest_bit> <fallow_bit>

    self.crModule.log:debug(
        string.format("CoverMap:debugPrepareField(last= %s, prev= %s, h=%s, f=%s)", 
        tostring(lastCropName), tostring(prevCropName), tostring(harvestBit), tostring(fallowBit)))

    local field = g_fieldManager:getFieldByIndex(tonumber(fieldIndex))

    local lastCrop = g_fruitTypeManager:getFruitTypeByName(tostring(lastCropName))
    local prevCrop = g_fruitTypeManager:getFruitTypeByName(tostring(prevCropName))

    log(string.format("CoverMap:debugPrepareField(): last = %s prev = %s", lastCrop.name, prevCrop.name))

    if field ~= nil and field.fieldDimensions ~= nil then
        local numDimensions = getNumOfChildren(field.fieldDimensions)

        if resetState == nil or resetState == "true" then
            local farmlandId = field.farmland.id

            if farmlandId ~= nil then
                -- self.crModule.soilMap:onFarmlandStateChanged(farmlandId, FarmlandManager.NO_OWNER_FARM_ID)
                self:debugUncoverField(tonumber(fieldIndex))
            end
        end
--[[
        for i = 1, numDimensions do
            local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = self:getCoordsFromFieldDimensions(field.fieldDimensions, i - 1)

            self.crModule.phosphagenMap:updateCropSensorArea(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, true, false)
        end

        for i = 1, numDimensions do
            local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = self:getCoordsFromFieldDimensions(field.fieldDimensions, i - 1)

            self.crModule.pHMap:updateSprayArea(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, SprayType.LIME, true, 0)
            self.crModule.phosphagenMap:updateSprayArea(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, SprayType.FERTILIZER, SprayType.FERTILIZER, true, 0, 0, 0, 1)
        end

        for i = 1, numDimensions do
            local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = self:getCoordsFromFieldDimensions(field.fieldDimensions, i - 1)

            self.crModule.pHMap:postUpdateSprayArea(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, SprayType.LIME, SprayType.LIME, true, 0)
            self.crModule.phosphagenMap:postUpdateSprayArea(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, SprayType.FERTILIZER, SprayType.FERTILIZER, true, 0)
        end
--]]
    end

    self.crModule:updateCropRotationOverlays()
end

function CoverMap:getCoordsFromFieldDimensions(fieldDimensions, index)
    local dimWidth = getChildAt(fieldDimensions, index)
    local dimStart = getChildAt(dimWidth, 0)
    local dimHeight = getChildAt(dimWidth, 1)
    local startWorldX, _, startWorldZ = getWorldTranslation(dimStart)
    local widthWorldX, _, widthWorldZ = getWorldTranslation(dimWidth)
    local heightWorldX, _, heightWorldZ = getWorldTranslation(dimHeight)

    return startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ
end


function CoverMap:debugUncoverField(fieldIndex)
    local field = g_fieldManager:getFieldByIndex(tonumber(fieldIndex))

    if field ~= nil and field.fieldDimensions ~= nil then
        local numDimensions = getNumOfChildren(field.fieldDimensions)

        for i = 1, numDimensions do
            local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = self:getCoordsFromFieldDimensions(field.fieldDimensions, i - 1)

            -- self:analyseArea(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, nil, g_farmlandManager:getFarmlandOwner(field.farmland.id), field.farmland.id)
        end

        -- self:uncoverAnalysedArea()
    end
end

function CoverMap:debugUncoverAll()
    for i = 1, #g_fieldManager.fields do
        self:debugUncoverField(i)
    end
end
