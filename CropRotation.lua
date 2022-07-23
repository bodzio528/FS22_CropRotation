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


function CropRotation:new(mission, messageCenter) --environment, fruitTypeManager, densityMapScanner, i18n, data)
    local self = setmetatable({}, CropRotation_mt)

    self.mission = mission
    self.messageCenter = messageCenter

--[[
    self.environment = environment
    self.fruitTypeManager = fruitTypeManager
    self.densityMapScanner = densityMapScanner
    self.data = data
    self.i18n = i18n

    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "updateSowingArea", SeasonsCropRotation.inj_densityMapUtil_updateSowingArea)
    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "updateDirectSowingArea", SeasonsCropRotation.inj_densityMapUtil_updateSowingArea)
    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "cutFruitArea", SeasonsCropRotation.inj_densityMapUtil_cutFruitArea)
--]]

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

--
--     local terrainRootNode = self.mission.terrainRootNode --  g_currentMission.terrainRootNode
--     local fieldGroundSystem = self.mission.fieldGroundSystem -- g_currentMission.fieldGroundSystem
--     local sprayLevelMapId, sprayLevelFirstChannel, sprayLevelNumChannels = fieldGroundSystem:getDensityMapData(FieldDensityMap.SPRAY_LEVEL)
--     local groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels = fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)
--
--
--     functionData.sprayLevelModifier = DensityMapModifier.new(sprayLevelMapId, sprayLevelFirstChannel, sprayLevelNumChannels, terrainRootNode)
--
--     modifiers.sprayModifier = DensityMapModifier:new(terrainDetailId, self.mission.sprayLevelFirstChannel, self.mission.sprayLevelNumChannels)
--     modifiers.filter = DensityMapFilter:new(modifiers.sprayModifier)
--
--     modifiers.terrainSowingFilter = DensityMapFilter:new(terrainDetailId, self.mission.terrainDetailTypeFirstChannel, self.mission.terrainDetailTypeNumChannels)
--     modifiers.terrainSowingFilter:setValueCompareParams("between", self.mission.firstSowableValue, self.mission.lastSowableValue)
--
    local modifiers = {}

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
end
