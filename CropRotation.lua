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
local CropRotation_mt = Class(SeasonsCropRotation)

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
    local self = setmetatable({}, SeasonsCropRotation_mt)
	
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
	self.messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)
end


function CropRotation:onMapLoaded(mission, node)
	print(string.format("CropRotation:onMapLoaded(mission, node): %s", "has been called"))
	
end

function CropRotation:onTerrainLoaded(mission, terrainId, mapFilename)
	print(string.format("CropRotation:onTerrainLoaded(mission, terrainId, mapFilename): %s", "has been called 00"))
	
    self.terrainSize = self.mission.terrainSize

    self:loadMap()
    self:loadModifiers()
end

function CropRotation:loadMap()
	print(string.format("CropRotation:loadMap(): %s", "has been called 10"))
end

function SeasonsCropRotation:onMissionLoaded()
	print(string.format("CropRotation:onMissionLoaded(mission, node): %s", "has been called"))
end

function CropRotation:loadModifiers()
	print(string.format("CropRotation:loadModifiers(): %s", "has been called 20"))
end

-- periodic event handlers (subscribed in constructor)

function CropRotation:onYearChanged()
	print(string.format("CropRotation:onYearChanged(): %s", "has been called 2 !"))
end

function CropRotation:onPeriodChanged()
	print(string.format("CropRotation:onPeriodChanged(): %s", "has been called 3 !"))
end

function CropRotation:onHourChanged()
	print(string.format("CropRotation:onHourChanged(): %s", "has been called 1 !"))
end
