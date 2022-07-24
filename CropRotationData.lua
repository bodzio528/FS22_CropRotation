--
-- FS22 - Crop Rotation mod
--
-- CropRotationData.lua
--
-- @Author: Bodzio528
-- @Date: 22.07.2022
-- @Version: 1.0.0.0
--
-- Changelog:
-- 	v1.0.0.0 (22.07.2022):
--      - Initial release
--

CropRotationData = {}

local CropRotationData_mt = Class(CropRotationData)

function CropRotationData:new(mission, fruitTypeManager)
    local self = setmetatable({}, CropRotationData_mt)

    self.mission = mission
    self.fruitTypeManager = fruitTypeManager
    self.paths = {}
    self.defaultFruits = {}
    self.cropRotation = {}

    self.isNewGame = true -- not used

    return self
end

function CropRotationData:delete()
    self.defaultFruits = nil
end

function CropRotationData:loadFromSavegame(xmlFile)
    self.isNewGame = false
end

function CropRotationData:setDataPaths(paths)
    self.paths = paths
end

--loads data from files and builds the necessary tables related to crop rotation

function CropRotationData:load()
    self:loadDataFromFiles()
    self:addCustomFruits()
end

-----------------------------------
--- loading functions from crops.xml
-----------------------------------

function CropRotationData:loadDataFromFiles()
--     for _, path in ipairs(self.paths) do
--         local xmlFile = loadXMLFile("xml", path.file)
--         if xmlFile then
--             self:loadDataFromFile(xmlFile)
--             delete(xmlFile)
--         end
--     end
end

function CropRotationData:loadDataFromFile(xmlFile)
    local overwriteGrowthData = Utils.getNoNil(getXMLBool(xmlFile, "crops.growth#overwrite"), false)
    self:loadDefaultFruitsData(xmlFile, overwriteGrowthData)
    self:loadRotationData(xmlFile)
    self:loadFruitTypesData(xmlFile)
end

function CropRotationData:loadDefaultFruitsData(xmlFile, overwriteData)
    if overwriteData == true then
        self.defaultFruits = {}
    end

    local defaultFruitsKey = "crops.growth.defaultCrops"

    if not hasXMLProperty(xmlFile, defaultFruitsKey) then
        -- ERROR!
        print("CropRotationData:loadDefaultFruitsData: XML loading failed " .. defaultFruitsKey .. " not found")
        return
    end

    local i = 0
    while true do
        local defaultFruitKey = string.format("%s.defaultCrop(%i)#name", defaultFruitsKey, i)

        if not hasXMLProperty(xmlFile, defaultFruitKey) then
            break
        end

        local fruitName = (getXMLString(xmlFile, defaultFruitKey)):upper()
        if fruitName ~= nil then
            self.defaultFruits[fruitName] = 1
        else
            -- ERROR!
            print("CropRotationData:loadDefaultFruitsData(): XML loading failed " .. xmlFile)
            return
        end

        i = i + 1
    end
end

-- crop rotation
function CropRotationData:loadRotationData(xmlFile)
    local i = 0
    while true do
        local key = string.format("crops.cropRotation.crop(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local category = getXMLString(xmlFile, key .. "#category")
        local categoryId = CropRotation.CATEGORIES[category]
        if categoryId ~= nil then
            local rotations = {}

            local j = 0
            while true do
                local rotationKey = string.format("%s.rotation(%d)", key, j)
                if not hasXMLProperty(xmlFile, rotationKey) then
                    break
                end

                local cat = getXMLString(xmlFile, rotationKey .. "#category")
                if CropRotation.CATEGORIES[cat] ~= nil then
                    rotations[CropRotation.CATEGORIES[cat]] = Utils.getNoNil(getXMLInt(xmlFile, rotationKey .. "#value"), 1)
                end

                j = j + 1
            end

            self.cropRotation[categoryId] = rotations
        end

        i = i + 1
    end
end

function CropRotationData:getRotationCategoryValue(n, current)
    if n == CropRotation.CATEGORIES.FALLOW then
        return 2
    end

    return self.cropRotation[current][n]
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
            print("CropRotationData:loadDataFromFile fruitTypes section is not defined correctly")
            break
        end

        local fruitType = self.fruitTypeManager:getFruitTypeByName(fruitName)

        -- Fruit type is nil if a fruit is not in the map but is in the GEO.
        if fruitType ~= nil then -- and self.mission.fruits[fruitType.index] ~= nil then
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
--     for index, fruit in pairs(self.mission.fruits) do
--         local fruitType = self.fruitTypeManager:getFruitTypeByIndex(index)
--         local fruitName = fruitType.name
--
--         if self.defaultFruits[fruitName] == nil then -- new fruit found
--             print("CropRotationData:addCustomFruits(): new fruit found: %s", fruitName)
--             self:updateFruitTypesDataWithNewFruit(fruitName)
--         end
--     end
end
--
-- function CropRotationData:updateFruitTypesDataWithNewFruit(fruitName)
--     local fruitType = self.fruitTypeManager:getFruitTypeByName(fruitName)
--
--     fruitType.rotation = {}
--     fruitType.rotation.category = CropRotation.CATEGORIES.CEREAL
--     fruitType.rotation.returnPeriod = 1
-- end
--