require 'fixture'

function log(s)
    print(s)
end

require('utils.Logger')

require 'CropRotation'

lu = require('luaunit')

TestCR = {}
    function TestCR:test_hasValueMaps()
        crModule = CropRotation.new(nil)
        assertEquals(3, #crModule:getValueMaps())
        assertEquals('crCoverMap', crModule:getValueMap(1).name)
        assertEquals('crYieldMap_n1', crModule:getValueMap(2).name)
        assertEquals('crYieldMap_n2', crModule:getValueMap(3).name)
    end

    function TestCR:test_hasInitialize()
        crModule = CropRotation.new(nil)
        -- crModule:initialize() --
    end


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

os.exit(lu.run())