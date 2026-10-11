-- Bots fill small groups: they run around, dodge hazards and come back as ghosts when they die.
-- A bot is a character Model with the attribute IsBot (no Player object), so hazards and the
-- Damage module treat it like a player. Bots never get coins, wins or saved data.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Meteor = require(script.Parent.Meteor)
local Util = require(script.Parent.Util)

local Bots = {}

local NAMES = {"Blaze", "Nova", "Pixel", "Rocket", "Ziggy", "Turbo", "Luna", "Comet", "Echo", "Fizz", "Jinx", "Koda",
	"Mango", "Nugget", "Ollie", "Pebble", "Quake", "Rex", "Sparky", "Taco", "Waffles", "Yeti", "Zappy", "Bubbles"}
local SKIN = {Color3.fromRGB(255, 205, 160), Color3.fromRGB(234, 184, 146), Color3.fromRGB(196, 140, 100),
	Color3.fromRGB(140, 95, 65), Color3.fromRGB(255, 220, 70)}
local SHIRTS = {Color3.fromRGB(255, 80, 80), Color3.fromRGB(70, 150, 255), Color3.fromRGB(90, 220, 110),
	Color3.fromRGB(255, 170, 40), Color3.fromRGB(190, 100, 255), Color3.fromRGB(255, 120, 200), Color3.fromRGB(40, 200, 200)}
local PANTS = {Color3.fromRGB(40, 50, 90), Color3.fromRGB(50, 50, 55), Color3.fromRGB(110, 80, 50), Color3.fromRGB(230, 230, 235)}
local GHOST_COLORS = {Color3.fromRGB(170, 120, 255), Color3.fromRGB(255, 90, 90), Color3.fromRGB(90, 255, 120), Color3.fromRGB(90, 200, 255)}

-- default R15 animations (Roblox-owned)
local ANIMS = {idle = "rbxassetid://507766388", run = "rbxassetid://507767714", jump = "rbxassetid://507765000", fall = "rbxassetid://507767968"}

local function pick(t) return t[math.random(#t)] end

-- One profile per bot for the whole match: name, look and skill stay the same every round
function Bots.makeProfiles(count)
	local names = table.clone(NAMES)
	local list = {}
	for _ = 1, count do
		local name = table.remove(names, math.random(#names))
		table.insert(list, {
			name = name,
			skin = pick(SKIN), shirt = pick(SHIRTS), pants = pick(PANTS), ghostColor = pick(GHOST_COLORS),
			reaction = 0.2 + math.random() * 0.3, -- seconds until a bot notices danger
			jumpSkill = 0.7 + math.random() * 0.25, -- chance to jump the laser in time
			aim = 2 + math.random() * 4, -- ghost bot meteor spread in studs
		})
	end
	return list
end

local function buildRig(profile)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = profile.skin; desc.LeftArmColor = profile.skin; desc.RightArmColor = profile.skin
	desc.TorsoColor = profile.shirt; desc.LeftLegColor = profile.pants; desc.RightLegColor = profile.pants
	local ok, rig = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
	if not ok or not rig then
		warn("[Bots] could not build rig: " .. tostring(rig))
		return nil
	end
	rig.Name = profile.name
	rig:SetAttribute("IsBot", true)
	rig:SetAttribute("DisplayName", profile.name)
	local hum = rig:FindFirstChildOfClass("Humanoid")
	hum.DisplayName = profile.name .. " [BOT]"
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.NameDisplayDistance = 60
	hum.WalkSpeed = Config.WALK_SPEED
	local animate = rig:FindFirstChild("Animate")
	if animate then animate:Destroy() end -- client script, would not run on a server-owned model
	return rig, hum
end

-- Small server-side animator: idle / run / jump / fall
local function animate(hum)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local tracks = {}
	for key, id in ANIMS do
		local a = Instance.new("Animation"); a.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, a)
		if ok then tracks[key] = track end
	end
	local current
	local function play(key, speed)
		local t = tracks[key]
		if not t then return end
		if current ~= t then
			if current then current:Stop(0.15) end
			current = t
			t:Play(0.15)
		end
		if speed then t:AdjustSpeed(speed) end
	end
	play("idle")
	hum.Running:Connect(function(speed)
		if speed > 0.5 then play("run", speed / 16) else play("idle") end
	end)
	hum.Jumping:Connect(function(active) if active then play("jump") end end)
	hum.FreeFalling:Connect(function(active) if active then play("fall") end end)
end

---------------------------------------------------------------- danger sense

-- Is this point about to be hit? (meteor/lightning warnings, rolling boulders)
local function inDanger(ctx, pos)
	for _, h in ctx.hazards:GetChildren() do
		if h:IsA("BasePart") then
			if h.Name == "MeteorWarning" or h.Name == "BoltWarning" then
				local r = math.max(h.Size.Y, h.Size.Z) / 2 + 3
				local d = Vector3.new(pos.X - h.Position.X, 0, pos.Z - h.Position.Z)
				if d.Magnitude < r then return true end
			elseif h.Name == "Boulder" then
				-- the lane the boulder will roll through in the next 2.5 seconds
				local v = h.AssemblyLinearVelocity
				local a = Vector3.new(h.Position.X, 0, h.Position.Z)
				local b = a + Vector3.new(v.X, 0, v.Z) * 2.5
				local p = Vector3.new(pos.X, 0, pos.Z)
				local ab = b - a
				local t = ab.Magnitude > 0 and math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) or 0
				if (a + ab * t - p).Magnitude < h.Size.X / 2 + 3.5 then return true end
			end
		end
	end
	return false
end

local function tileSafe(ctx, tile)
	if not tile.Parent or not tile.Anchored or not tile.CanCollide or tile:GetAttribute("Doomed") then return false end
	if ctx.safeColor and tile:GetAttribute("ColorIdx") ~= ctx.safeColor then return false end
	-- the spinning laser stays longest near the center: keep away from it
	if ctx.hazards:FindFirstChild("Laser") then
		local d = tile.Position - ctx.center
		if Vector3.new(d.X, 0, d.Z).Magnitude < 18 then return false end
	end
	return not inDanger(ctx, tile.Position)
end

-- Tile under a position (nil = hole or not on the arena)
local function tileAt(ctx, pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {ctx.tiles}
	local hit = workspace:Raycast(pos, Vector3.new(0, -12, 0), params)
	return hit and hit.Instance
end

-- Pick a safe tile: close to the bot, a bit towards the center, with some randomness
-- (fleeing = mostly the closest safe tile)
local function chooseTile(ctx, from, fleeing)
	local best, bestScore
	local tiles = ctx.tiles:GetChildren()
	for _ = 1, fleeing and 60 or 24 do
		local t = tiles[math.random(#tiles)]
		if t and tileSafe(ctx, t) then
			local score = (t.Position - from).Magnitude * (fleeing and 2 or 1) + (t.Position - ctx.center).Magnitude * 0.35 + math.random() * (fleeing and 3 or 10)
			if not bestScore or score < bestScore then best, bestScore = t, score end
		end
	end
	return best
end

-- Spinning laser: a line through the center turning at a growing speed.
-- Returns the laser's angle (radians) and the bot's angle around the center, or nil without a laser.
local function laserAngles(ctx, pos)
	local laser = ctx.hazards:FindFirstChild("Laser")
	if not laser then return nil end
	local dir = laser.CFrame.RightVector
	local theta = math.atan2(-dir.Z, dir.X)
	local rel = pos - laser.Position
	local phi = math.atan2(-rel.Z, rel.X)
	return theta, phi
end

---------------------------------------------------------------- survivor bot

-- Spawns a living bot in the arena. Returns the model (nil if the rig failed).
function Bots.spawn(profile, ctx, cframe)
	local rig, hum = buildRig(profile)
	if not rig then return nil end
	rig:PivotTo(cframe)
	rig.Parent = ctx.arena
	local root = rig:FindFirstChild("HumanoidRootPart")
	pcall(root.SetNetworkOwner, root, nil) -- server moves bots
	animate(hum)

	task.spawn(function()
		local target, nextPick = nil, 0
		local noticedAt = nil
		local jumpRoll = nil
		local lastTheta, lastClock = nil, nil
		local laserSpeed = 1.2
		while ctx.isRunning() and rig.Parent and hum.Health > 0 do
			local now = os.clock()
			local pos = root.Position

			-- danger where I'm going (or I'm standing in danger with no safe goal)? react after my reaction time
			local here = tileAt(ctx, pos)
			local hereBad = inDanger(ctx, pos) or (here and not tileSafe(ctx, here))
			local targetBad = target and not tileSafe(ctx, target)
			if targetBad or (hereBad and (not target or target == here)) then
				noticedAt = noticedAt or now
				if now - noticedAt >= profile.reaction then
					target = chooseTile(ctx, pos, true)
					nextPick = now + 1.5 + math.random() * 2
					noticedAt = nil
					hum.WalkSpeed = Config.WALK_SPEED * Config.SPRINT_MULT -- run!
				end
			elseif hereBad then
				noticedAt = nil -- already heading to a safe tile
			else
				noticedAt = nil
				if now > nextPick or not target then
					-- wander to a new spot from time to time
					target = chooseTile(ctx, pos)
					nextPick = now + 2 + math.random() * 3
					hum.WalkSpeed = Config.WALK_SPEED
				end
			end

			if target then
				local goal = target.Position + Vector3.new(0, target.Size.Y / 2, 0)
				if Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z).Magnitude > 2 then
					hum:MoveTo(goal)
				else
					hum:Move(Vector3.zero)
				end
			end

			-- jump the laser (most of the time): predict when the line reaches me
			local theta, phi = laserAngles(ctx, pos)
			if theta then
				if lastTheta then
					local d = (theta - lastTheta) % (2 * math.pi)
					if d < 1 and now > lastClock then laserSpeed = math.max(0.5, d / (now - lastClock)) end
				end
				lastTheta, lastClock = theta, now
				-- the body is ~2 studs wide: the laser touches it a bit before the center line arrives
				local rel = pos - ctx.center
				local r = math.max(Vector3.new(rel.X, 0, rel.Z).Magnitude, 1)
				local untilHit = ((phi - theta) % math.pi) / laserSpeed - math.min(2.2 / r, 1) / laserSpeed
				if untilHit < 0.1 then
					if jumpRoll == nil then jumpRoll = math.random() < profile.jumpSkill end
					if jumpRoll and hum.FloorMaterial ~= Enum.Material.Air then hum.Jump = true end
				elseif untilHit > 0.5 then
					jumpRoll = nil
				end
			end
			task.wait(theta and 0.03 or 0.1)
		end
	end)
	return rig
end

---------------------------------------------------------------- ghost bot

local function ghostifyPart(d, color)
	if d:IsA("BasePart") then
		d.CollisionGroup = "Ghosts"
		d.CanCollide = false; d.CanTouch = false; d.CastShadow = false
		d.Anchored = d.Name == "HumanoidRootPart"
		if d.Name ~= "HumanoidRootPart" then d.Transparency = 0.45 end
	elseif d:IsA("Decal") then
		d.Transparency = 0.45
	end
end

-- A dead bot floats above the arena and throws meteors at survivors (players and bots)
function Bots.makeGhost(profile, ctx)
	if not ctx.isRunning() then return end
	local floor = ctx.arena:FindFirstChild("GhostFloor")
	if not floor then return end
	local rig, hum = buildRig(profile)
	if not rig then return end
	rig:SetAttribute("IsGhost", true)
	hum.DisplayName = profile.name .. " [BOT]"
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	for _, d in rig:GetDescendants() do ghostifyPart(d, profile.ghostColor) end
	local hl = Instance.new("Highlight")
	hl.FillColor = profile.ghostColor; hl.FillTransparency = 0.6
	hl.OutlineColor = Color3.new(1, 1, 1); hl.OutlineTransparency = 0.3
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = rig

	local base = floor.Floor.Position + Vector3.new(0, 4, 0)
	local r = ctx.halfSize - 8
	local function randomSpot()
		return base + Vector3.new(math.random(-r, r), 0, math.random(-r, r))
	end
	local pos = randomSpot()
	rig:PivotTo(CFrame.new(pos))
	rig.Parent = ctx.arena
	animate(hum)

	local throwInterval = Config.BOT_THROW_INTERVAL
	task.spawn(function()
		local goal = randomSpot()
		local nextThrow = os.clock() + 2 + math.random() * 2
		local t = 0
		while ctx.isRunning() and rig.Parent do
			local dt = task.wait(0.05)
			t += dt
			-- drift around + bob up and down
			local flat = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
			if flat.Magnitude < 2 then goal = randomSpot() end
			local stunned = (rig:GetAttribute("StunnedUntil") or 0) > workspace:GetServerTimeNow()
			if not stunned and flat.Magnitude > 0 then
				pos += flat.Unit * math.min(flat.Magnitude, 10 * dt)
			end
			local look = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, -1)
			rig:PivotTo(CFrame.lookAt(pos, pos + look) + Vector3.new(0, math.sin(t * 2) * 0.6, 0))

			if os.clock() >= nextThrow and not stunned then
				nextThrow = os.clock() + throwInterval[1] + math.random() * (throwInterval[2] - throwInterval[1])
				local victims = ctx.alivePlayers()
				local victim = #victims > 0 and victims[math.random(#victims)]
				local char = victim and Util.charOf(victim)
				local vroot = char and char:FindFirstChild("HumanoidRootPart")
				if vroot then
					-- aim where the victim is heading, with some spread
					local lead = vroot.AssemblyLinearVelocity * 0.5
					local spread = Vector3.new((math.random() - 0.5) * 2 * profile.aim, 0, (math.random() - 0.5) * 2 * profile.aim)
					local aim = vroot.Position + Vector3.new(lead.X, 0, lead.Z) + spread
					local h = ctx.halfSize
					aim = Vector3.new(math.clamp(aim.X, ctx.center.X - h, ctx.center.X + h), ctx.center.Y, math.clamp(aim.Z, ctx.center.Z - h, ctx.center.Z + h))
					Meteor.spawn(ctx, aim, {
						radius = Config.GHOST_BLAST_RADIUS,
						warnTime = Config.GHOST_WARN_TIME,
						height = 35, speed = 70,
						color = profile.ghostColor,
						onKill = function(v)
							ctx.notify(profile.name .. " [BOT] got " .. Util.nameOf(v) .. "!", profile.ghostColor)
						end,
					})
				end
			end
		end
	end)
	return rig
end

return Bots
