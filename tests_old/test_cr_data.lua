require 'fixture'
require 'fruits'

require 'CropRotationData'

-- contents of crops.xml parsed to internal matrix
local GOOD = CropRotationData.GOOD
local NEUTRAL = CropRotationData.NEUTRAL
local BAD = CropRotationData.BAD
local matrix = {
    [FruitType.SOYBEAN] = {[FruitType.SOYBEAN] = NEUTRAL},
    [FruitType.CANOLA]  = {[FruitType.BARLEY] = GOOD, [FruitType.SOYBEAN] = GOOD, [FruitType.OAT] = GOOD,
                           [FruitType.POTATO] = BAD},
    [FruitType.POTATO]  = {[FruitType.SOYBEAN] = GOOD,
                           [FruitType.CANOLA] = BAD, [FruitType.POTATO] = BAD},
    [FruitType.MAIZE]   = {[FruitType.SOYBEAN] = GOOD,
                           [FruitType.CANOLA] = BAD},
    [FruitType.GRASS]   = {[FruitType.GRASS] = GOOD}
}

--[[ TESTCASES ]]--

lu = require('luaunit')

TestData = {}
    function TestData:SetUp()
        sut = CropRotationData:new(nil, g_currentModDirectory, FruitTypeManagerMock)
        sut.matrix = matrix -- TODO: test data parser separately!
    end

    function TestData:test_rotationForecropValue_when_fallow_then_always_good()
        lu.assertEquals(GOOD, sut:getRotationForecropValue(FruitType.UNKNOWN, nil))
    end

    function TestData:test_rotationForecropValue_when_soybean_before_soybean_then_neutral()
        -- explicit NEUTRAL
        lu.assertEquals(NEUTRAL, sut:getRotationForecropValue(FruitType.SOYBEAN, FruitType.SOYBEAN))
    end

    function TestData:test_rotationForecropValue_when_maize_before_soybean_then_neutral()
        -- implicit NEUTRAL
        lu.assertEquals(NEUTRAL, sut:getRotationForecropValue(FruitType.MAIZE, FruitType.SOYBEAN))
    end

    function TestData:test_rotationForecropValue_when_maize_before_maize_then_neutral()
        -- implicit NEUTRAL
        lu.assertEquals(NEUTRAL, sut:getRotationForecropValue(FruitType.MAIZE, FruitType.MAIZE))
    end

    function TestData:test_rotationForecropValue_when_soybean_before_maize_then_good()
        lu.assertEquals(GOOD, sut:getRotationForecropValue(FruitType.SOYBEAN, FruitType.MAIZE))
    end

    function TestData:test_rotationForecropValue_when_potato_before_canola_then_bad()
        lu.assertEquals(BAD, sut:getRotationForecropValue(FruitType.POTATO, FruitType.CANOLA))
    end

    function TestData:test_rotationForecropValue_when_potato_before_potato_then_bad()
        lu.assertEquals(BAD, sut:getRotationForecropValue(FruitType.POTATO, FruitType.POTATO))
    end

    function TestData:test_rotationForecropValue_when_soybean_before_canola_then_good()
        lu.assertEquals(GOOD, sut:getRotationForecropValue(FruitType.SOYBEAN, FruitType.CANOLA))
    end

    function TestData:test_rotationForecropValue_when_grass_before_grass_then_good()
        lu.assertEquals(GOOD, sut:getRotationForecropValue(FruitType.GRASS, FruitType.GRASS))
    end

    function TestData:test_rotationForecropValue_when_oat_before_canola_then_good()
        -- note that OAT is not present in MATRIX as KEY
        lu.assertEquals(GOOD, sut:getRotationForecropValue(FruitType.OAT, FruitType.CANOLA))
    end

    function test_rotationForecropValue_when_canola_before_oat_then_neutral()
        -- OAT is not present in MATRIX as KEY
        lu.assertEquals(NEUTRAL, sut:getRotationForecropValue(FruitType.CANOLA, FruitType.OAT))
    end

os.exit(lu.LuaUnit.run())


