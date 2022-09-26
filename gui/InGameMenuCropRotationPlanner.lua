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

    self.cropRotation = crModule -- yield calculating functions
    self.planner = planner -- data storage

	self.planId = 1 -- TODO: multiple crop rotation plans

    self:registerControls(InGameMenuCropRotationPlanner.CONTROLS)

    return self
end

function InGameMenuCropRotationPlanner:delete()
	InGameMenuCropRotationPlanner:superClass().delete(self)
end

function InGameMenuCropRotationPlanner:initialize()
    self.listOfAvailableCrops = {
        [-1] = { index = -1 },
        [0] = { index = 0 }
    }

    for i, fruitDesc in pairs(g_fruitTypeManager:getFruitTypes()) do
        if fruitDesc.rotation.enabled then
            table.insert(self.listOfAvailableCrops, {index = i, fruitDesc = fruitDesc})
        end
    end

    -- local plans = self.planner:fetch() -- TODO populate list of rotation plans

    local plan = self.planner:select(self.planId)
    for index, element in pairs(self.cropElement) do
        if element.listIndex == nil then
            element.listIndex = plan[index] or -1
            element.index = index
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
    local orig = {}
    for _, element in pairs(self.cropElement) do
        if self.listOfAvailableCrops[element.listIndex] ~= nil then
            table.insert(orig, self.listOfAvailableCrops[element.listIndex].index)
        else
            log("InGameMenuCropRotationPlanner:calculateFactors(): ERROR Fruit not available with index", element.listIndex)
            DebugUtil.printTableRecursively(self.listOfAvailableCrops, "", 0, 1)

            table.insert(orig, 0)
        end
    end

    self.planner:update(self.planId, orig)

    return cr_unskip(orig, self.cropRotation:getRotationPlannerYieldMultipliers(cr_skip(orig)))
end

function InGameMenuCropRotationPlanner:updateRotation()
    local factors = self:calculateFactors()

    for index, element in pairs(self.cropElement) do
        -- local cropText = self.cropText[index]
        -- local cropIcon = self.cropIcon[index]
        -- local cropFactor = self.cropFactor[index]

        if element.listIndex > 0 then
            local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(self.listOfAvailableCrops[element.listIndex].index)

            self.cropText[index]:setText(fruitDesc.fillType.title)

            local width = self.cropText[index]:getTextWidth()

            self.cropIcon[index]:setImageFilename(fruitDesc.fillType.hudOverlayFilename)
            self.cropIcon[index]:setPosition(self.cropText[index].position[1] - width * 0.5 - self.cropIcon[index].margin[3], nil)
            self.cropIcon[index]:setVisible(true)
        else -- special cases: fallow and skipped (nothing)
            if element.listIndex == 0 then
                self.cropText[index]:setText(g_i18n:getText("cropRotation_fallow"))
            else
                self.cropText[index]:setText("--") -- skipped
            end

            self.cropIcon[index]:setVisible(false)
        end

        self.cropFactor[index]:setText(factors[index]) -- this is always valid

        if index > 1 then
            element:setVisible(self.cropElement[index - 1].listIndex >= 0)
        end
    end

end

----------------------
-- Events
----------------------

function InGameMenuCropRotationPlanner:onValueChanged(value, element)
    if value > 0 then -- next crop
        element.listIndex = element.listIndex + 1

        if self.listOfAvailableCrops[element.listIndex] == nil then
            element.listIndex = -1

             -- or 0, when element.next.listIndex >= 0
            if element.index < InGameMenuCropRotationPlanner.MAX_ROTATION_ELEMENTS and self.cropElement[element.index + 1].listIndex >= 0 then
                element.listIndex = 0
            end
        end
    else -- previous crop
        element.listIndex = element.listIndex - 1
        if element.listIndex < 0 then
            if element.index < InGameMenuCropRotationPlanner.MAX_ROTATION_ELEMENTS and self.cropElement[element.index + 1].listIndex >= 0 then
                element.listIndex = #self.listOfAvailableCrops
            end
            if self.listOfAvailableCrops[element.listIndex] == nil then
                element.listIndex = #self.listOfAvailableCrops
            end
        end
    end

    self:updateRotation()
end
