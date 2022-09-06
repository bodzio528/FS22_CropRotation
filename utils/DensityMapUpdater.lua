--
-- FS22 Crop Rotation mod
--
-- DensityMapUpdater.lua - class for processing scheduled jobs in chunks, simulating asynchronous execution
--
-- Implementation of Reactor, as described in
-- Schmidt, Douglas et al. Pattern-Oriented Software Architecture Volume 2: Patterns for Concurrent and Networked Objects.

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
    self.tasks = {}

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

    if self.currentTask == nil then
        self.currentTask = self.queue:pop()

        if self.currentTask then
            self.currentTask.x = 0
            self.currentTask.z = 0

            log("DensityMapUpdater: INFO start processing", self.currentTask.taskId)
        end
    end

    if self.currentTask ~= nil then
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
            if self:process(self.currentTask) == DensityMapUpdater.FINISHED then
                self.currentTask = nil

                break
            end
        end
    end
end

function DensityMapUpdater:schedule(taskId)
    if self.isServer then
        if self.tasks[taskId] == nil then
            log("DensityMapUpdater: ERROR Task is not registered:", taskId)
            return
        end

        log("DensityMapUpdater: INFO schedule", taskId)

        self.queue:push({taskId = taskId})
    end
end

function DensityMapUpdater:register(taskId, func, target, onFinish)
    if self.tasks == nil then
        self.tasks = {}
    end

    self.tasks[taskId] = {
        target = target,
        func = func,
        onFinish = onFinish
    }
end

function DensityMapUpdater:unregister(taskId)
    self.tasks[taskId] = nil
end

function DensityMapUpdater:process(job)
    assert(job ~= nil)

    local jobDesc = self.tasks[job.taskId]
    if jobDesc == nil then
        log("DensityMapUpdater: ERROR Tried to run unknown task:", job.taskId)

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
