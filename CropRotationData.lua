--
-- FS22 - Crop Rotation mod
--
-- CropRotationData.lua
--
-- manage static data - crop categories and properties,
-- make contents of data/crops.xml accessible
--
-- @Author: Bodzio528
-- @Version: 2.0.0.0
--
-- Changelog:
--  v2.0.0.0 (30.08.2022):
--      - code rewrite
-- 	v1.0.0.0 (03.08.2022):
--      - Initial release

CropRotationData = {}
CropRotationData.debug = true -- false --

local CropRotationData_mt = Class(CropRotationData)

function CropRotationData:new(mission, fruitTypeManager)
    local self = setmetatable({}, CropRotationData_mt)

    self.mission = mission
    self.fruitTypeManager = fruitTypeManager

    self.matrix = {}

    if CropRotationData.debug then
        log("WARNING: CropRotationData is running with debug prints enabled. Expect high amount of messages at startup.")
    end

    return self
end

function CropRotationData:delete()
    self.defaultFruits = nil
end

function CropRotationData:loadFromSavegame(xmlFile)
end

----------------------------------------------------------------------
--- PUBLIC INTERFACE
----------------------------------------------------------------------

function CropRotationData:getRotationForecropValue(past, current)
    if past == FruitType.UNKNOWN then
        return 2.0 -- "FALLOW"
    end

    if self.matrix[current] ~= nil then
        return self.matrix[current][past] or 1.0
    end

    return 1.0
end

----------------------------------------------------------------------
--- LOADING DATA
----------------------------------------------------------------------

--load data from files and build the necessary tables related to crop rotation
function CropRotationData:load()
    log("CropRotationData:load(): [1] populate the crop rotation matrix")

    log("CropRotationData:load(): [2] populate the return period per fruit")

    if CropRotationData.debug then
        self:postLoadInfo()
    end
end

-- fruit category and return period
function CropRotationData:loadFruitTypesData(xmlFile)
    local i = 0

    while true do
        local key = string.format("crops.fruitTypes.fruitType(%d)", i)
        if not hasXMLProperty(xmlFile, key) then break end

        local fruitName = (getXMLString(xmlFile, key .. "#name")):upper()

        if fruitName == nil then
            -- ERROR!
            log("CropRotationData:loadFruitTypesData() fruitTypes section is not defined correctly")
            break
        end

        local fruitType = self.fruitTypeManager:getFruitTypeByName(fruitName)

        -- Fruit type is nil if a fruit is not in the map but is in the GEO.
        if fruitType ~= nil then -- and self.mission.fruits[fruitType.index] ~= nil then
            if fruitType.rotation == nil then
                fruitType.rotation = {}
                fruitType.rotation.category = CropRotation.CATEGORIES.CEREAL
                fruitType.rotation.returnPeriod = 1
            end

            local category = getXMLString(xmlFile, key .. ".rotation#category")
            if category ~= nil and CropRotation.CATEGORIES[category] ~= nil then
                fruitType.rotation.category = CropRotation.CATEGORIES[category]
            end
            fruitType.rotation.returnPeriod = Utils.getNoNil(getXMLInt(xmlFile, key .. ".rotation#returnPeriod"), fruitType.rotation.returnPeriod)
        end

        i = i + 1
    end
end

-- check for new fruits and update
function CropRotationData:addCustomFruits()
    for index, fruitType in pairs(self.fruitTypeManager:getFruitTypes()) do
        local fruitName = fruitType.name

        if self.defaultFruits[fruitName] == nil then -- new fruit found outside declarations in crops.xml
            log("CropRotationData:addCustomFruits(): new fruit found: %s", fruitName)
            self:initializeNewFruitToDefault(index)
        end
    end
end

function CropRotationData:initializeNewFruitToDefault(fruitIndex)
    local fruitType = self.fruitTypeManager:getFruitTypeByIndex(fruitIndex)

    fruitType.rotation = {}
    fruitType.rotation.category = CropRotation.CATEGORIES.CEREAL
    fruitType.rotation.returnPeriod = 1
end

----------------------------------------------------------------------
-- DEBUG
----------------------------------------------------------------------

function CropRotationData:postLoadInfo()
    log("CropRotationData:postLoadInfo(): [A] list fruit types currently in use...")
    for fruitIndex, fruitType in pairs(self.fruitTypeManager:getFruitTypes()) do
        log(string.format("fruit %d name: %s crop rotation table:", fruitIndex,  fruitType.name))
        if fruitType.rotation ~= nil then
            DebugUtil.printTableRecursively(fruitType.rotation, "", 0, 1)
        else
            log(string.format("Empty rotation data for fruit %s", fruitType.name))
        end
    end
    log("CropRotationData:postLoadInfo(): ... done [A]")
end
