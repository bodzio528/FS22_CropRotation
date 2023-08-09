require 'fixture'

require 'dataS.scripts.std'
require 'dataS.scripts.xml.XMLManager'
require 'dataS.scripts.utils.Utils'
require 'dataS.scripts.misc.AbstractManager'
require 'dataS.scripts.misc.FruitTypeManager'

FruitTypeManagerMock = {}

-- crops present in manager
FruitType.BARLEY = 1
FruitType.SOYBEAN = 2
FruitType.CANOLA = 3
FruitType.POTATO = 4
FruitType.MAIZE = 5
FruitType.GRASS = 6
FruitType.WHEAT = 7
FruitType.OAT = 8
FruitType.CARROT = 9
FruitType.SORGHUM = 10

local names = {
    BARLEY  = FruitType.BARLEY,
    SOYBEAN = FruitType.SOYBEAN,
    CANOLA  = FruitType.CANOLA,
    POTATO  = FruitType.POTATO,
    MAIZE   = FruitType.MAIZE,
    GRASS   = FruitType.GRASS,
    WHEAT   = FruitType.WHEAT,
    OAT     = FruitType.OAT,
    CARROT  = FruitType.CARROT,
    SORGHUM = FruitType.SORGHUM
}

local fruitTypes = {
    [FruitType.BARLEY]  = { index = FruitType.BARLEY,  name = 'BARLEY'  },
    [FruitType.SOYBEAN] = { index = FruitType.SOYBEAN, name = 'SOYBEAN' },
    [FruitType.CANOLA]  = { index = FruitType.CANOLA,  name = 'CANOLA'  },
    [FruitType.POTATO]  = { index = FruitType.POTATO,  name = 'POTATO'  },
    [FruitType.MAIZE]   = { index = FruitType.MAIZE,   name = 'MAIZE'   },
    [FruitType.GRASS]   = { index = FruitType.GRASS,   name = 'GRASS'   },
    [FruitType.WHEAT]   = { index = FruitType.WHEAT,   name = 'WHEAT'   },
    [FruitType.OAT]     = { index = FruitType.OAT,     name = 'OAT'     },
    [FruitType.CARROT]  = { index = FruitType.CARROT,  name = 'CARROT'  },
    [FruitType.SORGHUM] = { index = FruitType.SORGHUM, name = 'SORGHUM' }
}

function FruitTypeManagerMock:getFruitTypeByIndex(index)
    return fruitTypes[index]
end

function FruitTypeManagerMock:getFruitTypeByName(index)
    return fruitTypes[names[index]]
end

function FruitTypeManagerMock:getFruitTypes()
    return fruitTypes
end
