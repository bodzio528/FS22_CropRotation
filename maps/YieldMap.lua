YieldMap = {
    MOD_NAME = g_currentModName
}

local YieldMap_mt = Class(YieldMap, ValueMap)

function YieldMap.new(crModule, range, customMt)
    local self = ValueMap.new(crModule, customMt or YieldMap_mt)

    self.range = tostring(range)
    self.filename = string.format("cropRotation_yieldMap_%s.grle", self.range)
    self.name = string.format("crYieldMap_%s", self.range)
    self.id = string.format("YIELD_MAP_%s", self.range:upper())
    self.label = string.format("ui_mapOverviewYield_%s", self.range)

    self.densityMapModifiersYield = {}
    self.densityMapModifiersReset = {}
    self.yieldMapSelected = false
    self.selectedFarmland = nil
    self.selectedField = nil
    self.selectedFieldArea = nil

    self:debug("New map (%s): %s", self.name, self.filename)

    return self
end

function YieldMap:debug(s, ...)
    self.crModule.log:debug(
        string.format("YieldMap(%s):", tostring(self.range))..string.format(s, ...)
    )
end

function YieldMap:initialize()
    YieldMap:superClass().initialize(self)
    self:debug("initialize()")

    self.modifiers = {}

    self.densityMapModifiersYield = {}
    self.densityMapModifiersReset = {}
    self.yieldMapSelected = false
    self.selectedFarmland = nil
    self.selectedField = nil
    self.selectedFieldArea = nil
end

function YieldMap:delete()
    self:debug("delete()")

    g_farmlandManager:removeStateChangeListener(self)
    YieldMap:superClass().delete(self)
end

function YieldMap:loadFromXML(xmlFile, key, baseDirectory, configFileName, mapFilename)
    self:debug("loadFromXML("..key..")")

    key = key .. ".yieldMap"
    self.sizeX = getXMLInt(xmlFile, key .. "#sizeX") or 1024
    self.sizeY = getXMLInt(xmlFile, key .. "#sizeY") or 1024
    self.numChannels = getXMLInt(xmlFile, key .. "#numChannels") or 5
    self.bitVectorMap = self:loadSavedBitVectorMap(self.name, self.filename, self.numChannels, self.sizeX)

    self:addBitVectorMapToSync(self.bitVectorMap)
    self:addBitVectorMapToSave(self.bitVectorMap, self.filename)
    self:addBitVectorMapToDelete(self.bitVectorMap)

    self.yieldValues = {}
    for _, fruitDesc in pairs(g_fruitTypeManager:getFruitTypes()) do
        table.insert(self.yieldValues, {
            value = fruitDesc.index,
            displayValue = fruitDesc.fillType.title,
            color = fruitDesc.defaultMapColor, 
            colorBlind = colorBlindMapColor,
            showInMenu = fruitDesc.rotation.enabled
        })
    end

    local modifier = DensityMapModifier.new(self.bitVectorMap, 0, self.numChannels)
    modifier:setPolygonRoundingMode(DensityRoundingMode.INCLUSIVE)
    local filter = DensityMapFilter.new(modifier)

    self.modifiers = {
        modifier = modifier,
        filter = filter
    }

    g_farmlandManager:addStateChangeListener(self)

    return true
end

function YieldMap:update(dt)
end

local function worldCoordsToLocalCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, size, terrainSize)
    return math.floor(size * (startWorldX +  terrainSize * 0.5) / terrainSize),
           math.floor(size * (startWorldZ +  terrainSize * 0.5) / terrainSize),
           math.floor(size * (widthWorldX +  terrainSize * 0.5) / terrainSize),
           math.floor(size * (widthWorldZ +  terrainSize * 0.5) / terrainSize),
           math.floor(size * (heightWorldX + terrainSize * 0.5) / terrainSize),
           math.floor(size * (heightWorldZ + terrainSize * 0.5) / terrainSize)
end

function YieldMap:setAreaYield(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, fruitIndex)
    self:debug("setAreaYield(fruitIndex: "..tostring(fruitIndex)..")")

    local modifier = self.densityMapModifiersYield.modifier
    local maskFilter = self.densityMapModifiersYield.maskFilter

    if modifier == nil or maskFilter == nil then
        self.densityMapModifiersYield.modifier = DensityMapModifier.new(self.bitVectorMap, 0, self.numChannels)
        modifier = self.densityMapModifiersYield.modifier
        local fieldGroundSystem = g_currentMission.fieldGroundSystem
        local groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels = fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)
        self.densityMapModifiersYield.maskFilter = DensityMapFilter.new(groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels)
        maskFilter = self.densityMapModifiersYield.maskFilter

        maskFilter:setValueCompareParams(DensityValueCompareType.GREATER, 0)
    end

    startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = worldCoordsToLocalCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, self.sizeX, g_currentMission.terrainSize)

    modifier:setParallelogramDensityMapCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, DensityCoordType.POINT_POINT_POINT)

    -- local internalYieldValue = self:getNearestInternalYieldValueFromValue(yieldPercentage / 2 * 100)

    modifier:executeSet(fruitIndex, maskFilter) -- set new fruit for area eg. on harvest
    -- self:setMinimapRequiresUpdate(true)
end

function YieldMap:getNearestInternalYieldValueFromValue(value)
    self:debug("getNearestInternalYieldValueFromValue(value: %s)", tostring(value))

    local minDifference = 10000
    local minValue = 0

    if value > 0 then
        for i = 1, #self.yieldValues do
            local yieldValue = self.yieldValues[i].displayValue
            local difference = math.abs(value - yieldValue)

            if difference < minDifference then
                minDifference = difference
                minValue = self.yieldValues[i].value
            end
        end
    end

    return minValue
end

function YieldMap:resetFarmlandYieldArea(farmlandId)
    self:debug("resetFarmlandYieldArea(farmlandId: %d)", farmlandId)
--[[
    local modifier = self.densityMapModifiersReset.modifier
    local farmlandMask = self.densityMapModifiersReset.farmlandMask
    local farmlandManager = g_farmlandManager

    if modifier == nil or farmlandMask == nil then
        self.densityMapModifiersReset.modifier = DensityMapModifier.new(self.bitVectorMap, 0, self.numChannels)
        modifier = self.densityMapModifiersReset.modifier
        self.densityMapModifiersReset.farmlandMask = DensityMapFilter.new(farmlandManager.localMap, 0, farmlandManager.numberOfBits)
        farmlandMask = self.densityMapModifiersReset.farmlandMask
    end

    farmlandMask:setValueCompareParams(DensityValueCompareType.EQUAL, farmlandId)
    modifier:executeSet(0, farmlandMask)
    self:setMinimapRequiresUpdate(true)

    if g_server == nil and g_client ~= nil then
        g_client:getServerConnection():sendEvent(ResetYieldMapEvent.new(farmlandId))
    end
--]]
end

function YieldMap:buildOverlay(overlay, yieldFilter, isColorBlindMode)
    self:debug("buildOverlay()")

    resetDensityMapVisualizationOverlay(overlay)
    setOverlayColor(overlay, 1, 1, 1, 1)

    local yieldMapId = self.bitVectorMap
    local filterIndex = 1

    for i = 1, #self.yieldValues do
        local yieldValue = self.yieldValues[i]

        if yieldFilter[filterIndex] then
            local r, g, b = nil

            if isColorBlindMode then
                b = yieldValue.colorBlind[3]
                g = yieldValue.colorBlind[2]
                r = yieldValue.colorBlind[1]
            else
                b = yieldValue.color[3]
                g = yieldValue.color[2]
                r = yieldValue.color[1]
            end

            setDensityMapVisualizationOverlayStateColor(overlay, yieldMapId, 0, 0, 0, self.numChannels, yieldValue.value, r, g, b)
        end

        if yieldValue.showInMenu then
            filterIndex = filterIndex + 1
        end
    end
end

function YieldMap:getMinimapZoomFactor()
    self:debug("getMinimapZoomFactor() -> 3")

    return 3
end

function YieldMap:getMinMaxValue()
    self:debug("getMinMaxValue()")

    if #self.yieldValues > 0 then
        return self.yieldValues[1].displayValue, self.yieldValues[#self.yieldValues].displayValue, #self.yieldValues
    end

    return 0, 1, 0
end

function YieldMap:getDisplayValues()
    self:debug("getDisplayValues()")

    if self.valuesToDisplay == nil then
        self.valuesToDisplay = {}

        for i = 1, #self.yieldValues do
            local pct = (i - 1) / (#self.yieldValues - 1)
            local yieldValue = self.yieldValues[i]

            if yieldValue.showInMenu then
                local yieldValueToDisplay = {
                    colors = {}
                }
                yieldValueToDisplay.colors[true] = {
                    yieldValue.colorBlind or {
                        pct * 0.9 + 0.1,
                        pct * 0.9 + 0.1,
                        0.1
                    }
                }
                yieldValueToDisplay.colors[false] = {
                    yieldValue.color
                }
                yieldValueToDisplay.description = string.format("%s", yieldValue.displayValue)

                table.insert(self.valuesToDisplay, yieldValueToDisplay)
            end
        end
    end

    return self.valuesToDisplay
end

function YieldMap:getValueFilter()
    self:debug("getValueFilter()")

    if self.valueFilter == nil then
        self.valueFilter = {}

        for i = 1, #self.yieldValues do
            if self.yieldValues[i].showInMenu then
                table.insert(self.valueFilter, true)
            end
        end
    end

    return self.valueFilter
end

function YieldMap:onValueMapSelectionChanged(valueMap)
    self.yieldMapSelected = valueMap == self

    self:debug("onValueMapSelectionChanged(): is selected: %s", tostring(self.yieldMapSelected))

    self:updateResetButton()
end

function YieldMap:onFarmlandSelectionChanged(farmlandId, fieldNumber, fieldArea)
    self.selectedFarmland = farmlandId
    self.selectedField = fieldNumber
    self.selectedFieldArea = fieldArea

    self:debug("onFarmlandSelectionChanged(farmlandId: %s, fieldNumber: %s, fieldArea: %s)", 
        tostring(self.selectedFarmland), 
        tostring(self.selectedField), 
        tostring(self.selectedFieldArea))

    self:updateResetButton()
end

function YieldMap:onFarmlandStateChanged(farmlandId, farmId)
    self:debug("onFarmlandStateChanged(farmlandId: %d, farmId: %d)", farmlandId, farmId)

    if farmId == FarmlandManager.NO_OWNER_FARM_ID then
        self:resetFarmlandYieldArea(farmlandId)
    end
end

function YieldMap:setMapFrame(mapFrame)
	self:debug("setMapFrame()")

    self.mapFrame = mapFrame

    self:updateResetButton()
end

function YieldMap:getIsResetButtonActive()
    self:debug("getIsResetButtonActive() farmlandId: %s, fieldNumber: %s, fieldArea: %s", 
        tostring(self.selectedFarmland),
        tostring(self.selectedField),
        tostring(self.selectedFieldArea))

    return self.selectedFarmland ~= nil and self.selectedFieldArea ~= nil and self.selectedFieldArea > 0 and self.yieldMapSelected
end

function YieldMap:updateResetButton()
    self:debug("updateResetButton()")

    if self.mapFrame ~= nil then
        self.mapFrame:updateAdditionalFunctionButton()
    else
        self:debug('updateResetButton() - no mapFrame set!')
    end
end

function YieldMap:onClickButtonResetYield()
    self:debug("onClickButtonResetYield()")

    if self:getIsResetButtonActive() then
        -- local farmlandStatistics = g_precisionFarming.farmlandStatistics

        -- if farmlandStatistics ~= nil and farmlandStatistics.selectedFarmlandId ~= nil then
        --     self:resetFarmlandYieldArea(farmlandStatistics.selectedFarmlandId)
        --     g_precisionFarming:updatePrecisionFarmingOverlays()

        --     return true
        -- end
    end

    return false
end

function YieldMap:getHelpLinePage()
    self:debug("getHelpLinePage()")

    return 71
end

function YieldMap:getRequiresAdditionalActionButton(farmlandId)
    self:debug("getRequiresAdditionalActionButton(farmlandId: %d)", farmlandId)

    return self:getIsResetButtonActive()
end

function YieldMap:getAdditionalActionButtonText()
    self:debug("getAdditionalActionButtonText()")

    local text = nil

    if self.selectedField ~= nil and self.selectedField ~= 0 then
        text = string.format(g_i18n:getText("ui_resetYield", YieldMap.MOD_NAME), self.selectedField)
    else
        text = g_i18n:getText("ui_resetYieldAdditionalField", YieldMap.MOD_NAME)
    end

    -- return text
    return string.format("Reset field %d", self.selectedField)
end

function YieldMap:onAdditionalActionButtonPressed()
    self:debug("onAdditionalActionButtonPressed()")

    if self:getIsResetButtonActive() then
        -- local farmlandStatistics = g_precisionFarming.farmlandStatistics

        -- if farmlandStatistics ~= nil and farmlandStatistics.selectedFarmlandId ~= nil then
        --     self:resetFarmlandYieldArea(farmlandStatistics.selectedFarmlandId)
        --     g_precisionFarming:updatePrecisionFarmingOverlays()

        --     return true
        -- end
    end
end
