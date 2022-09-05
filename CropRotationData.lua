--
-- FS22 - Crop Rotation mod
--
-- CropRotationData.lua
--
-- manage static data - crop categories and properties,
-- make contents of data/crops.xml accessible

CropRotationData = {}
CropRotationData.debug = false -- true --

CropRotationData.BAD = 0
CropRotationData.GOOD = 2

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
        return CropRotationData.GOOD
    end

    return self.matrix[current][past] or 1.0
end

----------------------------------------------------------------------
--- LOADING DATA FROM crops.xml
----------------------------------------------------------------------

--load data from file and build the necessary tables for crop rotation
function CropRotationData:load()
    local xmlFile = loadXMLFile("xml", self.xmlFilePath)
    if xmlFile then
        local cropsKey = "crops"
        if not hasXMLProperty(xmlFile, cropsKey) then
            log(string.format("CropRotationData:load(): ERROR loading XML element '%s' failed:", cropsKey), self.xmlFilePath)
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
                break
            end

            local cropName = getXMLString(xmlFile, cropKey .. "#name"):upper()
            if cropName ~= nil then
                local cropReturnPeriod = Utils.getNoNil(getXMLInt(xmlFile, cropKey .. "#returnPeriod"), 2)
                local cropGrowth = Utils.getNoNil(getXMLInt(xmlFile, cropKey .. "#growth"), 0)
                local cropHarvest = Utils.getNoNil(getXMLInt(xmlFile, cropKey .. "#harvest"), 1)

                local goodForecrops = Utils.getNoNil(getXMLString(xmlFile, cropKey .. ".good"), ""):upper()
                local badForecrops = Utils.getNoNil(getXMLString(xmlFile, cropKey .. ".bad"), ""):upper()

                if CropRotationData.debug then
                    log("CropRotationData:load(): DEBUG read crop ", cropName, "forecrops: good: [", goodForecrops, "] bad: [", badForecrops, "]")
                end

                self.crops[cropName] = {
                    returnPeriod = cropReturnPeriod,
                    growth = cropGrowth,
                    harvest = cropHarvest,
                    good = string.split(goodForecrops, " "),
                    bad = string.split(badForecrops, " ")
                }

            else
                log("CropRotationData:load(): ERROR XML loading failed:", self.xmlFilePath)
                return
            end

            i = i + 1
        end

        delete(xmlFile)
    end

    for i, crop in pairs(self.crops) do
        local fruitType = self.fruitTypeManager:getFruitTypeByName(i)
        if fruitType ~= nil then
            fruitType.rotation = {}
            fruitType.rotation.enabled = true
            fruitType.rotation.returnPeriod = crop.returnPeriod
            fruitType.rotation.growth = crop.growth
            fruitType.rotation.harvest = crop.harvest

            self.matrix[fruitType.index] = {}

            for _, name in pairs(crop.good) do
                local forecropType = self.fruitTypeManager:getFruitTypeByName(name)
                if forecropType ~= nil then
                    self.matrix[fruitType.index][forecropType.index] = CropRotationData.GOOD
                end
            end

            for _, name in pairs(crop.bad) do
                local forecropType = self.fruitTypeManager:getFruitTypeByName(name)
                if forecropType ~= nil then
                    self.matrix[fruitType.index][forecropType.index] = CropRotationData.BAD
                end
            end
        end
    end

    -- process fruits not mentioned in crops.xml
    for k, fruitType in pairs(self.fruitTypeManager:getFruitTypes()) do
        if self.crops[fruitType.name] == nil then
            log("CropRotationData:load(): INFO fruit:", fruitType.index, fruitType.name,
                "not mentioned in data/crops.xml file. Loading sane defaults.")

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
end

----------------------------------------------------------------------
-- DEBUG
----------------------------------------------------------------------

function CropRotationData:postLoad()
    log("CropRotationData:postLoad(): DEBUG list fruits in use ...")

    for fruitIndex, fruitType in pairs(self.fruitTypeManager:getFruitTypes()) do
        log("CropRotationData:postLoad(): DEBUG begin crop rotation table for fruit:", fruitIndex, fruitType.name)

        if fruitType.rotation ~= nil then
            DebugUtil.printTableRecursively(fruitType.rotation, "", 0, 1)
        else
            log("CropRotationData:postLoad(): WARNING Empty rotation data for fruit", fruitIndex, fruitType.name)
        end

        log("CropRotationData:postLoad(): DEBUG end crop rotation table for fruit:", fruitIndex,  fruitType.name)
    end

    log("CropRotationData:postLoad(): DEBUG ... done")
end
