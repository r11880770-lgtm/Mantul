-- ═══════════════════════════════════════════════════════════
-- MAGIC BULLET ALL-IN-ONE + UI
-- Luau, Roblox client executor (Madium / sUNC)
-- Tekan Z = toggle. RCtrl = panic unhook. Drag panel buat pindah.
-- ═══════════════════════════════════════════════════════════

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Camera           = Workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

-- ══════════════════ CONFIG ══════════════════
local CONFIG = {
    toggleKey    = Enum.KeyCode.Z,
    panicKey     = Enum.KeyCode.RightControl,
    fov          = 200,
    maxDist      = 500,
    boneName     = "Head",
    silentAim    = true,
    -- safe mode
    cooldown     = 0.35,
    maxAngleDeg  = 35,
    requireLOS   = true,
    -- ui
    accent       = Color3.fromRGB(140, 90, 255),
    bg           = Color3.fromRGB(14, 14, 20),
    panelW       = 260,
    panelH       = 340,
}

local STATE = {
    enabled    = false,
    lastShot   = 0,
    hooks      = {},       -- remote -> original
    target     = nil,
    fps        = 0,
}

-- ══════════════════ UTIL ══════════════════
local function isEnemy(plr)
    if plr == LocalPlayer then return false end
    local char = plr.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return true
end

local function getBone(plr)
    local char = plr.Character
    if not char then return nil end
    return char:FindFirstChild(CONFIG.boneName) or char:FindFirstChild("HumanoidRootPart")
end

local function worldToScreen(pos)
    local sp, onScreen = Camera:WorldToViewportPoint(pos)
    if not onScreen or sp.Z <= 0 then return nil end
    local vp = Camera.ViewportSize
    return Vector2.new(sp.X, sp.Y), Vector2.new(vp.X * 0.5, vp.Y * 0.5)
end

-- ══════════════════ TARGET FINDER ══════════════════
local function nearestTarget()
    local best, bestD = nil, CONFIG.fov
    for _, plr in ipairs(Players:GetPlayers()) do
        if not isEnemy(plr) then continue end
        local bone = getBone(plr)
        if not bone then continue end
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myRoot then continue end
        local dist = (bone.Position - myRoot.Position).Magnitude
        if dist > CONFIG.maxDist then continue end
        local sp, center = worldToScreen(bone.Position)
        if not sp then continue end
        local d = (sp - center).Magnitude
        if d < bestD then
            best, bestD = { plr = plr, bone = bone, screen = sp, dist = dist }, d
        end
    end
    return best
end

-- ══════════════════ SANITY (safe mode) ══════════════════
local function saneShot(origin, targetPos, camLook)
    local dist = (targetPos - origin).Magnitude
    if dist > CONFIG.maxDist then return false end
    local want = (targetPos - origin).Unit
    local angle = math.deg(math.acos(math.clamp(want:Dot(camLook), -1, 1)))
    if angle > CONFIG.maxAngleDeg then return false end
    if CONFIG.requireLOS then
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {
            LocalPlayer.Character,
            targetPos.Parent or targetPos,
        }
        local hit = Workspace:Raycast(origin, want * dist, params)
        if hit then return false end
    end
    if os.clock() - STATE.lastShot < CONFIG.cooldown then return false end
    return true
end

-- ══════════════════ HOOK MANAGER ══════════════════
local function hookRemote(remote)
    if STATE.hooks[remote] or not hookfunction then return end
    local old
    local ok = pcall(function()
        old = hookfunction(remote.FireServer, function(self, ...)
            if not STATE.enabled then return old(self, ...) end
            local args = { ... }
            local origin, dirIdx = nil, nil
            for i, v in ipairs(args) do
                if typeof(v) == "Vector3" and not origin then
                    origin = v
                    for j = i + 1, #args do
                        if typeof(args[j]) == "Vector3" then dirIdx = j; break end
                    end
                    break
                end
            end
            if not origin or not dirIdx then return old(self, ...) end

            local t = nearestTarget()
            STATE.target = t
            if not t then return old(self, ...) end

            if not saneShot(origin, t.bone.Position, Camera.CFrame.LookVector) then
                return old(self, ...)
            end
            STATE.lastShot = os.clock()
            args[dirIdx] = (t.bone.Position - origin).Unit * 1000
            for i, v in ipairs(args) do
                if typeof(v) == "Instance" and v:IsA("BasePart") then
                    args[i] = t.bone
                end
            end
            return old(self, table.unpack(args))
        end)
    end)
    if ok then STATE.hooks[remote] = old end
end

local function unhookAll()
    for remote, old in pairs(STATE.hooks) do
        pcall(function() hookfunction(remote.FireServer, old) end)
    end
    STATE.hooks = {}
end

local function scanRemotes()
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            local n = obj.Name:lower()
            if n:find("hit") or n:find("shoot") or n:find("bullet")
               or n:find("fire") or n:find("damage") then
                hookRemote(obj)
            end
        end
    end
end

-- ══════════════════ UI ══════════════════
local UI = { drawing = {} }

local function makeDrawing(class, props)
    if not Drawing then return nil end
    local d = Drawing.new(class)
    for k, v in pairs(props) do d[k] = v end
    d.Visible = true
    return d
end

local function buildUI()
    -- panel background
    UI.bg = makeDrawing("Square", {
        Size = Vector2.new(CONFIG.panelW, CONFIG.panelH),
        Color = CONFIG.bg,
        Filled = true,
        Transparency = 0.08,
        Position = Vector2.new(40, 40),
    })
    UI.accentBar = makeDrawing("Square", {
        Size = Vector2.new(CONFIG.panelW, 3),
        Color = CONFIG.accent,
        Filled = true,
        Position = Vector2.new(40, 40),
    })
    UI.title = makeDrawing("Text", {
        Text = "UNKNOWN // MAGIC BULLET",
        Size = 15,
        Color = Color3.fromRGB(240, 240, 255),
        Font = 3,
        Position = Vector2.new(52, 48),
    })
    UI.statusDot = makeDrawing("Circle", {
        Radius = 5,
        Color = Color3.fromRGB(255, 60, 60),
        Position = Vector2.new(280, 56),
        Filled = true,
    })
    UI.statusTxt = makeDrawing("Text", {
        Text = "OFF",
        Size = 12,
        Color = Color3.fromRGB(255, 120, 120),
        Font = 3,
        Position = Vector2.new(244, 62),
    })

    -- FOV slider
    local y = 90
    UI.fovLabel = makeDrawing("Text", {
        Text = "FOV  [" .. math.floor(CONFIG.fov) .. "]",
        Size = 12, Color = Color3.fromRGB(180, 180, 200), Font = 2,
        Position = Vector2.new(52, y),
    })
    UI.fovTrack = makeDrawing("Square", {
        Size = Vector2.new(180, 4), Color = Color3.fromRGB(40, 40, 55),
        Filled = true, Position = Vector2.new(52, y + 18),
    })
    UI.fovFill = makeDrawing("Square", {
        Size = Vector2.new(90, 4), Color = CONFIG.accent,
        Filled = true, Position = Vector2.new(52, y + 18),
    })

    -- Cooldown slider
    y = 140
    UI.cdLabel = makeDrawing("Text", {
        Text = "CD  [" .. string.format("%.2f", CONFIG.cooldown) .. "s]",
        Size = 12, Color = Color3.fromRGB(180, 180, 200), Font = 2,
        Position = Vector2.new(52, y),
    })
    UI.cdTrack = makeDrawing("Square", {
        Size = Vector2.new(180, 4), Color = Color3.fromRGB(40, 40, 55),
        Filled = true, Position = Vector2.new(52, y + 18),
    })
    UI.cdFill = makeDrawing("Square", {
        Size = Vector2.new(90, 4), Color = CONFIG.accent,
        Filled = true, Position = Vector2.new(52, y + 18),
    })

    -- Toggle button
    UI.toggleBtn = makeDrawing("Square", {
        Size = Vector2.new(180, 26), Color = Color3.fromRGB(30, 30, 45),
        Filled = true, Position = Vector2.new(52, 200),
    })
    UI.toggleTxt = makeDrawing("Text", {
        Text = "TOGGLE  [Z]", Size = 13,
        Color = Color3.fromRGB(220, 220, 255), Font = 3,
        Position = Vector2.new(95, 207),
    })

    -- Panic button
    UI.panicBtn = makeDrawing("Square", {
        Size = Vector2.new(180, 26), Color = Color3.fromRGB(60, 20, 30),
        Filled = true, Position = Vector2.new(52, 234),
    })
    UI.panicTxt = makeDrawing("Text", {
        Text = "PANIC  [RCtrl]", Size = 13,
        Color = Color3.fromRGB(255, 180, 180), Font = 3,
        Position = Vector2.new(86, 241),
    })

    -- Stats
    UI.stats = makeDrawing("Text", {
        Text = "hits: 0  |  fps: 0",
        Size = 11, Color = Color3.fromRGB(120, 120, 140), Font = 2,
        Position = Vector2.new(52, 275),
    })
    UI.targetTxt = makeDrawing("Text", {
        Text = "target: --",
        Size = 11, Color = Color3.fromRGB(120, 120, 140), Font = 2,
        Position = Vector2.new(52, 292),
    })
    UI.foot = makeDrawing("Text", {
        Text = "absolute Unknown",
        Size = 10, Color = Color3.fromRGB(90, 70, 140), Font = 2,
        Position = Vector2.new(52, 312),
    })
end

-- ══════════════════ UI INTERACTION ══════════════════
local mouseDown = false
local dragOffset = Vector2.zero

local function uiPointInPanel(m)
    if not UI.bg then return false end
    local p = UI.bg.Position
    return m.X >= p.X and m.X <= p.X + CONFIG.panelW
       and m.Y >= p.Y and m.Y <= p.Y + CONFIG.panelH
end

local function setPanelPos(pos)
    local list = {
        UI.bg, UI.accentBar, UI.title, UI.statusDot, UI.statusTxt,
        UI.fovLabel, UI.fovTrack, UI.fovFill,
        UI.cdLabel, UI.cdTrack, UI.cdFill,
        UI.toggleBtn, UI.toggleTxt, UI.panicBtn, UI.panicTxt,
        UI.stats, UI.targetTxt, UI.foot,
    }
    local base = UI.bg.Position
    local delta = pos - base
    for _, d in ipairs(list) do
        if d then d.Position = d.Position + delta end
    end
end

local function setFOV(px)
    CONFIG.fov = math.clamp(px, 40, 600)
    local fillW = (CONFIG.fov / 600) * 180
    if UI.fovFill then UI.fovFill.Size = Vector2.new(fillW, 4) end
    if UI.fovLabel then UI.fovLabel.Text = "FOV  [" .. math.floor(CONFIG.fov) .. "]" end
end

local function setCD(sec)
    CONFIG.cooldown = math.clamp(sec, 0.1, 1.0)
    local fillW = (CONFIG.cooldown / 1.0) * 180
    if UI.cdFill then UI.cdFill.Size = Vector2.new(fillW, 4) end
    if UI.cdLabel then UI.cdLabel.Text = "CD  [" .. string.format("%.2f", CONFIG.cooldown) .. "s]" end
end

local function toggle()
    STATE.enabled = not STATE.enabled
    if UI.statusDot then
        UI.statusDot.Color = STATE.enabled and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 60, 60)
    end
    if UI.statusTxt then
        UI.statusTxt.Text = STATE.enabled and "ON" or "OFF"
        UI.statusTxt.Color = STATE.enabled and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 120, 120)
    end
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CONFIG.toggleKey then toggle() end
    if input.KeyCode == CONFIG.panicKey then
        STATE.enabled = false
        unhookAll()
        if UI.statusDot then UI.statusDot.Color = Color3.fromRGB(255, 60, 60) end
        if UI.statusTxt then UI.statusTxt.Text = "PANIC"; UI.statusTxt.Color = Color3.fromRGB(255, 120, 120) end
    end
end)

-- mouse drag + slider click via UserInputService (fallback kalau Drawing input gak ada)
RunService.RenderStepped:Connect(function()
    local m = UserInputService:GetMouseLocation()
    -- drag
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        if not mouseDown then
            if uiPointInPanel(m) then
                -- tombol?
                local tb = UI.toggleBtn.Position
                if m.X >= tb.X and m.X <= tb.X + 180 and m.Y >= tb.Y and m.Y <= tb.Y + 26 then
                    toggle()
                end
                local pb = UI.panicBtn.Position
                if m.X >= pb.X and m.X <= pb.X + 180 and m.Y >= pb.Y and m.Y <= pb.Y + 26 then
                    STATE.enabled = false; unhookAll()
                end
                -- slider fov
                local ft = UI.fovTrack.Position
                if m.X >= ft.X and m.X <= ft.X + 180 and m.Y >= ft.Y - 4 and m.Y <= ft.Y + 8 then
                    setFOV(((m.X - ft.X) / 180) * 600)
                end
                -- slider cd
                local ct = UI.cdTrack.Position
                if m.X >= ct.X and m.X <= ct.X + 180 and m.Y >= ct.Y - 4 and m.Y <= ct.Y + 8 then
                    setCD((m.X - ct.X) / 180)
                end
                -- drag dari area kosong atas panel
                if m.Y <= UI.bg.Position.Y + 36 then
                    mouseDown = true
                    dragOffset = m - UI.bg.Position
                end
            end
        else
            setPanelPos(m - dragOffset)
        end
    else
        mouseDown = false
    end
end)

-- ══════════════════ RENDER LOOP: FOV circle + status ══════════════════
local fovCircle = makeDrawing("Circle", {
    Radius = CONFIG.fov / 2,
    Color = CONFIG.accent,
    Thickness = 1,
    Filled = false,
    Transparency = 0.6,
})

RunService.RenderStepped:Connect(function(dt)
    if fovCircle then
        local vp = Camera.ViewportSize
        fovCircle.Position = Vector2.new(vp.X / 2, vp.Y / 2)
        fovCircle.Radius = CONFIG.fov / 2
        fovCircle.Visible = STATE.enabled
    end
    if UI.stats then
        UI.stats.Text = string.format("hits: %d  |  fps: %d", 0, math.floor(1 / math.max(dt, 0.001)))
    end
    if UI.targetTxt then
        local t = STATE.target
        UI.targetTxt.Text = t and ("target: " .. t.plr.Name .. "  " .. math.floor(t.dist) .. "m") or "target: --"
    end
end)

-- ══════════════════ BOOT ══════════════════
buildUI()
setFOV(CONFIG.fov)
setCD(CONFIG.cooldown)
scanRemotes()
game.DescendantAdded:Connect(function(obj)
    if obj:IsA("RemoteEvent") then
        local n = obj.Name:lower()
        if n:find("hit") or n:find("shoot") or n:find("bullet")
           or n:find("fire") or n:find("damage") then
            hookRemote(obj)
        end
    end
end)
print("[bench] unknown // magic bullet loaded — Z toggle, RCtrl panic")