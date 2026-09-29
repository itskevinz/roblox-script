--[[
    Extreme FPS Booster V3
    Client-side Roblox Luau
    Rayfield UI

    Optimization:
    - Incremental descendant processing
    - Adaptive batch size
    - Object deduplication
    - Weak-key cache
    - No permanent per-object polling
    - Lighting optimization
    - Terrain optimization
    - Optional FPS cap
    - Automatic workload throttling
    - Connection cleanup
    - Avoids repeated property writes
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Rayfield = loadstring(
    game:HttpGet("https://sirius.menu/rayfield")
)()

local State = {
    Enabled = false,
    Processing = false,

    BatchSize = 150,
    MinimumBatchSize = 25,
    MaximumBatchSize = 500,

    TargetFrameTime = 1 / 60,
    LastProcess = 0,

    Processed = setmetatable({}, {
        __mode = "k"
    }),

    Queue = {},
    QueueHead = 1,

    Connections = {},

    Statistics = {
        Processed = 0,
        Skipped = 0,
        Failed = 0
    }
}

local function Safe(fn)
    local success = pcall(fn)

    if not success then
        State.Statistics.Failed += 1
    end

    return success
end

local function IsAlive(instance)
    return instance ~= nil and instance.Parent ~= nil
end

local function SetPropertyIfNeeded(instance, property, value)
    local success, current = pcall(function()
        return instance[property]
    end)

    if not success then
        return
    end

    if current ~= value then
        pcall(function()
            instance[property] = value
        end)
    end
end

local function OptimizePart(part)
    if part:IsA("MeshPart") then
        SetPropertyIfNeeded(part, "TextureID", "")
    end

    SetPropertyIfNeeded(part, "Material", Enum.Material.SmoothPlastic)
    SetPropertyIfNeeded(part, "Reflectance", 0)
    SetPropertyIfNeeded(part, "CastShadow", false)
end

local function OptimizeEffect(instance)
    SetPropertyIfNeeded(instance, "Enabled", false)
end

local function OptimizeLightingEffect(instance)
    if instance:IsA("BlurEffect")
        or instance:IsA("SunRaysEffect")
        or instance:IsA("ColorCorrectionEffect")
        or instance:IsA("BloomEffect")
        or instance:IsA("DepthOfFieldEffect")
        or instance:IsA("Atmosphere") then

        OptimizeEffect(instance)
    end
end

local function OptimizeInstance(instance)
    if not IsAlive(instance) then
        return
    end

    if State.Processed[instance] then
        State.Statistics.Skipped += 1
        return
    end

    State.Processed[instance] = true

    local className = instance.ClassName

    if instance:IsA("BasePart") then
        OptimizePart(instance)

    elseif className == "ParticleEmitter"
        or className == "Trail"
        or className == "Beam"
        or className == "Smoke"
        or className == "Fire"
        or className == "Sparkles" then

        OptimizeEffect(instance)

    elseif instance:IsA("PostEffect")
        or className == "Atmosphere" then

        OptimizeLightingEffect(instance)
    end

    State.Statistics.Processed += 1
end

local function QueueInstance(instance)
    if not State.Enabled then
        return
    end

    if not instance then
        return
    end

    if State.Processed[instance] then
        return
    end

    State.Queue[#State.Queue + 1] = instance
end

local function QueueContainer(container)
    for _, instance in ipairs(container:GetDescendants()) do
        State.Queue[#State.Queue + 1] = instance
    end
end

local function OptimizeTerrain()
    local terrain = Workspace:FindFirstChildOfClass("Terrain")

    if not terrain then
        return
    end

    Safe(function()
        terrain.WaterWaveSize = 0
        terrain.WaterWaveSpeed = 0
        terrain.WaterReflectance = 0
        terrain.WaterTransparency = 0
    end)
end

local function OptimizeGlobalLighting()
    Safe(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
    end)

    for _, instance in ipairs(Lighting:GetDescendants()) do
        QueueInstance(instance)
    end
end

local function AdaptBatchSize(processTime)
    if processTime <= 0 then
        return
    end

    local ratio = State.TargetFrameTime / processTime

    if ratio > 1.5 then
        State.BatchSize = math.min(
            State.MaximumBatchSize,
            math.floor(State.BatchSize * 1.15)
        )

    elseif ratio < 0.75 then
        State.BatchSize = math.max(
            State.MinimumBatchSize,
            math.floor(State.BatchSize * 0.75)
        )
    end
end

local function ProcessQueue()
    if State.Processing or not State.Enabled then
        return
    end

    State.Processing = true

    local startTime = os.clock()
    local processedThisFrame = 0

    while State.QueueHead <= #State.Queue
        and processedThisFrame < State.BatchSize do

        local instance = State.Queue[State.QueueHead]
        State.Queue[State.QueueHead] = nil
        State.QueueHead += 1

        if instance and IsAlive(instance) then
            OptimizeInstance(instance)
        end

        processedThisFrame += 1
    end

    if State.QueueHead > #State.Queue then
        State.Queue = {}
        State.QueueHead = 1
    end

    local elapsed = os.clock() - startTime

    AdaptBatchSize(elapsed)

    State.LastProcess = elapsed
    State.Processing = false
end

local function StartProcessing()
    if State.Connections.Heartbeat then
        return
    end

    State.Connections.Heartbeat = RunService.Heartbeat:Connect(function()
        if not State.Enabled then
            return
        end

        ProcessQueue()
    end)
end

local function StopProcessing()
    if State.Connections.Heartbeat then
        State.Connections.Heartbeat:Disconnect()
        State.Connections.Heartbeat = nil
    end
end

local function OptimizeWholeMap()
    if State.Processing then
        return
    end

    State.Queue = {}
    State.QueueHead = 1

    local start = os.clock()

    QueueContainer(Workspace)
    OptimizeGlobalLighting()
    OptimizeTerrain()

    local queued = #State.Queue

    return {
        Queued = queued,
        Duration = os.clock() - start
    }
end

local function EnableOptimization()
    if State.Enabled then
        return
    end

    State.Enabled = true

    local result = OptimizeWholeMap()

    StartProcessing()

    Rayfield:Notify({
        Title = "Auto Boost Enabled",
        Content = string.format(
            "Queued %d objects. Adaptive processing active.",
            result and result.Queued or 0
        ),
        Duration = 3,
        Image = 4483362458
    })
end

local function DisableOptimization()
    if not State.Enabled then
        return
    end

    State.Enabled = false

    State.Queue = {}
    State.QueueHead = 1

    StopProcessing()

    Rayfield:Notify({
        Title = "Auto Boost Disabled",
        Content = "Automatic optimization stopped.",
        Duration = 2,
        Image = 4483362458
    })
end

local function ConnectDynamicOptimization()
    State.Connections.WorkspaceAdded =
        Workspace.DescendantAdded:Connect(function(instance)
            if State.Enabled then
                QueueInstance(instance)
            end
        end)

    State.Connections.LightingAdded =
        Lighting.DescendantAdded:Connect(function(instance)
            if State.Enabled then
                QueueInstance(instance)
            end
        end)
end

local function DisconnectAll()
    for name, connection in pairs(State.Connections) do
        if connection then
            connection:Disconnect()
        end

        State.Connections[name] = nil
    end
end

local Window = Rayfield:CreateWindow({
    Name = "🚀 Extreme FPS Booster V3",
    LoadingTitle = "Recovery Optimization",
    LoadingSubtitle = "Adaptive Client Performance System",
    ConfigurationSaving = {
        Enabled = false
    },
    Discord = {
        Enabled = false
    },
    KeySystem = false
})

local MainTab = Window:CreateTab(
    "🚀 Optimization",
    4483362458
)

local CustomTab = Window:CreateTab(
    "⚙️ Advanced",
    4483362458
)

MainTab:CreateSection("⚡ Adaptive Optimization")

MainTab:CreateToggle({
    Name = "🔄 Auto Boost",
    CurrentValue = false,
    Flag = "AutoBoost",
    Callback = function(value)
        if value then
            EnableOptimization()
        else
            DisableOptimization()
        end
    end
})

MainTab:CreateSection("📊 Runtime")

MainTab:CreateButton({
    Name = "📦 Optimize Current Map",
    Callback = function()
        State.Enabled = true

        local result = OptimizeWholeMap()

        StartProcessing()

        Rayfield:Notify({
            Title = "Recovery Scan Complete",
            Content = string.format(
                "%d objects queued for adaptive processing.",
                result and result.Queued or 0
            ),
            Duration = 3,
            Image = 4483362458
        })
    end
})

MainTab:CreateButton({
    Name = "📈 Runtime Statistics",
    Callback = function()
        Rayfield:Notify({
            Title = "Optimization Statistics",
            Content = string.format(
                "Processed: %d | Skipped: %d | Failed: %d | Batch: %d",
                State.Statistics.Processed,
                State.Statistics.Skipped,
                State.Statistics.Failed,
                State.BatchSize
            ),
            Duration = 5,
            Image = 4483362458
        })
    end
})

CustomTab:CreateSection("🎛️ FPS Cap")

CustomTab:CreateSlider({
    Name = "FPS Cap",
    Range = {15, 360},
    Increment = 5,
    Suffix = " FPS",
    CurrentValue = 60,
    Flag = "FPSCap",
    Callback = function(value)
        Safe(function()
            if typeof(setfpscap) == "function" then
                setfpscap(value)
            end
        end)
    end
})

CustomTab:CreateSection("🧠 Processing Engine")

CustomTab:CreateSlider({
    Name = "Maximum Batch Size",
    Range = {25, 500},
    Increment = 25,
    Suffix = " objects",
    CurrentValue = 150,
    Flag = "BatchSize",
    Callback = function(value)
        State.MaximumBatchSize = value

        if State.BatchSize > value then
            State.BatchSize = value
        end
    end
})

CustomTab:CreateButton({
    Name = "🧹 Reset Runtime Cache",
    Callback = function()
        State.Processed = setmetatable({}, {
            __mode = "k"
        })

        State.Queue = {}
        State.QueueHead = 1

        Rayfield:Notify({
            Title = "Cache Reset",
            Content = "Recovery processing cache cleared.",
            Duration = 2,
            Image = 4483362458
        })
    end
})

CustomTab:CreateButton({
    Name = "💡 Optimize Lighting",
    Callback = function()
        OptimizeGlobalLighting()

        Rayfield:Notify({
            Title = "Lighting Optimized",
            Content = "Post-processing effects and global shadows disabled.",
            Duration = 2,
            Image = 4483362458
        })
    end
})

CustomTab:CreateButton({
    Name = "🌊 Optimize Terrain",
    Callback = function()
        OptimizeTerrain()

        Rayfield:Notify({
            Title = "Terrain Optimized",
            Content = "Water rendering overhead reduced.",
            Duration = 2,
            Image = 4483362458
        })
    end
})

ConnectDynamicOptimization()

Rayfield:Notify({
    Title = "Extreme FPS Booster V3",
    Content = "Adaptive recovery optimization system initialized.",
    Duration = 3,
    Image = 4483362458
})
