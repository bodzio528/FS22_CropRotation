--
-- FS22 - Crop Rotation mod
--
-- InGameMenuCropRotationPlanner.lua
--
-- InGameMenu that allows player to plan crop rotation and get approx yield size
--
-- @Author: Bodzio528
-- @Date: 22.07.2022
-- @Version: 1.0.0.0
--
-- Changelog:
-- 	v1.0.0.0 (22.07.2022):
--      - Initial release

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


function InGameMenuCropRotationPlanner.new(i18n, cropRotation, planner)
    local self = InGameMenuCropRotationPlanner:superClass().new(nil, InGameMenuCropRotationPlanner._mt)

    self.name = "InGameMenuCropRotationPlanner"
    self.i18n = i18n

    self.cropRotation = cropRotation -- yield calculating functions
    self.planner = cropRotationPlanner -- data storage

	self.dataBindings = {}

    self:registerControls(InGameMenuCropRotationPlanner.CONTROLS)

    return self
end

function InGameMenuCropRotationPlanner:delete()
	InGameMenuCropRotationPlanner:superClass().delete(self)
end

function InGameMenuCropRotationPlanner:initialize()
    print(string.format("InGameMenuCropRotationPlanner:initialize(): DEBUG called!"))

    self.listOfAvailableCrops = {
        [-1] = { index = -1 },
        [0] = { index = 0 }
    }

    for i, fruitDesc in pairs(g_fruitTypeManager:getFruitTypes()) do
        if fruitDesc.rotation.enabled then
            table.insert(self.listOfAvailableCrops, {index = i, fruitDesc = fruitDesc})

            log("Adding fruit " .. tostring(i) .. " b'cuz rotation is enabled.")
        end
    end

    DebugUtil.printTableRecursively(self.listOfAvailableCrops, "l", 0, 1)

    for index, element in pairs(self.cropElement) do
        if element.listIndex == nil then
            element.listIndex = -1
            element.index = index
        end
    end

    self:updateRotation()

--
--     self.elementToRotationPosition = {}
--     self.stateToFruitType = {}
--     self.fruitTypeToState = {}
--     self.titles = {}
--     table.insert(self.titles, self.cropRotation:getCategoryName(CropRotation.CATEGORIES.FALLOW))
--     for _, fruitType in ipairs(g_fruitTypeManager:getFruitTypes()) do
--         print(string.format("CropRotation: process fruit type %s", fruitType.name))
--         if fruitType.allowsSeeding and fruitType.name ~= "OILSEEDRADISH" then
--             table.insert(self.titles, fruitType.fillType.title)
--             self.stateToFruitType[#self.titles] = fruitType
--             self.fruitTypeToState[fruitType] = #self.titles
--         end
--     end
--
--     DebugUtil.printTableRecursively(self.titles, "--", 0, 0)
--
-- --     self.titlesWithoutOptionNone = {unpack(self.titles)} -- clone table / make a copy of the table
--     table.insert(self.titles, "-") -- 'NONE'. This _shall_be_ the last entry, else "odd things" may happen, when `updateRotation` begins calling `setTexts()` on the MTOs.
--
--     print(string.format("add titles to rotations %s", tostring(self.rotationPlan)))
--     for i, element in ipairs(self.rotationPlan) do
--         print(string.format("add titles to element[%d] %s", i, element))
--
--         element:setTexts(self.titles)
--         self.elementToRotationPosition[element] = i
--
--         local resultElement = element:getDescendantByName("resultName")
--         local categoryElement = element:getDescendantByName("categoryName")
--
--         print(string.format("detected subelements yield %s and category %s in element[%d] %s",
--                             tostring(resultElement),
--                             tostring(categoryElement),
--                             i,
--                             element))
--     end
-- --
-- --     self:setSettings(self.localStorage:getCropRotations())
-- --
--     self:updateRotations()
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
    -- local factors = {"1.15", "1.10", "1.05", "1.00", "0.90", "0.80", "-.--", "-.--"}

    local orig = {}
    for index, element in pairs(self.cropElement) do
        table.insert(orig, self.listOfAvailableCrops[element.listIndex].index) -- add fruitIndex to original planner list
    end

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

--
-- -------------------------------------------------------------------------------------------------------------------
--
-- InGameMenuFieldplan = {}
-- InGameMenuFieldplan._mt = Class(InGameMenuFieldplan, TabbedMenuFrameElement)
--
-- InGameMenuFieldplan.CONTROLS = {
-- 	MAIN_BOX = "mainBox",
-- 	TABLE_SLIDER = "tableSlider",
-- 	HEADER_BOX = "tableHeaderBox",
-- 	TABLE = "fieldplanTable",
-- 	TABLE_TEMPLATE = "fieldplanRowTemplate",
-- }
--
-- function InGameMenuFieldplan.new(i18n, messageCenter)
-- 	local self = InGameMenuFieldplan:superClass().new(nil, InGameMenuFieldplan._mt)
--
--     self.name = "InGameMenuFieldplan"
--     self.i18n = i18n
--     self.messageCenter = messageCenter
--
-- 	self.dataBindings = {}
--
--     self:registerControls(InGameMenuFieldplan.CONTROLS)
--
--     self.backButtonInfo = {
-- 		inputAction = InputAction.MENU_BACK
-- 	}
-- 	self.btnAdd = {
-- 		text = self.i18n:getText("ui_btn_add"),
-- 		inputAction = InputAction.MENU_ACTIVATE,
-- 		callback = function ()
-- 			self:addRow()
-- 		end
-- 	}
-- 	self.btnEdit = {
-- 		text = self.i18n:getText("ui_btn_edit"),
-- 		inputAction = InputAction.MENU_EXTRA_1,
--         disabled = true,
-- 		callback = function ()
-- 			self:editRow()
-- 		end
-- 	}
-- 	self.btnDelete = {
-- 		text = self.i18n:getText("ui_btn_delete"),
-- 		inputAction = InputAction.MENU_EXTRA_2,
--         disabled = true,
-- 		callback = function ()
-- 			self:deleteRow()
-- 		end
-- 	}
--
--     self:setMenuButtonInfo({
--         self.backButtonInfo,
--         self.btnAdd,
--         self.btnEdit,
--         self.btnDelete,
--     })
--
--     return self
-- end
--
-- function InGameMenuFieldplan:delete()
-- 	InGameMenuFieldplan:superClass().delete(self)
-- end
--
-- function InGameMenuFieldplan:copyAttributes(src)
--     InGameMenuFieldplan:superClass().copyAttributes(self, src)
--     self.i18n = src.i18n
-- end
--
-- function InGameMenuFieldplan:onGuiSetupFinished()
-- 	InGameMenuFieldplan:superClass().onGuiSetupFinished(self)
-- 	self.fieldplanTable:setDataSource(self)
-- 	self.fieldplanTable:setDelegate(self)
-- end
--
-- function InGameMenuFieldplan:initialize()
-- end
--
-- function InGameMenuFieldplan:onFrameOpen()
-- 	InGameMenuFieldplan:superClass().onFrameOpen(self)
--     g_currentMission.workplanFieldsUi = self
--     self:updateContent()
-- 	FocusManager:setFocus(self.fieldplanTable)
-- end
--
-- function InGameMenuFieldplan:onFrameClose()
-- 	InGameMenuFieldplan:superClass().onFrameClose(self)
-- end
--
-- function InGameMenuFieldplan:updateContent()
--     local currentFarmId = -1
--     local farm = g_farmManager:getFarmByUserId(g_currentMission.playerUserId)
--     if farm ~= nil then
--         currentFarmId = farm.farmId
--     end
--
--     self.entries = {
--         {
-- 			title = "",
-- 			items = {}
--         }
--     }
--
--     for _, entry in pairs(g_currentMission.workplan.fieldEntries) do
--         if entry.farmId == currentFarmId or not g_currentMission.missionDynamicInfo.isMultiplayer then
--             table.insert(self.entries[1].items, entry)
--         end
--     end
--
--     self.currentEntry = nil
--     self.btnEdit.disabled = true
--     self.btnDelete.disabled = true
--     self:setMenuButtonInfoDirty()
--
-- 	self.fieldplanTable:reloadData()
-- end
--
-- function InGameMenuFieldplan:getNumberOfSections()
-- 	return #self.entries
-- end
--
-- function InGameMenuFieldplan:getNumberOfItemsInSection(list, section)
-- 	return #self.entries[section].items
-- end
--
-- function InGameMenuFieldplan:populateCellForItemInSection(list, section, index, cell)
-- 	local field = self.entries[section].items[index]
-- 	cell:getAttribute("field"):setText(field.fieldId)
--
--     local currentFruit = "-"
--     local plannedFruit = "-"
--
--     local currentFruitType = g_fruitTypeManager:getFruitTypeByIndex(field.currentFruit)
--     local plannedFruitType = g_fruitTypeManager:getFruitTypeByIndex(field.plannedFruit)
--     if currentFruitType ~= nil and currentFruitType.fillType ~= nil then
--         currentFruit = currentFruitType.fillType.title
--     end
--     if plannedFruitType ~= nil and plannedFruitType.fillType ~= nil then
--         plannedFruit = plannedFruitType.fillType.title
--     end
--
-- 	cell:getAttribute("currentFruit"):setText(currentFruit)
-- 	cell:getAttribute("planedFruit"):setText(plannedFruit)
-- 	cell:getAttribute("lime"):setText(g_currentMission.workplan:getDataTextShort(field.stateLime))
-- 	cell:getAttribute("mulching"):setText(g_currentMission.workplan:getDataTextShort(field.stateMulching))
-- 	cell:getAttribute("plow"):setText(g_currentMission.workplan:getDataTextShort(field.statePlow))
-- 	cell:getAttribute("roller"):setText(g_currentMission.workplan:getDataTextShort(field.stateRoller))
-- 	cell:getAttribute("fert1_typ"):setText(g_currentMission.workplan:getSprayTextShort(field.stateFert1_type))
-- 	cell:getAttribute("fert1_state"):setText(g_currentMission.workplan:getDataTextShort(field.stateFert1_state))
-- 	cell:getAttribute("fert2_typ"):setText(g_currentMission.workplan:getSprayTextShort(field.stateFert2_type))
-- 	cell:getAttribute("fert2_state"):setText(g_currentMission.workplan:getDataTextShort(field.stateFert2_state))
-- 	cell:getAttribute("weedGrooming"):setText(g_currentMission.workplan:getDataTextShort(field.stateWeed_grooming))
-- 	cell:getAttribute("weedSpray"):setText(g_currentMission.workplan:getDataTextShort(field.stateWeed_spray))
-- 	cell:getAttribute("stone"):setText(g_currentMission.workplan:getDataTextShort(field.stateStone))
-- end
--
-- function InGameMenuFieldplan:onListSelectionChanged(list, section, index)
-- 	local entries = self.entries[section]
-- 	if entries ~= nil and entries.items[index] ~= nil then
--         self.currentEntry = entries.items[index]
--         self.btnEdit.disabled = false
--         self.btnDelete.disabled = false
--         self:playSample(GuiSoundPlayer.SOUND_SAMPLES.HOVER)
--     else
--         self.btnEdit.disabled = true
--         self.btnDelete.disabled = true
--     end
--     self:setMenuButtonInfoDirty()
-- end
--
-- function InGameMenuFieldplan:addRow()
--     local dialog = g_gui:showDialog("AddEditFrame")
--     if dialog ~= nil then
--         dialog.target:addRow()
--     end
-- end
--
-- function InGameMenuFieldplan:editRow()
--     local dialog = g_gui:showDialog("AddEditFrame")
--     if dialog ~= nil then
--         dialog.target:editRow(self.currentEntry)
--     end
-- end
--
-- function InGameMenuFieldplan:onDoubleClick(list, section, index, element)
-- 	local data = self.entries[section]
-- 	if data ~= nil and data.items[index] ~= nil then
--         local dialog = g_gui:showDialog("AddEditFrame")
--         if dialog ~= nil then
--             dialog.target:editRow(data.items[index])
--         end
--     end
-- end
--
-- function InGameMenuFieldplan:deleteRow()
--     if self.currentEntry ~= nil then
--         local text = string.format(g_i18n:getText("ui_deleteText"), self.currentEntry.fieldId)
--         g_gui:showYesNoDialog({text = text, title = g_i18n:getText("ui_deleteTitle"), callback = self.onDelete, target = self})
--     end
-- end
--
-- function InGameMenuFieldplan:onDelete()
--     if self.currentEntry ~= nil then
--         g_client:getServerConnection():sendEvent(FieldEntryDeleteEvent.new(self.currentEntry.id))
--     end
-- end
