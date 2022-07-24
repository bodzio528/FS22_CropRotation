--
-- FS22 - Crop Rotation mod
--
-- CropRotation.lua
--
-- @Author: Bodzio528
-- @Date: 22.07.2022
-- @Version: 1.0.0.0
--
-- Changelog:
-- 	v1.0.0.0 (22.07.2022):
--      - Initial release
--

CropRotation = {}
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

CropRotation.debug = true -- false --

function overwrittenStaticFunction(target, name, newFunc)
    local oldFunc = target[name]
    target[name] = function (...)
        return newFunc(oldFunc, ...)
    end
end

function CropRotation:new(mission, messageCenter, fruitTypeManager, data) --environment, densityMapScanner, i18n)
    local self = setmetatable({}, CropRotation_mt)

    self.mission = mission
    self.messageCenter = messageCenter
    self.fruitTypeManager = fruitTypeManager

    self.data = data

--[[
    self.environment = environment
    self.fruitTypeManager = fruitTypeManager
    self.densityMapScanner = densityMapScanner
    self.data = data
    self.i18n = i18n
--]]

    overwrittenStaticFunction(FSDensityMapUtil, "updateSowingArea", CropRotation.inj_densityMapUtil_updateSowingArea)
    overwrittenStaticFunction(FSDensityMapUtil, "updateDirectSowingArea", CropRotation.inj_densityMapUtil_updateSowingArea)
    overwrittenStaticFunction(FSDensityMapUtil, "cutFruitArea", CropRotation.inj_densityMapUtil_cutFruitArea)

    addConsoleCommand("cropRotationInfo", "Get crop rotation info", "commandGetInfo", self)

    return self
end

function CropRotation:delete()
    if self.map ~= 0 then
        delete(self.map)
    end

    --self.densityMapScanner:unregisterCallback("UpdateFallow")

    self.messageCenter:unsubscribeAll(self)
end

function CropRotation:load()
    print(string.format("CropRotation:load(): %s", "has been called 100"))

    self:loadModifiers()

    self.messageCenter:subscribe(MessageType.YEAR_CHANGED, self.onYearChanged, self)
    self.messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    self.messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)
end


function CropRotation:onMapLoaded(mission, node)
    print(string.format("CropRotation:onMapLoaded(mission, node): %s", "has been called - NOOP"))
end

function CropRotation:onTerrainLoaded(mission, terrainId, mapFilename)
    print(string.format("CropRotation:onTerrainLoaded(): has been called with terrainId = %s", tostring(terrainId)))

    self.terrainSize = self.mission.terrainSize

    self:loadMap2()
    self:loadModifiers()
end

function CropRotation:loadMap2()
    print(string.format("CropRotation:loadMap(): %s", "has been called 10"))

    self.map = createBitVectorMap("cropRotation")
    local success = false

    if self.mission.missionInfo.isValid then
        local path = self.mission.missionInfo.savegameDirectory .. "/cropRotation.grle"
        print(string.format("CropRotation:loadMap(): path = %s", tostring(path)))

        if fileExists(path) then
            success = loadBitVectorMapFromFile(self.map, path, CropRotation.MAP_NUM_CHANNELS)
        end
    end

    if not success then
        print(string.format("CropRotation:loadMap(): DUPA 2 mission: %s, tdId: %s", tostring(self.mission), tostring(self.mission.terrainDetailId)))
        local size = getDensityMapSize(self.mission.terrainDetailId)
        loadBitVectorMapNew(self.map, size, size, CropRotation.MAP_NUM_CHANNELS, false)
    end

    self.mapSize = getBitVectorMapSize(self.map)
    print(string.format("CropRotation:loadMap(): self.mapSize = %s", tostring(self.mapSize)))
end

function CropRotation:onMissionLoaded()
    print(string.format("CropRotation:onMissionLoaded(mission, node): %s", "has been called - NOOP"))
end

function CropRotation:loadModifiers()
    print(string.format("CropRotation:loadModifiers(): %s", "has been called 20"))
--
--     local terrainDetailId = self.mission.terrainDetailId

    local modifiers = {}

--
    local terrainRootNode = self.mission.terrainRootNode --  g_currentMission.terrainRootNode
    local fieldGroundSystem = self.mission.fieldGroundSystem -- g_currentMission.fieldGroundSystem
    local groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels = fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)

    -- modifiers.sprayModifier =
    modifiers.groundModifier = DensityMapModifier.new(groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels, terrainRootNode)
    modifiers.filter = DensityMapFilter.new(modifiers.groundModifier)
    modifiers.filter:setValueCompareParams(DensityValueCompareType.GREATER, 0)

-- never used:
--     local groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels = fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)
--
--     modifiers.terrainSowingFilter = DensityMapFilter:new(terrainDetailId, self.mission.terrainDetailTypeFirstChannel, self.mission.terrainDetailTypeNumChannels)
--     modifiers.terrainSowingFilter:setValueCompareParams("between", self.mission.firstSowableValue, self.mission.lastSowableValue)
--
    modifiers.map = {}
    modifiers.map.modifier = DensityMapModifier.new(self.map, 0, CropRotation.MAP_NUM_CHANNELS)
    modifiers.map.modifier:setPolygonRoundingMode(DensityRoundingMode.INCLUSIVE)
    modifiers.map.filter = DensityMapFilter.new(modifiers.map.modifier)

    modifiers.map.harvestModifier = DensityMapModifier.new(self.map, 0, 1)
    modifiers.map.harvestFilter = DensityMapFilter.new(modifiers.map.harvestModifier)
    modifiers.map.harvestFilter:setValueCompareParams(DensityValueCompareType.EQUAL, 0)

    modifiers.map.modifierN2 = DensityMapModifier.new(self.map, 5, 3)
    modifiers.map.filterN2 = DensityMapFilter.new(modifiers.map.modifierN2)

    modifiers.map.modifierN1 = DensityMapModifier.new(self.map, 2, 3)
    modifiers.map.filterN1 = DensityMapFilter.new(modifiers.map.modifierN1)

    modifiers.map.modifierF = DensityMapModifier.new(self.map, 1, 1)
    modifiers.map.filterF = DensityMapFilter.new(modifiers.map.modifierF)
    modifiers.map.filterF:setValueCompareParams(DensityValueCompareType.EQUAL, 0)

    modifiers.map.modifierH = DensityMapModifier.new(self.map, 0, 1)

    self.modifiers = modifiers
end

function CropRotation:loadFromSavegame(xmlFile)
end

---Called after the mission is saved to XML
function CropRotation:onMissionSaveToSavegame(mission, xmlFile)
    -- setXMLInt(xmlFile, "seasons#version", self.version)

    self:saveToSavegame(xmlFile)
end

function CropRotation:saveToSavegame(xmlFile)
    if self.map ~= 0 then
        saveBitVectorMapToFile(self.map, self.mission.missionInfo.savegameDirectory .. "/cropRotation.grle")
    end
end

-- periodic event handlers (subscribed in constructor)

function CropRotation:onYearChanged(newYear)
    if newYear == nil then newYear = 0 end
    print(string.format("CropRotation:onYearChanged(year = %s): %s", tostring(newYear),"called!"))

   -- at this point we should check if a field was neither harvested/foraged or sown during entire year
   -- if so then set n2 := n1 and n1 := fellow
   -- and reset harvest state of all fields

   -- we should do it asynchronously, as the entire map needs to be scanned

    local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ

    local size = self.mission.terrainSize

    startWorldX = 0 - size / 2
    startWorldZ = 0 - size / 2

    widthWorldX = size / 2
    widthWorldZ = startWorldZ

    heightWorldX = startWorldX
    heightWorldZ = size / 2

    print("start(%d; %d) width(%d; %d), height(%d; %d)", startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)

    self:updateFallow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
end

function CropRotation:onPeriodChanged(newPeriod)
    if newPeriod == nil then newPeriod = 0 end
    print(string.format("CropRotation:onPeriodChanged(period = %s): %s", tostring(newPeriod), "called!"))
end

function CropRotation:onDayChanged(newDay)
    if newDay == nil then newDay = 0 end
    print(string.format("CropRotation:onDayChanged(day= %s): %s", tostring(newDay), "called!"))
end

function CropRotation:onHourChanged(newHour)
    if newHour == nil then newHour = 0 end
    print(string.format("CropRotation:onHourChanged(hour = %s): %s", tostring(newHour), "called!"))

    local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ
    local size = self.mission.terrainSize

    startWorldX = 0 - size / 2
    startWorldZ = 0 - size / 2

    widthWorldX = size / 2
    widthWorldZ = startWorldZ

    heightWorldX = startWorldX
    heightWorldZ = size / 2

    print("UPDATE FELLOW: start(%d; %d) width(%d; %d) height(%d; %d)", startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)

    self:updateFallow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
end


function CropRotation:updateFallow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
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

----------------------
-- Injections
----------------------

---Reset harvest bit
function CropRotation.inj_densityMapUtil_updateSowingArea(superFunc, fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, fieldGroundType, angle, growthState, blockedSprayTypeIndex)

    -- Oilseed ignores crop rotation
    if true then -- filter on crops that have crop rotation defined fruitId ~= FruitType.OILSEEDRADISH
        local cropRotation = g_cropRotation
        local modifiers = cropRotation.modifiers

        -- Set harvest bit to 0
        local terrainSize = cropRotation.terrainSize
        modifiers.map.harvestModifier:setParallelogramUVCoords(startWorldX / terrainSize + 0.5,
                                                               startWorldZ / terrainSize + 0.5,
                                                               widthWorldX / terrainSize + 0.5,
                                                               widthWorldZ / terrainSize + 0.5,
                                                               heightWorldX / terrainSize + 0.5,
                                                               heightWorldZ / terrainSize + 0.5,
                                                               DensityCoordType.POINT_POINT_POINT)
        modifiers.map.harvestModifier:executeSet(0)
    end

    -- Do the actual sowing
    return superFunc(fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, fieldGroundType, angle, growthState, blockedSprayTypeIndex)
end

---Update the rotation map on harvest (or forage... perhaps foraging should be more damaging to the ground)
function CropRotation.inj_densityMapUtil_cutFruitArea(superFunc, fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, useMinForageState, excludedSprayType, setsWeeds, limitToField)
    local cropRotation = g_cropRotation

    -- Get fruit info
    local desc = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
    if desc.terrainDataPlaneId == nil then
        return 0
    end

    -- Filter on fruit to limit bad hits like grass borders
    local fruitFilter = cropRotation.modifiers.filter
    local minState = useMinForageState and desc.minForageGrowthState or desc.minHarvestingGrowthState
    fruitFilter:resetDensityMapAndChannels(desc.terrainDataPlaneId, desc.startStateChannel, desc.numStateChannels)
    fruitFilter:setValueCompareParams(DensityValueCompareType.BETWEEN, minState + 1, desc.maxHarvestingGrowthState + 1)

    -- Read CR data
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
        mapModifier:executeSet(bits, fruitFilter, cropRotation.modifiers.map.harvestFilter)
    end

    print(string.format("currently cutting %s -> crop rotation yield multiplier = %d", desc.name, yieldMultiplier))

    local numPixels, totalNumPixels, sprayFactor, plowFactor, limeFactor, weedFactor, stubbleFactor, rollerFactor, beeFactor, growthState, maxArea, terrainDetailPixelsSum =
        superFunc(fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, useMinForageState, excludedSprayType, setsWeeds, limitToField)

    -- Update yield
    return numPixels * yieldMultiplier, totalNumPixels, sprayFactor, plowFactor, limeFactor, weedFactor, stubbleFactor, rollerFactor, beeFactor, growthState, maxArea, terrainDetailPixelsSum
end

----------------------
-- Reading and writing
----------------------

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
    local mapHarvestFilter = mapModifiers.harvestFilter

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
    local current = fruitDesc.rotation.category -- TODO: install rotation in fruitTypeManager!

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

----------------------
-- Getting info
----------------------

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
    if category == CropRotation.CATEGORIES.OILSEED then
        return "OILSEED"
    elseif category == CropRotation.CATEGORIES.CEREAL then
        return "CEREAL"
    elseif category == CropRotation.CATEGORIES.LEGUME then
        return "LEGUME"
    elseif category == CropRotation.CATEGORIES.ROOT then
        return "ROOT"
    elseif category == CropRotation.CATEGORIES.NIGHTSHADE then
        return "NIGHTSHADE"
    elseif category == CropRotation.CATEGORIES.GRASS then
        return "GRASS"
    else
        return "FELLOW"
    end

--     return self.i18n:getText(string.format("CropRotation_Category_%d", category))
end

function CropRotation:commandGetInfo()
    local x, _, z = getWorldTranslation(getCamera(0))

    local n2, n1, f, h = self:getInfoAtWorldCoords(x, z)

    log(string.format("(n2)%s -> (n1)%s CRV: %d [F: %s] [H: %s]",
                      self:getCategoryName(n2),
                      self:getCategoryName(n1),
                      self.data:getRotationCategoryValue(n2, n1),
                      tostring(f),
                      tostring(h)))
end

----------------------
-- Debugging
----------------------

-- borrowed from FS19_RM_Seasons mod :)
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
