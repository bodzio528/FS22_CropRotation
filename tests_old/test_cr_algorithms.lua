require 'fixture'
require 'fruits'

DEBUG = false

require 'CropRotation'
require 'CropRotationData'

--[[ TESTCASES ]]--

lu = require('luaunit')

local EPS = 0.01
local cropsXmlData = {
    BARLEY  = { enabled = true, returnPeriod = 2, bad = {},                   good = {'SOYBEAN', 'CANOLA', 'POTATO'} },
    SOYBEAN = { enabled = true, returnPeriod = 3, bad = {},                   good = {}                              },
    CANOLA  = { enabled = true, returnPeriod = 3, bad = {'POTATO'},           good = {'BARLEY', 'SOYBEAN', 'OAT'}    },
    POTATO  = { enabled = true, returnPeriod = 3, bad = {'CANOLA', 'POTATO'}, good = {'SOYBEAN'}                     },
    MAIZE   = { enabled = true, returnPeriod = 1, bad = {'CANOLA'},           good = {'SOYBEAN'}                     },
    GRASS   = { enabled = true, returnPeriod = 1, bad = {},                   good = {'GRASS'}                       },
    WHEAT   = { enabled = true, returnPeriod = 2, bad = {'WHEAT'},            good = {'SOYBEAN', 'CANOLA'}           },
    OAT     = { enabled = true, returnPeriod = 2, bad = {},                   good = {'SOYBEAN', 'CANOLA'}           },
    CARROT  = { enabled = true, returnPeriod = 2, bad = {},                   good = {'CARROT'}                      },
    BEETS   = { enabled = false } -- not present in FruitTypeManager - ignore
}

local fruitTypeManagerMock = FruitTypeManagerMock
local crDataMock = CropRotationData:new(nil, nil, fruitTypeManagerMock)

TestCRA = {}
    function TestCRA:setUp()
        crDataMock:process(cropsXmlData, fruitTypeManagerMock)

        -- mission, modDirectory, messageCenter, fruitTypeManager, i18n, data, densityMapUpdater, planner)
        sut = CropRotation:new(nil, nil, nil, fruitTypeManagerMock, nil, crDataMock, nil, nil)
    end

    function TestCRA:test_rotationYildMultiplier_fallow2x_before_soybean_then_perfect_115()
        local yield = sut:getRotationYieldMultiplier(FruitType.UNKNOWN, FruitType.UNKNOWN, FruitType.SOYBEAN)
        lu.assertAlmostEquals(1.15, yield, EPS)
    end

    function TestCRA:test_rotationYildMultiplier_potato3x_then_bad_50()
        local yield = sut:getRotationYieldMultiplier(FruitType.POTATO, FruitType.POTATO, FruitType.POTATO)
        lu.assertAlmostEquals(0.50, yield, EPS)
    end

    function TestCRA:test_rotationYildMultiplier_grass3x_then_good_110()
        local yield = sut:getRotationYieldMultiplier(FruitType.GRASS, FruitType.GRASS, FruitType.GRASS)
        lu.assertAlmostEquals(1.10, yield, EPS)
    end

    function TestCRA:test_rotationYildMultiplier_maize_fallow_before_maize_then_average_100()
        local yield = sut:getRotationYieldMultiplier(FruitType.MAIZE, FruitType.FALLOW, FruitType.MAIZE)
        lu.assertAlmostEquals(1.00, yield, EPS)
    end

    function TestCRA:test_planner_empty()
        lu.assertEquals({}, sut:getRotationPlannerYieldMultipliers({}))
    end

    function TestCRA:test_planner_degenerated()
        lu.assertEquals({0}, sut:getRotationPlannerYieldMultipliers({FruitType.UNKNOWN}))
        lu.assertAlmostEquals({1.05, 0.0, 1.1}, sut:getRotationPlannerYieldMultipliers({FruitType.MAIZE, FruitType.UNKNOWN, FruitType.MAIZE}))
    end

    function TestCRA:test_planner_barley_monoculture()
        lu.assertAlmostEquals({0.9}, sut:getRotationPlannerYieldMultipliers({FruitType.BARLEY}))
    end

    function TestCRA:test_plannerMonoculture1x()
        lu.assertAlmostEquals({0.50}, sut:getRotationPlannerYieldMultipliers({FruitType.POTATO}))
        lu.assertAlmostEquals({0.60}, sut:getRotationPlannerYieldMultipliers({FruitType.WHEAT}))
        lu.assertAlmostEquals({0.80}, sut:getRotationPlannerYieldMultipliers({FruitType.CANOLA}))
        lu.assertAlmostEquals({0.90}, sut:getRotationPlannerYieldMultipliers({FruitType.BARLEY}))
        lu.assertAlmostEquals({0.95}, sut:getRotationPlannerYieldMultipliers({FruitType.MAIZE}))
        lu.assertAlmostEquals({1.05}, sut:getRotationPlannerYieldMultipliers({FruitType.CARROT}))
        lu.assertAlmostEquals({1.10}, sut:getRotationPlannerYieldMultipliers({FruitType.GRASS}))
    end

    function TestCRA:test_plannerMonoculture2x()
        lu.assertAlmostEquals({0.50, 0.50}, sut:getRotationPlannerYieldMultipliers({FruitType.POTATO,   FruitType.POTATO}))
        lu.assertAlmostEquals({0.60, 0.60}, sut:getRotationPlannerYieldMultipliers({FruitType.WHEAT,    FruitType.WHEAT}))
        lu.assertAlmostEquals({0.80, 0.80}, sut:getRotationPlannerYieldMultipliers({FruitType.CANOLA,   FruitType.CANOLA}))
        lu.assertAlmostEquals({0.90, 0.90}, sut:getRotationPlannerYieldMultipliers({FruitType.BARLEY,   FruitType.BARLEY}))
        lu.assertAlmostEquals({0.95, 0.95}, sut:getRotationPlannerYieldMultipliers({FruitType.MAIZE,    FruitType.MAIZE}))
        lu.assertAlmostEquals({1.05, 1.05}, sut:getRotationPlannerYieldMultipliers({FruitType.CARROT,   FruitType.CARROT}))
        lu.assertAlmostEquals({1.10, 1.10}, sut:getRotationPlannerYieldMultipliers({FruitType.GRASS,    FruitType.GRASS}))
    end

    function TestCRA:test_plannerMonoculture3x()
        lu.assertAlmostEquals({0.50, 0.50, 0.50}, sut:getRotationPlannerYieldMultipliers({FruitType.POTATO, FruitType.POTATO,   FruitType.POTATO}))
        lu.assertAlmostEquals({0.60, 0.60, 0.60}, sut:getRotationPlannerYieldMultipliers({FruitType.WHEAT,  FruitType.WHEAT,    FruitType.WHEAT}))
        lu.assertAlmostEquals({0.80, 0.80, 0.80}, sut:getRotationPlannerYieldMultipliers({FruitType.CANOLA, FruitType.CANOLA,   FruitType.CANOLA}))
        lu.assertAlmostEquals({0.90, 0.90, 0.90}, sut:getRotationPlannerYieldMultipliers({FruitType.BARLEY, FruitType.BARLEY,   FruitType.BARLEY}))
        lu.assertAlmostEquals({0.95, 0.95, 0.95}, sut:getRotationPlannerYieldMultipliers({FruitType.MAIZE,  FruitType.MAIZE,    FruitType.MAIZE}))
        lu.assertAlmostEquals({1.05, 1.05, 1.05}, sut:getRotationPlannerYieldMultipliers({FruitType.CARROT, FruitType.CARROT,   FruitType.CARROT}))
        lu.assertAlmostEquals({1.10, 1.10, 1.10}, sut:getRotationPlannerYieldMultipliers({FruitType.GRASS,  FruitType.GRASS,    FruitType.GRASS}))
    end

    function TestCRA:test_plannerCereals2x()
        lu.assertAlmostEquals({1.0, 1.0}, sut:getRotationPlannerYieldMultipliers({FruitType.BARLEY, FruitType.OAT}))
    end

    function TestCRA:test_plannerCereals3x()
        lu.assertAlmostEquals({1.0, 1.0, 1.0}, sut:getRotationPlannerYieldMultipliers({FruitType.BARLEY, FruitType.WHEAT, FruitType.OAT}))
    end

    function TestCRA:test_perfect_plan()
        local crops = { -- all crops have return period of 3 years
            BARLEY  = { enabled = true, returnPeriod = 3, bad = {}, good = {'WHEAT',  'OAT'}   },
            WHEAT   = { enabled = true, returnPeriod = 3, bad = {}, good = {'BARLEY', 'OAT'}   },
            OAT     = { enabled = true, returnPeriod = 3, bad = {}, good = {'BARLEY', 'WHEAT'} }
        }
        crDataMock:process(crops, fruitTypeManagerMock)

        lu.assertAlmostEquals({1.15, 1.15, 1.15}, sut:getRotationPlannerYieldMultipliers({FruitType.BARLEY, FruitType.WHEAT, FruitType.OAT}))
    end


    function TestCRA:test_plannerFallow6x()
        lu.assertAlmostEquals({0, 0, 1.15, 0, 0, 1.15},
            sut:getRotationPlannerYieldMultipliers({FruitType.UNKNOWN, FruitType.UNKNOWN, FruitType.BARLEY,
                                                    FruitType.UNKNOWN, FruitType.UNKNOWN, FruitType.BARLEY}))
    end

    function TestCRA:test_plannerFallow9x()
        lu.assertAlmostEquals({0, 1.15, 0, 0, 1.15, 0, 0, 1.15, 0},
            sut:getRotationPlannerYieldMultipliers({FruitType.UNKNOWN, FruitType.BARLEY, FruitType.UNKNOWN,
                                                    FruitType.UNKNOWN, FruitType.BARLEY, FruitType.UNKNOWN,
                                                    FruitType.UNKNOWN, FruitType.BARLEY, FruitType.UNKNOWN}))
    end

os.exit(lu.run())

