--
-- FS22 - Crop Rotation mod
--
-- InGameMenuCropRotationPlanner.lua
--
-- InGameMenu that allows player to plan crop rotation and get approx yield size
--

InGameMenuCropRotationPlanner = {
    CONTROLS = {
    	MAIN_BOX = "mainBox",
        BOX_LAYOUT = "boxLayout",
        CROP_ELEMENTS = "cropElement",
        CROP_TEXTS = "cropText",
        CROP_ICONS = "cropIcon",
        CROP_FACTORS = "cropFactor"
    },
    MAX_ROTATION_ELEMENTS = 8
}
InGameMenuCropRotationPlanner._mt = Class(InGameMenuCropRotationPlanner, TabbedMenuFrameElement)


function InGameMenuCropRotationPlanner.new(i18n, crModule, planner)
    local self = InGameMenuCropRotationPlanner:superClass().new(nil, InGameMenuCropRotationPlanner._mt)

    self.name = "InGameMenuCropRotationPlanner"
    self.i18n = i18n

    self.cropRotation = crModule
    self.planner = planner

    self:registerControls(InGameMenuCropRotationPlanner.CONTROLS)

    return self
end

function InGameMenuCropRotationPlanner:delete()
	InGameMenuCropRotationPlanner:superClass().delete(self)
end

function InGameMenuCropRotationPlanner:initialize()
    self.cropIndexToFruitIndexMap = {
        [-1] = { index = -1 },
        [0] = { index = 0 }
    }

    self.fruitIndexToCropIndexMap = {}

    for i, fruitDesc in pairs(g_fruitTypeManager:getFruitTypes()) do
        if fruitDesc ~= nil and fruitDesc.rotation ~= nil then
            if fruitDesc.rotation.enabled then
                table.insert(self.cropIndexToFruitIndexMap, {index = i})
                self.fruitIndexToCropIndexMap[i] = #self.cropIndexToFruitIndexMap
            end
        end
    end

    local plans = self.planner:fetch() -- TODO populate list of rotation plans
    if #plans < 1 then self.planner:create("Default", 0) end

	self.planId = 0 -- TODO: selectable by user
    local plan = self.planner:select(self.planId)

    -- TODO: call on plan selection change: synchronize GUI elements with stored plan
    for index, element in pairs(self.cropElement) do
        if element.cropIndex == nil then
            element.index = index
        end

        element.cropIndex = -1 -- nothing
        if plan.crops[index] ~= nil then -- something
            element.cropIndex = 0 -- fallow
            if plan.crops[index] > 0 then -- crop
                element.cropIndex = self.fruitIndexToCropIndexMap[plan.crops[index]]
                if element.cropIndex == nil then
                    log(string.format(
                        "CropRotationPlanner:initialize(): WARNING plan(%d): '%s' pos: %d crop roptation disabled for fruit: %s. %s",
                        self.planId, plan.name, element.index, g_fruitTypeManager:getFruitTypeByIndex(plan.crops[index]).name,
                        "Most likely due to invalid entry in crop rotation planner save file. Did you remove crop definitions recently?"))
                    element.cropIndex = 0 -- fallback to fallow
                end
            end
        end

    end

    self:updateRotation()
end

local function cr_skip(input)
    result = {}
    for i, v in pairs(input) do
        if v ~= -1 then
            table.insert(result, v)
        end
    end
    return result
end

local function cr_unskip(orig, input)
    local j = 1
    local result = {}
    for k, v in pairs(orig) do
        if v ~= -1 then
            table.insert(result, string.format("%.2f", input[j]))
            j = 1 + j
        else
            table.insert(result, "-")
        end
    end
    return result
end

function InGameMenuCropRotationPlanner:calculateFactors()
    local data = {}
    for _, element in pairs(self.cropElement) do
        table.insert(data, self.cropIndexToFruitIndexMap[element.cropIndex].index)
    end

    self.planner:update(self.planId, data) -- store planner data

    return cr_unskip(data, self.cropRotation:getRotationPlannerYieldMultipliers(cr_skip(data)))
end

function InGameMenuCropRotationPlanner:updateRotation()
    local factors = self:calculateFactors()

    for index, element in pairs(self.cropElement) do
        local elementText = self.cropText[index]
        local elementIcon = self.cropIcon[index]

        if element.cropIndex > 0 then
            local fruitIndex = self.cropIndexToFruitIndexMap[element.cropIndex].index
            local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)

            elementText:setText(fruitDesc.fillType.title)

            local textWidth = elementText:getTextWidth()

            elementIcon:setImageFilename(fruitDesc.fillType.hudOverlayFilename)
            elementIcon:setPosition(elementText.position[1] - textWidth * 0.5 - elementIcon.margin[3], nil)
            elementIcon:setVisible(true)
        else
            if element.cropIndex == 0 then
                elementText:setText(g_i18n:getText("cropRotation_fallow"))
            else
                elementText:setText("--") -- "nothing"
            end

            elementIcon:setVisible(false)
        end

        self.cropFactor[index]:setText(factors[index]) -- this is always valid

        if index > 1 then
            element:setVisible(self.cropElement[index - 1].cropIndex >= 0) -- hide rotation elements after "nothing"
        end
    end
end

----------------------
-- Event handlers
----------------------

function InGameMenuCropRotationPlanner:onValueChanged(value, element)
    if value > 0 then -- next crop
        element.cropIndex = element.cropIndex + 1

        if self.cropIndexToFruitIndexMap[element.cropIndex] == nil then
            element.cropIndex = -1 -- "nothing"

            if element.index < InGameMenuCropRotationPlanner.MAX_ROTATION_ELEMENTS and self.cropElement[element.index + 1].cropIndex >= 0 then
                element.cropIndex = 0 -- or 0, if element.next.cropIndex >= 0
            end
        end
    else -- previous crop
        element.cropIndex = element.cropIndex - 1

        if element.cropIndex < 0 then
            if element.index < InGameMenuCropRotationPlanner.MAX_ROTATION_ELEMENTS and self.cropElement[element.index + 1].cropIndex >= 0 then
                element.cropIndex = #self.cropIndexToFruitIndexMap
            end
            if self.cropIndexToFruitIndexMap[element.cropIndex] == nil then
                element.cropIndex = #self.cropIndexToFruitIndexMap
            end
        end
    end

    self:updateRotation()
end
