-- Melee (R / HIT button): every survivor carries a melee weapon in the left hand (fists = boxing gloves).
-- A swing smacks every survivor in a cone in front of you: they ragdoll away (no life lost,
-- but the arena edge, holes and hazards are close...). Server checks cooldown, range and target.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Config)
local ShopItems = require(ReplicatedStorage.ShopItems)
local PlayerData = require(script.Parent.PlayerData)
local Util = require(script.Parent.Util)
local Damage = require(script.Parent.Damage)
local Heroes = require(ReplicatedStorage.Heroes)

local Melee = {}

local lastSwing = {} -- entity -> os.clock()

---------------------------------------------------------------- models
-- Built in "hand space": the grip is at the origin, the weapon points forward (-Z) and a bit up.

local function piece(model, size, color, cf, props)
	local p = Instance.new("Part")
	p.Size = size; p.Color = color; p.Material = Enum.Material.SmoothPlastic; p.CFrame = cf
	p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.Massless = true; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props or {} do p[k] = v end
	p.Parent = model
	return p
end

local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal

-- shaft along -Z from the grip: CFrame for a part centered `dist` studs forward
local function fwd(dist) return CFrame.new(0, 0, -dist) end
-- cylinder lying along Z
local function alongZ(dist) return fwd(dist) * CFrame.Angles(0, math.rad(90), 0) end

local BUILD = {}
function BUILD.melee_bat(m, item)
	piece(m, Vector3.new(1.6, 0.4, 0.4), item.colors[2], alongZ(0.4), {Shape = CYL})
	piece(m, Vector3.new(2.8, 0.75, 0.75), item.colors[1], alongZ(2.4), {Shape = CYL})
	piece(m, Vector3.new(0.8, 0.8, 0.8), item.colors[1], fwd(3.8), {Shape = BALL})
end
function BUILD.melee_pan(m, item)
	piece(m, Vector3.new(1.8, 0.3, 0.3), Color3.fromRGB(60, 40, 30), alongZ(0.6), {Shape = CYL, Material = Enum.Material.Wood})
	piece(m, Vector3.new(0.25, 2.4, 2.4), item.colors[2], fwd(2.6) * CFrame.Angles(0, 0, math.rad(90)), {Shape = CYL, Material = METAL})
	piece(m, Vector3.new(0.3, 2.1, 2.1), item.colors[1], fwd(2.6) * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), {Shape = CYL, Material = METAL})
end
function BUILD.melee_sword(m, item)
	piece(m, Vector3.new(0.3, 0.3, 1), Color3.fromRGB(90, 60, 40), fwd(0.2))
	piece(m, Vector3.new(1.6, 0.25, 0.3), Color3.fromRGB(230, 190, 70), fwd(0.8), {Material = METAL})
	piece(m, Vector3.new(0.4, 0.12, 3.6), item.colors[1], fwd(2.7), {Material = METAL, Reflectance = 0.3})
	piece(m, Vector3.new(0.12, 0.13, 3.4), item.colors[2], fwd(2.6), {Material = NEON})
end
function BUILD.melee_hammer(m, item)
	piece(m, Vector3.new(3, 0.35, 0.35), Color3.fromRGB(250, 230, 120), alongZ(1.3), {Shape = CYL})
	piece(m, Vector3.new(2.4, 1.4, 1.4), item.colors[1], fwd(3) * CFrame.Angles(0, 0, math.rad(90)), {Shape = CYL})
	piece(m, Vector3.new(2.5, 1.1, 1.1), item.colors[2], fwd(3) * CFrame.Angles(0, 0, math.rad(90)), {Shape = CYL, Material = NEON})
end
function BUILD.melee_blade(m, item)
	piece(m, Vector3.new(0.3, 0.3, 1), Color3.fromRGB(40, 40, 50), fwd(0.2), {Material = METAL})
	piece(m, Vector3.new(0.9, 0.2, 0.25), Color3.fromRGB(80, 80, 100), fwd(0.75), {Material = METAL})
	local blade = piece(m, Vector3.new(0.22, 0.22, 4.2), item.colors[1], fwd(2.95), {Material = NEON})
	local l = Instance.new("PointLight"); l.Color = item.colors[1]; l.Range = 9; l.Brightness = 2; l.Parent = blade
end
function BUILD.melee_scythe(m, item)
	piece(m, Vector3.new(4.6, 0.3, 0.3), Color3.fromRGB(50, 35, 30), alongZ(1.8), {Shape = CYL, Material = Enum.Material.Wood})
	for i = 0, 4 do
		local a = math.rad(i * 16)
		piece(m, Vector3.new(0.15, 0.5 - i * 0.06, 0.9), item.colors[1],
			fwd(3.9) * CFrame.Angles(a, 0, 0) * CFrame.new(0, 0.2 + i * 0.75, -0.25), {Material = METAL, Reflectance = 0.2})
	end
	piece(m, Vector3.new(0.4, 0.4, 0.4), item.colors[2], fwd(4.1), {Shape = BALL, Material = NEON})
end
function BUILD.melee_banhammer(m, item)
	piece(m, Vector3.new(3.4, 0.4, 0.4), Color3.fromRGB(40, 40, 50), alongZ(1.5), {Shape = CYL, Material = METAL})
	piece(m, Vector3.new(1.6, 1.6, 3), item.colors[2], fwd(3.4), {Material = METAL})
	piece(m, Vector3.new(1.7, 1.7, 0.4), item.colors[1], fwd(3.4) * CFrame.new(0, 0, 1.3), {Material = NEON})
	piece(m, Vector3.new(1.7, 1.7, 0.4), item.colors[1], fwd(3.4) * CFrame.new(0, 0, -1.3), {Material = NEON})
	local sp = Instance.new("Sparkles"); sp.SparkleColor = item.colors[1]; sp.Parent = m:GetChildren()[2]
end

function BUILD.melee_chaos(m, item)
	piece(m, Vector3.new(0.3, 0.3, 1), Color3.fromRGB(30, 30, 40), fwd(0.2), {Material = METAL})
	piece(m, Vector3.new(1.2, 0.25, 0.3), item.colors[2], fwd(0.8), {Material = NEON})
	local blade = piece(m, Vector3.new(0.28, 0.28, 4.8), item.colors[1], fwd(3.3), {Material = NEON})
	piece(m, Vector3.new(0.12, 0.3, 4.6), item.colors[2], fwd(3.2), {Material = NEON})
	local l = Instance.new("PointLight"); l.Color = item.colors[1]; l.Range = 10; l.Brightness = 2.5; l.Parent = blade
	local sp = Instance.new("Sparkles"); sp.SparkleColor = item.colors[2]; sp.Parent = blade
end

-- boxing gloves on both hands
local function gloves(char, item)
	for _, side in {"LeftHand", "RightHand"} do
		local hand = char:FindFirstChild(side)
		if hand then
			local g = Instance.new("Part")
			g.Name = "MeleeGlove"; g.Shape = BALL; g.Size = Vector3.new(1.05, 1.05, 1.05)
			g.Color = item.colors[2]; g.Material = Enum.Material.SmoothPlastic
			g.CanCollide = false; g.CanQuery = false; g.CanTouch = false; g.Massless = true; g.CastShadow = false
			g.CFrame = hand.CFrame * CFrame.new(0, -0.15, 0)
			local w = Instance.new("WeldConstraint"); w.Part0 = hand; w.Part1 = g; w.Parent = g
			g.Parent = char
		end
	end
end

local function itemOf(entity)
	if not entity:IsA("Player") then
		return ShopItems.byId[entity:GetAttribute("Melee") or ShopItems.DEFAULT_MELEE]
	end
	local data = PlayerData.get(entity)
	local id = data and data.Equipped.Melee
	local item = ShopItems.byId[id or ""]
	if not item or item.slot ~= "Melee" or not data.Owned[item.id] then
		item = ShopItems.byId[ShopItems.DEFAULT_MELEE]
	end
	return item
end
Melee.itemOf = itemOf

function Melee.remove(char)
	if not char then return end
	for _, c in char:GetChildren() do
		if c.Name == "MeleeWeapon" or c.Name == "MeleeGlove" then c:Destroy() end
	end
end

-- Put the equipped melee weapon on the character (round start)
function Melee.give(entity)
	local char = Util.charOf(entity)
	local hand = char and char:FindFirstChild("LeftHand")
	if not hand then return end
	Melee.remove(char)
	local item = itemOf(entity)
	char:SetAttribute("MeleeItem", item.id)
	if item.id == "melee_fists" then
		gloves(char, item)
		return
	end
	local model = Instance.new("Model"); model.Name = "MeleeWeapon"
	BUILD[item.id](model, item)
	-- move the hand-space model onto the hand: grip a bit below the palm, tilted up
	local grip = hand.CFrame * CFrame.new(0, -0.25, 0) * CFrame.Angles(math.rad(40), 0, 0)
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.CFrame = grip * p.CFrame
			local w = Instance.new("WeldConstraint"); w.Part0 = hand; w.Part1 = p; w.Parent = p
		end
	end
	model.Parent = char
end

---------------------------------------------------------------- swing

-- the left shoulder joint and the property that poses it:
-- new avatar joints -> the AnimationConstraint's torso attachment, classic rigs -> Motor6D.C0
local function shoulderOf(char)
	local torso = char:FindFirstChild("UpperTorso")
	local m = torso and torso:FindFirstChild("LeftShoulder")
	if m and m:IsA("Motor6D") then return m, "C0" end
	local arm = char:FindFirstChild("LeftUpperArm")
	local ac = arm and arm:FindFirstChild("LeftShoulder")
	if ac and ac:IsA("AnimationConstraint") and ac.Attachment0 then return ac.Attachment0, "CFrame" end
	return nil
end

-- arm animation on the server (replicates to everyone): wind up, smash, back
local function animate(char, item)
	local shoulder, prop = shoulderOf(char)
	if not shoulder then return end
	local base = shoulder:GetAttribute("BaseC0") or shoulder[prop]
	shoulder:SetAttribute("BaseC0", base)
	local punch = item.id == "melee_fists"
	local spin = item.arc < 0
	local windup, hit
	if punch then
		windup = base * CFrame.Angles(math.rad(30), 0, 0)
		hit = base * CFrame.Angles(math.rad(95), math.rad(-20), 0)
	elseif spin then
		windup = base * CFrame.Angles(math.rad(80), math.rad(70), 0)
		hit = base * CFrame.Angles(math.rad(80), math.rad(-80), 0)
	else
		windup = base * CFrame.Angles(math.rad(170), 0, 0)
		hit = base * CFrame.Angles(math.rad(40), 0, 0)
	end
	local up = TweenService:Create(shoulder, TweenInfo.new(punch and 0.06 or 0.1, Enum.EasingStyle.Quad), {[prop] = windup})
	up:Play()
	task.delay(punch and 0.06 or 0.1, function()
		if not shoulder.Parent then return end
		TweenService:Create(shoulder, TweenInfo.new(punch and 0.07 or 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {[prop] = hit}):Play()
		task.delay(0.18, function()
			if shoulder.Parent then
				TweenService:Create(shoulder, TweenInfo.new(0.22, Enum.EasingStyle.Back), {[prop] = base}):Play()
			end
		end)
	end)
	return (punch and 0.12 or 0.2)
end

-- `attacker` swings at everything in `candidates` (survivors of the same round). Returns hit count or nil.
function Melee.swing(ctx, attacker, candidates)
	local char = Util.charOf(attacker)
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 or char:GetAttribute("Ragdolled") then return nil end
	local item = itemOf(attacker)
	local stats = Heroes.stats(attacker)
	local force = item.force * Heroes.mult(stats, "meleeForce")
	local now = os.clock()
	if lastSwing[attacker] and now - lastSwing[attacker] < item.cooldown * Heroes.mult(stats, "meleeCooldown") - 0.1 then return nil end
	lastSwing[attacker] = now

	local delayTime = animate(char, item) or 0.15
	ctx.effect("swing", root.Position, item.id)
	task.delay(delayTime, function()
		if not ctx.isRunning() or not root.Parent then return end
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local count = 0
		for _, e in candidates do
			if e ~= attacker and e.Parent and not Util.sameTeam(attacker, e) then
				local tchar = Util.charOf(e)
				local troot = tchar and tchar:FindFirstChild("HumanoidRootPart")
				if troot then
					local d = troot.Position - root.Position
					local flat = Vector3.new(d.X, 0, d.Z)
					if flat.Magnitude <= item.range and math.abs(d.Y) < 6
						and (flat.Magnitude < 1.5 or item.arc < 0 or look:Dot(flat.Unit) >= item.arc) then
						count += 1
						local dir = flat.Magnitude > 0.1 and flat.Unit or look
						if (e:GetAttribute("ShieldUntil") or 0) > workspace:GetServerTimeNow() then
							ctx.effect("smack", troot.Position, item.id, true)
							if e:GetAttribute("ShieldBurn") then
								Util.knockback(attacker, -dir * 45 + Vector3.new(0, 22, 0), true)
							end
						else
							Damage.markHit(e, attacker)
							Util.knockback(e, dir * force + Vector3.new(0, item.lift, 0), true)
							ctx.effect("smack", troot.Position, item.id, false, attacker:IsA("Player") and attacker.UserId or 0)
							if attacker:IsA("Player") then PlayerData.quest(attacker, "shoves") end
						end
					end
				end
			end
		end
		-- the ban hammer / scythe also leave a shockwave
		if item.arc < 0 then ctx.effect("shockwave", root.Position - Vector3.new(0, 2.5, 0), item.range, item.colors[1]) end
	end)
	return true
end

Players.PlayerRemoving:Connect(function(p) lastSwing[p] = nil end)

return Melee
