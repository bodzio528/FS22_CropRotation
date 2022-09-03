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
    self.matrix = {}

    if CropRotationData.debug then
        log("CropRotationData:new(): DEBUG prints enabled - expect high amount of messages at startup.")
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
        return 2.0
    end

    return self.matrix[current][past] or 1.0
end

----------------------------------------------------------------------
--- LOADING DATA FROM crops.xml
----------------------------------------------------------------------

-- yet another LUA split string function.
-- performance level: use only in loading script
function split(s)
    chunks = {}
    for substring in s:gmatch("%S+") do
        table.insert(chunks, substring)
    end

    return chunks
end

--load data from file and build the necessary tables for crop rotation
function CropRotationData:load()
    local xmlFile = loadXMLFile("xml", self.xmlFilePath)
    if xmlFile then
        local cropsKey = "crops"
        if not hasXMLProperty(xmlFile, cropsKey) then
            log(string.format("CropRotationData:load(): ERROR loading XML element '%s' failed:", cropsKey), xmlFile)
            return
        end

        local overwriteData = Utils.getNoNil(getXMLBool(xmlFile, cropsKey .. "#overwrite"), false)
        if overwriteData then
            if CropRotationData.debug then
                log("CropRotationData:load(): DEBUG overwrite crops data with file", self.xmlFilePath)
            end
            self.crops = {}
        end

        local i = 0
        while true do
            local cropKey = string.format("%s.crop(%i)", cropsKey, i)

            if not hasXMLProperty(xmlFile, cropKey) then
                if CropRotationData.debug then log("CropRotationData:load(): successfully processed file", self.xmlFilePath) end
                break
            end

            if cropName ~= nil then
                local cropReturnPeriod = Utils.getNoNil(getXMLInt(xmlFile, cropKey .. "#returnPeriod"), 2)
                local cropGrowth = Utils.getNoNil(getXMLInt(xmlFile, cropKey .. "#growth"), 0)
                local cropHarvest = Utils.getNoNil(getXMLInt(xmlFile, cropKey .. "#harvest"), 0)

                local goodForecrops = Utils.getNoNil(getXMLString(xmlFile, cropKey .. ".good"), ""):upper()
                local badForecrops = Utils.getNoNil(getXMLString(xmlFile, cropKey .. ".bad"), ""):upper()

                if CropRotationData.debug then
                    log("CropRotationData:load(): DEBUG processing crop ", cropName, "forecrops: good: [", goodForecrops, "] bad: [", badForecrops, "]")
                end

                self.crops[cropName] = {
                    returnPeriod = cropReturnPeriod,
                    growth = cropGrowth,
                    harvest = cropHarvest,
                    good = split(goodForecrops),
                    bad = split(badForecrops)
                }

            else
                log("CropRotationData:load(): ERROR XML loading failed:", xmlFile)
                return
            end

            i = i + 1
        end

        delete(xmlFile)
    end

    for i, crop in pairs(self.crops) do
        local fruitType = self.fruitTypeManager:getFruitTypeByName(i)
        if fruitType ~= nil then
            if CropRotationData.debug then
                log("CropRotationData:load(): INFO populate rotation property in fruitType", fruitType.index, fruitType.name)
            end

            fruitType.rotation = {}
            fruitType.rotation.enabled = true
            fruitType.rotation.returnPeriod = crop.returnPeriod
            fruitType.rotation.growth = crop.growth
            fruitType.rotation.harvest = crop.harvest

            self.matrix[fruitType.index] = {}

            for _, name in pairs(crop.good) do
                local forecropType = self.fruitTypeManager:getFruitTypeByName(name)
                if forecropType ~= nil then
                    self.matrix[fruitType.index][forecropType.index] = 2 -- CropRotationData.GOOD
                end
            end

            for _, name in pairs(crop.bad) do
                local forecropType = self.fruitTypeManager:getFruitTypeByName(name)
                if forecropType ~= nil then
                    self.matrix[fruitType.index][forecropType.index] = 0 -- CropRotationData.BAD
                end
            end
        end
    end

    -- process fruits not mentioned in crops.xml
    for k, fruitType in pairs(self.fruitTypeManager:getFruitTypes()) do
        if self.crops[fruitType.name] == nil then
            if CropRotationData.debug then
                log("CropRotationData:load(): added fruit index:", fruitType.index, "not mentioned in crops.xml:", fruitType.name, "using default setting")
            end

            fruitType.rotation = {
                enabled = false,
                returnPeriod = 2,
                growth = 0,
                harvest = 0
            }

            -- no good & no bad forecrops
            self.matrix[fruitType.index] = {}
        end
    end

    self:postLoadInfo()
end

----------------------------------------------------------------------
-- DEBUG
----------------------------------------------------------------------

function CropRotationData:postLoadInfo()
    if CropRotationData.debug then
        log("CropRotationData:postLoadInfo(): [A] list fruit types currently in use...")

        for fruitIndex, fruitType in pairs(self.fruitTypeManager:getFruitTypes()) do
            log(string.format("fruit %d name: %s crop rotation table begin", fruitIndex,  fruitType.name))

            if fruitType.rotation ~= nil then
                DebugUtil.printTableRecursively(fruitType.rotation, "", 0, 1)
            else
                log(string.format("Empty rotation data for fruit %s", fruitType.name))
            end

            log(string.format("fruit %d name: %s crop rotation table end", fruitIndex,  fruitType.name))
        end

        log("CropRotationData:postLoadInfo(): ... done [A]")
    end
end
