--
-- FS22 - Crop Rotation mod
--
-- CropRotationPlanner.lua
--
-- storage class for plan crop rotation planner, supports (de)serialization
--
-- @Author: Bodzio528
-- @Date: 22.07.2022
-- @Version: 1.0.0.0
--
-- Changelog:
-- 	v1.0.0.0 (22.07.2022):
--      - Initial release

CropRotationPlanner = {}
CropRotationPlanner_mt = Class(CropRotationPlanner)

function CropRotationPlanner:new(fruitTypeManager)
    local self = setmetatable({}, CropRotationPlanner_mt)

    self.fruitTypeManager = fruitTypeManager

    return self
end

function CropRotationPlanner:saveToSavegame(xmlFile)
    print(string.format("CropRotationPlanner:saveToSavegame(xmlFile): called!"))
end

function CropRotationPlanner:loadFromSavegame(xmlFile)
    print(string.format("CropRotationPlanner:loadFromSavegame(xmlFile): called!"))
end