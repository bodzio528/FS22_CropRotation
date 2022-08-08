--
-- FS22 - Crop Rotation mod
--
-- CropRotationGeo.lua
--
-- import crops definitions from third party GEO mods
--
-- @Author: Bodzio528
-- @Date: 08.08.2022
-- @Version: 1.1.0.0
--
-- Changelog:
-- 	v1.1.0.0 (08.08.2022):
--      - added support for loading crops from GEO mods
--

CropRotationGeo = {}

local CropRotationGeo_mt = Class(CropRotationGeo)

function CropRotationGeo:new(modManager, modDirectory, mission)
    self = setmetatable({}, CropRotationGeo_mt)

    self.modManager = modManager
    self.modDirectory = modDirectory
    self.mission = mission

    -- align with Seasons19 version
    self.minAPIVersion = 10
    self.maxAPIVersion = 11 -- 1,2,3 = fs17, 10 = fs19 1.0, 11 = fs19 1.0.1 (geo fix)

    self.mods = {}
    self.dataDirectories = {}
    self.isGEOModActive = false

    return self
end

function CropRotationGeo:delete()
end

function CropRotationGeo:load()
    local mods = self.modManager:getActiveMods()

    for _, mod in ipairs(mods) do
        local xmlFile = loadXMLFile("ModDesc", mod.modFile)

        if xmlFile then
            self:loadMod(mod, xmlFile)

            delete(xmlFile)
        end
    end
end

---Load a third party mod
function CropRotationGeo:loadMod(mod, xmlFile)
    local version = getXMLInt(xmlFile, "modDesc.seasons#version")

    -- Version parameter is required
    if version == nil then
        return
    end

    if version > self.maxAPIVersion or version < self.minAPIVersion then
        log("WARNING: Mod '" .. mod.title .. "' is not compatible with the current version of Seasons. Skipping.")
        return
    end

    local modType = getXMLString(xmlFile, "modDesc.seasons.type")
    if modType == nil then
        log("ERROR: Mod '" .. mod.title .. "' has a Seasons information block but it missing a type. Skipping.")
        return
    end
    modType = modType:lower()

    -- Loading multiple GEO mods is never something that a player would want.
    if modType == "geo" and self.isGEOModActive then
        log("ERROR: Multiple GEO mods are active. Mod '" .. mod.title .. "' will not be loaded.")
        return
    end

    local modInfo = {}
    modInfo.mod = mod
    modInfo.modType = modType

    local dataFolder = getXMLString(xmlFile, "modDesc.seasons.dataFolder")
    if dataFolder ~= nil then
        modInfo.dataFolder = Utils.getFilename(dataFolder, mod.modDir)
        self:addDataDirectory(modInfo.dataFolder, mod.modDir)
    end

    if modType == "geo" then
        modInfo.isGEO = true
        self.isGEOModActive = true
    end

    table.insert(self.mods, modInfo)
end

---Get list of third party mods
function CropRotationGeo:getMods()
    return self.mods
end

---Add a data directory
function CropRotationGeo:addDataDirectory(path, modDir)
    table.insert(self.dataDirectories, { path = path, modDir = modDir })
end

---Get a list of data directories to find files, in order.
-- This also includes the folder from Seasons.
function CropRotationGeo:getDataDirectories()
    return self.dataDirectories
end

---Get all data directories, in order
function CropRotationGeo:getDataPaths(filename)
    local paths = {}

    -- Add map
    if self.mission.missionInfo.map ~= nil then
        local path = Utils.getFilename("seasons/" .. filename, self.mission.missionInfo.baseDirectory)
        if fileExists(path) then
            table.insert(paths, { file = path, modDir = self.mission.missionInfo.baseDirectory })
        end
    end

    -- Add third party mods
    for _, dir in ipairs(self.dataDirectories) do
        local path = Utils.getFilename(filename, dir.path)

        if fileExists(path) then
            table.insert(paths, { file = path, modDir = dir.modDir })
        end
    end

    return paths
end
