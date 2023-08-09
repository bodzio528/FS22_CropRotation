InGameMenuCRFrame = {}
local InGameMenuCRFrame_mt = Class(InGameMenuCRFrame, TabbedMenuFrameElement)
InGameMenuCRFrame.CONTROLS = {
    "mapOverviewSelector",
    "ingameMap",
    "mapCursor",
    "mapControls",
    "mapZoomGlyph",
    "mapMoveGlyph",
    "mapBox",
    "mapMoveGlyphText",
    "mapZoomGlyphText",
    "mapOverviewSoilBox",
    "valueMapFilterButton",
    "valueMapFilterColor",
    "valueMapFilterText",
    "laboratoryInfoText",
    "laboratoryWindow",
    "economicAnalysisWindow",
    "economicAnalysisHeaderField",
    "economicAnalysisHeaderValues",
    "buttonSwitchValues",
    "buttonResetStats",
    "statAmountText",
    "statCostText",
    "statPercentageText",
    "statTotalCostText",
    "statTotalCostPercentageText",
    "statTotalEarningsText",
    "statTotalEarningsPercentageText",
    "statTotalText",
    "statTotalPercentageText",
    "fieldBuyInfoWindow",
    "fieldBuyHeader",
    "soilNameText",
    "soilPercentageText",
    "soilPercentageBar",
    "yieldPercentageText",
    "yieldPercentageBarBase",
    "yieldPercentageBarPos",
    "yieldPercentageBarNeg",
    "resetYieldButtonBackground",
    "resetYieldButton",
    "helpButtonBackground",
    "helpButton",
    "envScoreWindow",
    "envScoreBarStatic",
    "envScoreBarDynamic",
    "envScoreBarIndicator",
    "envScoreBarNumber",
    "envScoreDistributionText",
    "envScoreDistributionBarBackground",
    "envScoreDistributionBar",
    "envScoreDistributionValue",
    "envScoreInfoText",
    "buttonAdditionalFunc",
    "buttonSelectIngame"
}
InGameMenuCRFrame.INPUT_CONTEXT_NAME = "MENU_CR"
InGameMenuCRFrame.MOD_NAME = g_currentModName
InGameMenuCRFrame.BUTTON_FRAME_SIDE = GuiElement.FRAME_RIGHT

local function NO_CALLBACK()
end

function InGameMenuCRFrame.new(subclass_mt, messageCenter, l10n, inputManager, inputDisplayManager, farmlandManager, farmManager)
    local self = TabbedMenuFrameElement.new(nil, subclass_mt or InGameMenuCRFrame_mt)

    self:registerControls(InGameMenuCRFrame.CONTROLS)

    self.inputManager = inputManager
    self.farmManager = farmManager
    self.farmlandManager = farmlandManager
    self.onClickBackCallback = NO_CALLBACK
    self.hasFullScreenMap = true
    self.hotspotFilterState = {}
    self.isColorBlindMode = g_gameSettings:getValue(GameSettings.SETTING.USE_COLORBLIND_MODE) or false
    self.isMapOverviewInitialized = false
    self.lastInputHelpMode = 0
    self.ingameMapBase = nil
    self.staticUIDeadzone = {
        0,
        0,
        0,
        0
    }
    self.needsSolidBackground = true
    self.cropRotation = g_cropRotation
    self.activeValueMapIndex = 1

    return self
end

function InGameMenuCRFrame:copyAttributes(src)
    InGameMenuCRFrame:superClass().copyAttributes(self, src)

    self.inputManager = src.inputManager
    self.farmlandManager = src.farmlandManager
    self.farmManager = src.farmManager
    self.onClickBackCallback = src.onClickBackCallback or NO_CALLBACK
end

function InGameMenuCRFrame:onGuiSetupFinished()
    InGameMenuCRFrame:superClass().onGuiSetupFinished(self)

    local _ = nil
    _, self.glyphTextSize = getNormalizedScreenValues(0, InGameMenuCRFrame.GLYPH_TEXT_SIZE)
    self.zoomText = g_i18n:getText(InGameMenuCRFrame.L10N_SYMBOL.INPUT_ZOOM_MAP)
    self.moveCursorText = g_i18n:getText(InGameMenuCRFrame.L10N_SYMBOL.INPUT_MOVE_CURSOR)
    self.panMapText = g_i18n:getText(InGameMenuCRFrame.L10N_SYMBOL.INPUT_PAN_MAP)
end

function InGameMenuCRFrame:delete()
    g_messageCenter:unsubscribeAll(self)
    self.farmlandManager:removeStateChangeListener(self)

    if self.soilStateOverlay ~= nil then
        delete(self.soilStateOverlay)
    end

    if self.farmlandSelectionOverlay ~= nil then
        delete(self.farmlandSelectionOverlay)
    end

    if self.coverStateOverlays ~= nil then
        for i = 1, #self.coverStateOverlays do
            delete(self.coverStateOverlays[i].overlay)
        end
    end

    InGameMenuCRFrame:superClass().delete(self)
end

function InGameMenuCRFrame:initialize(onClickBackCallback)
    if not GS_IS_MOBILE_VERSION then
        self:updateInputGlyphs()
    end

    self.deadzoneElements = {
        self.economicAnalysisWindow,
        self.laboratoryWindow,
        self.mapOverviewSelector
    }
    self.onClickBackCallback = onClickBackCallback or NO_CALLBACK
end

function InGameMenuCRFrame:onFrameOpen()
    InGameMenuCRFrame:superClass().onFrameOpen(self)

    self.isOpen = true

    self:toggleCustomInputContext(true, InGameMenuCRFrame.INPUT_CONTEXT_NAME)
    self.inputManager:removeActionEventsByActionName(InputAction.MENU_EXTRA_2)
    self.ingameMap:onOpen()
    self.ingameMap:registerActionEvents()

    for k, v in pairs(self.ingameMapBase.filter) do
        self.hotspotFilterState[k] = v

        self.ingameMapBase:setHotspotFilter(k, false)
    end

    self.ingameMapBase:setHotspotFilter(MapHotspot.CATEGORY_FIELD, true)
    self.ingameMapBase:setHotspotFilter(MapHotspot.CATEGORY_COMBINE, true)
    self.ingameMapBase:setHotspotFilter(MapHotspot.CATEGORY_STEERABLE, true)
    self.ingameMapBase:setHotspotFilter(MapHotspot.CATEGORY_PLAYER, true)

    self.mapOverviewZoom = 1
    self.mapOverviewCenterX = 0.5
    self.mapOverviewCenterY = 0.5

    if self.visible and not self.isMapOverviewInitialized then
        self:setupMapOverview()
    end

    local cropRotation = self.cropRotation

    if cropRotation.environmentalScore ~= nil then
        cropRotation.environmentalScore:onMapFrameOpen(self)
    end

    local isColorBlindMode = g_gameSettings:getValue(GameSettings.SETTING.USE_COLORBLIND_MODE)

    if self.isColorBlindMode ~= isColorBlindMode then
        self.isColorBlindMode = isColorBlindMode

        if self.visible and self.isMapOverviewInitialized then
            self:setActiveValueMap()
        end
    elseif self.visible and self.isMapOverviewInitialized then
        self:updateSoilStateMapOverlay()
    end

    FocusManager:setFocus(self.mapOverviewSelector)
    self:updateInputGlyphs()
    self:updateAdditionalFunctionButton()
end

function InGameMenuCRFrame:onFrameClose()
    self.ingameMap:onClose()
    self:toggleCustomInputContext(false, InGameMenuCRFrame.INPUT_CONTEXT_NAME)

    for k, v in pairs(self.ingameMapBase.filter) do
        self.ingameMapBase:setHotspotFilter(k, self.hotspotFilterState[k])
    end

    self.isOpen = false

    InGameMenuCRFrame:superClass().onFrameClose(self)
end

function InGameMenuCRFrame:onLoadMapFinished()
    self.soilStateOverlay = createDensityMapVisualizationOverlay("soilState", 1024, 1024)

    setDensityMapVisualizationOverlayUpdateTimeLimit(self.soilStateOverlay, 20)

    self.soilStateOverlayReady = false
    self.farmlandSelectionOverlay = createDensityMapVisualizationOverlay("farmlandSelection", 512, 512)

    setDensityMapVisualizationOverlayUpdateTimeLimit(self.farmlandSelectionOverlay, 20)

    self.farmlandSelectionOverlayReady = false
    local coverMap = self.cropRotation.coverMap

    if coverMap ~= nil then
        self.coverStateOverlays = {}

        for i = 1, coverMap:getNumCoverOverlays() do
            local coverStateOverlay = {
                overlay = createDensityMapVisualizationOverlay("coverState" .. i, 1024, 1024)
            }

            setDensityMapVisualizationOverlayUpdateTimeLimit(coverStateOverlay.overlay, 20)

            coverStateOverlay.overlayReady = false

            table.insert(self.coverStateOverlays, coverStateOverlay)
        end
    end

    self.cropRotation:registerVisualizationOverlay(self.soilStateOverlay)
    self.cropRotation:registerVisualizationOverlay(self.farmlandSelectionOverlay)

    if self.coverStateOverlays ~= nil then
        for i = 1, #self.coverStateOverlays do
            self.cropRotation:registerVisualizationOverlay(self.coverStateOverlays[i].overlay)
        end 
    end
end

function InGameMenuCRFrame:reset()
    InGameMenuCRFrame:superClass().reset(self)

    self.isMapOverviewInitialized = false

    InGameMenuMapUtil.hideContextBox(self.contextBox)
end

function InGameMenuCRFrame:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    return InGameMenuCRFrame:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
end

function InGameMenuCRFrame:update(dt)
    InGameMenuCRFrame:superClass().update(self, dt)

    local currentInputHelpMode = self.inputManager:getInputHelpMode()

    if currentInputHelpMode ~= self.lastInputHelpMode then
        self.lastInputHelpMode = currentInputHelpMode

        CropRotationGUI.updateButtonOnInputHelpChange(self.helpButton, "ingameMenuPrecisionFarmingHelpButtonConsole", "ingameMenuPrecisionFarmingHelpButton")
        self.buttonSelectIngame:setVisible(currentInputHelpMode == GS_INPUT_HELP_MODE_GAMEPAD)

        if self.cropRotation.environmentalScore ~= nil then
            self.cropRotation.environmentalScore:setInputHelpMode(currentInputHelpMode)
        end

        if not GS_IS_MOBILE_VERSION then
            self:updateInputGlyphs()
            self:updateAdditionalFunctionButton()
        end
    end
end

function InGameMenuCRFrame:setTargetPointHotspotPosition(localX, localY)
end

function InGameMenuCRFrame:setInGameMap(ingameMap)
    self.ingameMapBase = ingameMap

    self.ingameMap:setIngameMap(ingameMap)
end

function InGameMenuCRFrame:setTerrainSize(terrainSize)
    self.ingameMap:setTerrainSize(terrainSize)
end

function InGameMenuCRFrame:setMissionFruitTypes(missionFruitTypes)
    self.missionFruitTypes = missionFruitTypes
end

function InGameMenuCRFrame:setClient(client)
    self.client = client
end

function InGameMenuCRFrame:resetUIDeadzones()
    self.ingameMap:clearCursorDeadzones()

    for i = 1, #self.deadzoneElements do
        local element = self.deadzoneElements[i]

        if element:getIsVisible() then
            self.ingameMap:addCursorDeadzone(element.absPosition[1], element.absPosition[2], element.size[1], element.size[2])
        end
    end
end

function InGameMenuCRFrame:setStaticUIDeadzone(screenX, screenY, width, height)
    self.staticUIDeadzone = {
        screenX,
        screenY,
        width,
        height
    }
end

function InGameMenuCRFrame:setupMapOverview()
    self.isMapOverviewInitialized = true
    local cropRotation = self.cropRotation

    if cropRotation.soilMap ~= nil then
        cropRotation.soilMap:setMapFrame(self)
    end

    if cropRotation.farmlandStatistics ~= nil then
        cropRotation.farmlandStatistics:setMapFrame(self)
    end

    if cropRotation.yieldMap ~= nil then
        cropRotation.yieldMap:setMapFrame(self)
    end

    if cropRotation.environmentalScore ~= nil then
        cropRotation.environmentalScore:setMapFrame(self)
    end

    self.mapSelectorTexts = {}
    local valueMaps = self.cropRotation:getValueMaps()

    for i = 1, #valueMaps do
        local valueMap = valueMaps[i]

        if valueMap:getShowInMenu() then
            table.insert(self.mapSelectorTexts, valueMap:getOverviewLabel())
        end
    end

    self.mapOverviewSelector:setTexts(self.mapSelectorTexts)
    self:setActiveValueMap()
    self:updateFarmlandSelection()
end

function InGameMenuCRFrame:updateFarmlandSelection()
    if self.cropRotation.farmlandStatistics ~= nil then
        self.cropRotation.farmlandStatistics:buildOverlay(self.farmlandSelectionOverlay)
        generateDensityMapVisualizationOverlay(self.farmlandSelectionOverlay)

        self.farmlandSelectionOverlayReady = false
    end
end

function InGameMenuCRFrame:setActiveValueMap(valueMapindex)
    valueMapindex = valueMapindex or self.activeValueMapIndex

    if valueMapindex ~= nil then
        local valueMaps = self.cropRotation:getValueMaps()
        local valueMap = valueMaps[valueMapindex]
        local displayValues = valueMap:getDisplayValues()
        local valueFilter, valueFilterEnabled = valueMap:getValueFilter()

        for i = 1, #self.valueMapFilterButton do
            if i <= #valueFilter then
                local filterButton = self.valueMapFilterButton[i]

                filterButton:setVisible(true)
                filterButton:toggleFrameSide(InGameMenuMapFrame.BUTTON_FRAME_SIDE, false)

                filterButton.onHighlightCallback = self.onFilterButtonSelect
                filterButton.onHighlightRemoveCallback = self.onFilterButtonUnselect
                filterButton.onFocusCallback = self.onFilterButtonSelect
                filterButton.onLeaveCallback = self.onFilterButtonUnselect
                local state = displayValues[i]
                local colors = state.colors[self.isColorBlindMode]

                self.valueMapFilterColor[i]:setImageColor(GuiOverlay.STATE_NORMAL, unpack(colors[1]))
                self.valueMapFilterText[i]:setText(state.description)

                if valueFilterEnabled == nil or valueFilterEnabled[i] then
                    function filterButton.onClickCallback()
                        self:onClickValueFilter(filterButton, i)
                    end
                else
                    filterButton.onClickCallback = nil
                end

                for _, child in pairs(filterButton.elements) do
                    child:setDisabled(not valueFilter[i])
                end
            else
                self.valueMapFilterButton[i]:setVisible(false)
            end
        end

        self.activeValueMapIndex = valueMapindex

        for i = 1, #valueMaps do
            if valueMaps[i].onValueMapSelectionChanged ~= nil then
                valueMaps[i]:onValueMapSelectionChanged(valueMap)
            end
        end

        self:updateSoilStateMapOverlay()
        self:updateAdditionalFunctionButton()
    end
end

function InGameMenuCRFrame:updateSoilStateMapOverlay()
    local valueMaps = self.cropRotation:getValueMaps()
    local valueMap = valueMaps[self.activeValueMapIndex]

    if valueMap ~= nil then
        local valueFilter, _ = valueMap:getValueFilter()

        valueMap:buildOverlay(self.soilStateOverlay, valueFilter, self.isColorBlindMode)
        generateDensityMapVisualizationOverlay(self.soilStateOverlay)

        self.soilStateOverlayReady = false
    end

    local coverMap = self.cropRotation.coverMap

    if coverMap ~= nil then
        for i = 1, #self.coverStateOverlays do
            local coverStateOverlay = self.coverStateOverlays[i]

            coverMap:buildCoverStateOverlay(coverStateOverlay.overlay, i)
            generateDensityMapVisualizationOverlay(coverStateOverlay.overlay)

            coverStateOverlay.overlayReady = false
        end
    end
end

function InGameMenuCRFrame:updateAdditionalFunctionButton()
    local isActive = false
    local valueMaps = self.cropRotation:getValueMaps()
    local valueMap = valueMaps[self.activeValueMapIndex]

    if valueMap ~= nil then
        local farmlandId = nil

        if self.cropRotation.farmlandStatistics ~= nil then
            farmlandId = self.cropRotation.farmlandStatistics:getSelectedFarmland()
        end

        isActive = valueMap:getRequiresAdditionalActionButton(farmlandId)

        if isActive then
            local text = valueMap:getAdditionalActionButtonText()

            self.buttonAdditionalFunc:setText(text)
        end
    end

    if not isActive then
        if self.lastInputHelpMode == GS_INPUT_HELP_MODE_GAMEPAD then
            isActive = true

            self.buttonAdditionalFunc:setText(g_i18n:getText("ui_environmentalScoreShowDetails"))
        else
            self:setEnvironmentalScoreWindowState(false)
        end
    else
        self:setEnvironmentalScoreWindowState(false)
    end

    self.buttonAdditionalFunc:setVisible(isActive)
    self.buttonAdditionalFunc.parent:invalidateLayout()
end

function InGameMenuCRFrame:setMapSelectionItem(hotspot)
end

function InGameMenuCRFrame:setMapSelectionPosition(worldX, worldZ)
end

function InGameMenuCRFrame:setEnvironmentalScoreWindowState(state)
    if self.cropRotation.environmentalScore ~= nil then
        self.cropRotation.environmentalScore:toggleWindowSize(state)
    end
end

function InGameMenuCRFrame:onClickMapOverviewSelector(state)
    self:setActiveValueMap(state)
end

function InGameMenuCRFrame:onClickValueFilter(button, index)
    local valueMaps = self.cropRotation:getValueMaps()
    local valueMap = valueMaps[self.activeValueMapIndex]
    local valueFilter, _ = valueMap:getValueFilter()

    if valueFilter ~= nil then
        valueFilter[index] = not valueFilter[index]

        for i = 1, #self.valueMapFilterButton do
            for _, child in pairs(self.valueMapFilterButton[i].elements) do
                child:setDisabled(not valueFilter[i])
            end
        end

        button:toggleFrameSide(InGameMenuMapFrame.BUTTON_FRAME_SIDE, false)
        self:updateSoilStateMapOverlay()
    end
end

function InGameMenuCRFrame.onFilterButtonSelect(_, button)
    button:toggleFrameSide(InGameMenuMapFrame.BUTTON_FRAME_SIDE, true)
end

function InGameMenuCRFrame.onFilterButtonUnselect(_, button)
    button:toggleFrameSide(InGameMenuMapFrame.BUTTON_FRAME_SIDE, false)

    for _, child in pairs(button.elements) do
        child:setDisabled(child:getIsDisabled())
    end
end

function InGameMenuCRFrame:onClickButtonHelp()
    local valueMaps = self.cropRotation:getValueMaps()
    local valueMap = valueMaps[self.activeValueMapIndex]

    if valueMap ~= nil then
        self.cropRotation.helplineExtension:openHelpMenu(valueMap:getHelpLinePage())
    else
        self.cropRotation.helplineExtension:openHelpMenu(0)
    end
end

function InGameMenuCRFrame:onClickButtonResetStats()
    if self.cropRotation.farmlandStatistics ~= nil then
        self.cropRotation.farmlandStatistics:onClickButtonResetStats()
    end
end

function InGameMenuCRFrame:onClickButtonSwitchValues()
    if self.cropRotation.farmlandStatistics ~= nil then
        self.cropRotation.farmlandStatistics:onClickButtonSwitchValues()
    end
end

function InGameMenuCRFrame:onDrawPostIngameMap(element, ingameMap)
    local width, height = self.ingameMapBase.fullScreenLayout:getMapSize()
    local x, y = self.ingameMapBase.fullScreenLayout:getMapPosition()

    if not self.farmlandSelectionOverlayReady and getIsDensityMapVisualizationOverlayReady(self.farmlandSelectionOverlay) then
        self.farmlandSelectionOverlayReady = true
    end

    if self.farmlandSelectionOverlayReady and self.farmlandSelectionOverlay ~= 0 then
        setOverlayUVs(self.farmlandSelectionOverlay, 0, 0, 0, 1, 1, 0, 1, 1)
        renderOverlay(self.farmlandSelectionOverlay, x + width * 0.25, y + height * 0.25, width * 0.5, height * 0.5)
    end

    if not self.soilStateOverlayReady and getIsDensityMapVisualizationOverlayReady(self.soilStateOverlay) then
        self.soilStateOverlayReady = true
    end

    if self.soilStateOverlayReady and self.soilStateOverlay ~= 0 then
        setOverlayUVs(self.soilStateOverlay, 0, 0, 0, 1, 1, 0, 1, 1)
        renderOverlay(self.soilStateOverlay, x + width * 0.25, y + height * 0.25, width * 0.5, height * 0.5)
    end

    local allowCoverage = false
    local valueMaps = self.cropRotation:getValueMaps()
    local valueMap = valueMaps[self.activeValueMapIndex]

    if valueMap ~= nil then
        allowCoverage = valueMap:getAllowCoverage()
    end

    if allowCoverage then
        local coverMap = self.cropRotation.coverMap

        if coverMap ~= nil then
            for i = 1, #self.coverStateOverlays do
                local coverStateOverlay = self.coverStateOverlays[i]

                if not coverStateOverlay.overlayReady and getIsDensityMapVisualizationOverlayReady(coverStateOverlay.overlay) then
                    coverStateOverlay.overlayReady = true
                end

                if coverStateOverlay.overlayReady and coverStateOverlay.overlay ~= 0 then
                    setOverlayUVs(coverStateOverlay.overlay, 0, 0, 0, 1, 1, 0, 1, 1)
                    renderOverlay(coverStateOverlay.overlay, x + width * 0.25, y + height * 0.25, width * 0.5, height * 0.5)
                end
            end
        end
    end
end

function InGameMenuCRFrame:onDrawPostIngameMapHotspots(element, ingameMap)
    if self.activeValueMapIndex == 1 and self.cropRotation.environmentalScore ~= nil then
        self.cropRotation.environmentalScore:onDraw(element, ingameMap)
    end
end

function InGameMenuCRFrame:onClickMap(element, worldX, worldZ)
    local farmlandId = self.farmlandManager:getFarmlandIdAtWorldPosition(worldX, worldZ)

    if farmlandId ~= nil and self.cropRotation.farmlandStatistics ~= nil then
        self.cropRotation.farmlandStatistics:onClickMapFarmland(farmlandId)
        self:updateFarmlandSelection()
    end
end

function InGameMenuCRFrame:updateInputGlyphs()
    local moveActions, moveText = nil

    if self.lastInputHelpMode == GS_INPUT_HELP_MODE_GAMEPAD then
        moveText = self.moveCursorText
        moveActions = {
            InputAction.AXIS_MAP_SCROLL_LEFT_RIGHT,
            InputAction.AXIS_MAP_SCROLL_UP_DOWN
        }
    else
        moveText = self.panMapText
        moveActions = {
            InputAction.AXIS_LOOK_LEFTRIGHT_DRAG,
            InputAction.AXIS_LOOK_UPDOWN_DRAG
        }
    end

    self.mapMoveGlyph:setActions(moveActions, nil, true, true, true)
    self.mapZoomGlyph:setActions({
        InputAction.AXIS_MAP_ZOOM_IN,
        InputAction.AXIS_MAP_ZOOM_OUT
    }, nil, nil, false, true)
    self.mapMoveGlyphText:setText(moveText)
    self.mapZoomGlyphText:setText(self.zoomText)
end

function InGameMenuCRFrame:hasMouseOverlapInFrame()
    return GuiUtils.checkOverlayOverlap(g_lastMousePosX, g_lastMousePosY, self.absPosition[1], self.absPosition[2], self.absSize[1], self.absSize[2])
end

function InGameMenuCRFrame:onZoomIn()
    if self:hasMouseOverlapInFrame() then
        self.ingameMap:zoom(1)
    end
end

function InGameMenuCRFrame:onZoomOut()
    if self:hasMouseOverlapInFrame() then
        self.ingameMap:zoom(-1)
    end
end

function InGameMenuCRFrame:onClickBack()
    self:onClickBackCallback()
end

function InGameMenuCRFrame:onClickAdditionalFuncButton()
    local usedEvent = false
    local valueMaps = self.cropRotation:getValueMaps()
    local valueMap = valueMaps[self.activeValueMapIndex]

    if valueMap ~= nil then
        local farmlandId = nil

        if self.cropRotation.farmlandStatistics ~= nil then
            farmlandId = self.cropRotation.farmlandStatistics:getSelectedFarmland()
        end

        if valueMap:getRequiresAdditionalActionButton(farmlandId) then
            valueMap:onAdditionalActionButtonPressed(farmlandId)

            usedEvent = true
        end
    end

    if not usedEvent and self.lastInputHelpMode == GS_INPUT_HELP_MODE_GAMEPAD then
        self:setEnvironmentalScoreWindowState()
    end
end

InGameMenuCRFrame.GLYPH_TEXT_SIZE = 20
InGameMenuCRFrame.L10N_SYMBOL = {
    INPUT_PAN_MAP = "ui_ingameMenuMapPan",
    INPUT_ZOOM_MAP = "ui_ingameMenuMapZoom",
    INPUT_MOVE_CURSOR = "ui_ingameMenuMapMoveCursor"
}
