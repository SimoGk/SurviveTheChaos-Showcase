-- Visual effects, camera shake and music. The server only says "explosion at X";
-- everything is drawn here so it is smooth.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Sounds = require(ReplicatedStorage:WaitForChild("Sounds"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalEffects"
fxFolder.Parent = workspace

---------------------------------------------------------------- camera shake

local shakeStrength, shakeTime, shakeDuration = 0, 0, 0

local function shake(strength, duration)
	if strength >= shakeStrength * (shakeTime / math.max(shakeDuration, 0.01)) then
		shakeStrength, shakeTime, shakeDuration = strength, duration, duration
	end
end

-- shake scaled by distance to our character
local function shakeFrom(position, strength, range)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local d = (root.Position - position).Magnitude
	local k = math.clamp(1 - d / range, 0, 1)
	if k > 0 then shake(strength * k, 0.45) end
end

RunService.RenderStepped:Connect(function(dt)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if shakeTime > 0 then
		shakeTime -= dt
		local k = shakeStrength * math.max(shakeTime, 0) / shakeDuration
		hum.CameraOffset = Vector3.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, (math.random() - 0.5) * k)
	elseif hum.CameraOffset ~= Vector3.zero then
		hum.CameraOffset = Vector3.zero
	end
end)

---------------------------------------------------------------- helpers

local function fxPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do p[k] = v end
	p.Parent = fxFolder
	return p
end

local function tween(obj, time, goal, style)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- white screen flash (for close lightning)
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "Flash"; flashGui.IgnoreGuiInset = true; flashGui.DisplayOrder = 50; flashGui.ResetOnSpawn = false
local flash = Instance.new("Frame")
flash.Size = UDim2.new(1, 0, 1, 0); flash.BackgroundColor3 = Color3.new(1, 1, 1); flash.BackgroundTransparency = 1
flash.Parent = flashGui
flashGui.Parent = player:WaitForChild("PlayerGui")

local function screenFlash(amount)
	flash.BackgroundTransparency = 1 - amount
	tween(flash, 0.35, {BackgroundTransparency = 1})
end

---------------------------------------------------------------- effects

local Effects = {}

function Effects.explosion(pos, radius, color)
	color = color or Color3.fromRGB(255, 140, 40)
	radius = radius or 7

	-- core fireball
	local ball = fxPart({Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Position = pos, Color = Color3.fromRGB(255, 240, 180)})
	tween(ball, 0.3, {Size = Vector3.one * radius * 2.2, Transparency = 1, Color = color})
	Debris:AddItem(ball, 0.35)

	-- shockwave ring on the ground
	local ring = fxPart({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2, 2),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Transparency = 0.2})
	tween(ring, 0.45, {Size = Vector3.new(0.3, radius * 3.2, radius * 3.2), Transparency = 1})
	Debris:AddItem(ring, 0.5)

	-- debris chunks
	local att = Instance.new("Attachment")
	att.WorldPosition = pos
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color, Color3.fromRGB(60, 50, 45))
	pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0)})
	pe.Lifetime = NumberRange.new(0.5, 0.9)
	pe.Speed = NumberRange.new(25, 45)
	pe.SpreadAngle = Vector2.new(70, 70)
	pe.Acceleration = Vector3.new(0, -80, 0)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.LightEmission = 0.4
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(22)
	Debris:AddItem(att, 1.2)

	Sounds.playAt("Explosion", pos)
	shakeFrom(pos, 1.6, 45)
end

function Effects.lightning(pos)
	local color = Color3.fromRGB(255, 245, 140)
	-- jagged bolt from the sky
	local top = pos + Vector3.new(math.random(-6, 6), 90, math.random(-6, 6))
	local segments = 7
	local last = top
	for i = 1, segments do
		local t = i / segments
		local nextPoint = top:Lerp(pos, t)
		if i < segments then
			nextPoint += Vector3.new(math.random(-5, 5), 0, math.random(-5, 5))
		end
		local len = (nextPoint - last).Magnitude
		local seg = fxPart({Size = Vector3.new(1.1, 1.1, len), CFrame = CFrame.lookAt((last + nextPoint) / 2, nextPoint), Color = color})
		tween(seg, 0.3, {Transparency = 1, Size = Vector3.new(0.2, 0.2, len)})
		Debris:AddItem(seg, 0.35)
		last = nextPoint
	end
	local glow = fxPart({Shape = Enum.PartType.Ball, Size = Vector3.one * 4, Position = pos, Color = color})
	local light = Instance.new("PointLight"); light.Color = color; light.Range = 40; light.Brightness = 6; light.Parent = glow
	tween(glow, 0.35, {Size = Vector3.one * 14, Transparency = 1})
	Debris:AddItem(glow, 0.4)

	Sounds.playAt("Thunder", pos, {duration = 3, volume = 0.6})
	shakeFrom(pos, 1.2, 40)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and (root.Position - pos).Magnitude < 60 then screenFlash(0.35) end
end

function Effects.poof(pos)
	local att = Instance.new("Attachment")
	att.WorldPosition = pos
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(210, 200, 255))
	pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5)})
	pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1)})
	pe.Lifetime = NumberRange.new(0.5, 0.8)
	pe.Speed = NumberRange.new(6, 12)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(18)
	Debris:AddItem(att, 1.2)
	Sounds.playAt("Pop", pos, {volume = 0.5, duration = 1.5})
end

function Effects.shake(strength, duration)
	shake(strength or 1, duration or 0.5)
end

remotes:WaitForChild("Effect").OnClientEvent:Connect(function(kind, ...)
	local fn = Effects[kind]
	if fn then fn(...) end
end)

---------------------------------------------------------------- music

local music = Instance.new("Sound")
music.Name = "Music"
music.SoundId = Sounds.Ids.Music
music.Volume = Sounds.Volume.Music
music.Looped = true
music.Parent = game:GetService("SoundService")
music:Play()
