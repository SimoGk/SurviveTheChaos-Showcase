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

---------------------------------------------------------------- camera shake (position + rotation)

local trauma = 0 -- 0..1, decays over time; shake = trauma^2

local function addTrauma(amount)
	trauma = math.clamp(trauma + amount, 0, 1)
end

-- shake scaled by distance to our character
local function shakeFrom(position, strength, range)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local d = (root.Position - position).Magnitude
	local k = math.clamp(1 - d / range, 0, 1)
	if k > 0 then addTrauma(strength * k) end
end

local seed = math.random() * 1000
RunService:BindToRenderStep("CameraShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if trauma <= 0 then return end
	local s = trauma * trauma
	local t = os.clock() * 25
	local cam = workspace.CurrentCamera
	local rx = math.noise(seed, t) * 0.06 * s
	local ry = math.noise(seed + 10, t) * 0.06 * s
	local rz = math.noise(seed + 20, t) * 0.09 * s
	local offset = Vector3.new(math.noise(seed + 30, t), math.noise(seed + 40, t), 0) * 1.2 * s
	cam.CFrame = cam.CFrame * CFrame.new(offset) * CFrame.Angles(rx, ry, rz)
	trauma = math.max(0, trauma - dt * 1.6)
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

local function tween(obj, time, goal, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- full-screen color flash (white for lightning, red for hits, blue for shield)
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "Flash"; flashGui.IgnoreGuiInset = true; flashGui.DisplayOrder = 50; flashGui.ResetOnSpawn = false
local flash = Instance.new("Frame")
flash.Size = UDim2.new(1, 0, 1, 0); flash.BackgroundColor3 = Color3.new(1, 1, 1); flash.BackgroundTransparency = 1
flash.Parent = flashGui
-- red vignette for hits
local vignette = Instance.new("Frame")
vignette.Size = UDim2.new(1, 0, 1, 0); vignette.BackgroundTransparency = 1
local stroke = Instance.new("UIStroke", vignette); stroke.Color = Color3.fromRGB(255, 30, 40); stroke.Thickness = 0; stroke.Transparency = 0.2
vignette.Parent = flashGui
flashGui.Parent = player:WaitForChild("PlayerGui")

local function screenFlash(color, amount, time)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - amount
	tween(flash, time or 0.35, {BackgroundTransparency = 1})
end

local function distanceTo(pos)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and (root.Position - pos).Magnitude or math.huge
end

-- particle burst at a point
local function burst(pos, props, count, life)
	local att = Instance.new("Attachment")
	att.WorldPosition = pos
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	for k, v in props do pe[k] = v end
	pe.Parent = att
	pe:Emit(count)
	Debris:AddItem(att, life or 3)
	return pe
end

-- physical rock chunks flying away from an impact (client-side physics)
local function chunks(pos, color, count, power)
	for i = 1, count do
		local s = 0.6 + math.random() * 1.4
		local c = Instance.new("Part")
		c.Size = Vector3.new(s, s * (0.6 + math.random() * 0.6), s)
		c.Material = Enum.Material.Slate; c.Color = color:Lerp(Color3.fromRGB(60, 50, 45), math.random() * 0.6)
		c.CanQuery = false; c.CanTouch = false; c.CastShadow = false
		-- nearly weightless: bounces on the floor but cannot push players
		c.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0.6, 0.4)
		c.CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		c.Parent = fxFolder
		local a = math.random() * math.pi * 2
		c.AssemblyLinearVelocity = Vector3.new(math.cos(a), 0, math.sin(a)) * (power * (0.4 + math.random() * 0.6)) + Vector3.new(0, power * (0.7 + math.random() * 0.6), 0)
		c.AssemblyAngularVelocity = Vector3.new(math.random(-15, 15), math.random(-15, 15), math.random(-15, 15))
		task.delay(2.2 + math.random(), function()
			if c.Parent then tween(c, 0.4, {Size = Vector3.zero, Transparency = 1}) end
			Debris:AddItem(c, 0.5)
		end)
	end
end

-- dark scorch mark that stays on the ground for a while
local function scorch(pos, radius, color)
	local mark = fxPart({Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = color or Color3.fromRGB(30, 22, 20),
		Size = Vector3.new(0.12, radius * 2, radius * 2), CFrame = CFrame.new(pos + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.15})
	local ember = fxPart({Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(255, 120, 30),
		Size = Vector3.new(0.14, radius * 1.1, radius * 1.1), CFrame = mark.CFrame + Vector3.new(0, 0.02, 0), Transparency = 0.3})
	tween(ember, 2.5, {Transparency = 1, Size = Vector3.new(0.14, radius * 0.4, radius * 0.4)})
	task.delay(4, function() tween(mark, 1.5, {Transparency = 1}) end)
	Debris:AddItem(mark, 6); Debris:AddItem(ember, 3)
end

---------------------------------------------------------------- effects

local Effects = {}

function Effects.explosion(pos, radius, color)
	color = color or Color3.fromRGB(255, 140, 40)
	radius = radius or 7

	-- white-hot core, then fireball
	local core = fxPart({Shape = Enum.PartType.Ball, Size = Vector3.one * 3, Position = pos, Color = Color3.fromRGB(255, 255, 230)})
	tween(core, 0.15, {Size = Vector3.one * radius * 1.4, Transparency = 0.4})
	Debris:AddItem(core, 0.2)
	local ball = fxPart({Shape = Enum.PartType.Ball, Size = Vector3.one * radius, Position = pos, Color = Color3.fromRGB(255, 200, 90)})
	tween(ball, 0.45, {Size = Vector3.one * radius * 2.6, Transparency = 1, Color = color})
	Debris:AddItem(ball, 0.5)
	local light = Instance.new("PointLight"); light.Color = color; light.Range = radius * 6; light.Brightness = 8; light.Parent = ball

	-- two shockwave rings
	for i, t in {0.35, 0.6} do
		local ring = fxPart({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2, 2),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.3 + i * 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = i == 1 and Color3.fromRGB(255, 240, 200) or color, Transparency = 0.15})
		tween(ring, t, {Size = Vector3.new(0.3, radius * (2.6 + i), radius * (2.6 + i)), Transparency = 1})
		Debris:AddItem(ring, t + 0.05)
	end

	-- dust cloud, sparks, rocks
	burst(pos, {Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(150, 130, 110), Color3.fromRGB(90, 80, 75)),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9)}),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1)}),
		Lifetime = NumberRange.new(1, 1.8), Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(80, 80),
		EmissionDirection = Enum.NormalId.Top, Drag = 3, RotSpeed = NumberRange.new(-40, 40)}, 16, 3)
	burst(pos, {Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), color),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0)}), LightEmission = 1,
		Lifetime = NumberRange.new(0.4, 0.9), Speed = NumberRange.new(30, 60), SpreadAngle = Vector2.new(80, 80),
		Acceleration = Vector3.new(0, -60, 0), EmissionDirection = Enum.NormalId.Top}, 30, 1.5)
	chunks(pos, Color3.fromRGB(120, 100, 85), 9, 38)
	scorch(pos, radius * 0.9)

	Sounds.playAt("Explosion", pos)
	local d = distanceTo(pos)
	shakeFrom(pos, 0.9, 55)
	if d < radius * 2.5 then screenFlash(Color3.fromRGB(255, 180, 90), 0.35, 0.3) end
end

function Effects.lightning(pos)
	local color = Color3.fromRGB(255, 245, 140)
	-- main bolt from the sky + two small branches
	local function bolt(from, to, width, segments)
		local last = from
		for i = 1, segments do
			local nextPoint = from:Lerp(to, i / segments)
			if i < segments then nextPoint += Vector3.new(math.random(-5, 5), 0, math.random(-5, 5)) end
			local len = (nextPoint - last).Magnitude
			local seg = fxPart({Size = Vector3.new(width, width, len), CFrame = CFrame.lookAt((last + nextPoint) / 2, nextPoint), Color = color})
			tween(seg, 0.35, {Transparency = 1, Size = Vector3.new(0.15, 0.15, len)})
			Debris:AddItem(seg, 0.4)
			last = nextPoint
		end
	end
	local top = pos + Vector3.new(math.random(-6, 6), 90, math.random(-6, 6))
	bolt(top, pos, 1.3, 8)
	for i = 1, 2 do
		local from = top:Lerp(pos, 0.3 + math.random() * 0.3)
		bolt(from, from + Vector3.new(math.random(-14, 14), -math.random(10, 20), math.random(-14, 14)), 0.5, 3)
	end

	-- glowing cracks in the ground
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2 + math.random() * 0.5
		local len = 4 + math.random() * 4
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local crack = fxPart({Size = Vector3.new(0.35, 0.1, len), CFrame = CFrame.lookAt(pos + dir * len / 2 + Vector3.new(0, 0.12, 0), pos + dir * len + Vector3.new(0, 0.12, 0)), Color = color})
		tween(crack, 2.5, {Transparency = 1})
		Debris:AddItem(crack, 2.6)
	end
	local glow = fxPart({Shape = Enum.PartType.Ball, Size = Vector3.one * 4, Position = pos, Color = color})
	local light = Instance.new("PointLight"); light.Color = color; light.Range = 40; light.Brightness = 7; light.Parent = glow
	tween(glow, 0.4, {Size = Vector3.one * 12, Transparency = 1})
	Debris:AddItem(glow, 0.45)
	burst(pos, {Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.new(1, 1, 1), color),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0)}), LightEmission = 1,
		Lifetime = NumberRange.new(0.3, 0.7), Speed = NumberRange.new(25, 50), SpreadAngle = Vector2.new(90, 90),
		Acceleration = Vector3.new(0, -40, 0), EmissionDirection = Enum.NormalId.Top}, 35, 1.2)
	chunks(pos, Color3.fromRGB(90, 85, 80), 5, 28)
	scorch(pos, 4.5, Color3.fromRGB(25, 25, 30))

	Sounds.playAt("Thunder", pos, {duration = 3, volume = 0.7})
	shakeFrom(pos, 0.8, 50)
	if distanceTo(pos) < 60 then screenFlash(Color3.new(1, 1, 1), 0.5, 0.35) end
end

function Effects.poof(pos)
	burst(pos, {Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(210, 200, 255)),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5)}),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1)}),
		Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(180, 180)}, 18, 1.2)
	Sounds.playAt("Pop", pos, {volume = 0.5, duration = 1.5})
end

-- we lost a life: red edge, shake, little bounce
function Effects.hurt(livesLeft)
	stroke.Thickness = 60
	stroke.Transparency = 0.1
	tween(stroke, 0.8, {Thickness = 0, Transparency = 1})
	screenFlash(Color3.fromRGB(255, 40, 40), 0.25, 0.4)
	addTrauma(0.7)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then root.AssemblyLinearVelocity += Vector3.new(0, 35, 0) end
	Sounds.playUI("Pop")
end

-- our shield blocked a hit
function Effects.shieldBlock()
	screenFlash(Color3.fromRGB(90, 190, 255), 0.35, 0.4)
	addTrauma(0.35)
	Sounds.playUI("Sweep")
end

function Effects.shake(strength, duration)
	addTrauma(math.clamp((strength or 1) * 0.6, 0, 1))
end

-- weapon projectile flying from a survivor to a ghost (or into the sky on a miss)
local PROJECTILE = {
	slingshot = {size = Vector3.new(0.7, 0.7, 0.7), shape = Enum.PartType.Ball, material = Enum.Material.Slate, color = Color3.fromRGB(120, 110, 100)},
	bow = {size = Vector3.new(0.18, 0.18, 3), material = Enum.Material.Wood},
	crossbow = {size = Vector3.new(0.2, 0.2, 2.4), material = Enum.Material.Metal},
	blaster = {size = Vector3.new(0.5, 0.5, 3.2), material = Enum.Material.Neon},
}
function Effects.shot(from, to, weapon, color, travel, hit)
	local look = (to - from).Magnitude > 0.1 and CFrame.lookAt(from, to) or CFrame.new(from)
	local style = PROJECTILE[weapon] or PROJECTILE.slingshot
	local p = fxPart({Size = style.size, CFrame = look, Material = style.material, Color = style.color or color})
	if style.shape then p.Shape = style.shape end
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.15, 0); a0.Parent = p
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.15, 0); a1.Parent = p
	local trail = Instance.new("Trail"); trail.Attachment0 = a0; trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color); trail.LightEmission = 1; trail.Lifetime = 0.25
	trail.Transparency = NumberSequence.new(0.2, 1); trail.FaceCamera = true; trail.Parent = p
	Sounds.playAt("Whoosh", from, {volume = 0.35, speed = 1.5 + math.random() * 0.3, range = 90, duration = 1.5})
	tween(p, travel, {CFrame = CFrame.lookAt(to, to + look.LookVector)}, Enum.EasingStyle.Linear)
	task.delay(travel, function()
		p:Destroy()
		if hit then
			burst(to, {Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), color),
				Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0)}), LightEmission = 1,
				Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(14, 28), SpreadAngle = Vector2.new(180, 180)}, 22, 1)
			local ring = fxPart({Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Position = to, Color = Color3.fromRGB(255, 230, 60), Transparency = 0.2})
			tween(ring, 0.3, {Size = Vector3.one * 8, Transparency = 1})
			Debris:AddItem(ring, 0.35)
			Sounds.playAt("Pop", to, {volume = 0.8, speed = 1.3, range = 150, duration = 1.5})
		end
	end)
end

-- we are a ghost and just got stunned
function Effects.stunned(duration, byName)
	screenFlash(Color3.fromRGB(255, 230, 60), 0.4, 0.5)
	addTrauma(0.5)
	Sounds.playUI("Tick")
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
