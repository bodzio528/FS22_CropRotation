----------------------------------------------------------------------------------------------------
-- TODO:
-- try to replace it with GIANTS engine functions (not documented).
--
-- what have I found so far:
-- self.fallowUpdater = createDensityMapUpdater("cropRotation", self.bitVectorMap, firstChannel, numChannels, minValue, maxValue, 0, 0, 0, 0, 0)
-- setDensityMapUpdaterApplyFinishedCallback(self.fallowUpdater, "onEngineStepFinished", self)
-- setDensityMapUpdaterApplyMaxTimePerFrame(self.fallowUpdater, self:getMaxUpdateTime())                        -- 1 or 1.5 when sleeping, use g_sleepManager
--
-- local groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels = self.mission.fieldGroundSystem:getDensityMapData(FieldDensityMap.GROUND_TYPE)
-- setDensityMapUpdaterMask(self.fallowUpdater, groundTypeMapId, groundTypeFirstChannel, groundTypeNumChannels) -- update only field ground
-- setDensityMapUpdaterEnabled(self.fallowUpdater, true)                                                        -- probably unneeded, could be usefull to pause updater under heavy stress
--
-- call prepared updater with different masks to update category to FALLOW wherever the conditions are satisfied
-- setDensityMapUpdaterNextValue(self.fallowUpdater, 0, from, to)                                               -- second argument seems to be wrong, engine refuses it, while in PrecisionFarming it works well
-- applyDensityMapUpdater(self.fallowUpdater, "onEngineStepFinishedCallback", self, self:getMaxUpdateTime())    -- schedule the work
----------------------------------------------------------------------------------------------------

DensityMapUpdater = {}

local DensityMapUpdater_mt = Class(DensityMapUpdater)

DensityMapUpdater.BLOCK_WIDTH = 32
DensityMapUpdater.BLOCK_HEIGHT = 32

-- job processing status
DensityMapUpdater.FINISHED = 1
DensityMapUpdater.CONTINUE = 2

function DensityMapUpdater:new(mission, sleepManager, isDedicatedServer)
    local self = setmetatable({}, DensityMapUpdater_mt)

    self.mission = mission
    self.isServer = self.mission:getIsServer()
    self.isDedicatedServer = isDedicatedServer

    self.sleepManager = sleepManager

    self.queue = Queue:new()
    self.callbacks = {}

    return self
end

function DensityMapUpdater:delete()
    self.queue:delete()
end

function DensityMapUpdater:load()
end

function DensityMapUpdater:update(dt)
    if not self.isServer then
        return
    end

    if self.currentJob == nil then
        self.currentJob = self.queue:pop()

        if self.currentJob then
            self.currentJob.x = 0
            self.currentJob.z = 0

            log("DensityMapUpdater: INFO start processing", self.currentJob.callbackId)
        end
    end

    if self.currentJob ~= nil then
        local num = 2 * math.floor(self.mission.terrainSize / 2048)

        if not GS_IS_CONSOLE_VERSION then
            num = num * 4
        end

        if self.sleepManager.isSleeping then
            num = num * 16
        end

        if self.isDedicatedServer then
            num = self.mission.terrainSize / DensityMapUpdater.BLOCK_WIDTH
        end

        for i = 1, num do
            if self:process(self.currentJob) == DensityMapUpdater.FINISHED then
                self.currentJob = nil

                break
            end
        end
    end
end

function DensityMapUpdater:schedule(callbackId)
    if self.isServer then
        if self.callbacks[callbackId] == nil then
            log("DensityMapUpdater: ERROR Callback is not registered:", callbackId)
            return
        end

        log("DensityMapUpdater: INFO schedule", callbackId)

        self.queue:push({callbackId = callbackId})
    end
end

function DensityMapUpdater:registerCallback(callbackId, func, target, onFinish)
    if self.callbacks == nil then
        self.callbacks = {}
    end

    self.callbacks[callbackId] = {
        target = target,
        func = func,
        onFinish = onFinish
    }
end

function DensityMapUpdater:unregisterCallback(callbackId)
    self.callbacks[callbackId] = nil
end

function DensityMapUpdater:process(job)
    assert(job ~= nil)

    local jobDesc = self.callbacks[job.callbackId]
    if jobDesc == nil then
        log("DensityMapUpdater: ERROR Tried to run unknown callback:", job.callbackId)

        return false
    end

    local height = DensityMapUpdater.BLOCK_HEIGHT
    local width = DensityMapUpdater.BLOCK_WIDTH

    local size = self.mission.terrainSize
    local pixelSize = size / getDensityMapSize(self.mission.terrainDetailHeightId)

    local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ

    startWorldX = job.x * width - size / 2 + pixelSize * 0.25
    startWorldZ = job.z * height - size / 2 + pixelSize * 0.25

    widthWorldX = startWorldX + width - pixelSize * 0.5
    widthWorldZ = startWorldZ

    heightWorldX = startWorldX
    heightWorldZ = startWorldZ + height - pixelSize * 0.5

    jobDesc.func(jobDesc.target, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)

    if job.x < (size / width) - 1 then
        job.x = job.x + 1
    elseif job.z < (size / height) - 1 then
        job.z = job.z + 1
        job.x = 0
    else
        if jobDesc.onFinish ~= nil then
            jobDesc.onFinish(jobDesc.target)
        end

        return DensityMapUpdater.FINISHED
    end

    return DensityMapUpdater.CONTINUE
end
