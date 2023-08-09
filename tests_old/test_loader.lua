require 'fixture'

require 'dataS.scripts.std'
require 'dataS.scripts.xml.XMLManager'
require 'dataS.scripts.utils.Utils'
require 'dataS.scripts.misc.AbstractManager'

require 'dataS.scripts.network.EventIds'
require 'dataS.scripts.FSBaseMission'
require 'dataS.scripts.missions.mission00'
require 'dataS.scripts.misc.HelpLineManager'

require "main"

--[[ TESTCASES ]]--

lu = require('luaunit')

TestIsActive = {}
    function TestIsActive:setUp()
        g_modIsLoaded["FS22_CropRotation"] = false
        lu.assertEquals(false, isActive())
        g_modIsLoaded["FS22_CropRotation_update"] = false
        lu.assertEquals(false, isActive())
    end

    function TestIsActive:tearDown()
        g_modIsLoaded["FS22_CropRotation"] = true
        g_modIsLoaded["FS22_CropRotation_update"] = false
    end

    function TestIsActive:test_when_mod_loaded()
        g_modIsLoaded["FS22_CropRotation"] = true
        lu.assertEquals(true, isActive())
    end

    function TestIsActive:test_when_mod_update_loaded()
        g_modIsLoaded["FS22_CropRotation_update"] = true
        lu.assertEquals(true, isActive())
    end

os.exit(lu.LuaUnit.run())
