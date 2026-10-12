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
	Sounds.playUI(math.random() < 0.5 and "Ouch" or "Grunt")
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

-- weapon projectile flying from a survivor to a ghost (or away on a miss)
local ShopItems = require(ReplicatedStorage:WaitForChild("ShopItems"))
local PROJECTILE = {
	slingshot = {size = Vector3.new(0.8, 0.8, 0.8), shape = Enum.PartType.Ball, material = Enum.Material.Slate, color = Color3.fromRGB(120, 110, 100), sound = {"Swing", 1.7}},
	bow = {size = Vector3.new(0.18, 0.18, 3), material = Enum.Material.Wood, sound = {"Swing", 2.1}},
	crossbow = {size = Vector3.new(0.22, 0.22, 2.4), material = Enum.Material.Metal, sound = {"Click", 0.7}},
	boomerang = {size = Vector3.new(2.2, 0.3, 2.2), material = Enum.Material.SmoothPlastic, spin = true, sound = {"Whoosh", 1.1}},
	blaster = {size = Vector3.new(0.6, 0.6, 3.6), material = Enum.Material.Neon, sound = {"Sweep", 1.8}},
	rocket = {size = Vector3.new(0.9, 0.9, 2.6), material = Enum.Material.Metal, color = Color3.fromRGB(230, 230, 240), smoke = true, sound = {"Whoosh", 0.6}},
}

-- hit marker for the shooter: a quick X in the screen center + pop
local hitGui = Instance.new("ScreenGui")
hitGui.Name = "HitMarker"; hitGui.ResetOnSpawn = false; hitGui.IgnoreGuiInset = true; hitGui.DisplayOrder = 40
hitGui.Parent = player:WaitForChild("PlayerGui")
local function hitMarker()
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5); holder.Position = UDim2.new(0.5, 0, 0.5, 0); holder.Size = UDim2.fromOffset(46, 46)
	holder.BackgroundTransparency = 1; holder.Rotation = 45; holder.Parent = hitGui
	for _, size in {UDim2.fromOffset(46, 7), UDim2.fromOffset(7, 46)} do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5); bar.Position = UDim2.new(0.5, 0, 0.5, 0); bar.Size = size
		bar.BackgroundColor3 = Color3.fromRGB(255, 235, 80); bar.BorderSizePixel = 0
		local st = Instance.new("UIStroke", bar); st.Thickness = 2; st.Color = Color3.fromRGB(20, 20, 30)
		bar.Parent = holder
	end
	local sc = Instance.new("UIScale", holder); sc.Scale = 1.6
	tween(sc, 0.15, {Scale = 1})
	task.delay(0.35, function() holder:Destroy() end)
	Sounds.playUI("Pop")
end

local function lightningSegments(from, to, color, width)
	local segments = 6
	local last = from
	for i = 1, segments do
		local nextPoint = from:Lerp(to, i / segments)
		if i < segments then nextPoint += Vector3.new(math.random(-2, 2), math.random(-2, 2), math.random(-2, 2)) end
		local len = (nextPoint - last).Magnitude
		local seg = fxPart({Size = Vector3.new(width, width, len), CFrame = CFrame.lookAt((last + nextPoint) / 2, nextPoint), Color = color})
		tween(seg, 0.25, {Transparency = 1})
		Debris:AddItem(seg, 0.3)
		last = nextPoint
	end
end

function Effects.shot(from, to, weapon, color, travel, hit, shooterId)
	local item = ShopItems.byId[weapon]
	local mine = shooterId == player.UserId
	if weapon == "staff" then
		-- instant lightning bolt
		lightningSegments(from, to, Color3.fromRGB(255, 250, 200), 0.5)
		lightningSegments(from, to, color, 0.25)
		Sounds.playAt("Thunder", from, {volume = 0.35, speed = 2.2, range = 120, duration = 1})
		if hit then
			burst(to, {Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.new(1, 1, 1), color),
				Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0)}), LightEmission = 1,
				Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(14, 26), SpreadAngle = Vector2.new(180, 180)}, 20, 0.8)
			if mine then hitMarker() end
		end
		if mine then addTrauma(0.2) end
		return
	end
	local style = PROJECTILE[weapon] or PROJECTILE.slingshot
	local look = (to - from).Magnitude > 0.1 and CFrame.lookAt(from, to) or CFrame.new(from)
	local p = fxPart({Size = style.size, CFrame = look, Material = style.material, Color = style.color or color})
	if style.shape then p.Shape = style.shape end
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.15, 0); a0.Parent = p
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.15, 0); a1.Parent = p
	local trail = Instance.new("Trail"); trail.Attachment0 = a0; trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color); trail.LightEmission = 1; trail.Lifetime = 0.25
	trail.Transparency = NumberSequence.new(0.2, 1); trail.FaceCamera = true; trail.Parent = p
	if style.smoke then
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/smoke_main.dds"; pe.Color = ColorSequence.new(Color3.fromRGB(220, 220, 220))
		pe.Size = NumberSequence.new(0.8, 2.4); pe.Transparency = NumberSequence.new(0.3, 1); pe.Lifetime = NumberRange.new(0.5, 0.8)
		pe.Rate = 60; pe.Speed = NumberRange.new(1); pe.Parent = a0
		local fire = Instance.new("Fire"); fire.Size = 2; fire.Heat = 0; fire.Parent = p
	end
	Sounds.playAt(style.sound[1], from, {volume = 0.45, speed = style.sound[2] + math.random() * 0.15, range = 90, duration = 1.5})
	if mine then addTrauma(weapon == "rocket" and 0.35 or 0.12) end

	-- fly along an arc (heavier shots drop more), the boomerang spins and comes back
	local arc = (item and item.arc or 0) * (to - from).Magnitude * 0.25
	local start = os.clock()
	local returnStart
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - start) / math.max(travel, 0.01)
		if style.spin then
			if t <= 1 then
				p.CFrame = CFrame.new(from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * 3, 0)) * CFrame.Angles(0, os.clock() * 25, 0)
			else
				-- come back to the thrower
				local back = math.clamp(t - 1, 0, 1)
				local char = player.Character
				p.CFrame = CFrame.new(to:Lerp(from, back)) * CFrame.Angles(0, os.clock() * 25, 0)
				if back >= 1 then conn:Disconnect(); p:Destroy() end
			end
			return
		end
		local tc = math.clamp(t, 0, 1)
		local pos = from:Lerp(to, tc) + Vector3.new(0, arc * 4 * tc * (1 - tc), 0) -- parabola
		local nextPos = from:Lerp(to, math.min(1, tc + 0.02)) + Vector3.new(0, arc * 4 * (tc + 0.02) * (1 - tc - 0.02), 0)
		p.CFrame = (nextPos - pos).Magnitude > 0.01 and CFrame.lookAt(pos, nextPos) or CFrame.new(pos)
		if t >= 1 then
			conn:Disconnect()
			p:Destroy()
			if hit then
				burst(to, {Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), color),
					Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0)}), LightEmission = 1,
					Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(14, 28), SpreadAngle = Vector2.new(180, 180)}, 22, 1)
				local ring = fxPart({Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Position = to, Color = Color3.fromRGB(255, 230, 60), Transparency = 0.2})
				tween(ring, 0.3, {Size = Vector3.one * 8, Transparency = 1})
				Debris:AddItem(ring, 0.35)
				Sounds.playAt("Pop", to, {volume = 0.8, speed = 1.3, range = 150, duration = 1.5})
				if mine then hitMarker() end
			end
		end
	end)
	if style.spin and hit and mine then task.delay(travel * 0.5, hitMarker) end
end

-- big celebration in the middle of the screen (level up, rebirth, prestige)
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local celebrateGui = Instance.new("ScreenGui")
celebrateGui.Name = "Celebrate"; celebrateGui.ResetOnSpawn = false; celebrateGui.DisplayOrder = 30
UIKit.autoScale(celebrateGui)
celebrateGui.Parent = player:WaitForChild("PlayerGui")
function Effects.celebrate(title, icon, subtitle)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5); holder.Position = UDim2.new(0.5, 0, 0.38, 0); holder.Size = UDim2.fromOffset(520, 200)
	holder.BackgroundTransparency = 1; holder.Parent = celebrateGui
	local rays = UIKit.icon(holder, "star", {size = UDim2.fromOffset(150, 150), anchor = Vector2.new(0.5, 0.5), position = UDim2.new(0.5, 0, 0, 40)})
	rays.ImageTransparency = 0.6; rays.ZIndex = 0
	if rays:IsA("ImageLabel") then
		rays.Size = UDim2.fromOffset(190, 190)
		tween(rays, 3, {Rotation = 180})
	end
	UIKit.icon(holder, icon or "star", {size = UDim2.fromOffset(110, 110), anchor = Vector2.new(0.5, 0.5), position = UDim2.new(0.5, 0, 0, 40)})
	local t = UIKit.text(holder, title, {max = 64, stroke = 5, color = Color3.fromRGB(255, 225, 80), size = UDim2.new(1, 0, 0, 70), position = UDim2.new(0, 0, 0, 96)})
	if subtitle then
		UIKit.text(holder, subtitle, {max = 30, stroke = 3, color = Color3.fromRGB(170, 255, 140), size = UDim2.new(1, 0, 0, 34), position = UDim2.new(0, 0, 0, 162)})
	end
	local sc = Instance.new("UIScale", holder); sc.Scale = 0.2
	tween(sc, 0.45, {Scale = 1}, Enum.EasingStyle.Back)
	Sounds.playUI("Win", 3)
	screenFlash(Color3.fromRGB(255, 230, 120), 0.3, 0.6)
	task.delay(2.8, function()
		tween(sc, 0.3, {Scale = 0}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.32)
		holder:Destroy()
	end)
	-- sparkles around the character
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		burst(root.Position, {Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 160, 40)),
			Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0)}), LightEmission = 1,
			Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -20, 0)}, 60, 2)
	end
end

-- we knocked someone out: punchy text in the middle of the screen
function Effects.koPopup(count)
	local label = UIKit.text(celebrateGui, count > 1 and ("KNOCKOUT x" .. count .. "!") or "KNOCKOUT!", {max = 54, stroke = 5,
		color = Color3.fromRGB(255, 120, 80), size = UDim2.new(0, 520, 0, 64), position = UDim2.new(0.5, 0, 0.3, 0)})
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Rotation = -6
	local sc = Instance.new("UIScale", label); sc.Scale = 2
	tween(sc, 0.25, {Scale = 1}, Enum.EasingStyle.Back)
	Sounds.playUI("Stinger")
	addTrauma(0.3)
	task.delay(1.1, function()
		tween(label, 0.3, {TextTransparency = 1})
		local st = label:FindFirstChildOfClass("UIStroke")
		if st then tween(st, 0.3, {Transparency = 1}) end
		task.wait(0.32)
		label:Destroy()
	end)
end

-- we drank something: colored bubbles + gulp
function Effects.drink(color)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		burst(root.Position + Vector3.new(0, 1, 0), {Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.new(1, 1, 1), color),
			Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0)}), LightEmission = 1,
			Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top}, 30, 1.5)
	end
	screenFlash(color, 0.2, 0.4)
	Sounds.playUI("Pop")
end

-- ghost power: wind gust (swirling rings + dust blown outwards)
function Effects.gust(pos, radius)
	for i = 1, 3 do
		local ring = fxPart({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3, 3), Material = Enum.Material.ForceField,
			CFrame = CFrame.new(pos + Vector3.new(0, 1 + i * 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(230, 250, 255), Transparency = 0.1})
		tween(ring, 0.45 + i * 0.1, {Size = Vector3.new(0.4, radius * 2.4, radius * 2.4), Transparency = 1})
		Debris:AddItem(ring, 0.8)
	end
	burst(pos, {Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(240, 250, 255)),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4)}),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1)}),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(35, 55), SpreadAngle = Vector2.new(5, 180),
		EmissionDirection = Enum.NormalId.Top, Drag = 4}, 30, 1.5)
	Sounds.playAt("Whoosh", pos, {volume = 0.8, speed = 0.7, range = 160, duration = 2})
	shakeFrom(pos, 0.4, 35)
end

-- ghost power: freeze bomb (icy burst)
function Effects.freeze(pos, radius)
	local ball = fxPart({Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Position = pos, Color = Color3.fromRGB(200, 240, 255), Transparency = 0.1})
	tween(ball, 0.35, {Size = Vector3.one * radius * 2.2, Transparency = 1})
	Debris:AddItem(ball, 0.4)
	burst(pos, {Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 220, 255)),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0)}), LightEmission = 1,
		Lifetime = NumberRange.new(0.5, 1), Speed = NumberRange.new(15, 35), SpreadAngle = Vector2.new(90, 90),
		Acceleration = Vector3.new(0, -30, 0), EmissionDirection = Enum.NormalId.Top}, 40, 1.5)
	-- frost patch on the ground
	scorch(pos, radius * 0.9, Color3.fromRGB(190, 235, 255))
	Sounds.playAt("Pop", pos, {volume = 0.8, speed = 0.6, range = 150, duration = 2})
	shakeFrom(pos, 0.35, 30)
end

-- Fall Guys shove: little impact puff (blocked = shield flash)
function Effects.shove(pos, blocked)
	local ring = fxPart({Shape = Enum.PartType.Ball, Size = Vector3.one * 1.5, Position = pos,
		Color = blocked and Color3.fromRGB(90, 190, 255) or Color3.fromRGB(255, 240, 200), Transparency = 0.2})
	tween(ring, 0.25, {Size = Vector3.one * 7, Transparency = 1})
	Debris:AddItem(ring, 0.3)
	burst(pos, {Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(Color3.fromRGB(255, 230, 120)),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0)}), LightEmission = 1,
		Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(14, 24), SpreadAngle = Vector2.new(180, 180)}, 14, 0.8)
	Sounds.playAt("Pop", pos, {volume = 0.7, speed = 0.8 + math.random() * 0.2, range = 90, duration = 1.5})
	if distanceTo(pos) < 6 then addTrauma(0.45) end
end

-- melee swing: whoosh (heavier weapons sound deeper)
local SWING_PITCH = {melee_fists = 1.35, melee_bat = 1.1, melee_pan = 1.1, melee_sword = 1.25, melee_hammer = 0.85,
	melee_blade = 1.4, melee_scythe = 0.9, melee_banhammer = 0.7}
function Effects.swing(pos, itemId)
	Sounds.playAt("Swing", pos, {speed = (SWING_PITCH[itemId] or 1.1) + math.random() * 0.1, range = 80, duration = 1.2})
end

-- something hit a survivor (melee or shot): impact sound + voice + stars. attackerId = who gets the hit marker.
local IMPACT = {
	melee_bat = {"Bat", 1.15}, melee_hammer = {"Bat", 0.85}, melee_pan = {"Bonk", 1.7},
	melee_banhammer = {"Explosion", 0.7}, rocket = {"Bonk", 0.8},
}
function Effects.smack(pos, itemId, blocked, attackerId)
	if blocked then
		Effects.shove(pos, true)
		return
	end
	local snd = IMPACT[itemId] or {"Bonk", 1.2}
	Sounds.playAt(snd[1], pos, {speed = snd[2] + math.random() * 0.1, range = 120, duration = 1.5,
		volume = snd[1] == "Explosion" and 0.5 or nil})
	Sounds.playAt(math.random() < 0.5 and "Ouch" or "Grunt", pos, {speed = 0.9 + math.random() * 0.3, range = 90, duration = 1.2})
	-- cartoon impact: white flash ball + yellow stars
	local ring = fxPart({Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2, Position = pos, Color = Color3.new(1, 1, 1), Transparency = 0.1})
	tween(ring, 0.18, {Size = Vector3.one * 6, Transparency = 1})
	Debris:AddItem(ring, 0.25)
	burst(pos + Vector3.new(0, 1, 0), {Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 250, 180), Color3.fromRGB(255, 190, 40)),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)}), LightEmission = 1,
		Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(16, 30), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -25, 0)}, 18, 0.9)
	if attackerId == player.UserId then
		hitMarker()
		addTrauma(0.25)
	end
	if distanceTo(pos) < 3 then addTrauma(0.6) end
end

-- ghost power: grave hands rise out of the floor, grab and sink back
function Effects.hands(pos, radius)
	local purple = Color3.fromRGB(150, 80, 230)
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2 + math.random() * 0.4
		local r = radius * (0.35 + math.random() * 0.5)
		local base = pos + Vector3.new(math.cos(a) * r, -4.5, math.sin(a) * r)
		local hand = Instance.new("Model")
		local arm = fxPart({Size = Vector3.new(1.5, 5, 1.5), CFrame = CFrame.new(base) * CFrame.Angles(0, -a, math.rad(math.random(-15, 15))),
			Color = purple, Material = Enum.Material.Neon, Transparency = 0.15})
		arm.Parent = hand
		hand.PrimaryPart = arm
		for f = -1, 1 do
			local finger = fxPart({Size = Vector3.new(0.45, 1.9, 0.45), CFrame = arm.CFrame * CFrame.new(f * 0.5, 3.2, 0) * CFrame.Angles(0, 0, math.rad(f * 18)),
				Color = purple, Material = Enum.Material.Neon, Transparency = 0.15})
			finger.Parent = hand
		end
		hand.Parent = workspace
		local start = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			-- up fast, grab, slowly sink again
			local up = t < 0.25 and (t / 0.25) or (t < 0.9 and 1 or math.max(0, 1 - (t - 0.9) / 0.5))
			hand:PivotTo(CFrame.new(base + Vector3.new(0, up * 5.6, 0)) * CFrame.Angles(0, -a, 0))
			if t > 1.4 then conn:Disconnect(); hand:Destroy() end
		end)
	end
	burst(pos, {Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(Color3.fromRGB(120, 60, 180)),
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5)}),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1)}),
		Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(180, 30)}, 20, 1.5)
	Sounds.playAt("GhostWind", pos, {volume = 0.6, speed = 1.6, range = 120, duration = 1.6})
	shakeFrom(pos, 0.35, 30)
end

-- ban hammer / scythe: shockwave ring on the floor
function Effects.shockwave(pos, radius, color)
	local ring = fxPart({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2, 2), Material = Enum.Material.Neon,
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color = color or Color3.new(1, 1, 1), Transparency = 0.2})
	tween(ring, 0.35, {Size = Vector3.new(0.4, radius * 2.4, radius * 2.4), Transparency = 1})
	Debris:AddItem(ring, 0.4)
	shakeFrom(pos, 0.5, 30)
end

function Effects.grab(pos)
	Sounds.playAt("Click", pos, {volume = 0.6, speed = 0.8, range = 60, duration = 1})
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
