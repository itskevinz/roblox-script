-- Tải thư viện Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Biến lưu trạng thái Tự động
local AutoOptimizeEnabled = false

-- Tạo Cửa sổ UI
local Window = Rayfield:CreateWindow({
   Name = "🚀 Extreme FPS Booster V2",
   LoadingTitle = "Đang tải hệ thống tối ưu...",
   LoadingSubtitle = "Giảm Lag - Tự Động Hóa",
   ConfigurationSaving = { Enabled = false },
   Discord = { Enabled = false },
   KeySystem = false
})

-- Tạo Tabs
local MainTab = Window:CreateTab("🚀 Tối Ưu Chính", 4483362458)
local CustomTab = Window:CreateTab("⚙️ Tùy Chỉnh", 4483362458)

-- ================= HÀM XỬ LÝ 1 VẬT THỂ (DÙNG CHO AUTO) ================= --
-- Hàm này an toàn (pcall) để không báo lỗi nếu vật thể bị xóa ngay khi vừa xuất hiện
local function OptimizeSingleObject(v)
    pcall(function()
        -- 1. Xử lý Part & Mesh (Xóa texture, đổi nhựa mượt)
        if v:IsA("BasePart") then
            if v:IsA("MeshPart") then
                v.TextureID = ""
            end
            v.Material = Enum.Material.SmoothPlastic
            v.Reflectance = 0
            v.CastShadow = false
            
        -- 2. Xử lý Hiệu ứng hạt (Tắt lửa, khói, skill...)
        elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then
            v.Enabled = false
            
        -- 3. Xử lý Ánh sáng môi trường
        elseif v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("BloomEffect") or v:IsA("DepthOfFieldEffect") then
            v.Enabled = false
        end
    end)
end

-- Lắng nghe vật thể mới sinh ra trong Game
workspace.DescendantAdded:Connect(function(descendant)
    if AutoOptimizeEnabled then
        OptimizeSingleObject(descendant)
    end
end)

game.Lighting.DescendantAdded:Connect(function(descendant)
    if AutoOptimizeEnabled then
        OptimizeSingleObject(descendant)
    end
end)


-- ================= HÀM XỬ LÝ TOÀN BỘ MAP HIỆN TẠI ================= --
local function OptimizeWholeMap()
    for _, v in pairs(workspace:GetDescendants()) do
        OptimizeSingleObject(v)
    end
    for _, v in pairs(game.Lighting:GetDescendants()) do
        OptimizeSingleObject(v)
    end
    
    -- Tối ưu Nước và Cài đặt ánh sáng tổng
    game.Lighting.GlobalShadows = false
    game.Lighting.FogEnd = 9e9
    if workspace:FindFirstChildOfClass("Terrain") then
        workspace.Terrain.WaterWaveSize = 0
        workspace.Terrain.WaterWaveSpeed = 0
        workspace.Terrain.WaterReflectance = 0
        workspace.Terrain.WaterTransparency = 0
    end
end


-- ================= GIAO DIỆN MAIN TAB ================= --

MainTab:CreateSection("⚡ Tối Ưu Tự Động (Khuyên dùng)")

MainTab:CreateToggle({
   Name = "🔄 Tự động tối ưu liên tục (Auto Boost)",
   CurrentValue = false,
   Flag = "AutoBoostToggle",
   Callback = function(Value)
       AutoOptimizeEnabled = Value
       if Value then
           -- Khi bật lên, quét luôn 1 lần toàn bộ map để làm mượt những cái đang có sẵn
           OptimizeWholeMap()
           Rayfield:Notify({
               Title = "Auto Boost Đã Bật",
               Content = "Đã làm mượt map. Các vật thể/hiệu ứng mới sinh ra sẽ tự động bị tắt/làm mượt.",
               Duration = 3,
               Image = 4483362458
           })
       else
           Rayfield:Notify({
               Title = "Auto Boost Đã Tắt",
               Content = "Vật thể mới sinh ra sẽ giữ nguyên chất lượng gốc.",
               Duration = 2,
               Image = 4483362458
           })
       end
   end,
})

MainTab:CreateSection("Ghi chú: Bật nút trên để không bao giờ bị tụt FPS khi qua đảo mới hoặc khi ai đó spam skill.")


-- ================= GIAO DIỆN CUSTOM TAB ================= --

CustomTab:CreateSection("🛠️ Tác vụ thủ công (Chỉ chạy 1 lần)")

CustomTab:CreateButton({
   Name = "Quét & Tối ưu thủ công toàn Map",
   Callback = function()
       OptimizeWholeMap()
   end,
})

CustomTab:CreateSection("🎛️ Giới Hạn FPS")

CustomTab:CreateSlider({
   Name = "Giới hạn FPS (FPS Cap)",
   Range = {15, 240},
   Increment = 5,
   Suffix = "FPS",
   CurrentValue = 60,
   Flag = "FPSCapSlider", 
   Callback = function(Value)
        pcall(function()
            setfpscap(Value)
        end)
   end,
})
