InGameMenuExtension = {
	MOD_NAME = g_currentModName,
	MOD_DIR = g_currentModDirectory,
	GUI_ELEMENTS = g_currentModDirectory .. "gui/ui_elements.png",
	GUI_ELEMENTS_SIZE = {
		1024,
		1024
	},
	GUI_FRAME_REF_XML = g_currentModDirectory .. "gui/IngameMenuCRFrameReference.xml"
}
local InGameMenuExtension_mt = Class(InGameMenuExtension)

function InGameMenuExtension.new(customMt)
	local self = setmetatable({}, customMt or InGameMenuExtension_mt)

	return self
end

function InGameMenuExtension:unloadMapData()
end

function InGameMenuExtension:delete()
end

function InGameMenuExtension:update(dt)
end

function InGameMenuExtension:updateCropRotationOverlays()
	print("InGameMenuExtension:updateCropRotationOverlays()")

	if self.inGameMenuCRFrame ~= nil then
		self.inGameMenuCRFrame:updateSoilStateMapOverlay()
	end
end

function InGameMenuExtension.sortCropRotationPage()
	print("InGameMenuExtension.sortCropRotationPage()")

	local inGameMenu = g_gui.screenControllers[InGameMenu]
	local orderId = inGameMenu.pageTour ~= nil and 3 or 2

	for i = 1, #inGameMenu.pagingElement.elements do
		local child = inGameMenu.pagingElement.elements[i]

		if child == inGameMenu.pageCR then
			table.remove(inGameMenu.pagingElement.elements, i)
			table.insert(inGameMenu.pagingElement.elements, orderId, child)

			break
		end
	end

	for i = 1, #inGameMenu.pagingElement.pages do
		local child = inGameMenu.pagingElement.pages[i]

		if child.element == inGameMenu.pageCR then
			table.remove(inGameMenu.pagingElement.pages, i)
			table.insert(inGameMenu.pagingElement.pages, orderId, child)

			break
		end
	end
end

function InGameMenuExtension.sortCropRotationPageFrame()
	print("InGameMenuExtension.sortCropRotationPageFrame()")

	local inGameMenu = g_gui.screenControllers[InGameMenu]
	local orderId = inGameMenu.pageTour ~= nil and 3 or 2

	for i = 1, #inGameMenu.pageFrames do
		local child = inGameMenu.pageFrames[i]

		if child == inGameMenu.pageCR then
			table.remove(inGameMenu.pageFrames, i)
			table.insert(inGameMenu.pageFrames, orderId, child)

			break
		end
	end

	inGameMenu:rebuildTabList()
end

function InGameMenuExtension:overwriteGameFunctions(crModule)
	local inGameMenu = g_gui.screenControllers[InGameMenu]
	local xmlFile = loadXMLFile("Temp", InGameMenuExtension.GUI_FRAME_REF_XML)

	if xmlFile ~= nil and xmlFile ~= 0 then
		for k, v in pairs({
			"pageCR"
		}) do
			inGameMenu.controlIDs[v] = nil
		end

		inGameMenu:registerControls({
			"pageCR"
		})
		g_gui:loadGuiRec(xmlFile, "inGameMenuCRFrameReference", inGameMenu.pagingElement, self)
		inGameMenu:exposeControlsAsFields("pageCR")
		InGameMenuExtension.sortCropRotationPage()
		inGameMenu.pagingElement:updateAbsolutePosition()
		inGameMenu.pagingElement:updatePageMapping()
		delete(xmlFile)
	end

	self.inGameMenuCRFrame = g_gui:resolveFrameReference(inGameMenu.pageCR)
	local inGameMenuCRFrame = self.inGameMenuCRFrame

	crModule:overwriteGameFunction(InGameMenu, "setInGameMap", function (superFunc, self, inGameMap)
		inGameMenuCRFrame:setInGameMap(inGameMap)
		superFunc(self, inGameMap)
	end)
	crModule:overwriteGameFunction(InGameMenu, "setTerrainSize", function (superFunc, self, terrainSize)
		inGameMenuCRFrame:setTerrainSize(terrainSize)
		superFunc(self, terrainSize)
	end)
	crModule:overwriteGameFunction(InGameMenu, "onLoadMapFinished", function (superFunc, self)
		inGameMenuCRFrame:onLoadMapFinished()
		InGameMenuExtension.sortCropRotationPage()
		InGameMenuExtension.sortCropRotationPageFrame()
		superFunc(self)
	end)
	crModule:overwriteGameFunction(TabbedMenu, "onPageChange", function (superFunc, self, pageIndex, pageMappingIndex, element, skipTabVisualUpdate)
		if self.pageMapOverview ~= nil and self.pageAI ~= nil and self.pageCR ~= nil then
			local prevPage = self.pagingElement:getPageElementByIndex(self.currentPageId)

			if prevPage == self.pageMapOverview then
				self.pageAI.ingameMap:copySettingsFromElement(self.pageMapOverview.ingameMap)
				self.pageCR.ingameMap:copySettingsFromElement(self.pageMapOverview.ingameMap)
			elseif prevPage == self.pageAI then
				self.pageMapOverview.ingameMap:copySettingsFromElement(self.pageAI.ingameMap)
				self.pageCR.ingameMap:copySettingsFromElement(self.pageAI.ingameMap)
			elseif prevPage == self.pageCR then
				self.pageCR.ingameMap:copySettingsFromElement(self.pageCR.ingameMap)
				self.pageMapOverview.ingameMap:copySettingsFromElement(self.pageCR.ingameMap)
			end
		end

		superFunc(self, pageIndex, pageMappingIndex, element, skipTabVisualUpdate)
	end)
	inGameMenu:registerPage(inGameMenu.pageCR, 19, function ()
		return true
	end)
	inGameMenu:addPageTab(inGameMenu.pageCR, InGameMenuExtension.GUI_ELEMENTS, GuiUtils.getUVs({
		129,
		1,
		62,
		62
	}))
	inGameMenu.pageCR:applyScreenAlignment()
	inGameMenu.pageCR:updateAbsolutePosition()
	inGameMenu.pageCR:onGuiSetupFinished()
	InGameMenuExtension.sortCropRotationPageFrame()
	self.inGameMenuCRFrame:initialize(inGameMenu.clickBackCallback)
end

if g_gui ~= nil then
	local frameController = InGameMenuCRFrame.new(nil, g_messageCenter, g_i18n, g_inputBinding, g_inputDisplayManager, g_farmlandManager, g_farmManager)

	g_gui:loadGui(InGameMenuExtension.MOD_DIR .. "gui/InGameMenuCRFrame.xml", "CRFrame", frameController, true)
end
