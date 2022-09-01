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

function CropRotationData:new(mission, modDirectory, fruitTypeManager)
    local self = setmetatable({}, CropRotationData_mt)

    self.mission = mission
    self.fruitTypeManager = fruitTypeManager

    self.xmlFilePath = Utils.getFilename("data/crops.xml", modDirectory)

    self.crops = {}

    if CropRotationData.debug then
        log("CropRotationData:new(): DEBUG running with debug prints enabled. Expect high amount of messages at startup.")
    end

    return self
end

function CropRotationData:delete()
    self.crops = nil
end

function CropRotationData:loadFromSavegame(xmlFile)
end

----------------------------------------------------------------------
--- PUBLIC INTERFACE
----------------------------------------------------------------------

function CropRotationData:getRotationForecropValue(past, current)
    if past == FruitType.UNKNOWN then
        return 1.0 -- "UNKNOWN"
    end

    -- TODO: rewrite
    -- if self.matrix[current] ~= nil then
    --     return self.matrix[current][past] or 1.0
    -- end

    return 1.0
end

----------------------------------------------------------------------
--- LOADING DATA FROM crops.xml
----------------------------------------------------------------------

function split(s)
    chunks = {}
    for substring in s:gmatch("%S+") do
        table.insert(chunks, substring)
    end

    return chunks
end


--load data from file and build the necessary tables related to crop rotation
function CropRotationData:load()
    log("CropRotationData:load(): INFO populate static crop properties")

    local xmlFile = loadXMLFile("xml", self.xmlFilePath)
    if xmlFile then

        local cropsKey = "crops"
        if not hasXMLProperty(xmlFile, cropsKey) then
            log(string.format("CropRotationData:load(): ERROR XML element %s loading failed:", cropsKey), xmlFile)
            return
        end

        -- local overwriteData = Utils.getNoNil(getXMLBool(xmlFile, cropsKey .. "#overwrite"), false)
        -- if overwriteData then
        --     if CropRotationData.debug then
        --         log(string.format("CropRotationData:load(): DEBUG overwrite crops data in file %s", self.xmlFilePath))
        --     end
        --     self.crops = {}
        -- end

        local i = 0
        while true do
            local cropKey = string.format("%s.crop(%i)", cropsKey, i)

            if not hasXMLProperty(xmlFile, cropKey) then
                break
            end

            local cropName = (getXMLString(xmlFile, cropKey .. "#name")):upper()

            log("CropRotationData:load(): DEBUG processing fruit", cropName)

            if cropName ~= nil then
                local cropReturnPeriod = Utils.getNoNil(getXMLInt(xmlFile, cropKey .. "#returnPeriod"), 2)
                local cropGrowth = Utils.getNoNil(getXMLInt(xmlFile, cropKey .. "#growth"), 0)
                local cropHarvest = Utils.getNoNil(getXMLInt(xmlFile, cropKey .. "#harvest"), 0)
                local cropForage = Utils.getNoNil(getXMLInt(xmlFile, cropKey .. "#forage"), 0)

                local goodForecrops = Utils.getNoNil(getXMLString(xmlFile, cropKey .. ".good"), ""):upper()
                local badForecrops = Utils.getNoNil(getXMLString(xmlFile, cropKey .. ".bad"), ""):upper()
                log("CROP:", cropName, "FORECROPS: GOOD [", goodForecrops, "] BAD: [", badForecrops, "]")

                self.crops[cropName] = {
                    returnPeriod = cropReturnPeriod,
                    growth = cropGrowth,
                    harvest = cropHarvest,
                    forage = cropForage,
                    good = split(goodForecrops),
                    bad = split(badForecrops)
                }

            else
                log("CropRotationData:load(): ERROR XML loading failed:", xmlFile)
                return
            end

            i = i + 1
        end

        DebugUtil.printTableRecursively(self.crops, "", 0, 4)

        -- END: self:loadDataFromFile
        delete(xmlFile)
    end

    log("CropRotationData:load(): INFO populate the crop rotation matrix")


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
