FS22_PATH = '/home/bchojnow/Projekty/FS22/fs22-1.10.1.1/?.lua'
MOD_PATH = '/home/bchojnow/Projekty/FS22/FS22_CropRotation/?.lua'

package.path = package.path .. ";".. FS22_PATH .. ";" .. MOD_PATH

function log(...)
    -- print(...)
    --NOOP
end

function addConsoleCommand(...) end
function removeConsoleCommand(...) end

require 'dataS.scripts.shared.class'
require 'utils.Logger'

lu = require('luaunit')

TestLogger = {}
    function TestLogger:test_logSomthing()
        local logger = Logger.create("CRLoggerName")
        logger:setLevel(Logger.INFO)
        logger:setLevel(Logger.OFF)
        logger:debug("DEBUG HAKUNAMATATA")
        logger:info("INFO MARAKUJA")
        logger:warn("WARNING SZAKALAKA")
        logger:error("ERROR PUMBA")
    end

CropRotation = {}
CropRotation.mt = {}

function CropRotation.new()
    local self = setmetatable({}, CropRotation.mt)

    self.log = Logger.create("TEST_CropRotation")
    return self
end

g_cropRotation = CropRotation.new()

require 'maps.ValueMap'

TestValueMap = {}
    function TestValueMap:setUp()
        self.sut = ValueMap.new(g_cropRotation, nil)
    end

    function TestValueMap:test_initialize()
        self.sut:initialize()
        lu.assertEquals("valueMap.grle", self.sut.filename)
        lu.assertEquals("valueMap", self.sut.name)
        lu.assertEquals("VALUE_MAP", self.sut.id)
        lu.assertEquals("unknown", self.sut.label)

        lu.assertEquals(g_cropRotation, self.sut.crModule)

        lu.assertEquals({}, self.sut.bitVectorMapsToSync)
        lu.assertEquals({}, self.sut.bitVectorMapsToSave)
        lu.assertEquals({}, self.sut.bitVectorMapsToDelete)
    end

    function TestValueMap:test_loadFromXml()
        lu.assertTrue(self.sut:loadFromXML())
    end

    function TestValueMap:test_postLoad()
        lu.assertTrue(self.sut:postLoad())
    end

    function TestValueMap:test_addBitVectorMapToSync()
        self.sut:addBitVectorMapToSync({41})
        lu.assertEquals({bitVectorMap={41}}, self.sut.bitVectorMapsToSync[1])
    end

    function TestValueMap:test_addBitVectorMapToSave()
        self.sut:addBitVectorMapToSave({42}, 'file.grle')
        lu.assertEquals({bitVectorMap={42}, filename='file.grle'}, self.sut.bitVectorMapsToSave[1])
    end

    function TestValueMap:test_addBitVectorMapToDelete()
        self.sut:addBitVectorMapToDelete({43})
        lu.assertEquals({bitVectorMap={43}}, self.sut.bitVectorMapsToDelete[1])
    end

require 'maps.CoverMap'

TestCoverMap = {}
    function TestCoverMap:setUp()
        self.sut = CoverMap.new(g_cropRotation)
    end

    function TestCoverMap:test_initialize()
        lu.assertEquals("cropRotation_coverMap.grle", self.sut.filename)
        lu.assertEquals("crCoverMap", self.sut.name)
        lu.assertEquals("VALUE_MAP", self.sut.id)
        lu.assertEquals("unknown", self.sut.label)

        lu.assertEquals(g_cropRotation, self.sut.crModule)

        lu.assertFalse(self.sut:getShowInMenu())
    end

require 'maps.YieldMap'

TestYieldMap = {}
    function TestYieldMap:setUp()
        self.sut = YieldMap.new(g_cropRotation, 'r3')
    end

    function TestYieldMap:test_initialize()
        lu.assertEquals("cropRotation_yieldMap_r3.grle", self.sut.filename)
        lu.assertEquals("crYieldMap_r3", self.sut.name)
        lu.assertEquals("YIELD_MAP_R3", self.sut.id)
        lu.assertEquals("ui_mapOverviewYield_r3", self.sut.label)

        lu.assertEquals(g_cropRotation, self.sut.crModule)

        lu.assertTrue(self.sut:getShowInMenu())
    end

os.exit(lu.LuaUnit.run())
