-- Ghost mode: dead players fly above their arena and use ghost powers on the survivors
-- (meteor, wind gust, freeze bomb, lightning). Flying itself runs on the client (GhostClient);
-- the server validates every power: cooldown, ownership, range, stun.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Meteor = require(script.Parent.Meteor)
local PlayerData = require(script.Parent.PlayerData)
local Cosmetics = require(script.Parent.Cosmetics)
local ShopItems = require(ReplicatedStorage.ShopItems)
local Util = require(script.Parent.Util)
local Damage = require(script.Parent.Damage)
local Champion = require(script.Parent.Champion)
local Heroes = require(ReplicatedStorage.Heroes)

local remotes = ReplicatedStorage.Remotes
local GOLD = Color3.fromRGB(255, 200, 40)

local Ghosts = {}

-- coins for ghost work (Bounty Hunter skill gives more)
local function ghostCoins(owner, amount)
	PlayerData.addCoins(owner, math.floor(amount * Heroes.mult(Heroes.stats(owner), "ghostCoins")))
end

local ghostCtx = {} -- player -> round ctx the ghost belongs to
local lastUse = {} -- player -> {power -> os.clock()}

local function ghostifyPart(d)
	if d:IsA("BasePart") then
		d.CollisionGroup = "Ghosts"
		d.CastShadow = false
		if d.Name ~= "HumanoidRootPart" then
			d.Transparency = math.max(d.Transparency, 0.45)
		end
	elseif d:IsA("Decal") then
		d.Transparency = math.max(d.Transparency, 0.45)
	end
end

function Ghosts.isGhost(player)
	return player:GetAttribute("IsGhost") == true
end

-- Turn the player's current character into a flying ghost above ctx's arena
function Ghosts.makeGhost(player, ctx)
	local char = player.Character
	if not char or not ctx.isRunning() then return end
	player:SetAttribute("IsGhost", true)
	ghostCtx[player] = ctx

	local root = char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or ghostCtx[player] ~= ctx then return end

	local crown = char:FindFirstChild("ChampionCrown")
	if crown then crown:Destroy() end
	Cosmetics.clear(player)
	for _, d in char:GetDescendants() do ghostifyPart(d) end
	char.DescendantAdded:Connect(ghostifyPart)

	local hl = Instance.new("Highlight")
	hl.FillColor = Cosmetics.ghostColor(player); hl.FillTransparency = 0.6
	hl.OutlineColor = Color3.new(1, 1, 1); hl.OutlineTransparency = 0.3
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = char
	-- the arena center, so the client can set up flying + camera
	player:SetAttribute("GhostCenter", ctx.center)
	player:SetAttribute("GhostHalfSize", ctx.halfSize)

	local r = ctx.halfSize - 8
	local pos = ctx.center + Vector3.new(math.random(-r, r), 32, math.random(-r, r))
	char:PivotTo(CFrame.lookAt(pos, Vector3.new(ctx.center.X, pos.Y, ctx.center.Z)))
	remotes.Notify:FireClient(player, "You're a ghost! Fly with WASD and click to attack!", Cosmetics.ghostColor(player))
end

-- Ghost state off (caller decides where the player respawns)
function Ghosts.release(player)
	ghostCtx[player] = nil
	lastUse[player] = nil
	player:SetAttribute("IsGhost", nil)
	player:SetAttribute("StunnedUntil", nil)
	player:SetAttribute("GhostCenter", nil)
	player:SetAttribute("GhostHalfSize", nil)
end

---------------------------------------------------------------- powers
-- Shared by player ghosts and ghost bots. `owner` = Player (gets coins) or nil (bot).
-- color = ghost color, name = who gets credit in the feed.

local POWERS = {}

function POWERS.meteor(ctx, target, owner, color, name)
	Meteor.spawn(ctx, target, {
		radius = Config.GHOST_BLAST_RADIUS,
		warnTime = Config.GHOST_WARN_TIME,
		height = 35, speed = 70,
		color = color,
		onKill = function(victim)
			if owner and owner.Parent then
				local mult = owner:GetAttribute("Pass_GhostKing") and 1.5 or 1
				if victim:GetAttribute("IsChampion") then
					local bounty = math.floor(Champion.bounty(victim) * mult)
					ghostCoins(owner, bounty)
					ctx.notify(name .. " took down champion " .. Util.nameOf(victim) .. " and claimed the " .. bounty .. " coin bounty!", GOLD)
					return
				end
				ghostCoins(owner, Config.GHOST_KILL_REWARD * mult)
				PlayerData.addXP(owner, Config.XP_GHOST_KILL)
				PlayerData.quest(owner, "ghostkills")
			end
			ctx.notify(name .. " got " .. Util.nameOf(victim) .. "!", color)
		end,
	})
end

-- warning circle on the floor, then fn()
local function telegraph(ctx, target, radius, color, time, fn)
	local warn = Instance.new("Part")
	warn.Name = "MeteorWarning" -- bots dodge everything called *Warning
	warn.Anchored = true; warn.CanCollide = false; warn.CanQuery = false; warn.CanTouch = false
	warn.Shape = Enum.PartType.Cylinder
	warn.Size = Vector3.new(0.2, radius * 2, radius * 2)
	warn.CFrame = CFrame.new(target + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	warn.Material = Enum.Material.Neon; warn.Color = color; warn.Transparency = 0.45
	warn.Parent = ctx.hazards
	task.delay(time, function()
		if warn.Parent then warn:Destroy() end
		if ctx.isRunning() then fn() end
	end)
end

local function reward(owner, count)
	if owner and owner.Parent and count > 0 then
		ghostCoins(owner, Config.GHOST_POWER_REWARD * count)
	end
end

function POWERS.gust(ctx, target, owner, color, name)
	local radius = 11
	telegraph(ctx, target, radius, Color3.fromRGB(220, 245, 255), 0.6, function()
		ctx.effect("gust", target, radius)
		local hit = 0
		for _, s in Util.survivorsNear(ctx, target, radius) do
			local away = Vector3.new(s.root.Position.X - target.X, 0, s.root.Position.Z - target.Z)
			away = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
			if owner then Damage.markHit(s.entity, owner) end
			Util.knockback(s.entity, away * 70 + Vector3.new(0, 35, 0), true)
			hit += 1
		end
		reward(owner, hit)
	end)
end

function POWERS.freeze(ctx, target, owner, color, name)
	local radius = 8
	telegraph(ctx, target, radius, Color3.fromRGB(120, 220, 255), 0.9, function()
		ctx.effect("freeze", target, radius)
		local hit = 0
		for _, s in Util.survivorsNear(ctx, target, radius) do
			Util.freeze(s.entity, Config.FREEZE_TIME)
			hit += 1
		end
		if hit > 0 then ctx.notify(name .. " froze " .. hit .. (hit == 1 and " survivor!" or " survivors!"), Color3.fromRGB(120, 220, 255)) end
		reward(owner, hit)
	end)
end

-- grave hands burst out of the floor and toss everyone in the circle around (ragdoll, no life lost)
function POWERS.hands(ctx, target, owner, color, name)
	local radius = 7
	telegraph(ctx, target, radius, Color3.fromRGB(180, 100, 255), 0.8, function()
		ctx.effect("hands", target, radius)
		local hit = 0
		for _, s in Util.survivorsNear(ctx, target, radius) do
			local a = math.random() * math.pi * 2
			if owner then Damage.markHit(s.entity, owner) end
			Util.knockback(s.entity, Vector3.new(math.cos(a), 0, math.sin(a)) * 28 + Vector3.new(0, 48, 0), true, 1.8)
			hit += 1
		end
		if hit > 0 then ctx.notify(name .. "'s grave hands grabbed " .. hit .. (hit == 1 and " survivor!" or " survivors!"), Color3.fromRGB(180, 100, 255)) end
		reward(owner, hit)
	end)
end

function POWERS.lightning(ctx, target, owner, color, name)
	local radius = 5
	telegraph(ctx, target, radius, Color3.fromRGB(255, 240, 120), 0.5, function()
		ctx.effect("lightning", target)
		for _, s in Util.survivorsNear(ctx, target, radius) do
			local hum = s.root.Parent:FindFirstChildOfClass("Humanoid")
			if hum and Damage.hit(s.entity, hum, "lightning") then
				if owner and owner.Parent then
					ghostCoins(owner, Config.GHOST_KILL_REWARD)
					PlayerData.addXP(owner, Config.XP_GHOST_KILL)
					PlayerData.quest(owner, "ghostkills")
				end
				ctx.notify(name .. " zapped " .. Util.nameOf(s.entity) .. "!", color)
			end
		end
	end)
end

-- Use a power (no checks: callers validate). target = point on the arena floor.
function Ghosts.usePower(power, ctx, target, owner, color, name)
	local fn = POWERS[power]
	if fn then fn(ctx, target, owner, color, name) end
end

local function ownedSet(player)
	local data = PlayerData.get(player)
	return data and data.Owned or {}
end

remotes.GhostThrow.OnServerEvent:Connect(function(player, target, power)
	local ctx = ghostCtx[player]
	if not ctx or not ctx.isRunning() or not Ghosts.isGhost(player) then return end
	if typeof(target) ~= "Vector3" or target ~= target then return end
	if (player:GetAttribute("StunnedUntil") or 0) > workspace:GetServerTimeNow() then return end
	power = type(power) == "string" and power or "meteor"
	local def = ShopItems.powerById[power]
	if not def or not (ShopItems.hasPower(ownedSet(player), power) or player:GetAttribute("Pass_AllPowers")) then return end

	local now = os.clock()
	local cooldown = def.cooldown
	if power == "meteor" then
		cooldown = math.max(1, cooldown - ShopItems.upgradeValue("ghost", ShopItems.upgradeLevel(player, "ghost")))
	end
	cooldown *= Heroes.mult(Heroes.stats(player), "ghostCooldown")
	lastUse[player] = lastUse[player] or {}
	local last = lastUse[player][power]
	if last and now - last < cooldown - 0.15 then return end

	local offset = target - ctx.center
	if math.abs(offset.X) > ctx.halfSize or math.abs(offset.Z) > ctx.halfSize then return end
	lastUse[player][power] = now
	PlayerData.quest(player, "powers")
	Ghosts.usePower(power, ctx, Vector3.new(target.X, ctx.center.Y, target.Z), player, Cosmetics.ghostColor(player), player.DisplayName)
end)

Players.PlayerRemoving:Connect(function(p)
	ghostCtx[p] = nil
	lastUse[p] = nil
end)

return Ghosts
