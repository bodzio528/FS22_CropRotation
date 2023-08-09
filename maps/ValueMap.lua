ValueMap = {
    MOD_NAME = g_currentModName
}
local ValueMap_mt = Class(ValueMap)

function ValueMap.new(crModule, customMt)
    local self = setmetatable({}, customMt or ValueMap_mt)

    self.crModule = crModule

    self.filename = "valueMap.grle"
    self.name = "valueMap"
    self.id = "VALUE_MAP"
    self.label = "unknown"
    --[[
    self.requireMinimapDisplay = false
    self.minimapSourceObject = nil
    self.minimapSourceObjectSelected = false
    self.requireMinimapUpdate = false
    self.minimapMissionState = false
    self.minimapAdditionalElementRealSize = {
        -1,
        -1
    }
    self.minimapAdditionalElementLinkNode = nil
    self.minimapGradientUVs = nil
    self.minimapGradientColorBlindUVs = nil
    self.minimapLabelName = nil
    self.minimapLabelNameMission = nil
    self.minimapGradientLabelName = nil
    --]]
    self.bitVectorMapsToSync = {}
    self.bitVectorMapsToSave = {}
    self.bitVectorMapsToDelete = {}

    return self
end

function ValueMap:initialize()
    self.bitVectorMapsToSync = {}
    self.bitVectorMapsToSave = {}
    self.bitVectorMapsToDelete = {}
    --[[
    self.requireMinimapDisplay = false
    self.minimapSourceObject = nil
    self.minimapSourceObjectSelected = false
    self.requireMinimapUpdate = false
    self.minimapMissionState = false
    ]]
end

function ValueMap:loadFromXML(xmlFile, key, baseDirectory, configFileName, mapFilename)
    return true
end

function ValueMap:postLoad(xmlFile, key, baseDirectory, configFileName, mapFilename)
    return true
end

function ValueMap:loadSavedBitVectorMap(name, filename, numChannels, size)
    self.crModule.log:debug(string.format("ValueMap:loadSavedBitVectorMap(): name=%s, filename=%s, numChannels=%d, size=%d", name, filename, numChannels, size))

    local missionInfo = g_currentMission.missionInfo
    local savegameFilename = nil

    if missionInfo.savegameDirectory ~= nil then
        savegameFilename = missionInfo.savegameDirectory .. "/" .. filename

        if not fileExists(savegameFilename) then
            savegameFilename = nil
        end
    end

    local bitVectorMap = createBitVectorMap(name)

    if savegameFilename ~= nil and not loadBitVectorMapFromFile(bitVectorMap, savegameFilename, numChannels) then
        self.crModule.log:error("Error while loading bit vector map " .. savegameFilename)

        savegameFilename = nil
    end

    local newValueMap = false

    if savegameFilename == nil then
        delete(bitVectorMap)

        bitVectorMap = createBitVectorMap(name)

        loadBitVectorMapNew(bitVectorMap, size, size, numChannels, false)

        newValueMap = true
    end

    return bitVectorMap, newValueMap
end

function ValueMap:addBitVectorMapToSync(bitVectorMap)
    self.crModule.log:debug(string.format("ValueMap:addBitVectorMapToSync(): bitVectorMap=%s", tostring(bitVectorMap)))

    if bitVectorMap ~= nil then
        table.insert(self.bitVectorMapsToSync, {
            bitVectorMap = bitVectorMap
        })
    end
end

function ValueMap:addBitVectorMapToSave(bitVectorMap, filename)
    self.crModule.log:debug(string.format("ValueMap:addBitVectorMapToSave(): bitVectorMap=%s, filename=%s", tostring(bitVectorMap), filename))

    if bitVectorMap ~= nil then
        table.insert(self.bitVectorMapsToSave, {
            bitVectorMap = bitVectorMap,
            filename = filename
        })
    end
end

function ValueMap:addBitVectorMapToDelete(bitVectorMap)
    self.crModule.log:debug(string.format("ValueMap:addBitVectorMapToDelete(): bitVectorMap=%s", tostring(bitVectorMap)))

    if bitVectorMap ~= nil then
        table.insert(self.bitVectorMapsToDelete, {
            bitVectorMap = bitVectorMap
        })
    end
end

function ValueMap:initTerrain(mission, terrainId, filename)
    self.crModule.log:debug("ValueMap:initTerrain() - next addBitVectorMapToSync calls ineffective")

    if mission.densityMapSyncer ~= nil then
        for i = 1, #self.bitVectorMapsToSync do
            mission.densityMapSyncer:addDensityMap(self.bitVectorMapsToSync[i].bitVectorMap)
        end
    end
end

function ValueMap:delete()
    self.crModule.log:debug("ValueMap:delete()")

    for i = 1, #self.bitVectorMapsToDelete do
        delete(self.bitVectorMapsToDelete[i].bitVectorMap)
    end

    self.bitVectorMapsToDelete = {}
end

function ValueMap:loadFromItemsXML(xmlFile, key)
end

function ValueMap:saveToXMLFile(xmlFile, key, usedModNames)
end

function ValueMap:update(dt)
end

function ValueMap:buildOverlay(overlay, valueFilter, isColorBlindMode)
end

function ValueMap:getDisplayValues()
    return {}
end

function ValueMap:getValueFilter()
    return {}
end

function ValueMap:getMinimapValueFilter()
    return self:getValueFilter()
end

function ValueMap:getOverviewLabel()
    return g_i18n:getText(self.label, ValueMap.MOD_NAME)
end

function ValueMap:getId()
    return self.id
end

function ValueMap:getShowInMenu()
    return true
end

function ValueMap:getAllowCoverage()
    return false
end

function ValueMap:setRequireMinimapDisplay(state, sourceObject, isSelected)
    if self.minimapSourceObject == nil or self.minimapSourceObject == sourceObject then
        self.requireMinimapDisplay = state

        if state then
            self.minimapSourceObject = sourceObject
            self.minimapSourceObjectSelected = isSelected
        else
            self.minimapSourceObject = nil
            self.minimapSourceObjectSelected = false
        end
    end
end

function ValueMap:getRequireMinimapDisplay()
    return self.requireMinimapDisplay, self.minimapSourceObjectSelected
end

function ValueMap:setMinimapRequiresUpdate(state)
    self.requireMinimapUpdate = state
end

function ValueMap:setMinimapMissionState(state)
    if state ~= self.minimapMissionState then
        self.minimapMissionState = state

        self:setMinimapRequiresUpdate(true)
    end
end

function ValueMap:getMinimapUpdateTimeLimit()
    if self.minimapMissionState then
        return 1
    else
        return 0.25
    end
end

function ValueMap:getMinimapRequiresUpdate()
    return self.requireMinimapUpdate
end

function ValueMap:getMinimapAdditionalElement()
    return nil
end

function ValueMap:setMinimapAdditionalElementRealSize(x, y)
    self.minimapAdditionalElementRealSize[1] = x
    self.minimapAdditionalElementRealSize[2] = y
end

function ValueMap:getMinimapAdditionalElementRealSize()
    return self.minimapAdditionalElementRealSize[1], self.minimapAdditionalElementRealSize[2]
end

function ValueMap:setMinimapAdditionalElementLinkNode(linkNode)
    self.minimapAdditionalElementLinkNode = linkNode
end

function ValueMap:getMinimapAdditionalElementLinkNode()
    return self.minimapAdditionalElementLinkNode
end

function ValueMap:getMinimapLabel()
    if self.minimapMissionState then
        return self.minimapLabelNameMission or self.minimapLabelName
    else
        return self.minimapLabelName
    end
end

function ValueMap:getMinimapGradientLabel()
    if not self.minimapMissionState then
        return self.minimapGradientLabelName
    end
end

function ValueMap:getMinimapGradientUVs(isColorBlindMode)
    return isColorBlindMode and self.minimapGradientColorBlindUVs or self.minimapGradientUVs
end

function ValueMap:getMinimapZoomFactor()
    return 3
end

function ValueMap:collectFieldInfos(fieldInfoDisplayExtension)
end

function ValueMap:getHelpLinePage()
    return 0
end

function ValueMap:getRequiresAdditionalActionButton(farmlandId)
    return false
end

function ValueMap:getAdditionalActionButtonText()
    return ""
end

function ValueMap:onAdditionalActionButtonPressed()
end

function ValueMap:overwriteGameFunctions(crModule)
    crModule:overwriteGameFunction(DensityMapHeightManager, "saveCollisionMap", function (superFunc, densityMapHeightManager, directory)
        for i = 1, #self.bitVectorMapsToSave do
            local bitVectorMapToSave = self.bitVectorMapsToSave[i]

            saveBitVectorMapToFile(bitVectorMapToSave.bitVectorMap, directory .. "/" .. bitVectorMapToSave.filename)
        end

        superFunc(densityMapHeightManager, directory)
    end)
    crModule:overwriteGameFunction(DensityMapHeightManager, "prepareSaveCollisionMap", function (superFunc, densityMapHeightManager, directory)
        for i = 1, #self.bitVectorMapsToSave do
            local bitVectorMapToSave = self.bitVectorMapsToSave[i]

            prepareSaveBitVectorMapToFile(bitVectorMapToSave.bitVectorMap, directory .. "/" .. bitVectorMapToSave.filename)
        end

        superFunc(densityMapHeightManager, directory)
    end)
    crModule:overwriteGameFunction(DensityMapHeightManager, "savePreparedCollisionMap", function (superFunc, densityMapHeightManager, callback, callbackObject)
        local localFuncObject = {}

        function localFuncObject.saveBitVectorMap(index)
            local tempObject = {
                tempCallback = function ()
                    if index < #self.bitVectorMapsToSave then
                        localFuncObject.saveBitVectorMap(index + 1)
                    else
                        superFunc(densityMapHeightManager, callback, callbackObject)
                    end
                end
            }
            local bitVectorMapToSave = self.bitVectorMapsToSave[index]

            savePreparedBitVectorMapToFile(bitVectorMapToSave.bitVectorMap, "tempCallback", tempObject)
        end

        if #self.bitVectorMapsToSave >= 1 then
            localFuncObject.saveBitVectorMap(1)
        else
            superFunc(densityMapHeightManager, callback, callbackObject)
        end
    end)
end
