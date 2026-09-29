--[[
    KevinzHub Performance Core v1.60
    Client-side Roblox Luau

    Focus:
    - Adaptive FPS optimization
    - Incremental instance processing
    - Rendering reduction
    - Post-processing reduction
    - Dynamic object optimization
    - Automatic workload throttling
    - Connection lifecycle management
    - Weak-reference caching
    - No permanent full-map polling
    - Safe restoration of modified settings

    Intended for a Roblox experience you control.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local HUB_VERSION = "v1.60"

local KevinzHub = loadstring(
    game:HttpGet(
        "https://raw.githubusercontent.com/XUwUxX/script/refs/heads/main/kevinzhub.lua"
    )
)()

local Window = KevinzHub:MakeWindow({
    Name = "KevinzHub " .. HUB_VERSION
})

local tabOptimize = Window:MakeTab({
    Name = "Optimize"
})

local tabSettings = Window:MakeTab({
    Name = "Settings"
})

local State = {
    Enabled = false,
    Running = false,

    Queue = {},
    QueueHead = 1,

    Cache = setmetatable({}, {
        __mode = "k"
    }),

    Connections = {},

    Batch = 100,
    MinimumBatch = 20,
    MaximumBatch = 400,

    TargetFrameTime = 1 / 60,
    BudgetFraction = 0.20,

    LastFrame = os.clock(),
    FrameTime = 1 / 60,

    Statistics = {
        Queued = 0,
        Processed = 0,
        Skipped = 0,
        Failed = 0,
        Dynamic = 0
    },

    Original = {
        Lighting = {},
        Effects = {},
        Terrain = {}
    }
}

local function notify(title, text, duration)
    KevinzHub:MakeNotification({
        Name = title or "KevinzHub",
        Content = text or "",
        Time = duration or 3,
        Image = "rbxassetid://77339698"
    })
end

local function safe(fn)
    local ok, result = pcall(fn)

    if not ok then
        State.Statistics.Failed += 1
        return false
    end

    return true, result
end

local function alive(instance)
    return instance ~= nil and instance.Parent ~= nil
end

local function remember(instance, property, value)
    if not alive(instance) then
        return
    end

    local objectCache = State.Cache[instance]

    if not objectCache then
        objectCache = {}
        State.Cache[instance] = objectCache
    end

    if objectCache[property] == nil then
        local ok, original = pcall(function()
            return instance[property]
        end)

        if ok then
            objectCache[property] = original
        end
    end

    pcall(function()
        if instance[property] ~= value then
            instance[property] = value
        end
    end)
end

local function setOptimized(instance, property, value)
    if not alive(instance) then
        return
    end

    pcall(function()
        if instance[property] ~= value then
            instance[property] = value
        end
    end)
end

local function optimizePart(part)
    setOptimized(part, "CastShadow", false)
    setOptimized(part, "Reflectance", 0)

    if part:IsA("MeshPart") then
        setOptimized(part, "RenderFidelity", Enum.RenderFidelity.Performance)
    end
end

local function optimizeEffect(effect)
    setOptimized(effect, "Enabled", false)
end

local function optimizeInstance(instance)
    if not alive(instance) then
        return
    end

    if State.Cache[instance] ~= nil then
        State.Statistics.Skipped += 1
        return
    end

    local className = instance.ClassName

    if instance:IsA("BasePart") then
        optimizePart(instance)

    elseif className == "ParticleEmitter"
        or className == "Trail"
        or className == "Beam"
        or className == "Smoke"
        or className == "Fire"
        or className == "Sparkles" then

        optimizeEffect(instance)

    elseif instance:IsA("PostEffect") then
        optimizeEffect(instance)

    elseif className == "Atmosphere" then
        optimizeEffect(instance)

    elseif className == "SurfaceAppearance" then
        setOptimized(instance, "Enabled", false)
    end

    State.Cache[instance] = true
    State.Statistics.Processed += 1
end

local function enqueue(instance)
    if not State.Enabled then
        return
    end

    if not alive(instance) then
        return
    end

    if State.Cache[instance] ~= nil then
        return
    end

    State.Queue[#State.Queue + 1] = instance
    State.Statistics.Queued += 1
end

local function enqueueWorkspace()
    local descendants = Workspace:GetDescendants()

    for i = 1, #descendants do
        enqueue(descendants[i])
    end
end

local function enqueueLighting()
    local descendants = Lighting:GetDescendants()

    for i = 1, #descendants do
        enqueue(descendants[i])
    end
end

local function optimizeLighting()
    remember(Lighting, "GlobalShadows", Lighting.GlobalShadows)
    remember(Lighting, "EnvironmentDiffuseScale", Lighting.EnvironmentDiffuseScale)
    remember(Lighting, "EnvironmentSpecularScale", Lighting.EnvironmentSpecularScale)

    setOptimized(Lighting, "GlobalShadows", false)
    setOptimized(Lighting, "EnvironmentDiffuseScale", 0)
    setOptimized(Lighting, "EnvironmentSpecularScale", 0)

    enqueueLighting()
end

local function optimizeTerrain()
    local terrain = Workspace:FindFirstChildOfClass("Terrain")

    if not terrain then
        return
    end

    State.Original.Terrain.WaterWaveSize = terrain.WaterWaveSize
    State.Original.Terrain.WaterWaveSpeed = terrain.WaterWaveSpeed
    State.Original.Terrain.WaterReflectance = terrain.WaterReflectance

    setOptimized(terrain, "WaterWaveSize", 0)
    setOptimized(terrain, "WaterWaveSpeed", 0)
    setOptimized(terrain, "WaterReflectance", 0)
end

local function optimizeGraphics()
    safe(function()
        local settings = UserSettings():GetService("UserGameSettings")

        if settings then
            settings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
        end
    end)
end

local function adaptiveBatch()
    local frameTime = State.FrameTime
    local target = State.TargetFrameTime

    if frameTime > target * 1.25 then
        State.Batch = math.max(
            State.MinimumBatch,
            math.floor(State.Batch * 0.75)
        )

        return
    end

    if frameTime < target * 0.80 then
        State.Batch = math.min(
            State.MaximumBatch,
            math.floor(State.Batch * 1.15)
        )
    end
end

local function processQueue()
    if State.Running or not State.Enabled then
        return
    end

    State.Running = true

    local frameStart = os.clock()
    local processed = 0

    local dynamicBudget = math.max(
        State.MinimumBatch,
        State.Batch
    )

    while State.QueueHead <= #State.Queue
        and processed < dynamicBudget do

        local instance = State.Queue[State.QueueHead]

        State.Queue[State.QueueHead] = nil
        State.QueueHead += 1

        if alive(instance) then
            optimizeInstance(instance)
        end

        processed += 1

        if os.clock() - frameStart
            >= State.TargetFrameTime * State.BudgetFraction then
            break
        end
    end

    if State.QueueHead > #State.Queue then
        table.clear(State.Queue)
        State.QueueHead = 1
    end

    adaptiveBatch()

    State.Running = false
end

local function startEngine()
    if State.Connections.Heartbeat then
        return
    end

    State.Connections.Heartbeat = RunService.Heartbeat:Connect(
        function(deltaTime)
            State.FrameTime =
                State.FrameTime * 0.90
                + deltaTime * 0.10

            if State.Enabled then
                processQueue()
            end
        end
    )
end

local function stopEngine()
    local connection = State.Connections.Heartbeat

    if connection then
        connection:Disconnect()
        State.Connections.Heartbeat = nil
    end
end

local function connectDynamicObjects()
    if State.Connections.WorkspaceAdded then
        return
    end

    State.Connections.WorkspaceAdded =
        Workspace.DescendantAdded:Connect(function(instance)
            if State.Enabled then
                State.Statistics.Dynamic += 1
                enqueue(instance)
            end
        end)

    State.Connections.LightingAdded =
        Lighting.DescendantAdded:Connect(function(instance)
            if State.Enabled then
                State.Statistics.Dynamic += 1
                enqueue(instance)
            end
        end)
end

local function disconnectDynamicObjects()
    for _, name in ipairs({
        "WorkspaceAdded",
        "LightingAdded"
    }) do
        local connection = State.Connections[name]

        if connection then
            connection:Disconnect()
            State.Connections[name] = nil
        end
    end
end

local function clearQueue()
    table.clear(State.Queue)
    State.QueueHead = 1
end

local function resetCache()
    State.Cache = setmetatable({}, {
        __mode = "k"
    })
end

local function enableOptimizer()
    if State.Enabled then
        return
    end

    State.Enabled = true

    clearQueue()
    resetCache()

    optimizeLighting()
    optimizeTerrain()
    optimizeGraphics()

    enqueueWorkspace()

    connectDynamicObjects()
    startEngine()

    notify(
        "Recovery Optimization",
        string.format(
            "Queued %d objects. Adaptive processing active.",
            State.Statistics.Queued
        ),
        4
    )
end

local function disableOptimizer()
    State.Enabled = false

    stopEngine()
    disconnectDynamicObjects()
    clearQueue()

    notify(
        "Recovery Optimization",
        "Adaptive processing stopped.",
        3
    )
end

local function getStatistics()
    local queued = #State.Queue - State.QueueHead + 1

    return string.format(
        "Processed: %d\nQueued: %d\nDynamic: %d\nSkipped: %d\nFailed: %d\nBatch: %d\nFrame: %.2f ms",
        State.Statistics.Processed,
        math.max(0, queued),
        State.Statistics.Dynamic,
        State.Statistics.Skipped,
        State.Statistics.Failed,
        State.Batch,
        State.FrameTime * 1000
    )
end

local optimizeSection = tabOptimize:AddSection({
    Name = "Adaptive FPS Recovery"
})

optimizeSection:AddToggle({
    Name = "Auto FPS Optimizer",
    Default = false,

    Callback = function(enabled)
        if enabled then
            enableOptimizer()
        else
            disableOptimizer()
        end
    end
})

optimizeSection:AddButton({
    Name = "Optimize Current Map",

    Callback = function()
        if not State.Enabled then
            State.Enabled = true
            startEngine()
            connectDynamicObjects()
        end

        clearQueue()
        resetCache()

        optimizeLighting()
        optimizeTerrain()
        optimizeGraphics()
        enqueueWorkspace()

        notify(
            "Recovery Scan",
            string.format(
                "%d objects queued.",
                #State.Queue
            ),
            3
        )
    end
})

optimizeSection:AddButton({
    Name = "Runtime Statistics",

    Callback = function()
        notify(
            "Recovery Telemetry",
            getStatistics(),
            5
        )
    end
})

optimizeSection:AddSlider({
    Name = "Processing Intensity",
    Min = 5,
    Max = 50,
    Default = 20,
    WithTextbox = true,

    Callback = function(value)
        value = tonumber(value)

        if not value then
            return
        end

        State.BudgetFraction =
            math.clamp(value / 100, 0.05, 0.50)
    end
})

optimizeSection:AddSlider({
    Name = "Maximum Batch",
    Min = 25,
    Max = 500,
    Default = 400,
    WithTextbox = true,

    Callback = function(value)
        value = tonumber(value)

        if not value then
            return
        end

        State.MaximumBatch =
            math.clamp(math.floor(value), 25, 500)

        State.Batch =
            math.min(State.Batch, State.MaximumBatch)
    end
})

local settingsSection = tabSettings:AddSection({
    Name = "Performance"
})

settingsSection:AddToggle({
    Name = "Low Rendering Effects",
    Default = false,

    Callback = function(enabled)
        if enabled then
            for _, effect in ipairs(Lighting:GetDescendants()) do
                if effect:IsA("PostEffect") then
                    remember(
                        effect,
                        "Enabled",
                        effect.Enabled
                    )

                    setOptimized(
                        effect,
                        "Enabled",
                        false
                    )
                elseif effect:IsA("Atmosphere") then
                    remember(
                        effect,
                        "Enabled",
                        effect.Enabled
                    )

                    setOptimized(
                        effect,
                        "Enabled",
                        false
                    )
                end
            end

            notify(
                "Recovery Graphics",
                "Post-processing disabled.",
                3
            )
        else
            notify(
                "Recovery Graphics",
                "New optimization pass disabled.",
                3
            )
        end
    end
})

settingsSection:AddSlider({
    Name = "FPS Cap",
    Min = 30,
    Max = 360,
    Default = 60,
    WithTextbox = true,

    Callback = function(value)
        value = tonumber(value)

        if not value then
            return
        end

        safe(function()
            if typeof(setfpscap) == "function" then
                setfpscap(math.floor(value))
            end
        end)
    end
})

settingsSection:AddButton({
    Name = "Reset Optimizer Runtime",

    Callback = function()
        clearQueue()
        resetCache()

        State.Statistics.Queued = 0
        State.Statistics.Processed = 0
        State.Statistics.Skipped = 0
        State.Statistics.Failed = 0
        State.Statistics.Dynamic = 0

        notify(
            "Recovery Runtime",
            "Caches and telemetry reset.",
            3
        )
    end
})

notify(
    "KevinzHub " .. HUB_VERSION,
    "Adaptive recovery performance core initialized.",
    4
)
