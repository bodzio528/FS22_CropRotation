--
-- FS22 - Crop Rotation mod
--
-- CropRotationPlanner.lua
--
-- storage class for plans in crop rotation planner, supports (de)serialization
--

CropRotationPlanner = {}
CropRotationPlanner_mt = Class(CropRotationPlanner)

function CropRotationPlanner:new(crModule)
    local self = setmetatable({}, CropRotationPlanner_mt)

    self.crModule = crModule
    self.crModule.log:debug("CropRotationPlanner:new()")

    return self
end

function CropRotationPlanner:initialize()
    self.crModule.log:debug("CropRotationPlanner:initialize()")

    self.plans = {}
    self.farmlandMapping = {}

    -- self:create("Plan A", 0)
end

function CropRotationPlanner:serialize(plan)
    local crops = {}
    for _, cropIndex in pairs(plan) do
        if cropIndex > 0 then
            table.insert(crops, g_fruitTypeManager:getFruitTypeByIndex(cropIndex).name)
        else
            if cropIndex == 0 then
                table.insert(crops, "FALLOW")
            end
        end
    end
    return table.concat(crops, " ")
end

function CropRotationPlanner:saveToXMLFile(xmlFile, key)
    self.crModule.log:debug("CropRotationPlanner:saveToXMLFile(): key="..key..")")

    local plannerKey = key..".planner"
    for i, plan in pairs(self.plans) do
        local planKey = string.format(plannerKey..".plan(%d)", i - 1)
        xmlFile:setString(planKey .. "#name", plan.name)
        xmlFile:setInt(planKey .. "#farmlandId", plan.farmlandId or 0)
        xmlFile:setString(planKey, self:serialize(plan.crops))
    end
end

function CropRotationPlanner:deserialize(cropNames)
    local crops = {} -- cropIndices
    for j, fruitName in pairs(cropNames) do
        if fruitName == "FALLOW" then
            table.insert(crops, 0)
        else
            local fruitDesc = g_fruitTypeManager:getFruitTypeByName(fruitName)

            if fruitDesc ~= nil then
                table.insert(crops, fruitDesc.index)
            else
                self.crModule.log:info("CropRotationPlanner:deserialize(): replace unknown fruit "..fruitName.."with FALLOW")
                table.insert(crops, 0)
            end
        end
    end
    return crops
end

function CropRotationPlanner:loadFromItemsXML(xmlFile, key)
    self.crModule.log:debug("CropRotationPlanner:loadFromItemsXML(): key="..key)
    
    local plannerKey = key..".planner"
    if not xmlFile:hasProperty(plannerKey) then
        local name = string.format(g_i18n:getText("cropRotation_gui_planner_defaultPlanName"), "A")
        self:create(name, 0)
        return -- nothing to do
    end

    self.plans = {} -- clear old plans
    self.farmlandMapping = {} -- clear farmland mapping

    local i = 0
    while true do
        local planKey = string.format(plannerKey..".plan(%d)", i)
        if not xmlFile:hasProperty(planKey) then
            break
        end

        local planName = Utils.getNoNil(xmlFile:getString(planKey .. "#name"), "Default Plan Name")
        local planId = Utils.getNoNil(xmlFile:getInt(planKey .. "#farmlandId"), 0)
        local cropNames = string.split(Utils.getNoNil(xmlFile:getString(planKey), ""):upper(), " ")
        local crops = self:deserialize(cropNames)

        self:create(planName, planId, crops)
        i = i + 1
    end
end

----------------------
-- PUBLIC INTERFACE
----------------------

function CropRotationPlanner:fetch()
    return self.plans
end

-- planId == farmlandId
function CropRotationPlanner:create(planName, farmlandId, crops)
    local idx = #self.plans + 1
    self.plans[idx] = {
        name = planName,
        farmlandId = farmlandId,
        crops = crops or {}
    }
    self.farmlandMapping[farmlandId] = idx
    return farmlandId
end

function CropRotationPlanner:delete(farmlandId)
    self.plans[self.farmlandMapping[farmlandId]] = nil
    self.farmlandMapping[farmlandId] = nil
    return self:fetch()
end

function CropRotationPlanner:select(farmlandId)
    return self.plans[self.farmlandMapping[farmlandId]]
end

function CropRotationPlanner:update(farmlandId, crops)
    local idx = self.farmlandMapping[farmlandId]
    if self.plans[idx] == nil then
        self.crModule.log:error("CropRotationPlanner:update(): new plan requested for update? Unexpected flow.")
        return
    end
    self.plans[idx].crops = crops
end
