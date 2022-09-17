--
-- FS22 - Crop Rotation mod
--
-- CropRotationPlanner.lua
--
-- storage class for plans in crop rotation planner, supports (de)serialization
--

CropRotationPlanner = {}
CropRotationPlanner_mt = Class(CropRotationPlanner)

function CropRotationPlanner:new(fruitTypeManager)
    local self = setmetatable({}, CropRotationPlanner_mt)

    self.fruitTypeManager = fruitTypeManager

    self.plans = {}
    self:create(string.format(g_i18n:getText("cropRotation_gui_planner_defaultPlanName"), "A"))

    return self
end

function CropRotationPlanner:saveToSavegame(xmlFile)
    for i, plan in pairs(self.plans) do
        local planKey = string.format("cropRotation.planner.plan(%d)", i - 1)
        setXMLString(xmlFile, planKey .. "#name", plan.name)

        local crops = {}
        for k, cropIndex in pairs(plan.crops) do
            if cropIndex > 0 then
                table.insert(crops, self.fruitTypeManager:getFruitTypeByIndex(cropIndex).name)
            else
                if cropIndex == 0 then
                    table.insert(crops, "FALLOW")
                end
            end
        end

        setXMLString(xmlFile, planKey, table.concat(crops, " "))
    end

end

function CropRotationPlanner:loadFromSavegame(xmlFile)
    local plannerKey = "cropRotation.planner"
    if not hasXMLProperty(xmlFile, plannerKey) then
        log("CropRotationPlanner:loadFromSavegame(): INFO create empty crop rotation plan in memory.")
        return
    end

    self.plans = {}

    local i = 0
    while true do
        local planKey = string.format("%s.plan(%d)", plannerKey, i)
        if not hasXMLProperty(xmlFile, planKey) then
            break
        end

        local planName = Utils.getNoNil(getXMLString(xmlFile, planKey .. "#name"), "Default Plan Name")
        local cropNames = string.split(Utils.getNoNil(getXMLString(xmlFile, planKey), ""):upper(), " ")

        local crops = {} -- cropIndices
        for i, fruitName in pairs(cropNames) do
            if fruitName == "FALLOW" then
                table.insert(crops, 0)
            else
                local fruitDesc = self.fruitTypeManager:getFruitTypeByName(fruitName)
                table.insert(crops, fruitDesc.index)
            end

        end

        local planId = self:create(planName)
        self:update(planId, crops)

        i = i + 1
    end
end

----------------------
-- PUBLIC API
----------------------

function CropRotationPlanner:fetch()
    return self.plans
end

function CropRotationPlanner:create(planName)
    local idx = #self.plans + 1
    self.plans[idx] = {
        name = planName,
        crops = {}
    }
    return idx
end

function CropRotationPlanner:delete(planId)
    self.plans[planId] = nil

    return self:fetch()
end

function CropRotationPlanner:select(planId)
    return self.plans[planId].crops
end

function CropRotationPlanner:update(planId, crops)
    if self.plans[planId] == nil then
        log("CropRotationPlanner:update(): ERROR new plan is requested during update? Unexpected flow.")
        return
    end
    self.plans[planId].crops = crops
end
