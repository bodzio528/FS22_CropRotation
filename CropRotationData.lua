--
-- FS22 - Crop Rotation mod
--
-- CropRotationData.lua
--
-- manage static data - crop categories and properties,
-- make contents of data/crops.xml accessible

CropRotationData = {
    MOD_DIRECTORY = g_currentModDirectory
}

CropRotationData.BAD = 0
CropRotationData.NEUTRAL = 1
CropRotationData.GOOD = 2

local CropRotationData_mt = Class(CropRotationData)

function CropRotationData:new(crModule, customMt)
    local self = setmetatable({}, customMt or CropRotationData_mt)

    self.crModule = crModule
    self.crModule.log:debug("CropRotationData:new() debug prints enabled - expect high amount of messages at startup.")

    self.matrix = {}

    return self
end

function CropRotationData:initialize()
    self.crModule.log:debug("CropRotationData:initialize()")

    self.fruitTypeManager = g_fruitTypeManager
end

function CropRotationData:delete()
    self.crModule.log:debug("CropRotationData:delete() kthxbye!")

    self.matrix = nil
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

    if self.matrix[current] then
        return self.matrix[current][past] or CropRotationData.NEUTRAL
    end

    return CropRotationData.NEUTRAL
end

----------------------------------------------------------------------
--- LOADING DATA FROM crops.xml
----------------------------------------------------------------------

function CropRotationData:loadFromXML(xmlFile, key, baseDirectory, cropsXmlFileName, mapFilename)
    self.crModule.log:debug("CropRotationData:loadFromXML() path: " .. cropsXmlFileName)

    if xmlFile then
        local crops, overwrite = self:parseCropsXml(xmlFile, key, cropsXmlFileName)

        if crops then
            self:process(crops, overwrite, cropsXmlFileName)
        end
    end

    -- optional: load crops.xml from different locations
end

--load data from file and build the necessary tables for crop rotation
function CropRotationData:parseCropsXml(xmlFile, cropsKey, cropsXmlFileName)
    self.crModule.log:debug("CropRotationData:parseCropsXml()")

    if not hasXMLProperty(xmlFile, cropsKey) then
        self.crModule.log:error("CropRotationData:parseCropsXml(): loading XML element '" .. cropsKey .. "' failed: " .. cropsXmlFileName)
        return
    end

    local crops = {}
    local overwrite = Utils.getNoNil(getXMLBool(xmlFile, cropsKey .. "#overwrite"), false)
    if overwrite then
        self.crModule.log:debug("CropRotationData:parseCropsXml(): overwrite crops data with file " .. cropsXmlFileName)
    end

    local i = 0
    while true do
        local cropKey = string.format("%s.crop(%i)", cropsKey, i)
        if not hasXMLProperty(xmlFile, cropKey) then
            break
        end

        local cropName = getXMLString(xmlFile, cropKey .. "#name"):upper()
        if cropName ~= nil then
            local cropEnabled = Utils.getNoNil(getXMLBool(xmlFile, cropKey .. "#enabled"), true)
            local cropReturnPeriod = Utils.getNoNil(getXMLInt(xmlFile, cropKey .. "#returnPeriod"), 2)
            local goodForecrops = Utils.getNoNil(getXMLString(xmlFile, cropKey .. ".good"), ""):upper()
            local badForecrops = Utils.getNoNil(getXMLString(xmlFile, cropKey .. ".bad"), ""):upper()

            self.crModule.log:debug(string.format("CropRotationData:parseCropsXml(): reading crop %s forecrops: good: [%s] bad: [%s]", cropName, goodForecrops, badForecrops))
            
            crops[cropName] = {
                enabled = cropEnabled,
                returnPeriod = cropReturnPeriod,
                good = string.split(goodForecrops, " "),
                bad = string.split(badForecrops, " ")
            }
        else
            self.crModule.log:error("CropRotationData:parseCropsXml():  loading XML element '"..cropKey .. "#name' failed: " .. cropsXmlFileName)
            return crops, overwrite
        end

        i = i + 1
    end

    return crops, overwrite
end

function CropRotationData:process(crops, overwrite, cropsXmlFileName)
    self.crModule.log:debug("CropRotationData:process()")

    if overwrite then
        self.crModule.log:debug('CropRotationData:process(): overwrite crop rotation matrix by discarding entries created so far')
        self.matrix = {}
    end

    -- write crop rotation data to fruitTypeManager and compose local matrix
    for cropName, cropDesc in pairs(crops) do
        local fruitType = self.fruitTypeManager:getFruitTypeByName(cropName)
        if fruitType ~= nil then
            fruitType.rotation = {}
            fruitType.rotation.enabled = cropDesc.enabled
            fruitType.rotation.returnPeriod = cropDesc.returnPeriod

            self.matrix[fruitType.index] = {}

            for _, name in pairs(cropDesc.good) do
                local forecropType = self.fruitTypeManager:getFruitTypeByName(name)
                if forecropType ~= nil then
                    self.matrix[fruitType.index][forecropType.index] = CropRotationData.GOOD
                end
            end

            for _, name in pairs(cropDesc.bad) do
                local forecropType = self.fruitTypeManager:getFruitTypeByName(name)
                if forecropType ~= nil then
                    self.matrix[fruitType.index][forecropType.index] = CropRotationData.BAD
                end
            end
        end
    end

    -- process fruits not mentioned in crops.xml
    for k, fruitType in pairs(self.fruitTypeManager:getFruitTypes()) do
        if crops[fruitType.name] == nil then
            self.crModule.log:info(string.format("CropRotationData:process(): fruit (%i): '%s' not mentioned in file %s", fruitType.index, fruitType.name, cropsXmlFileName))

            fruitType.rotation = {
                enabled = false,
                returnPeriod = 2
            }

            -- no good and no bad forecrops
            self.matrix[fruitType.index] = {}
        end
    end
end

----------------------------------------------------------------------
-- DEBUG
----------------------------------------------------------------------

function CropRotationData:postLoad()
    self.crModule.log:debug("CropRotationData:postLoad(): list fruits in rotation ...")

    for fruitIndex, fruitType in pairs(self.fruitTypeManager:getFruitTypes()) do
        if fruitType.rotation ~= nil then
            if fruitType.rotation.enabled then
                self.crModule.log:debug(string.format("ENABLED fruit(%d): %s RP=%d", fruitIndex, fruitType.name, fruitType.rotation.returnPeriod))
            else
                self.crModule.log:debug(string.format("DISABLED fruit(%d): %s", fruitIndex, fruitType.name))
            end
        else
            local s = string.format("INVALID fruit(%d): %s", fruitIndex, fruitType.name)
            self.crModule.log:warning(s)
        end
    end

    self.crModule.log:debug("CropRotationData:postLoad(): ... done")
end
