--[[
  =====================================================================
   PORTAL GUN V2  (Rick & Morty style)  -  Delta / Roblox, client-side
   Paste into Delta and Execute.  Tap / click = fire.
   PC keys: Q dimension | E mode | R size | T timer | F clear | M mute
  =====================================================================

  THE 30 FEATURES
  GUN
   1  Replica-style model (~110 parts): rounded white shell, caged glass tank,
      pipes, stepped bell muzzle, angled ribbed grip, trigger guard
   2  Glass fluid tank: glowing liquid, rising bubbles, sloshing, tank light
   3  Working trigger: trigger pull + recoil kick on every shot
   4  Side display screens: dimension name + live signal bars
   5  Side dials that click-spin when you change dimension
   6  Spinning energy coil + energy dots flowing along the pipes
   7  Charge meter LEDs on the back that refill after each shot
   8  Muzzle mini-portal swirl + charge-up glow before each shot
  PORTALS
   9  Two linked elliptical portals (A/B); a new one replaces the old in its slot
  10  Surface-aligned raycast placement + impact shockwave rings on the surface
  11  Multi-layer vortex: halo, rim, depth gradient, 3 spiral arms, glowing eye
  12  Boiling ragged liquid rim (animated blobs)
  13  Lightning arcs crackling around the rim (beams)
  14  Open / close animations with expanding and collapsing shock rings
  15  Helix projectile bolt (corkscrew orbs + trails)
  16  Seamless teleport that keeps momentum + anti-loop arming
  17  Portal size toggle (S / M / L)
  18  Portal lifetime timer (INF / 15s / 45s)
  DIMENSIONS + MODES
  19  8 dimensions, everything color-blends smoothly between them
  20  World grading: color tint + bloom while the gun is equipped
  21  BLINK mode: shoot a spot and jump straight there
  22  ROULETTE mode: random dimension on every shot
  SYSTEMS
  23  Mobile UI (panel, crosshair, toasts) + PC keybinds
  24  Clear-all-portals
  25  Layered synth sound engine: multi-layer cues, pitch sweeps, effect chains
  26  Custom sound override table + mute
  27  Teleport warp: FOV kick, radial-style blur, flash, expanding screen rings
  28  Camera shake on fire / open / teleport
  29  Random electric zaps with sparks (gun + portals)
  30  Respawn-proof: gun is re-given and re-equipped after you die
]]

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local Debris           = game:GetService("Debris")
local Workspace        = game:GetService("Workspace")

local player = Players.LocalPlayer

-- remove any previous copy so you can re-execute safely
local env = (getgenv and getgenv()) or _G
if env.__PortalGunCleanup then pcall(env.__PortalGunCleanup) end

local V = Vector3.new

--------------------------------------------------------------------- CONFIG
local CONFIG = {
    GunName = "Portal Gun",
    Range = 500,
    BoltSpeed = 300,
    FireDelay = 0.55,
    ChargeTime = 0.16,
    TeleportCooldown = 0.6,
    Volume = 1,
    -- {label, portal height in studs}. Width is 78% of height.
    Sizes = { {"S", 6.5}, {"M", 9}, {"L", 13} },
    Lifetimes = { {"INF", 0}, {"15s", 15}, {"45s", 45} },
    -- Want different sounds? Paste "rbxassetid://ID" for a cue and it replaces
    -- the built-in layered version of that cue.
    CustomSounds = {
        Charge = "", Fire = "", Impact = "", Open = "", Close = "",
        Teleport = "", Dial = "", Mode = "", Equip = "", Zap = "", Deny = "",
    },
}
local ELLIPSE = 0.78

local DIMENSIONS = {
    { name = "C-137",      color = Color3.fromRGB(70, 255, 60),   tint = Color3.fromRGB(225, 255, 225) },
    { name = "J19-7",      color = Color3.fromRGB(0, 200, 255),   tint = Color3.fromRGB(215, 240, 255) },
    { name = "35-C",       color = Color3.fromRGB(255, 140, 20),  tint = Color3.fromRGB(255, 238, 215) },
    { name = "CRONENBERG", color = Color3.fromRGB(255, 50, 80),   tint = Color3.fromRGB(255, 220, 225) },
    { name = "FANTASY",    color = Color3.fromRGB(190, 90, 255),  tint = Color3.fromRGB(240, 225, 255) },
    { name = "TOXIC",      color = Color3.fromRGB(240, 255, 40),  tint = Color3.fromRGB(250, 255, 215) },
    { name = "ICE-9",      color = Color3.fromRGB(170, 235, 255), tint = Color3.fromRGB(225, 245, 255) },
    { name = "EVIL-PRIME", color = Color3.fromRGB(255, 255, 255), tint = Color3.fromRGB(205, 205, 220) },
}

local MODES = { "LINK", "BLINK", "ROULETTE" }

local state = {
    dim = 1, mode = 1, size = 2, life = 1,
    muted = false, nextSlot = 1,
    armed = true, lastTeleport = 0,
}

local conns = {}
local function bind(signal, fn)
    local c = signal:Connect(fn)
    table.insert(conns, c)
    return c
end

-- forward declarations
local currentGun
local equipped = false
local portals = {}   -- [1], [2] = live portals
local active = {}    -- every portal still being drawn (including closing ones)
local cycleDimension, cycleMode, cycleSize, cycleTimer, clearPortals, toggleMute
local setDimension, refreshUI, toast, applyTint

local WHITE3 = Color3.new(1, 1, 1)
local R90 = CFrame.Angles(0, math.rad(90), 0)   -- cylinder lies along Z
local RY  = CFrame.Angles(0, 0, math.rad(90))   -- cylinder stands along Y

local portalFolder = Instance.new("Folder")
portalFolder.Name = "PG_Portals"
portalFolder.Parent = Workspace

--------------------------------------------------------------------- SOUND ENGINE (25, 26)
-- Built-in Roblox sounds are layered, pitch-swept and run through effect
-- chains to build sci-fi cues.
local PING   = "rbxasset://sounds/electronicpingshort.wav"
local SPLASH = "rbxasset://sounds/impact_water.mp3"
local SWITCH = "rbxasset://sounds/switch.wav"
local CLICK  = "rbxasset://sounds/button.wav"
local BASS   = "rbxasset://sounds/bass.wav"
local SNAP   = "rbxasset://sounds/snap.mp3"

local CUES = {
    Charge = {
        { id = PING, speed = 0.5, to = 3.2, time = 0.16, vol = 0.8, fx = { {"chorus"} } },
        { id = BASS, speed = 0.6, to = 1.4, time = 0.16, vol = 0.7 },
    },
    Fire = {
        { id = PING,   speed = 3.2, to = 0.35, time = 0.5, vol = 1.1, fx = { {"distort", level = 0.3}, {"reverb"} } },
        { id = SPLASH, speed = 2.6, to = 1.2, time = 0.3, vol = 0.7, fx = { {"distort", level = 0.55}, {"flange"} } },
        { id = BASS,   speed = 0.5, vol = 1.4, fx = { {"eq", low = 8}, {"reverb"} } },
        { id = SNAP,   speed = 1.6, vol = 0.8 },
        { id = PING,   speed = 1.0, to = 0.2, time = 0.8, vol = 0.5, delay = 0.05, fx = { {"echo"} } },
    },
    Impact = {
        { id = SNAP,   speed = 0.9, vol = 0.6 },
        { id = BASS,   speed = 0.8, vol = 0.8 },
        { id = SPLASH, speed = 1.8, vol = 0.4, fx = { {"reverb"} } },
    },
    Open = {
        { id = SPLASH, speed = 0.55, vol = 1.4, fx = { {"reverb", decay = 3.5}, {"echo"} } },
        { id = PING,   speed = 0.3, to = 2.2, time = 0.7, vol = 1.0, fx = { {"flange"} } },
        { id = BASS,   speed = 0.35, vol = 1.6, fx = { {"eq", low = 8} } },
        { id = SPLASH, speed = 1.6, vol = 0.5, delay = 0.12, fx = { {"chorus"} } },
        { id = PING,   speed = 2.5, to = 1.2, time = 0.4, vol = 0.5, delay = 0.25, fx = { {"echo"} } },
    },
    Close = {
        { id = PING,   speed = 2.0, to = 0.2, time = 0.45, vol = 1.0, fx = { {"reverb"} } },
        { id = SPLASH, speed = 1.0, to = 0.5, time = 0.4, vol = 0.8 },
        { id = BASS,   speed = 0.5, vol = 1.0 },
    },
    Teleport = {
        { id = PING,   speed = 3.0, to = 0.5, time = 0.3, vol = 1.0, fx = { {"chorus"} } },
        { id = SPLASH, speed = 1.4, vol = 1.1, fx = { {"reverb"} } },
        { id = BASS,   speed = 0.4, vol = 1.5 },
        { id = SNAP,   speed = 0.7, vol = 0.7 },
    },
    Dial = {
        { id = CLICK,  speed = 0.9, vol = 1.0 },
        { id = CLICK,  speed = 1.1, vol = 1.0, delay = 0.07 },
        { id = CLICK,  speed = 1.3, vol = 1.0, delay = 0.14 },
        { id = PING,   speed = 1.0, to = 3.0, time = 0.25, vol = 0.7, delay = 0.1, fx = { {"chorus"} } },
        { id = SPLASH, speed = 1.5, vol = 0.4, delay = 0.15 },
    },
    Mode = {
        { id = SWITCH, speed = 1.0, vol = 1.0 },
        { id = PING,   speed = 1.5, to = 2.5, time = 0.15, vol = 0.5 },
    },
    Equip = {
        { id = SWITCH, speed = 0.6, vol = 1.0 },
        { id = PING,   speed = 0.4, to = 2.4, time = 0.55, vol = 0.8, fx = { {"flange"}, {"reverb"} } },
        { id = BASS,   speed = 0.5, vol = 1.0 },
        { id = SNAP,   speed = 0.8, vol = 0.6, delay = 0.25 },
    },
    Zap = {
        { id = PING, speed = 2.5, speedMax = 4.5, vol = 0.3, fx = { {"distort", level = 0.4} } },
        { id = SNAP, speed = 2.5, vol = 0.25 },
    },
    Deny = {
        { id = BASS,  speed = 0.35, vol = 1.0 },
        { id = CLICK, speed = 0.6,  vol = 0.8 },
    },
}

local LOOPS = {
    GunHum = {
        { id = BASS, speed = 0.5,  vol = 0.32, fx = { {"tremolo", freq = 6.5, depth = 0.55}, {"flange"} } },
        { id = BASS, speed = 0.76, vol = 0.16, fx = { {"tremolo", freq = 9, depth = 0.5} } },
    },
    PortalHum = {
        { id = BASS, speed = 0.38, vol = 0.4,  fx = { {"tremolo", freq = 4, depth = 0.6}, {"flange"}, {"reverb"} } },
        { id = BASS, speed = 0.62, vol = 0.2,  fx = { {"tremolo", freq = 11, depth = 0.5} } },
    },
}

local function applyFx(s, list)
    if not list then return end
    for _, e in ipairs(list) do
        local k = e[1]
        local inst
        if k == "reverb" then
            inst = Instance.new("ReverbSoundEffect")
            inst.DecayTime = e.decay or 2.5
            inst.Density = 1
            inst.Diffusion = 1
            inst.DryLevel = -2
            inst.WetLevel = e.wet or -5
        elseif k == "echo" then
            inst = Instance.new("EchoSoundEffect")
            inst.Delay = e.delay or 0.18
            inst.Feedback = e.fb or 0.45
            inst.DryLevel = 0
            inst.WetLevel = e.wet or -6
        elseif k == "distort" then
            inst = Instance.new("DistortionSoundEffect")
            inst.Level = e.level or 0.5
        elseif k == "chorus" then
            inst = Instance.new("ChorusSoundEffect")
            inst.Depth = 0.5
            inst.Mix = 0.6
            inst.Rate = e.rate or 4
        elseif k == "flange" then
            inst = Instance.new("FlangeSoundEffect")
            inst.Depth = 0.45
            inst.Mix = 0.6
            inst.Rate = e.rate or 3
        elseif k == "tremolo" then
            inst = Instance.new("TremoloSoundEffect")
            inst.Depth = e.depth or 0.6
            inst.Duty = 0.5
            inst.Frequency = e.freq or 8
        elseif k == "eq" then
            inst = Instance.new("EqualizerSoundEffect")
            inst.LowGain = e.low or 0
            inst.MidGain = e.mid or 0
            inst.HighGain = e.high or 0
        end
        if inst then inst.Parent = s end
    end
end

local function cue(name, parent)
    if state.muted or not parent then return end
    local custom = CONFIG.CustomSounds[name]
    if custom and custom ~= "" then
        local s = Instance.new("Sound")
        s.SoundId = custom
        s.Volume = CONFIG.Volume
        s.RollOffMaxDistance = 140
        s.Parent = parent
        s:Play()
        Debris:AddItem(s, 8)
        return
    end
    local layers = CUES[name]
    if not layers then return end
    for _, L in ipairs(layers) do
        local function go()
            if not parent or not parent.Parent then return end
            local s = Instance.new("Sound")
            s.SoundId = L.id
            local sp = L.speed
            if L.speedMax then sp = sp + math.random() * (L.speedMax - L.speed) end
            s.PlaybackSpeed = sp
            s.Volume = L.vol * CONFIG.Volume
            s.RollOffMinDistance = 8
            s.RollOffMaxDistance = 140
            applyFx(s, L.fx)
            s.Parent = parent
            s:Play()
            if L.to then
                TweenService:Create(s, TweenInfo.new(L.time or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { PlaybackSpeed = L.to }):Play()
            end
            Debris:AddItem(s, 6)
        end
        if L.delay and L.delay > 0 then task.delay(L.delay, go) else go() end
    end
end

local function cueAt(name, position)
    if state.muted then return end
    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.Transparency = 1
    p.Size = V(0.2, 0.2, 0.2)
    p.Position = position
    p.Parent = Workspace
    cue(name, p)
    Debris:AddItem(p, 8)
end

local function uiCue(name)
    if currentGun then cue(name, currentGun.handle) end
end

local function startLoop(name, parent)
    local list = {}
    for _, L in ipairs(LOOPS[name]) do
        local s = Instance.new("Sound")
        s.SoundId = L.id
        s.PlaybackSpeed = L.speed
        s.Looped = true
        s.Volume = state.muted and 0 or L.vol * CONFIG.Volume
        s.RollOffMinDistance = 6
        s.RollOffMaxDistance = 90
        applyFx(s, L.fx)
        s.Parent = parent
        s:Play()
        table.insert(list, { sound = s, vol = L.vol })
    end
    return list
end

local function setLoopMute(list, muted)
    if not list then return end
    for _, e in ipairs(list) do
        e.sound.Volume = muted and 0 or e.vol * CONFIG.Volume
    end
end

local function stopLoop(list)
    if not list then return end
    for _, e in ipairs(list) do pcall(function() e.sound:Destroy() end) end
end

--------------------------------------------------------------------- UI (23)
local function getGuiParent()
    local ok, res = pcall(function() return gethui and gethui() end)
    if ok and res then return res end
    return player:WaitForChild("PlayerGui")
end

local function corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = inst
end

local gui = Instance.new("ScreenGui")
gui.Name = "PortalGunUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = getGuiParent()

local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.ZIndex = 100
flashFrame.Active = false
flashFrame.Parent = gui

local crosshair = Instance.new("Frame")
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(10, 10)
crosshair.BorderSizePixel = 0
crosshair.Visible = false
crosshair.Parent = gui
corner(crosshair, 5)
local chStroke = Instance.new("UIStroke")
chStroke.Thickness = 1.5
chStroke.Color = Color3.new(0, 0, 0)
chStroke.Parent = crosshair

local toastLabel = Instance.new("TextLabel")
toastLabel.AnchorPoint = Vector2.new(0.5, 0)
toastLabel.Position = UDim2.new(0.5, 0, 0.1, 0)
toastLabel.Size = UDim2.fromOffset(320, 34)
toastLabel.BackgroundTransparency = 1
toastLabel.TextTransparency = 1
toastLabel.TextStrokeTransparency = 1
toastLabel.Font = Enum.Font.GothamBold
toastLabel.TextSize = 18
toastLabel.Text = ""
toastLabel.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 8, 0.5, 0)
panel.Size = UDim2.fromOffset(138, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(10, 14, 12)
panel.BackgroundTransparency = 0.15
panel.Visible = false
panel.Parent = gui
corner(panel, 10)

local panelStroke = Instance.new("UIStroke")
panelStroke.Thickness = 1.5
panelStroke.Parent = panel

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingBottom = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 6)
pad.PaddingRight = UDim.new(0, 6)
pad.Parent = panel

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 4)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = panel

local title = Instance.new("TextLabel")
title.LayoutOrder = 0
title.Size = UDim2.new(1, 0, 0, 20)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 14
title.Text = "PORTAL GUN"
title.Parent = panel

local buttons = {}
local buttonStrokes = {}
local function addButton(name, order, onClick)
    local b = Instance.new("TextButton")
    b.Name = name
    b.LayoutOrder = order
    b.Size = UDim2.new(1, 0, 0, 30)
    b.BackgroundColor3 = Color3.fromRGB(22, 30, 26)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.AutoButtonColor = true
    b.Parent = panel
    corner(b, 6)
    local st = Instance.new("UIStroke")
    st.Thickness = 1
    st.Transparency = 0.5
    st.Parent = b
    b.Activated:Connect(onClick)
    buttons[name] = b
    buttonStrokes[name] = st
    return b
end

addButton("Dim",   1, function() cycleDimension() end)
addButton("Mode",  2, function() cycleMode() end)
addButton("Size",  3, function() cycleSize() end)
addButton("Timer", 4, function() cycleTimer() end)
addButton("Clear", 5, function() clearPortals() end)
addButton("Sound", 6, function() toggleMute() end)

local toastToken = 0
toast = function(text, color)
    toastToken = toastToken + 1
    local my = toastToken
    toastLabel.Text = text
    toastLabel.TextColor3 = color or DIMENSIONS[state.dim].color
    toastLabel.TextTransparency = 0
    toastLabel.TextStrokeTransparency = 0.4
    task.delay(1.6, function()
        if my == toastToken then
            TweenService:Create(toastLabel, TweenInfo.new(0.4), {
                TextTransparency = 1, TextStrokeTransparency = 1,
            }):Play()
        end
    end)
end

refreshUI = function()
    local d = DIMENSIONS[state.dim]
    buttons.Dim.Text = "DIM  " .. d.name
    buttons.Mode.Text = "MODE  " .. MODES[state.mode]
    buttons.Size.Text = "SIZE  " .. CONFIG.Sizes[state.size][1]
    buttons.Timer.Text = "TIMER  " .. CONFIG.Lifetimes[state.life][1]
    buttons.Clear.Text = "CLEAR PORTALS"
    buttons.Sound.Text = state.muted and "SOUND  OFF" or "SOUND  ON"
    panelStroke.Color = d.color
    title.TextColor3 = d.color
    crosshair.BackgroundColor3 = d.color
    for name, b in pairs(buttons) do
        b.TextColor3 = d.color
        buttonStrokes[name].Color = d.color
    end
end

--------------------------------------------------------------------- SCREEN + WORLD FX (20, 27, 28)
local tintFx = Instance.new("ColorCorrectionEffect")
tintFx.Name = "PG_Tint"
tintFx.Parent = Lighting

local bloomFx = Instance.new("BloomEffect")
bloomFx.Name = "PG_Bloom"
bloomFx.Intensity = 0
bloomFx.Size = 24
bloomFx.Threshold = 0.85
bloomFx.Parent = Lighting

local blurFx = Instance.new("BlurEffect")
blurFx.Name = "PG_Blur"
blurFx.Size = 0
blurFx.Parent = Lighting

applyTint = function(on)
    local d = DIMENSIONS[state.dim]
    TweenService:Create(tintFx, TweenInfo.new(0.7), {
        TintColor = on and d.tint or WHITE3,
        Saturation = on and 0.15 or 0,
    }):Play()
    TweenService:Create(bloomFx, TweenInfo.new(0.7), { Intensity = on and 0.9 or 0 }):Play()
end

local function flash(color, alpha)
    flashFrame.BackgroundColor3 = color
    flashFrame.BackgroundTransparency = alpha or 0.35
    TweenService:Create(flashFrame, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
end

local shakeT, shakeDur, shakeAmp, shaking = 0, 0.01, 0, false
local function shake(amp, dur)
    shakeAmp, shakeT, shakeDur = amp, dur, dur
end

local fovBusy = false
local function fovWarp()
    if fovBusy then return end
    fovBusy = true
    task.spawn(function()
        local cam = Workspace.CurrentCamera
        local base = cam.FieldOfView
        local up = TweenService:Create(cam, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base + 30 })
        up:Play()
        up.Completed:Wait()
        local down = TweenService:Create(cam, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base })
        down:Play()
        down.Completed:Wait()
        fovBusy = false
    end)
end

local function ringWipe(color)
    local vp = Workspace.CurrentCamera.ViewportSize
    local maxd = math.max(vp.X, vp.Y) * 2.4
    for i = 1, 3 do
        task.delay((i - 1) * 0.07, function()
            local f = Instance.new("Frame")
            f.AnchorPoint = Vector2.new(0.5, 0.5)
            f.Position = UDim2.fromScale(0.5, 0.5)
            f.Size = UDim2.fromOffset(30, 30)
            f.BackgroundTransparency = 1
            f.ZIndex = 90
            f.Parent = gui
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0.5, 0)
            c.Parent = f
            local st = Instance.new("UIStroke")
            st.Thickness = 10 - i * 2
            st.Color = color
            st.Parent = f
            TweenService:Create(f, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(maxd, maxd) }):Play()
            TweenService:Create(st, TweenInfo.new(0.55), { Transparency = 1 }):Play()
            Debris:AddItem(f, 0.7)
        end)
    end
end

-- full teleport warp (27)
local function warp(color)
    flash(color, 0.3)
    fovWarp()
    shake(1.0, 0.45)
    blurFx.Size = 26
    TweenService:Create(blurFx, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 0 }):Play()
    tintFx.Brightness = 0.22
    TweenService:Create(tintFx, TweenInfo.new(0.6), { Brightness = 0 }):Play()
    ringWipe(color)
end

local function burstAt(pos, color, count)
    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.Transparency = 1
    p.Size = V(0.2, 0.2, 0.2)
    p.Position = pos
    p.Parent = Workspace
    local pe = Instance.new("ParticleEmitter")
    pe.Enabled = false
    pe.Rate = 0
    pe.Color = ColorSequence.new(color)
    pe.LightEmission = 1
    pe.Lifetime = NumberRange.new(0.4, 0.9)
    pe.Speed = NumberRange.new(10, 25)
    pe.SpreadAngle = Vector2.new(180, 180)
    pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
    pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
    pe.Parent = p
    pe:Emit(count or 30)
    Debris:AddItem(p, 2)
end

-- expanding / collapsing ring drawn with a SurfaceGui (clean circle outline)
local function spawnRing(parent, cf, w, h, toScale, color, dur, delay, fromScale)
    task.delay(delay or 0, function()
        if not parent or not parent.Parent then return end
        local fs = fromScale or 0.2
        local part = Instance.new("Part")
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = false
        part.Transparency = 1
        part.Size = V(w * fs, h * fs, 0.05)
        part.CFrame = cf
        part.Parent = parent
        local sg = Instance.new("SurfaceGui")
        sg.Face = Enum.NormalId.Front
        sg.CanvasSize = Vector2.new(256, 256)
        sg.LightInfluence = 0
        sg.Brightness = 3
        sg.Parent = part
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, -12, 1, -12)
        f.Position = UDim2.fromOffset(6, 6)
        f.BackgroundTransparency = 1
        f.Parent = sg
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0.5, 0)
        c.Parent = f
        local st = Instance.new("UIStroke")
        st.Thickness = 14
        st.Color = color
        st.Parent = f
        TweenService:Create(part, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V(w * toScale, h * toScale, 0.05) }):Play()
        TweenService:Create(st, TweenInfo.new(dur), { Transparency = 1 }):Play()
        Debris:AddItem(part, dur + 0.1)
    end)
end

local function surfaceCF(pos, normal)
    local up = (math.abs(normal.Y) > 0.95) and Vector3.zAxis or Vector3.yAxis
    local o = pos + normal * 0.08
    return CFrame.lookAt(o, o + normal, up)
end

local function impactFx(pos, normal, color)
    local cf = surfaceCF(pos, normal)
    spawnRing(portalFolder, cf, 3, 3, 3.4, color, 0.45, 0, 0.15)
    spawnRing(portalFolder, cf, 3, 3, 2.2, WHITE3, 0.3, 0.05, 0.1)
    burstAt(pos + normal * 0.4, color, 22)
    cueAt("Impact", pos)
    local lp = Instance.new("Part")
    lp.Anchored = true
    lp.CanCollide = false
    lp.CanQuery = false
    lp.CanTouch = false
    lp.Transparency = 1
    lp.Size = V(0.2, 0.2, 0.2)
    lp.Position = pos + normal * 1.2
    lp.Parent = portalFolder
    local l = Instance.new("PointLight")
    l.Color = color
    l.Range = 20
    l.Brightness = 6
    l.Parent = lp
    TweenService:Create(l, TweenInfo.new(0.4), { Brightness = 0 }):Play()
    Debris:AddItem(lp, 0.5)
end

--------------------------------------------------------------------- DIMENSIONS (19)
local function slotColor(slot)
    local c = DIMENSIONS[state.dim].color
    if slot == 1 then return c end
    local h, s, v = c:ToHSV()
    if s < 0.2 then return Color3.fromRGB(150, 150, 255) end
    return Color3.fromHSV((h + 0.5) % 1, s, v)
end

setDimension = function(i, silent)
    state.dim = i
    local d = DIMENSIONS[i]
    if currentGun then
        currentGun.setColor(d)
        if not silent then currentGun.dialStep() end
    end
    if equipped then applyTint(true) end
    refreshUI()
    if not silent then
        toast("DIMENSION  " .. d.name, d.color)
        uiCue("Dial")
        flash(d.color, 0.75)
        blurFx.Size = 10
        TweenService:Create(blurFx, TweenInfo.new(0.4), { Size = 0 }):Play()
    end
end

--------------------------------------------------------------------- GUN MODEL (1-8, 29)
local C = {
    white    = Color3.fromRGB(238, 238, 230),
    steel    = Color3.fromRGB(160, 164, 172),
    lightsteel = Color3.fromRGB(205, 208, 212),
    gray     = Color3.fromRGB(110, 114, 122),
    charcoal = Color3.fromRGB(58, 60, 66),
    dark     = Color3.fromRGB(34, 34, 38),
    black    = Color3.fromRGB(20, 20, 22),
    glass    = Color3.fromRGB(190, 255, 200),
    ledOff   = Color3.fromRGB(25, 28, 26),
}

local function makeScreen(part, face)
    local sg = Instance.new("SurfaceGui")
    sg.Face = face
    sg.CanvasSize = Vector2.new(360, 205)
    sg.LightInfluence = 0
    sg.Brightness = 2.2
    sg.Parent = part
    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = Color3.fromRGB(4, 8, 6)
    bg.BorderSizePixel = 0
    bg.Parent = sg
    local st = Instance.new("UIStroke")
    st.Thickness = 4
    st.Parent = bg
    local cap = Instance.new("TextLabel")
    cap.Position = UDim2.fromScale(0.06, 0.05)
    cap.Size = UDim2.fromScale(0.88, 0.2)
    cap.BackgroundTransparency = 1
    cap.Font = Enum.Font.Code
    cap.TextScaled = true
    cap.Text = "DIMENSION"
    cap.TextXAlignment = Enum.TextXAlignment.Left
    cap.Parent = bg
    local nm = Instance.new("TextLabel")
    nm.Position = UDim2.fromScale(0.06, 0.26)
    nm.Size = UDim2.fromScale(0.88, 0.42)
    nm.BackgroundTransparency = 1
    nm.Font = Enum.Font.Code
    nm.TextScaled = true
    nm.Text = ""
    nm.TextXAlignment = Enum.TextXAlignment.Left
    nm.Parent = bg
    local bars = {}
    for i = 1, 10 do
        local b = Instance.new("Frame")
        b.AnchorPoint = Vector2.new(0, 1)
        b.Position = UDim2.fromScale(0.06 + (i - 1) * 0.088, 0.95)
        b.Size = UDim2.fromScale(0.07, 0.2)
        b.BorderSizePixel = 0
        b.Parent = bg
        bars[i] = b
    end
    return { stroke = st, cap = cap, name = nm, bars = bars }
end

local function buildGun()
    local tool = Instance.new("Tool")
    tool.Name = CONFIG.GunName
    tool.ToolTip = "Portal Gun"
    tool.RequiresHandle = true
    tool.CanBeDropped = false
    tool.Grip = CFrame.new()

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = V(0.6, 1.4, 0.8)
    handle.Transparency = 1
    handle.CanCollide = false
    handle.Massless = true
    handle.Parent = tool

    local tinted = {}
    local function paint(part, k)
        table.insert(tinted, { part = part, k = k or 0 })
    end

    local Block, Ball, Cyl = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
    local Neon, Metal, Glass = Enum.Material.Neon, Enum.Material.Metal, Enum.Material.Glass

    local function add(spec)
        local p = Instance.new("Part")
        p.Name = spec.Name
        p.Shape = spec.Shape or Block
        p.Size = spec.Size
        p.Color = spec.Color or C.dark
        p.Material = spec.Material or Enum.Material.SmoothPlastic
        p.Transparency = spec.Transparency or 0
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.Massless = true
        p.CastShadow = false
        p.TopSurface = Enum.SurfaceType.Smooth
        p.BottomSurface = Enum.SurfaceType.Smooth
        p.Parent = tool
        local w = Instance.new("Weld")
        w.Part0 = spec.Base or handle
        w.Part1 = p
        w.C0 = spec.Offset
        w.Parent = p
        return p, w
    end

    -------- angled ribbed grip
    local gripCF = CFrame.new(0, 0, 0.12) * CFrame.Angles(math.rad(-12), 0, 0)
    local grip = add{ Name = "Grip", Size = V(0.6, 1.5, 0.85), Offset = gripCF, Color = C.dark }
    for i = 0, 5 do
        add{ Name = "Rib", Base = grip, Size = V(0.52, 0.07, 0.06), Offset = CFrame.new(0, -0.55 + i * 0.2, 0.44), Color = C.black }
    end
    add{ Name = "GripCap", Base = grip, Size = V(0.7, 0.12, 0.95), Offset = CFrame.new(0, -0.78, 0), Color = C.charcoal, Material = Metal }
    for _, s in ipairs({ 1, -1 }) do
        add{ Name = "Inlay", Base = grip, Size = V(0.04, 1.0, 0.5), Offset = CFrame.new(s * 0.3, 0.05, -0.05), Color = C.charcoal, Material = Metal }
    end

    -------- rounded main shell
    local bodyY, bodyZ = 1.1, -0.85
    add{ Name = "BodyCore",  Size = V(0.8, 0.62, 2.6),  Offset = CFrame.new(0, bodyY, bodyZ), Color = C.white }
    add{ Name = "BodyCore2", Size = V(0.52, 0.9, 2.6),  Offset = CFrame.new(0, bodyY, bodyZ), Color = C.white }
    for _, sx in ipairs({ 1, -1 }) do
        for _, sy in ipairs({ 1, -1 }) do
            add{ Name = "Edge", Shape = Cyl, Size = V(2.6, 0.28, 0.28), Offset = CFrame.new(sx * 0.26, bodyY + sy * 0.31, bodyZ) * R90, Color = C.white }
        end
    end
    add{ Name = "Seam",       Size = V(0.83, 0.03, 2.5), Offset = CFrame.new(0, bodyY, bodyZ), Color = Color3.fromRGB(70, 72, 78) }
    add{ Name = "FrontPlate", Size = V(0.84, 0.94, 0.1), Offset = CFrame.new(0, bodyY, -2.2), Color = C.charcoal, Material = Metal }
    add{ Name = "RearPlate",  Size = V(0.84, 0.94, 0.1), Offset = CFrame.new(0, bodyY, 0.5), Color = C.charcoal, Material = Metal }
    add{ Name = "LowerShell", Size = V(0.7, 0.22, 2.2),  Offset = CFrame.new(0, 0.58, -0.7), Color = C.steel, Material = Metal }
    add{ Name = "TopPlate",   Size = V(0.5, 0.05, 1.0),  Offset = CFrame.new(0, bodyY + 0.47, -1.65), Color = C.charcoal, Material = Metal }
    add{ Name = "Sight",      Size = V(0.1, 0.12, 0.5),  Offset = CFrame.new(0, 1.65, -2.0), Color = C.dark }
    for i = 0, 3 do
        add{ Name = "Vent", Size = V(0.46, 0.03, 0.07), Offset = CFrame.new(0, 1.57, 0.35 - i * 0.12), Color = C.black }
    end

    -------- side screens, bolts, light strips
    local screens = {}
    for _, s in ipairs({ 1, -1 }) do
        add{ Name = "Bezel", Size = V(0.06, 0.62, 1.0), Offset = CFrame.new(s * 0.42, bodyY - 0.02, -0.55), Color = C.dark }
        local scr = add{ Name = "Screen", Size = V(0.03, 0.5, 0.88), Offset = CFrame.new(s * 0.455, bodyY - 0.02, -0.55), Color = Color3.new(0, 0, 0) }
        table.insert(screens, makeScreen(scr, (s == 1) and Enum.NormalId.Right or Enum.NormalId.Left))
        for _, dy in ipairs({ 0.27, -0.27 }) do
            for _, dz in ipairs({ 0.45, -0.45 }) do
                add{ Name = "Bolt", Shape = Cyl, Size = V(0.04, 0.08, 0.08), Offset = CFrame.new(s * 0.45, bodyY - 0.02 + dy, -0.55 + dz), Color = C.steel, Material = Metal }
            end
        end
        local strip = add{ Name = "Strip", Size = V(0.03, 0.05, 1.5), Offset = CFrame.new(s * 0.41, 0.74, -0.6), Material = Neon }
        paint(strip, 0.1)
    end

    -------- side dials (spin when dimension changes)
    local dials = {}
    for _, s in ipairs({ 1, -1 }) do
        local hubBase = CFrame.new(s * 0.44, bodyY, -1.6)
        local hub, hw = add{ Name = "DialHub", Size = V(0.1, 0.1, 0.1), Offset = hubBase, Transparency = 1 }
        add{ Name = "DialBase", Base = hub, Shape = Cyl, Size = V(0.1, 0.5, 0.5),  Offset = CFrame.new(s * 0.02, 0, 0), Color = C.charcoal, Material = Metal }
        add{ Name = "DialKnob", Base = hub, Shape = Cyl, Size = V(0.14, 0.36, 0.36), Offset = CFrame.new(s * 0.1, 0, 0), Color = C.steel, Material = Metal }
        local ptr = add{ Name = "DialPtr", Base = hub, Size = V(0.05, 0.05, 0.16), Offset = CFrame.new(s * 0.18, 0, 0.1), Material = Neon }
        paint(ptr, 0.2)
        table.insert(dials, { weld = hw, base = hubBase })
    end

    -------- glass fluid tank (caged)
    local tankZ = -0.9
    add{ Name = "TankBase", Shape = Cyl, Size = V(0.16, 1.1, 1.1), Offset = CFrame.new(0, 1.63, tankZ) * RY, Color = C.charcoal, Material = Metal }
    local tankRing = add{ Name = "TankRing", Shape = Cyl, Size = V(0.05, 1.0, 1.0), Offset = CFrame.new(0, 1.73, tankZ) * RY, Material = Neon }
    paint(tankRing, 0.2)
    local fluid = add{ Name = "Fluid", Shape = Cyl, Size = V(0.64, 0.8, 0.8), Offset = CFrame.new(0, 2.05, tankZ) * RY, Material = Neon, Transparency = 0.1 }
    paint(fluid, 0)
    local fluidCap, fluidCapWeld = add{ Name = "FluidCap", Shape = Ball, Size = V(0.8, 0.36, 0.8), Offset = CFrame.new(0, 2.37, tankZ), Material = Neon, Transparency = 0.1 }
    paint(fluidCap, 0)
    local glass = add{ Name = "Glass", Shape = Cyl, Size = V(0.78, 0.96, 0.96), Offset = CFrame.new(0, 2.1, tankZ) * RY, Color = C.glass, Material = Glass, Transparency = 0.55 }
    paint(glass, 0.7)
    local dome = add{ Name = "GlassDome", Shape = Ball, Size = V(0.96, 0.5, 0.96), Offset = CFrame.new(0, 2.49, tankZ), Color = C.glass, Material = Glass, Transparency = 0.55 }
    paint(dome, 0.7)
    add{ Name = "TankBand", Shape = Cyl, Size = V(0.07, 1.0, 1.0), Offset = CFrame.new(0, 2.12, tankZ) * RY, Color = C.charcoal, Material = Metal }
    add{ Name = "TankCap", Shape = Cyl, Size = V(0.14, 0.5, 0.5), Offset = CFrame.new(0, 2.78, tankZ) * RY, Color = C.charcoal, Material = Metal }
    local nozzle = add{ Name = "Nozzle", Shape = Cyl, Size = V(0.2, 0.2, 0.2), Offset = CFrame.new(0, 2.92, tankZ) * RY, Color = C.steel, Material = Metal }
    for _, sx in ipairs({ 0.4, -0.4 }) do
        for _, sz in ipairs({ 0.4, -0.4 }) do
            add{ Name = "Strut", Shape = Cyl, Size = V(0.9, 0.07, 0.07), Offset = CFrame.new(sx, 2.12, tankZ + sz) * RY, Color = C.steel, Material = Metal }
        end
    end
    local tankLight = Instance.new("PointLight")
    tankLight.Range = 16
    tankLight.Brightness = 2.2
    tankLight.Parent = fluid

    local bubbles = Instance.new("ParticleEmitter")
    bubbles.Rate = 14
    bubbles.LightEmission = 1
    bubbles.Speed = NumberRange.new(0.4, 0.9)
    bubbles.Lifetime = NumberRange.new(1.0, 1.6)
    bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
    bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
    bubbles.Parent = fluid

    local zapFx = Instance.new("ParticleEmitter")
    zapFx.Enabled = false
    zapFx.Rate = 0
    zapFx.LightEmission = 1
    zapFx.Speed = NumberRange.new(4, 9)
    zapFx.SpreadAngle = Vector2.new(180, 180)
    zapFx.Lifetime = NumberRange.new(0.15, 0.35)
    zapFx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
    zapFx.Parent = nozzle

    -------- pipes + energy flow
    for _, sx in ipairs({ 0.2, -0.2 }) do
        add{ Name = "Pipe", Shape = Cyl, Size = V(1.3, 0.12, 0.12), Offset = CFrame.new(sx, 1.64, -1.65) * R90, Color = C.steel, Material = Metal }
        add{ Name = "Clamp", Size = V(0.18, 0.2, 0.1), Offset = CFrame.new(sx, 1.62, -1.55), Color = C.charcoal, Material = Metal }
    end
    local flows = {}
    for _, sx in ipairs({ 0.2, -0.2 }) do
        for k = 0, 1 do
            local d, w = add{ Name = "Flow", Size = V(0.15, 0.15, 0.22), Offset = CFrame.new(sx, 1.66, -1.1), Material = Neon }
            paint(d, 0.5)
            table.insert(flows, { weld = w, x = sx, phase = k * 0.5 })
        end
    end

    -------- barrel: neck, rings, coil, stepped bell, lens
    add{ Name = "Neck",  Shape = Cyl, Size = V(0.6, 0.9, 0.9),   Offset = CFrame.new(0, bodyY, -2.55) * R90, Color = C.steel, Material = Metal }
    add{ Name = "RingA", Shape = Cyl, Size = V(0.14, 1.05, 1.05), Offset = CFrame.new(0, bodyY, -2.92) * R90, Color = C.dark }
    add{ Name = "MidBarrel", Shape = Cyl, Size = V(0.8, 0.8, 0.8), Offset = CFrame.new(0, bodyY, -3.39) * R90, Color = C.lightsteel, Material = Metal }
    add{ Name = "RingB", Shape = Cyl, Size = V(0.14, 1.0, 1.0),   Offset = CFrame.new(0, bodyY, -3.86) * R90, Color = C.dark }
    for i = 1, 4 do
        add{ Name = "Bell" .. i, Shape = Cyl, Size = V(0.13, 1.0 + 0.12 * i, 1.0 + 0.12 * i),
            Offset = CFrame.new(0, bodyY, -3.99 - (i - 1) * 0.13) * R90,
            Color = (i % 2 == 1) and C.white or C.steel, Material = (i % 2 == 1) and Enum.Material.SmoothPlastic or Metal }
    end
    add{ Name = "LensBezel", Shape = Cyl, Size = V(0.05, 1.1, 1.1), Offset = CFrame.new(0, bodyY, -4.455) * R90, Color = C.black }
    local lens = add{ Name = "Lens", Shape = Cyl, Size = V(0.06, 0.95, 0.95), Offset = CFrame.new(0, bodyY, -4.5) * R90, Material = Neon }
    paint(lens, 0.35)
    local lensLight = Instance.new("PointLight")
    lensLight.Range = 14
    lensLight.Brightness = 0.5
    lensLight.Parent = lens

    -- spinning coil
    local coilBase = CFrame.new(0, bodyY, -3.39)
    local coilHub, coilWeld = add{ Name = "CoilHub", Size = V(0.1, 0.1, 0.1), Offset = coilBase, Transparency = 1 }
    for i = 0, 7 do
        local a = i * math.pi / 4
        local b = add{ Name = "Coil", Base = coilHub, Size = V(0.18, 0.1, 0.55),
            Offset = CFrame.new(math.cos(a) * 0.46, math.sin(a) * 0.46, 0) * CFrame.Angles(0, 0, a), Material = Neon }
        paint(b, 0.15)
    end

    -- mini portal swirl inside the muzzle
    local swirlBase = CFrame.new(0, bodyY, -4.56)
    local swirlHub, swirlWeld = add{ Name = "SwirlHub", Size = V(0.1, 0.1, 0.1), Offset = swirlBase, Transparency = 1 }
    for i = 1, 7 do
        local f = 0.12 + 0.85 * (i - 1) / 6
        local a = i * 0.95
        local d = add{ Name = "SwirlDot", Base = swirlHub, Size = V(0.09, 0.09, 0.05),
            Offset = CFrame.new(math.cos(a) * f * 0.4, math.sin(a) * f * 0.4, 0), Material = Neon }
        paint(d, 0.7)
    end

    local muzzle = add{ Name = "Muzzle", Size = V(0.2, 0.2, 0.2), Offset = CFrame.new(0, bodyY, -4.75), Transparency = 1 }

    local muzzleSparks = Instance.new("ParticleEmitter")
    muzzleSparks.Enabled = false
    muzzleSparks.Rate = 0
    muzzleSparks.LightEmission = 1
    muzzleSparks.EmissionDirection = Enum.NormalId.Front
    muzzleSparks.SpreadAngle = Vector2.new(35, 35)
    muzzleSparks.Speed = NumberRange.new(8, 18)
    muzzleSparks.Lifetime = NumberRange.new(0.3, 0.7)
    muzzleSparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
    muzzleSparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
    muzzleSparks.Parent = muzzle

    local muzzleGlow = Instance.new("ParticleEmitter")
    muzzleGlow.Enabled = false
    muzzleGlow.Rate = 0
    muzzleGlow.Texture = "rbxasset://textures/particles/smoke_main.dds"
    muzzleGlow.LightEmission = 1
    muzzleGlow.Speed = NumberRange.new(0, 0)
    muzzleGlow.Lifetime = NumberRange.new(0.2, 0.28)
    muzzleGlow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 3.2) })
    muzzleGlow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
    muzzleGlow.Parent = muzzle

    -------- rear cap + charge meter LEDs
    add{ Name = "RearCap", Shape = Cyl, Size = V(0.25, 0.6, 0.6), Offset = CFrame.new(0, bodyY, 0.62) * R90, Color = C.charcoal, Material = Metal }
    local rearGlow = add{ Name = "RearGlow", Shape = Cyl, Size = V(0.05, 0.32, 0.32), Offset = CFrame.new(0, bodyY, 0.76) * R90, Material = Neon }
    paint(rearGlow, 0.3)
    local leds = {}
    for _, sx in ipairs({ 0.37, -0.37 }) do
        for i = 0, 5 do
            local p = add{ Name = "LED", Size = V(0.1, 0.07, 0.05), Offset = CFrame.new(sx, 0.78 + i * 0.12, 0.56), Material = Neon }
            table.insert(leds, { part = p, idx = i + 1 })
        end
    end

    -------- trigger + guard
    local trigBase = CFrame.new(0, 0.32, -0.5)
    local trigger, trigWeld = add{ Name = "Trigger", Size = V(0.1, 0.3, 0.12), Offset = trigBase, Color = C.steel, Material = Metal }
    add{ Name = "GuardFront", Size = V(0.1, 0.55, 0.07), Offset = CFrame.new(0, 0.27, -0.98), Color = C.charcoal, Material = Metal }
    add{ Name = "GuardBottom", Size = V(0.1, 0.07, 0.55), Offset = CFrame.new(0, 0.0, -0.72), Color = C.charcoal, Material = Metal }

    -------- sounds
    local gun = {
        tool = tool, handle = handle, muzzle = muzzle,
        cur = DIMENSIONS[state.dim].color, target = DIMENSIONS[state.dim].color,
        spinSpeed = 2, spin = 0, swirl = 0,
        charge = 0, chargeTarget = 0, flash = 0, trigPull = 0,
        dialAngle = 0, dialTarget = 0, lastShot = -10,
        nextZap = os.clock() + 2, nextBars = 0,
        hum = nil,
    }

    function gun.setColor(d, instant)
        gun.target = d.color
        if instant then gun.cur = d.color end
        muzzleSparks.Color = ColorSequence.new(d.color)
        muzzleGlow.Color = ColorSequence.new(d.color)
        bubbles.Color = ColorSequence.new(d.color)
        zapFx.Color = ColorSequence.new(d.color)
        for _, sc in ipairs(screens) do
            sc.name.Text = d.name
            sc.name.TextColor3 = d.color
            sc.cap.TextColor3 = d.color
            sc.stroke.Color = d.color
            for _, b in ipairs(sc.bars) do b.BackgroundColor3 = d.color end
        end
    end

    function gun.dialStep()
        gun.dialTarget = gun.dialTarget + math.rad(120)
    end

    function gun.beginCharge()
        gun.chargeTarget = 1
        muzzleGlow:Emit(1)
    end

    function gun.release()
        gun.chargeTarget = 0
        gun.spinSpeed = 45
        gun.flash = 1
        gun.trigPull = 1
        gun.lastShot = os.clock()
        muzzleSparks:Emit(22)
        muzzleGlow:Emit(2)
        tool.Grip = CFrame.new(0, 0, -0.5) * CFrame.Angles(math.rad(-12), 0, 0)
        pcall(function()
            TweenService:Create(tool, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Grip = CFrame.new() }):Play()
        end)
    end

    function gun.update(dt, t)
        -- smooth dimension color blend
        gun.cur = gun.cur:Lerp(gun.target, math.min(dt * 6, 1))
        for _, e in ipairs(tinted) do
            e.part.Color = gun.cur:Lerp(WHITE3, e.k)
        end
        tankLight.Color = gun.cur
        lensLight.Color = gun.cur

        -- charge / flash
        gun.charge = gun.charge + (gun.chargeTarget - gun.charge) * math.min(dt * 14, 1)
        gun.flash = math.max(0, gun.flash - dt * 3)
        lensLight.Brightness = 0.6 + 6 * gun.charge + 6 * gun.flash
        tankLight.Brightness = 2.0 + 0.5 * math.sin(t * 3) + math.noise(t * 9, 0.5) * 1.2 + gun.flash * 3
        bubbles.Rate = 14 + 50 * gun.charge

        -- coil + muzzle swirl
        gun.spinSpeed = gun.spinSpeed + ((2 + 40 * gun.charge) - gun.spinSpeed) * math.min(dt * 2.5, 1)
        gun.spin = gun.spin + gun.spinSpeed * dt
        coilWeld.C0 = coilBase * CFrame.Angles(0, 0, gun.spin)
        gun.swirl = gun.swirl + (3 + 20 * gun.charge) * dt
        swirlWeld.C0 = swirlBase * CFrame.Angles(0, 0, -gun.swirl)

        -- fluid slosh
        fluidCapWeld.C0 = CFrame.new(0, 2.37, tankZ) * CFrame.Angles(0.07 * math.sin(t * 2.1), 0, 0.07 * math.sin(t * 1.7))
        fluid.Transparency = 0.1 + 0.06 * (0.5 + 0.5 * math.sin(t * 3))

        -- energy flowing along the pipes
        for _, f in ipairs(flows) do
            local u = (t * 0.9 + f.phase) % 1
            f.weld.C0 = CFrame.new(f.x, 1.66, -1.05 - u * 1.2)
        end

        -- trigger
        gun.trigPull = math.max(0, gun.trigPull - dt * 6)
        trigWeld.C0 = trigBase * CFrame.new(0, 0, 0.12 * gun.trigPull)

        -- dials
        gun.dialAngle = gun.dialAngle + (gun.dialTarget - gun.dialAngle) * math.min(dt * 9, 1)
        for _, d in ipairs(dials) do
            d.weld.C0 = d.base * CFrame.Angles(gun.dialAngle, 0, 0)
        end

        -- charge meter
        local meter = math.clamp((t - gun.lastShot) / (CONFIG.FireDelay + 0.35), 0, 1)
        local lit = math.floor(meter * 6 + 0.001)
        for _, l in ipairs(leds) do
            if l.idx <= lit then
                l.part.Color = gun.cur:Lerp(WHITE3, 0.2)
            else
                l.part.Color = C.ledOff
            end
        end

        -- screen signal bars
        if t > gun.nextBars then
            gun.nextBars = t + 0.12
            for _, sc in ipairs(screens) do
                for i, b in ipairs(sc.bars) do
                    b.Size = UDim2.fromScale(0.07, 0.04 + 0.2 * (0.5 + math.noise(t * 2.2, i * 1.7)))
                end
            end
        end

        -- random electric zaps
        if t > gun.nextZap then
            gun.nextZap = t + 1.2 + math.random() * 2.5
            zapFx:Emit(8)
            cue("Zap", handle)
        end
    end

    return gun
end

--------------------------------------------------------------------- PORTALS (9, 11-14, 16-18, 29)
local function mkPart(parent, shape, material, color, transparency)
    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.CastShadow = false
    p.Shape = shape
    p.Material = material
    p.Color = color
    p.Transparency = transparency or 0
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Size = V(0.2, 0.2, 0.2)
    p.Parent = parent
    return p
end

local function createPortal(slot, pos, normal)
    local H = CONFIG.Sizes[state.size][2]
    local W = H * ELLIPSE
    local color = slotColor(slot)
    local bright = color:Lerp(WHITE3, 0.55)
    local cf = surfaceCF(pos, normal)
    cf = cf - cf.Position + (pos + normal * 0.07)   -- keep orientation, set final position
    local discCF = cf * R90

    local folder = Instance.new("Folder")
    folder.Name = "Portal" .. slot
    folder.Parent = portalFolder

    local p = {
        slot = slot, cf = cf, normal = normal, H = H, W = W, rx = W / 2, ry = H / 2,
        color = color, bright = bright, folder = folder,
        alive = true, dead = false, lastScale = -1, seed = math.random() * 10,
        nextArc = 0, nextZap = os.clock() + 1 + math.random() * 3,
        layers = {}, movers = {}, cfs = {}, dotMeta = {}, blobMeta = {},
        rimAtts = {}, beams = {},
    }

    -- stacked ellipse layers: halo, rim, void, depth gradient, eye
    local function layer(scale, thick, col, transp)
        local part = mkPart(folder, Enum.PartType.Cylinder, Enum.Material.Neon, col, transp)
        part.CFrame = discCF
        local L = { part = part, scale = scale, thick = thick }
        table.insert(p.layers, L)
        return L
    end
    p.haloL = layer(1.32, 0.1, color, 0.82)
    layer(1.0, 0.3, color, 0)
    layer(0.86, 0.34, Color3.new(color.R * 0.15, color.G * 0.15, color.B * 0.15), 0.05)
    layer(0.66, 0.35, Color3.new(color.R * 0.4, color.G * 0.4, color.B * 0.4), 0.35)
    layer(0.45, 0.36, Color3.new(color.R * 0.7, color.G * 0.7, color.B * 0.7), 0.5)
    p.eyeL = layer(0.22, 0.37, bright, 0.55)

    -- anchor for particles / lights / beam attachments
    p.core = mkPart(folder, Enum.PartType.Block, Enum.Material.SmoothPlastic, color, 1)
    p.core.Size = V(W * 0.8, H * 0.8, 0.3)
    p.core.CFrame = cf

    local light = Instance.new("PointLight")
    light.Color = color
    light.Range = 24
    light.Brightness = 3
    light.Parent = p.core
    p.light = light

    local swirlFx = Instance.new("ParticleEmitter")
    swirlFx.Color = ColorSequence.new(color)
    swirlFx.LightEmission = 1
    swirlFx.Rate = 40
    swirlFx.Lifetime = NumberRange.new(1.0, 1.8)
    swirlFx.Speed = NumberRange.new(0.5, 2)
    swirlFx.SpreadAngle = Vector2.new(25, 25)
    swirlFx.EmissionDirection = Enum.NormalId.Front
    swirlFx.Rotation = NumberRange.new(0, 360)
    swirlFx.RotSpeed = NumberRange.new(-120, 120)
    swirlFx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
    swirlFx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
    swirlFx.Parent = p.core

    local sparkFx = Instance.new("ParticleEmitter")
    sparkFx.Color = ColorSequence.new(bright)
    sparkFx.LightEmission = 1
    sparkFx.Rate = 25
    sparkFx.Lifetime = NumberRange.new(0.4, 0.8)
    sparkFx.Speed = NumberRange.new(6, 14)
    sparkFx.SpreadAngle = Vector2.new(70, 70)
    sparkFx.EmissionDirection = Enum.NormalId.Front
    sparkFx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
    sparkFx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
    sparkFx.Parent = p.core
    p.sparkFx = sparkFx

    p.hum = startLoop("PortalHum", p.core)

    -- spiral arms: 3 forward + 2 counter-rotating streaks
    local function addDots(arms, per, base, wDir, szMul)
        for a = 1, arms do
            for j = 1, per do
                local u = (j - 1) / (per - 1)
                local f = 0.1 + 0.84 * u
                local part = mkPart(folder, Enum.PartType.Block, Enum.Material.Neon, base, 0.3 * u)
                local sz = H * 0.055 * (1 - 0.55 * u) * szMul
                table.insert(p.movers, part)
                table.insert(p.dotMeta, {
                    f = f, a = (a - 1) * (2 * math.pi / arms) + (1 - f) * 4.6 * wDir,
                    w = wDir * (1.1 + 2.0 * (1 - f)), size = sz,
                })
            end
        end
    end
    addDots(3, 12, bright, 1, 1)
    addDots(2, 8, color, -1, 0.7)

    -- boiling ragged rim blobs
    local blobCount = 22
    for i = 1, blobCount do
        local part = mkPart(folder, Enum.PartType.Ball, Enum.Material.Neon, bright, 0.05)
        table.insert(p.movers, part)
        table.insert(p.blobMeta, { ang = (i - 1) / blobCount * 2 * math.pi, size = H * 0.075, seed = i * 1.7 })
    end

    -- lightning arcs
    for i = 1, 12 do
        local att = Instance.new("Attachment")
        att.Parent = p.core
        table.insert(p.rimAtts, { att = att, ang = (i - 1) / 12 * 2 * math.pi })
    end
    p.centerAtt = Instance.new("Attachment")
    p.centerAtt.Parent = p.core
    for i = 1, 4 do
        local b = Instance.new("Beam")
        b.Attachment0 = p.rimAtts[i].att
        b.Attachment1 = p.rimAtts[i + 5].att
        b.Color = ColorSequence.new(WHITE3, color)
        b.LightEmission = 1
        b.LightInfluence = 0
        b.Width0 = 0.22
        b.Width1 = 0.22
        b.Segments = 10
        b.FaceCamera = true
        b.Transparency = NumberSequence.new(0.05)
        b.Parent = p.core
        table.insert(p.beams, b)
    end

    p.scale = Instance.new("NumberValue")
    p.scale.Value = 0
    p.openTween = TweenService:Create(p.scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 })
    p.openTween:Play()

    -- opening shock rings
    spawnRing(folder, cf, W, H, 1.9, bright, 0.6, 0, 0.3)
    spawnRing(folder, cf, W, H, 2.6, color, 0.9, 0.12, 0.3)

    table.insert(active, p)
    return p
end

local function closePortal(p)
    if not p or not p.alive then return end
    p.alive = false
    if portals[p.slot] == p then portals[p.slot] = nil end
    if p.openTween then p.openTween:Cancel() end
    cueAt("Close", p.cf.Position)
    spawnRing(portalFolder, p.cf, p.W, p.H, 0.15, p.bright, 0.4, 0, 1.5)
    local tw = TweenService:Create(p.scale, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 })
    tw.Completed:Connect(function() p.dead = true end)
    tw:Play()
end

local function openPortal(slot, pos, normal)
    if portals[slot] then closePortal(portals[slot]) end
    local p = createPortal(slot, pos, normal)
    portals[slot] = p
    cueAt("Open", p.cf.Position)
    burstAt(p.cf.Position + normal * 0.5, p.color, 30)
    shake(0.35, 0.25)
    local life = CONFIG.Lifetimes[state.life][2]
    if life > 0 then
        task.delay(life, function()
            if portals[slot] == p then closePortal(p) end
        end)
    end
end

local function updatePortal(p, t)
    local s = math.max(p.scale.Value, 0.02)
    local rx, ry = p.rx * s, p.ry * s
    local cf = p.cf

    if math.abs(s - p.lastScale) > 0.002 then
        p.lastScale = s
        for _, L in ipairs(p.layers) do
            L.part.Size = V(L.thick, p.H * L.scale * s, p.W * L.scale * s)
        end
        p.core.Size = V(p.W * s * 0.8, p.H * s * 0.8, 0.3)
        for _, a in ipairs(p.rimAtts) do
            a.att.Position = V(math.cos(a.ang) * rx * 0.95, math.sin(a.ang) * ry * 0.95, -0.15)
        end
        for i, d in ipairs(p.dotMeta) do
            local sz = math.max(d.size * s, 0.05)
            p.movers[i].Size = V(sz, sz, 0.14)
        end
    end

    -- pulsing eye + halo
    local pulse = 0.5 + 0.5 * math.sin(t * 3 + p.seed)
    local e = p.eyeL
    local k = 0.85 + 0.3 * pulse
    e.part.Size = V(e.thick, p.H * e.scale * s * k, p.W * e.scale * s * k)
    p.haloL.part.Transparency = 0.78 + 0.1 * pulse

    -- spiral dots + boiling blobs, moved in one batch
    local n = 0
    for _, d in ipairs(p.dotMeta) do
        n = n + 1
        local ang = d.a + t * d.w
        local r = d.f * 0.92 * (1 + 0.04 * math.sin(t * 3 + d.a))
        p.cfs[n] = cf * CFrame.new(math.cos(ang) * rx * r, math.sin(ang) * ry * r, -0.22)
    end
    for _, b in ipairs(p.blobMeta) do
        n = n + 1
        local jit = 1.0 + 0.18 * math.noise(t * 1.8 + b.seed, b.seed) + 0.035 * math.sin(t * 7 + b.seed * 2.1)
        local sz = math.max(b.size * s * (0.8 + 0.7 * (math.noise(t * 2.5, b.seed) + 0.5)), 0.05)
        p.movers[n].Size = V(sz, sz, sz)
        local ang = b.ang + t * 0.2
        p.cfs[n] = cf * CFrame.new(math.cos(ang) * rx * jit, math.sin(ang) * ry * jit, -0.05)
    end
    Workspace:BulkMoveTo(p.movers, p.cfs, Enum.BulkMoveMode.FireCFrameChanged)

    -- crackling lightning
    if t > p.nextArc then
        p.nextArc = t + 0.07 + math.random() * 0.08
        for _, b in ipairs(p.beams) do
            local i1 = math.random(1, #p.rimAtts)
            b.Attachment0 = p.rimAtts[i1].att
            if math.random() < 0.3 then
                b.Attachment1 = p.centerAtt
            else
                b.Attachment1 = p.rimAtts[((i1 + math.random(3, 8) - 1) % #p.rimAtts) + 1].att
            end
            b.CurveSize0 = (math.random() - 0.5) * 3
            b.CurveSize1 = (math.random() - 0.5) * 3
            b.Enabled = math.random() > 0.25
        end
    end

    p.light.Brightness = (2.5 + math.noise(t * 8, p.seed) * 2 + pulse) * math.min(s, 1)

    -- random zaps
    if p.alive and t > p.nextZap then
        p.nextZap = t + 1.5 + math.random() * 2.5
        p.sparkFx:Emit(12)
        cue("Zap", p.core)
    end
end

local function destroyPortal(p)
    stopLoop(p.hum)
    pcall(function() p.folder:Destroy() end)
    pcall(function() p.scale:Destroy() end)
end

-- teleport logic (16)
local function inZone(p, hrp)
    local rel = p.cf:PointToObjectSpace(hrp.Position)
    local ex = rel.X / (p.rx + 0.5)
    local ey = rel.Y / (p.ry + 0.5)
    return (ex * ex + ey * ey) < 1 and rel.Z < 0.6 and rel.Z > -3.6
end

local function wantsIn(p, hrp, hum)
    local n = p.normal
    if math.abs(n.Y) > 0.7 then return true end
    return hum.MoveDirection:Dot(n) < -0.2 or hrp.AssemblyLinearVelocity:Dot(n) < -4
end

local function flatten(v)
    return V(v.X, 0, v.Z)
end

local function teleportThrough(src, dst, hrp)
    local rel = src.cf:ToObjectSpace(hrp.CFrame)
    local flipped = dst.cf * CFrame.Angles(0, math.pi, 0) * rel
    local lp = dst.cf:PointToObjectSpace(flipped.Position)
    local depth = math.max(3, -lp.Z)
    local lx = 0
    if math.abs(dst.normal.Y) <= 0.7 then
        lx = math.clamp(lp.X, -dst.rx * 0.4, dst.rx * 0.4)
    end
    local outPos = dst.cf:PointToWorldSpace(V(lx, 0, -depth))

    local look
    if math.abs(dst.normal.Y) <= 0.7 then
        look = flatten(dst.normal)
    else
        look = flatten(flipped.LookVector)
        if look.Magnitude < 0.2 then look = flatten(hrp.CFrame.LookVector) end
    end
    if look.Magnitude < 0.01 then look = Vector3.zAxis end

    local vl = src.cf:VectorToObjectSpace(hrp.AssemblyLinearVelocity)
    local vw = dst.cf:VectorToWorldSpace(V(-vl.X, vl.Y, -vl.Z))
    local outSpeed = vw:Dot(dst.normal)
    if outSpeed < 12 then vw = vw + dst.normal * (12 - outSpeed) end

    hrp.CFrame = CFrame.lookAt(outPos, outPos + look.Unit)
    hrp.AssemblyLinearVelocity = vw

    state.armed = false
    state.lastTeleport = os.clock()

    burstAt(src.cf.Position + src.normal * 0.5, src.color, 45)
    burstAt(dst.cf.Position + dst.normal * 0.5, dst.color, 45)
    spawnRing(portalFolder, src.cf, src.W, src.H, 1.5, src.bright, 0.4, 0, 1.0)
    spawnRing(portalFolder, dst.cf, dst.W, dst.H, 1.5, dst.bright, 0.4, 0, 1.0)
    cueAt("Teleport", src.cf.Position)
    cueAt("Teleport", dst.cf.Position)
    warp(dst.color)
end

local function checkTeleport()
    local a, b = portals[1], portals[2]
    if not (a and b and a.alive and b.alive) then return end
    if a.scale.Value < 0.8 or b.scale.Value < 0.8 then return end
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end

    local inA, inB = inZone(a, hrp), inZone(b, hrp)
    if not (inA or inB) then
        if os.clock() - state.lastTeleport > 0.25 then state.armed = true end
        return
    end
    if not state.armed or os.clock() - state.lastTeleport < CONFIG.TeleportCooldown then return end

    if inA and wantsIn(a, hrp, hum) then
        teleportThrough(a, b, hrp)
    elseif inB and wantsIn(b, hrp, hum) then
        teleportThrough(b, a, hrp)
    end
end

--------------------------------------------------------------------- FIRING (10, 15, 21, 22)
local function useCenterAim()
    return (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
        or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

local function getAim()
    local cam = Workspace.CurrentCamera
    local pos
    if useCenterAim() then
        local vp = cam.ViewportSize
        pos = Vector2.new(vp.X / 2, vp.Y / 2)
    else
        pos = UserInputService:GetMouseLocation()
    end
    local ray = cam:ViewportPointToRay(pos.X, pos.Y)
    return ray.Origin, ray.Direction
end

-- helix projectile (15)
local function launchBolt(from, to, color, onHit)
    local bright = color:Lerp(WHITE3, 0.6)
    local made = {}

    local function glow(size, col, transp, withTrail)
        local part = mkPart(portalFolder, Enum.PartType.Ball, Enum.Material.Neon, col, transp)
        part.Size = V(size, size, size)
        part.Position = from
        if withTrail then
            local a0 = Instance.new("Attachment")
            a0.Position = V(0, size * 0.4, 0)
            a0.Parent = part
            local a1 = Instance.new("Attachment")
            a1.Position = V(0, -size * 0.4, 0)
            a1.Parent = part
            local trail = Instance.new("Trail")
            trail.Attachment0 = a0
            trail.Attachment1 = a1
            trail.Lifetime = 0.3
            trail.Color = ColorSequence.new(col)
            trail.Transparency = NumberSequence.new(0, 1)
            trail.LightEmission = 1
            trail.Parent = part
        end
        table.insert(made, part)
        return part
    end

    local core = glow(0.7, bright, 0, true)
    local halo = glow(1.6, color, 0.7, false)
    local orbs = {}
    for k = 1, 3 do
        orbs[k] = glow(0.35, color, 0.05, true)
    end

    local dir = (to - from)
    local len = dir.Magnitude
    dir = dir.Unit
    local p1 = dir:Cross(Vector3.yAxis)
    if p1.Magnitude < 0.1 then p1 = dir:Cross(Vector3.xAxis) end
    p1 = p1.Unit
    local p2 = dir:Cross(p1)
    local dur = math.max(len / CONFIG.BoltSpeed, 0.06)

    task.spawn(function()
        local t0 = os.clock()
        while true do
            local el = os.clock() - t0
            local a = el / dur
            if a >= 1 then break end
            local pos = from:Lerp(to, a)
            core.Position = pos
            halo.Position = pos
            local r = 0.75 * math.min(1, a * 8)
            for k, orb in ipairs(orbs) do
                local ang = el * 28 + k * 2.094
                orb.Position = pos + p1 * math.cos(ang) * r + p2 * math.sin(ang) * r
            end
            RunService.RenderStepped:Wait()
        end
        for _, part in ipairs(made) do
            part.Transparency = 1
            Debris:AddItem(part, 0.5)
        end
        onHit()
    end)
end

local function blinkTo(pos, normal, color)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local from = hrp.Position
    local dest = pos + normal * 3
    local look = flatten(hrp.CFrame.LookVector)
    if look.Magnitude < 0.01 then look = Vector3.zAxis end
    burstAt(from, color, 45)
    hrp.CFrame = CFrame.lookAt(dest, dest + look.Unit)
    hrp.AssemblyLinearVelocity = V(0, 0, 0)
    burstAt(dest, color, 45)
    cueAt("Teleport", from)
    cueAt("Teleport", dest)
    warp(color)
end

local lastFire = 0
local function fire()
    if not equipped or not currentGun then return end
    local now = os.clock()
    if now - lastFire < CONFIG.FireDelay then return end
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local origin, dir = getAim()
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { char, portalFolder }
    local result = Workspace:Raycast(origin, dir * CONFIG.Range, params)

    if not result then
        lastFire = now
        toast("NO SURFACE IN RANGE", Color3.fromRGB(255, 120, 120))
        uiCue("Deny")
        return
    end
    local model = result.Instance:FindFirstAncestorOfClass("Model")
    if model and model:FindFirstChildOfClass("Humanoid") then
        lastFire = now
        toast("CAN'T PORTAL A PERSON", Color3.fromRGB(255, 120, 120))
        uiCue("Deny")
        return
    end

    lastFire = now
    local gun = currentGun
    local mode = MODES[state.mode]
    local slot = state.nextSlot
    if mode ~= "BLINK" then
        state.nextSlot = (slot == 1) and 2 or 1
    end
    local hitPos, hitNormal = result.Position, result.Normal

    gun.beginCharge()
    cue("Charge", gun.handle)

    task.delay(CONFIG.ChargeTime, function()
        if not equipped or currentGun ~= gun or not gun.tool.Parent then
            gun.chargeTarget = 0
            return
        end
        if mode == "ROULETTE" then
            local i
            repeat i = math.random(#DIMENSIONS) until i ~= state.dim
            setDimension(i, true)
        end
        local color = DIMENSIONS[state.dim].color
        gun.release()
        cue("Fire", gun.handle)
        shake(0.45, 0.2)
        launchBolt(gun.muzzle.Position, hitPos, color, function()
            impactFx(hitPos, hitNormal, color)
            if mode == "BLINK" then
                blinkTo(hitPos, hitNormal, color)
            else
                openPortal(slot, hitPos, hitNormal)
            end
        end)
    end)
end

--------------------------------------------------------------------- ACTIONS (17, 18, 23, 24, 26)
cycleDimension = function() setDimension(state.dim % #DIMENSIONS + 1) end

cycleMode = function()
    state.mode = state.mode % #MODES + 1
    refreshUI()
    toast("MODE  " .. MODES[state.mode])
    uiCue("Mode")
end

cycleSize = function()
    state.size = state.size % #CONFIG.Sizes + 1
    refreshUI()
    toast("PORTAL SIZE  " .. CONFIG.Sizes[state.size][1])
    uiCue("Mode")
end

cycleTimer = function()
    state.life = state.life % #CONFIG.Lifetimes + 1
    refreshUI()
    toast("PORTAL TIMER  " .. CONFIG.Lifetimes[state.life][1])
    uiCue("Mode")
end

clearPortals = function()
    for _, p in ipairs(active) do
        if p.alive then closePortal(p) end
    end
    state.nextSlot = 1
    toast("PORTALS CLEARED")
end

toggleMute = function()
    state.muted = not state.muted
    if currentGun then setLoopMute(currentGun.hum, state.muted) end
    for _, p in ipairs(active) do setLoopMute(p.hum, state.muted) end
    refreshUI()
    toast(state.muted and "SOUND OFF" or "SOUND ON")
end

bind(UserInputService.InputBegan, function(input, gpe)
    if gpe or not equipped then return end
    local k = input.KeyCode
    if k == Enum.KeyCode.Q then cycleDimension()
    elseif k == Enum.KeyCode.E then cycleMode()
    elseif k == Enum.KeyCode.R then cycleSize()
    elseif k == Enum.KeyCode.T then cycleTimer()
    elseif k == Enum.KeyCode.F then clearPortals()
    elseif k == Enum.KeyCode.M then toggleMute()
    end
end)

--------------------------------------------------------------------- EQUIP + RESPAWN (30)
local function onEquip()
    equipped = true
    panel.Visible = true
    applyTint(true)
    refreshUI()
    if currentGun then
        stopLoop(currentGun.hum)
        currentGun.hum = startLoop("GunHum", currentGun.handle)
        cue("Equip", currentGun.handle)
    end
    toast("PORTAL GUN  //  " .. DIMENSIONS[state.dim].name)
end

local function onUnequip()
    equipped = false
    panel.Visible = false
    crosshair.Visible = false
    applyTint(false)
    if currentGun then
        stopLoop(currentGun.hum)
        currentGun.hum = nil
        currentGun.chargeTarget = 0
    end
end

local function giveGun()
    local char = player.Character
    if not char then return end
    local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
    if not backpack then return end
    if currentGun then pcall(function() currentGun.tool:Destroy() end) end

    local g = buildGun()
    currentGun = g
    g.setColor(DIMENSIONS[state.dim], true)
    g.tool.Equipped:Connect(onEquip)
    g.tool.Unequipped:Connect(onUnequip)
    g.tool.Activated:Connect(fire)
    g.tool.Parent = backpack

    local hum = char:FindFirstChildOfClass("Humanoid")
    task.delay(0.2, function()
        if hum and hum.Parent and g.tool.Parent == backpack then
            pcall(function() hum:EquipTool(g.tool) end)
        end
    end)
end

bind(player.CharacterAdded, function()
    equipped = false
    panel.Visible = false
    applyTint(false)
    task.wait(1)
    giveGun()
end)

--------------------------------------------------------------------- MAIN LOOP
bind(RunService.RenderStepped, function(dt)
    local t = os.clock()

    if currentGun and equipped then currentGun.update(dt, t) end
    crosshair.Visible = equipped and useCenterAim()

    for i = #active, 1, -1 do
        local p = active[i]
        if p.dead then
            destroyPortal(p)
            table.remove(active, i)
        else
            updatePortal(p, t)
        end
    end

    checkTeleport()

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        if shakeT > 0 then
            shakeT = shakeT - dt
            local amp = shakeAmp * math.max(shakeT, 0) / shakeDur
            hum.CameraOffset = V((math.random() - 0.5) * amp, (math.random() - 0.5) * amp, 0)
            shaking = true
        elseif shaking then
            hum.CameraOffset = V(0, 0, 0)
            shaking = false
        end
    end
end)

--------------------------------------------------------------------- CLEANUP + START
env.__PortalGunCleanup = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
    pcall(function() portalFolder:Destroy() end)
    pcall(function() tintFx:Destroy() end)
    pcall(function() bloomFx:Destroy() end)
    pcall(function() blurFx:Destroy() end)
    if currentGun then pcall(function() currentGun.tool:Destroy() end) end
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum.CameraOffset = V(0, 0, 0) end) end
    env.__PortalGunCleanup = nil
end

refreshUI()
if player.Character then giveGun() end
print("[PortalGun V2] loaded. Tap/click to fire. Keys: Q E R T F M")
