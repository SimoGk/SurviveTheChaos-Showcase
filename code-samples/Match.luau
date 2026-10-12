-- A match = one lobby playing its rounds in its own arena slot (several matches run at once).
-- The host's settings pick the mode (Classic, Infected, Knockout, Team Knockout, Gun Game),
-- the number of bots, the difficulty and the number of rounds.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage.Config)
local Modes = require(ReplicatedStorage.Modes)
local Ghosts = require(script.Parent.Ghosts)
local Champion = require(script.Parent.Champion)
local PlayerData = require(script.Parent.PlayerData)
local Cosmetics = require(script.Parent.Cosmetics)
local Damage = require(script.Parent.Damage)
local Maps = require(script.Parent.Maps)
local Util = require(script.Parent.Util)
local Bots = require(script.Parent.Bots)
local Weapons = require(script.Parent.Weapons)
local Melee = require(script.Parent.Melee)
local Events = require(script.Parent.Events)
local ShopItems = require(ReplicatedStorage.ShopItems)
local Heroes = require(ReplicatedStorage.Heroes)

local remotes = ReplicatedStorage.Remotes
local GOLD = Color3.fromRGB(255, 200, 40)
local GREEN = Color3.fromRGB(120, 230, 90)
local TEAM_COLORS = {Red = Color3.fromRGB(255, 80, 80), Blue = Color3.fromRGB(80, 150, 255)}

-- Studio solo test: a round keeps running even if everyone died
local KEEP_ROUND_ALIVE = Config.DEBUG_SOLO and RunService:IsStudio()

-- disasters that break or push the floor: the Knockout modes only use these
local KNOCKOUT_DISASTERS = {FallingFloor = true, ShrinkingArena = true, CrumbleFloor = true, Sweeper = true,
	HammerTime = true, WindStorm = true, Tornado = true, BoulderRoll = true, BlockParty = true}

local disasters = {}
for _, m in ServerStorage.Disasters:GetChildren() do
	if m:IsA("ModuleScript") then
		local d = require(m)
		if type(d) == "table" and d.Run then
			d.Module = m.Name
			table.insert(disasters, d)
		end
	end
end

local Match = {}
Match.__index = Match

local active = {} -- slot -> match
local playerMatch = {} -- player -> match

function Match.forPlayer(player)
	return playerMatch[player]
end

function Match.isSlotBusy(slot)
	return active[slot] ~= nil
end

function Match.get(slot)
	return active[slot]
end

local function keys(t)
	local list = {}
	for k in t do table.insert(list, k) end
	return list
end

-- 1 disaster, from STACK_FROM_ROUND sometimes 2 (never two floor-destroying ones).
-- `previous` = disasters of the last round, they are not picked again. pool: "all" or "floor".
local function pickDisasters(round, previous, pool, stackChance)
	local all = {}
	for _, d in disasters do
		if (not d.Event or ShopItems.seasonalActive(d.Event)) and (pool ~= "floor" or KNOCKOUT_DISASTERS[d.Module]) then
			table.insert(all, d)
		end
	end
	-- Studio test: always play one disaster (set via the ForceDisaster attribute on ServerStorage)
	local forced = RunService:IsStudio() and ServerStorage:GetAttribute("ForceDisaster")
	if forced then
		for _, d in disasters do
			if d.Name == forced then return {d} end
		end
	end
	local fresh = {}
	for _, d in all do
		if not table.find(previous, d) then table.insert(fresh, d) end
	end
	if #fresh == 0 then fresh = all end
	if #fresh == 0 then return {} end
	local first = fresh[math.random(#fresh)]
	local overload = Events.isActive("chaos_overload")
	if not overload and (round < Config.STACK_FROM_ROUND or math.random() >= stackChance) then
		return {first}
	end
	local options = {}
	for _, d in fresh do
		if d ~= first and not (d.Floor and first.Floor) then table.insert(options, d) end
	end
	if #options == 0 then return {first} end
	local second = table.remove(options, math.random(#options))
	-- Chaos Overload: from round 3 even three at once (only one of them may break the floor)
	if overload and round >= 3 and #options > 0 then
		local third = {}
		for _, d in options do
			if not (d.Floor and (first.Floor or second.Floor)) then table.insert(third, d) end
		end
		if #third > 0 then return {first, second, third[math.random(#third)]} end
	end
	return {first, second}
end

---------------------------------------------------------------- players

function Match:count()
	local n = 0
	for _ in self.players do n += 1 end
	return n
end

function Match:setStatus(text, timeLeft)
	for p in self.players do
		p:SetAttribute("Status", text)
		p:SetAttribute("TimeLeft", timeLeft or 0)
	end
end

function Match:notify(text, color)
	for p in self.players do remotes.Notify:FireClient(p, text, color) end
end

function Match:effect(kind, ...)
	for p in self.players do remotes.Effect:FireClient(p, kind, ...) end
end

function Match:callout(text, color, duration)
	for p in self.players do remotes.Callout:FireClient(p, text, color, duration) end
end

function Match:sendToWaiting(player)
	local char = player.Character
	local wp = self.area:FindFirstChild("WaitPlatform")
	if char and wp then
		local x = (math.random() - 0.5) * (wp.Size.X - 8)
		local z = (math.random() - 0.5) * (wp.Size.Z - 8)
		char:PivotTo(CFrame.new(wp.Position + Vector3.new(x, 4, z), self.center))
	end
end

-- score key: the Player, or "bot:<name>" (bot rigs change every round)
local function keyOf(entity)
	if entity:IsA("Player") then return entity end
	return "bot:" .. (entity:GetAttribute("DisplayName") or entity.Name)
end

local function nameOfKey(key)
	if typeof(key) == "Instance" then return key.DisplayName end
	return (key:gsub("^bot:", ""))
end

-- Group list for the clients (avatars between rounds): JSON on every match player
function Match:updateRoster()
	local list = {}
	for p in self.players do
		table.insert(list, {n = p.DisplayName, u = p.UserId, l = p:GetAttribute("Level") or 1, c = p:GetAttribute("IsChampion") == true,
			k = self.kos[p] or 0, t = self.teamOf[p]})
	end
	for _, b in self.botProfiles do
		local key = "bot:" .. b.name
		table.insert(list, {n = b.name, u = 0, b = true, k = self.kos[key] or 0, t = self.teamOf[key]})
	end
	local json = HttpService:JSONEncode(list)
	for p in self.players do
		p:SetAttribute("Roster", json)
		p:SetAttribute("MatchMode", self.mode.id)
	end
end

function Match:add(player)
	self.players[player] = true
	playerMatch[player] = self
	player:SetAttribute("MatchSlot", self.slot)
	player:SetAttribute("Team", self.teamOf[player])
	self:sendToWaiting(player)
end

-- Remove a player from the match. respawn = send them back to the lobby now.
function Match:remove(player, respawn)
	if not self.players[player] then return end
	self.players[player] = nil
	self.alive[player] = nil
	self.infected[player] = nil
	playerMatch[player] = nil
	if self.champion == player then self.champion = nil end
	Ghosts.release(player)
	Champion.clear(player)
	Damage.clear(player)
	Weapons.take(player)
	for _, a in {"MatchSlot", "Roster", "MapTheme", "ArenaCenter", "ArenaHalf", "AliveLeft", "Team", "Infected", "MatchMode", "GunLevel"} do
		player:SetAttribute(a, nil)
	end
	self:updateRoster()
	if respawn and player.Parent then player:LoadCharacter() end
end

-- standing on the ground outside the arena (knocked off the edge) counts like a fall
function Match:landedOutside(root, ctx)
	local rel = root.Position - ctx.center
	return math.max(math.abs(rel.X), math.abs(rel.Z)) > ctx.halfSize + 4 and rel.Y < 4
end

-- a safe tile to drop someone on (revives, respawns, infected)
function Match:safeSpot(ctx)
	local safe = {}
	for _, t in ctx.tiles:GetChildren() do
		if t.Anchored and t.CanCollide and not t:GetAttribute("Doomed") and not t:GetAttribute("Hot") then table.insert(safe, t) end
	end
	local tile = safe[math.random(math.max(#safe, 1))]
	return tile and tile.Position + Vector3.new(0, 5, 0) or self.center + Vector3.new(0, 5, 0)
end

-- Called by GameServer whenever a match player gets a new character
function Match:onCharacterAdded(player)
	local ctx = self.ctx
	local running = ctx and ctx.isRunning()
	local function onArena(fn)
		task.defer(function()
			local char = player.Character
			if not char or not char:WaitForChild("HumanoidRootPart", 5) then return end
			fn(char)
		end)
	end
	if running and self.reviving[player] then
		self.reviving[player] = nil
		onArena(function()
			local pos = self:safeSpot(ctx)
			self:enterArena(player, ctx, CFrame.new(pos), 1)
			player:SetAttribute("InvulnUntil", workspace:GetServerTimeNow() + 3)
			Cosmetics.apply(player)
			self:effect("poof", pos)
			self:notify(player.DisplayName .. " is BACK from the dead!", Color3.fromRGB(255, 120, 140))
		end)
		return
	end
	self.reviving[player] = nil
	if running and not self.alive[player] then
		if self.mode.infected then
			-- died in Infected mode: come back as one of them
			onArena(function(char)
				char:PivotTo(CFrame.new(self:safeSpot(ctx)))
				self:infect(player)
			end)
		elseif self.mode.respawn then
			onArena(function()
				self:enterArena(player, ctx, CFrame.new(self:safeSpot(ctx)), 3)
				Weapons.give(player, ctx, Modes.GUN_LADDER[self.gunLevel[player] or 1])
			end)
		else
			task.defer(Ghosts.makeGhost, player, ctx)
		end
		return
	end
	onArena(function()
		self:sendToWaiting(player)
		Champion.applyCrown(player)
	end)
	task.spawn(Cosmetics.apply, player)
end

---------------------------------------------------------------- teams / infected / knock-outs

local function teamLook(char, team)
	local old = char and char:FindFirstChild("TeamGlow")
	if old then old:Destroy() end
	if not char or not team then return end
	local hl = Instance.new("Highlight")
	hl.Name = "TeamGlow"; hl.FillColor = TEAM_COLORS[team]; hl.FillTransparency = 0.82
	hl.OutlineColor = TEAM_COLORS[team]; hl.OutlineTransparency = 0; hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = char
end

-- someone becomes infected (patient zero at round start, or tagged / fallen survivors)
function Match:infect(entity, byWhom)
	local ctx = self.ctx
	if not ctx or not ctx.isRunning() or self.infected[entity] then return end
	local char = Util.charOf(entity)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	self.alive[entity] = nil
	self.infected[entity] = true
	if entity:IsA("Player") then
		Weapons.take(entity)
		Damage.clear(entity)
		remotes.Notify:FireClient(entity, "You are INFECTED! Touch survivors to turn them!", GREEN)
	else
		entity:SetAttribute("Lives", nil)
	end
	Melee.remove(char)
	entity:SetAttribute("Infected", true)
	entity:SetAttribute("InvulnUntil", nil)
	-- turning takes a moment (patient zero waits longer so survivors can run)
	entity:SetAttribute("FrozenUntil", workspace:GetServerTimeNow() + (byWhom and 2 or 4))
	local old = char:FindFirstChild("InfectedGlow")
	if not old then
		local hl = Instance.new("Highlight")
		hl.Name = "InfectedGlow"; hl.FillColor = GREEN; hl.FillTransparency = 0.45
		hl.OutlineColor = Color3.fromRGB(30, 80, 20); hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = char
		local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")
		if torso then
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = "rbxasset://textures/particles/smoke_main.dds"; pe.Color = ColorSequence.new(GREEN)
			pe.Size = NumberSequence.new(1, 2.5); pe.Transparency = NumberSequence.new(0.6, 1)
			pe.Lifetime = NumberRange.new(0.6, 1); pe.Rate = 12; pe.Speed = NumberRange.new(1, 2)
			pe.Parent = torso
		end
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if root then self:effect("poof", root.Position) end
	if byWhom then
		self:notify(Util.nameOf(byWhom) .. " infected " .. Util.nameOf(entity) .. "!", GREEN)
		self:onKO(entity, byWhom)
	else
		self:notify(Util.nameOf(entity) .. " is infected!", GREEN)
	end
	if not entity:IsA("Player") then Bots.runInfected(entity, ctx) end
end

-- a knock-out happened (attacker hit the victim shortly before they lost a life / got infected)
function Match:onKO(victim, attacker)
	local ctx = self.ctx
	if not ctx or not ctx.isRunning() or victim == attacker then return end
	local key = keyOf(attacker)
	self.kos[key] = (self.kos[key] or 0) + 1
	if not self.mode.infected then
		self:notify(Util.nameOf(attacker) .. " knocked out " .. Util.nameOf(victim) .. "!", Color3.fromRGB(255, 160, 80))
	end
	if attacker:IsA("Player") and self.players[attacker] then
		PlayerData.addCoins(attacker, Config.KO_REWARD)
		remotes.Effect:FireClient(attacker, "koPopup", self.kos[key])
	end
	if self.mode.gungame then
		local level = (self.gunLevel[key] or 1) + 1
		self.gunLevel[key] = level
		if level > #Modes.GUN_LADDER then
			self.gunWinner = self.gunWinner or attacker
		elseif attacker:IsA("Player") and self.alive[attacker] then
			attacker:SetAttribute("GunLevel", level)
			Weapons.give(attacker, ctx, Modes.GUN_LADDER[level])
			local item = ShopItems.byId[Modes.GUN_LADDER[level]]
			remotes.Notify:FireClient(attacker, "Level up! Now: " .. item.name .. (level == #Modes.GUN_LADDER and " - one more KO wins!" or ""), GOLD)
		end
	end
	self:updateRoster()
end

---------------------------------------------------------------- round

-- Put a living player into the running round (round start, revive, gun game respawn)
function Match:enterArena(p, ctx, cframe, lives)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	-- face the center so nobody runs straight off the edge
	char:PivotTo(cframe)
	self.alive[p] = true
	p:SetAttribute("Lives", lives)
	p:SetAttribute("ArenaCenter", ctx.center)
	p:SetAttribute("ArenaHalf", ctx.halfSize)
	teamLook(char, self.teamOf[p])
	table.insert(self.roundConns, hum.Died:Connect(function()
		self.alive[p] = nil
		Damage.clear(p)
		Weapons.take(p)
		Melee.remove(char)
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then self:effect("poof", root.Position) end
	end))
	if self.mode.gungame then
		Weapons.give(p, ctx, Modes.GUN_LADDER[self.gunLevel[p] or 1])
		p:SetAttribute("GunLevel", self.gunLevel[p] or 1)
	else
		Weapons.give(p, ctx)
	end
	Melee.give(p)
end

-- Revive (Robux product): a ghost comes back to life with 1 life on a safe tile
function Match.revive(player)
	local self = playerMatch[player]
	local ctx = self and self.ctx
	if not ctx or not ctx.isRunning() or self.alive[player] or not Ghosts.isGhost(player) then return false end
	Ghosts.release(player)
	self.reviving[player] = true
	player:LoadCharacter()
	return true
end

function Match:startLives(p)
	local lives = Config.LIVES + ShopItems.upgradeValue("lives", ShopItems.upgradeLevel(p, "lives")) + (p:GetAttribute("Pass_ExtraLife") and 1 or 0)
	return math.max(1, lives + self.difficulty.lives + (Heroes.stats(p).lives or 0))
end

function Match:playRound()
	local mode = self.mode
	local arena = ServerStorage.ArenaTemplate:Clone()
	arena:PivotTo(arena:GetPivot() + (self.center - arena:GetAttribute("Center")))
	arena.Name = "Arena"
	arena.Parent = self.area

	local running = true
	local ctx
	ctx = {
		arena = arena,
		tiles = arena.Tiles,
		hazards = arena.Hazards,
		center = self.center,
		halfSize = arena:GetAttribute("HalfSize"),
		mode = mode,
		isRunning = function() return running end,
		alivePlayers = function() return keys(self.alive) end,
		callout = function(text, color, duration) self:callout(text, color, duration) end,
		notify = function(text, color) self:notify(text, color) end,
		effect = function(kind, ...) self:effect(kind, ...) end,
		-- targets that get stunned by weapons: ghosts (players and bots) and the infected
		ghosts = function()
			local list = {}
			for p in self.players do
				if Ghosts.isGhost(p) and p.Character then table.insert(list, p) end
			end
			for _, m in arena:GetChildren() do
				if m:GetAttribute("IsBot") and m:GetAttribute("IsGhost") then table.insert(list, m) end
			end
			for e in self.infected do
				if e.Parent and Util.charOf(e) then table.insert(list, e) end
			end
			return list
		end,
		-- everyone a melee swing can hit: survivors and the infected
		targets = function()
			local list = keys(self.alive)
			for e in self.infected do table.insert(list, e) end
			return list
		end,
	}
	if mode.infected then
		-- bots run away from these
		ctx.threats = function()
			local list = {}
			for e in self.infected do
				local c = Util.charOf(e)
				local r = c and c:FindFirstChild("HumanoidRootPart")
				if r then table.insert(list, r.Position) end
			end
			return list
		end
	end

	-- ghosts fly now: the old ghost floor is not needed
	local gf = arena:FindFirstChild("GhostFloor")
	if gf then gf:Destroy() end

	-- random themed map (never the same twice in a row)
	local theme = Maps.pick(self.lastMap)
	self.lastMap = theme.name
	Maps.apply(arena, theme, ctx)
	self:notify("Map: " .. theme.name, Color3.fromRGB(140, 220, 255))
	for p in self.players do p:SetAttribute("MapTheme", theme.name) end
	-- Knockout modes: no invisible walls at the edge - smack people off the arena!
	if mode.ko then
		for _, b in arena:GetDescendants() do
			if b.Name == "Boundary" then b:Destroy() end
		end
	end

	-- Living players into the arena
	table.clear(self.alive)
	table.clear(self.infected)
	self.gunWinner = nil
	local conns = {}
	self.roundConns = conns
	for p in self.players do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not Ghosts.isGhost(p) then
			local h = ctx.halfSize - 6
			local pos = self.center + Vector3.new(math.random(-h, h), 4, math.random(-h, h))
			self:enterArena(p, ctx, CFrame.lookAt(pos, Vector3.new(self.center.X, pos.Y, self.center.Z)),
				mode.respawn and 3 or self:startLives(p))
		end
	end
	-- bots
	for _, profile in self.botProfiles do
		local h = ctx.halfSize - 6
		local pos = self.center + Vector3.new(math.random(-h, h), 4, math.random(-h, h))
		local bot = Bots.spawn(profile, ctx, CFrame.lookAt(pos, Vector3.new(self.center.X, pos.Y, self.center.Z)))
		local hum = bot and bot:FindFirstChildOfClass("Humanoid")
		if hum then
			self.alive[bot] = true
			bot:SetAttribute("Lives", math.max(1, Config.LIVES + self.difficulty.lives))
			local team = self.teamOf["bot:" .. profile.name]
			if team then bot:SetAttribute("Team", team); teamLook(bot, team) end
			table.insert(conns, hum.Died:Connect(function()
				self.alive[bot] = nil
				local root = bot:FindFirstChild("HumanoidRootPart")
				if root then self:effect("poof", root.Position) end
				task.delay(1.5, function()
					if bot.Parent then bot:Destroy() end
					if mode.ghosts then Bots.makeGhost(profile, ctx) end
				end)
			end))
		end
	end
	self.ctx = ctx

	-- knock-outs: whoever hit a survivor last gets the KO when they lose a life
	table.insert(conns, Damage.KnockedOut:Connect(function(victim, attacker)
		if (self.players[victim] or victim:IsDescendantOf(arena)) and (self.players[attacker] or attacker:IsDescendantOf(arena)) then
			self:onKO(victim, attacker)
		end
	end))

	-- what is this round about?
	local picked = mode.disasters and pickDisasters(self.round, self.lastPicked or {}, mode.disasters, self.difficulty.stack) or {}
	self.lastPicked = picked
	local names = {}
	for _, d in picked do table.insert(names, d.Name) end
	local roundName = #names > 0 and table.concat(names, " + ") or mode.name
	local title
	if mode.infected then
		title, roundName = "INFECTED!", "Infected - don't get touched!"
	elseif mode.gungame then
		title, roundName = "GUN GAME!", "Gun Game - KO to level up!"
	elseif mode.teams then
		title = "RED vs BLUE" .. (#names > 0 and (": " .. names[1]:upper()) or "!")
	elseif mode.ko then
		title = "KNOCKOUT" .. (#names > 0 and (": " .. roundName:upper()) or "!")
	else
		title = (#picked > 1 and "CHAOS: " or "") .. roundName:upper()
	end
	self:callout(title, mode.color or Color3.fromRGB(255, 200, 60), Config.ANNOUNCE_TIME)
	if self.champion and self.alive[self.champion] and not mode.teams and not mode.infected then
		self:notify("Champion " .. self.champion.DisplayName .. " has a " .. Champion.bounty(self.champion) .. " coin BOUNTY on their head!", GOLD)
		remotes.Notify:FireClient(self.champion, "You are the champion! Survive this round to keep your crown.", GOLD)
	end

	for t = Config.ANNOUNCE_TIME, 1, -1 do
		self:setStatus("Get ready: " .. roundName, t)
		task.wait(1)
	end
	self:callout("GO!", Color3.fromRGB(140, 255, 110), 0.8)
	for _, d in picked do
		task.spawn(d.Run, ctx)
	end

	-- Infected: patient zero (one per 5 survivors), then the touch check
	if mode.infected then
		local list = keys(self.alive)
		for _ = 1, math.max(1, math.floor(#list / 5)) do
			if #list > 1 then self:infect(table.remove(list, math.random(#list))) end
		end
		self:callout("RUN! THE INFECTION SPREADS!", GREEN, 2.5)
		task.spawn(function()
			while running do
				for inf in self.infected do
					local ichar = Util.charOf(inf)
					local iroot = ichar and ichar:FindFirstChild("HumanoidRootPart")
					local frozen = (inf:GetAttribute("FrozenUntil") or 0) > workspace:GetServerTimeNow()
					if iroot and not frozen and not ichar:GetAttribute("Ragdolled") then
						for s in self.alive do
							local schar = Util.charOf(s)
							local sroot = schar and schar:FindFirstChild("HumanoidRootPart")
							if sroot and (sroot.Position - iroot.Position).Magnitude < Config.INFECT_RADIUS then
								if (s:GetAttribute("ShieldUntil") or 0) > workspace:GetServerTimeNow() then
									-- the shield throws the infected back
									local away = iroot.Position - sroot.Position
									Util.knockback(inf, Vector3.new(away.X, 0, away.Z).Unit * 50 + Vector3.new(0, 25, 0), true)
								elseif not Damage.isInvulnerable(s) then
									self:infect(s, inf)
									inf:SetAttribute("FrozenUntil", workspace:GetServerTimeNow() + 0.8)
								end
							end
						end
					end
				end
				task.wait(0.1)
			end
		end)
	end

	-- Halloween: candy pops up on the floor, players grab it
	if ShopItems.seasonalActive("halloween") then
		task.spawn(function()
			local candyColors = {Color3.fromRGB(255, 140, 30), Color3.fromRGB(170, 80, 255), Color3.fromRGB(120, 255, 120)}
			while running do
				task.wait(Config.CANDY_SPAWN_EVERY)
				if not running then break end
				local tiles = {}
				for _, t in ctx.tiles:GetChildren() do
					if t.Anchored and t.CanCollide and not t:GetAttribute("Doomed") then table.insert(tiles, t) end
				end
				if #tiles > 0 then
					local tile = tiles[math.random(#tiles)]
					local candy = Instance.new("Part")
					candy.Name = "Candy"; candy.Shape = Enum.PartType.Ball; candy.Size = Vector3.new(1.6, 1.6, 1.6)
					candy.Anchored = true; candy.CanCollide = false; candy.Material = Enum.Material.Neon
					candy.Color = candyColors[math.random(#candyColors)]
					candy.Position = tile.Position + Vector3.new(0, tile.Size.Y / 2 + 1.3, 0)
					local l = Instance.new("PointLight"); l.Color = candy.Color; l.Range = 7; l.Parent = candy
					local sp = Instance.new("Sparkles"); sp.SparkleColor = candy.Color; sp.Parent = candy
					candy.Parent = arena
					local taken = false
					candy.Touched:Connect(function(hit)
						local p = Players:GetPlayerFromCharacter(hit.Parent)
						if taken or not p or not self.alive[p] then return end
						taken = true
						PlayerData.addCandy(p, 1)
						self:effect("poof", candy.Position)
						candy:Destroy()
					end)
					task.delay(9, function() if candy.Parent then candy:Destroy() end end)
				end
			end
		end)
	end

	-- Round running; fall check every 0.25s
	local killY = self.center.Y - Config.FALL_KILL_DEPTH
	local roundTime = mode.roundTime or Config.ROUND_TIME
	local endTime = os.clock() + roundTime
	local function teamsLeft()
		local seen, n = {}, 0
		for e in self.alive do
			local t = e:GetAttribute("Team")
			if t and not seen[t] then seen[t] = true; n += 1 end
		end
		return n
	end
	while os.clock() < endTime and (next(self.alive) or (KEEP_ROUND_ALIVE and self:count() > 0)) do
		if self.gunWinner then break end
		if self:count() == 0 then break end -- every real player left: stop (bots alone don't play on)
		if mode.teams and teamsLeft() < 2 and not KEEP_ROUND_ALIVE then break end
		self:setStatus(roundName, math.ceil(endTime - os.clock()))
		local left = 0
		for _ in self.alive do left += 1 end
		for p in self.players do p:SetAttribute("AliveLeft", left) end
		for p in self.alive do
			local char = Util.charOf(p)
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root or not char.Parent then
				self.alive[p] = nil
			elseif root.Position.Y < killY or self:landedOutside(root, ctx) then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if mode.infected then
					-- fell off in Infected mode = you're one of them now
					char:PivotTo(CFrame.new(self:safeSpot(ctx)))
					self:infect(p, Damage.lastAttacker(p))
				elseif mode.respawn then
					-- Gun Game: the KO counts, you drop back in
					local by = Damage.lastAttacker(p)
					if by then self:onKO(p, by) end
					Damage.clearHit(p)
					char:PivotTo(CFrame.new(self:safeSpot(ctx)))
					p:SetAttribute("InvulnUntil", workspace:GetServerTimeNow() + 1.5)
				-- fell through a hole: lose a life and land back on a random tile
				elseif hum and not Damage.hit(p, hum, "fall") and hum.Health > 0 then
					char:PivotTo(CFrame.new(self:safeSpot(ctx)))
				end
				if not hum or hum.Health <= 0 then self.alive[p] = nil end
			end
		end
		-- infected who fall come straight back
		for inf in self.infected do
			local char = Util.charOf(inf)
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root.Position.Y < killY then char:PivotTo(CFrame.new(self:safeSpot(ctx))) end
		end
		task.wait(0.25)
	end
	running = false
	for _, c in conns do c:Disconnect() end
	for p in self.players do
		Damage.clear(p)
		Weapons.take(p)
		Melee.remove(p.Character)
		for _, a in {"ArenaCenter", "ArenaHalf", "AliveLeft", "Infected", "GunLevel"} do p:SetAttribute(a, nil) end
	end

	-- survivors = players and bots; only players get rewards
	local survivors, players = {}, {}
	for p in self.alive do
		if p.Parent and (self.players[p] or p:GetAttribute("IsBot")) then
			table.insert(survivors, p)
			if self.players[p] then table.insert(players, p) end
		end
	end
	local infectedPlayers = {}
	for e in self.infected do
		if self.players[e] then table.insert(infectedPlayers, e) end
	end
	local soloWinMode = not mode.teams and not mode.infected and not mode.gungame
	if soloWinMode then
		local previousChampion = self.champion
		Champion.afterRound(self, survivors)
		if previousChampion and self.champion ~= previousChampion and previousChampion.Parent then
			self:notify(previousChampion.DisplayName .. " lost the crown!", GOLD)
		end
	end
	self:updateRoster()
	self.ctx = nil

	-- who haunted this round (for the ghost team win)
	local ghostPlayers = {}
	for p in self.players do
		if Ghosts.isGhost(p) then table.insert(ghostPlayers, p) end
	end
	-- Ghosts / infected back to the waiting platform
	for p in self.players do
		if Ghosts.isGhost(p) or table.find(infectedPlayers, p) then
			Ghosts.release(p)
			p:LoadCharacter()
		end
	end
	table.clear(self.infected)

	-- Rewards: coins + XP (everyone who played gets a little XP)
	for p in self.players do
		if p.Parent then
			PlayerData.addXP(p, Config.XP_ROUND)
			PlayerData.quest(p, "rounds")
		end
	end
	local function win(p)
		PlayerData.addCoins(p, Config.WIN_BONUS)
		PlayerData.addXP(p, Config.XP_WIN)
		PlayerData.addWin(p)
		PlayerData.quest(p, "wins")
	end
	for _, p in players do
		PlayerData.addCoins(p, Config.SURVIVE_REWARD)
		PlayerData.addXP(p, Config.XP_SURVIVE)
		PlayerData.quest(p, "survived")
		if ShopItems.seasonalActive("halloween") then
			PlayerData.addCandy(p, #survivors == 1 and Config.CANDY_WIN or Config.CANDY_SURVIVE)
		end
	end

	if mode.gungame then
		-- winner: finished the ladder, else most KOs
		local winner = self.gunWinner
		if not winner then
			local bestKey, best = nil, 0
			for k, n in self.kos do
				if n > best then bestKey, best = k, n end
			end
			winner = bestKey
		end
		if winner then
			local name = typeof(winner) == "Instance" and Util.nameOf(winner) or nameOfKey(winner)
			self:setStatus(name .. " wins Gun Game!", Config.RESULTS_TIME)
			self:callout(name:upper() .. " WINS!", GOLD, Config.RESULTS_TIME)
			if typeof(winner) == "Instance" and winner:IsA("Player") and self.players[winner] then win(winner) end
		else
			self:setStatus("No knock-outs this round!", Config.RESULTS_TIME)
		end
	elseif mode.teams then
		local count = {Red = 0, Blue = 0}
		for _, s in survivors do
			local t = s:GetAttribute("Team")
			if t then count[t] += 1 end
		end
		local winTeam = (count.Red > count.Blue and "Red") or (count.Blue > count.Red and "Blue") or nil
		if not winTeam then
			-- same number of survivors: the team with more knock-outs wins
			local ko = {Red = 0, Blue = 0}
			for key, n in self.kos do
				local t = self.teamOf[key]
				if t then ko[t] += n end
			end
			winTeam = (ko.Red > ko.Blue and "Red") or (ko.Blue > ko.Red and "Blue") or nil
		end
		if winTeam then
			self:setStatus(winTeam .. " team wins!", Config.RESULTS_TIME)
			self:callout(winTeam:upper() .. " TEAM WINS!", TEAM_COLORS[winTeam], Config.RESULTS_TIME)
			for p in self.players do
				if p.Parent and self.teamOf[p] == winTeam then win(p) end
			end
		else
			self:setStatus("Draw!", Config.RESULTS_TIME)
			self:callout("DRAW!", Color3.new(1, 1, 1), Config.RESULTS_TIME)
		end
	elseif mode.infected then
		if #survivors > 0 then
			self:setStatus(#survivors .. " survived the infection!", Config.RESULTS_TIME)
			self:callout("SURVIVORS WIN!", Color3.fromRGB(140, 220, 255), Config.RESULTS_TIME)
			for _, p in players do win(p) end
		else
			self:setStatus("Everyone got infected!", Config.RESULTS_TIME)
			self:callout("THE INFECTED WIN!", GREEN, Config.RESULTS_TIME)
			for _, p in infectedPlayers do
				if p.Parent then
					PlayerData.addCoins(p, Config.GHOST_WIN_BONUS)
					PlayerData.addXP(p, Config.GHOST_WIN_XP)
				end
			end
		end
	elseif #survivors == 0 and #ghostPlayers > 0 then
		-- nobody made it: the ghost team wins the round
		self:setStatus("Ghosts win!", Config.RESULTS_TIME)
		self:callout("GHOSTS WIN!", Color3.fromRGB(190, 120, 255), Config.RESULTS_TIME)
		for _, g in ghostPlayers do
			if g.Parent then
				PlayerData.addCoins(g, Config.GHOST_WIN_BONUS)
				PlayerData.addXP(g, Config.GHOST_WIN_XP)
				remotes.Notify:FireClient(g, "Ghost team win! +" .. Config.GHOST_WIN_BONUS .. " coins", Color3.fromRGB(190, 120, 255))
			end
		end
	elseif #survivors == 0 then
		self:setStatus("Nobody survived!", Config.RESULTS_TIME)
	elseif #survivors == 1 then
		local name = Util.nameOf(survivors[1])
		if self.players[survivors[1]] then win(survivors[1]) end
		self:setStatus(name .. " wins!", Config.RESULTS_TIME)
		local streak = survivors[1]:GetAttribute("Streak") or 1
		self:callout(name .. (streak > 1 and (" WINS x" .. streak .. "!") or " WINS!"), GOLD, Config.RESULTS_TIME)
	else
		self:setStatus(#survivors .. " survived!", Config.RESULTS_TIME)
	end
	task.wait(Config.RESULTS_TIME)

	for _, p in players do
		if self.players[p] then
			teamLook(p.Character, nil)
			self:sendToWaiting(p)
		end
	end
	table.clear(self.alive)
	arena:Destroy()
	for p in self.players do p:SetAttribute("MapTheme", nil) end
end

function Match:run()
	local rounds = self.settings.rounds
	for round = 1, rounds do
		self.round = round
		if self.mode.gungame then
			-- every Gun Game round starts from the first weapon
			table.clear(self.gunLevel)
			table.clear(self.kos)
			self:updateRoster()
		end
		for t = Config.ROUND_INTERMISSION, 1, -1 do
			if self:count() == 0 then return end
			self:setStatus("Round " .. round .. "/" .. rounds .. " starts in", t)
			if t <= 3 then self:callout(tostring(t), Color3.new(1, 1, 1), 0.9) end
			task.wait(1)
		end
		self:playRound()
	end
	self:setStatus("Match over! Back to the lobby...", Config.RESULTS_TIME)
	task.wait(Config.RESULTS_TIME)
end

function Match:finish()
	self.ctx = nil
	for p in self.players do self:remove(p, true) end
	local arena = self.area:FindFirstChild("Arena")
	if arena then arena:Destroy() end
	active[self.slot] = nil
	if Match.onFinished then task.spawn(Match.onFinished, self.slot) end
end

-- settings: see Modes.sanitize (mode, bots, difficulty, privacy, rounds)
function Match.start(slot, players, settings)
	settings = Modes.sanitize(settings)
	local self = setmetatable({
		slot = slot,
		area = workspace.MatchAreas["Slot" .. slot],
		players = {},
		alive = {},
		infected = {},
		round = 0,
		champion = nil,
		ctx = nil,
		botProfiles = {},
		reviving = {},
		roundConns = {},
		kos = {},
		gunLevel = {},
		teamOf = {},
		settings = settings,
		mode = Modes.byId[settings.mode],
		difficulty = Modes.difficultyById[settings.difficulty],
	}, Match)
	self.center = self.area:GetAttribute("ArenaCenter")
	active[slot] = self
	-- bots chosen by the host (never more than the free spots)
	local botCount = Config.BOTS_ENABLED and math.min(settings.bots, Modes.MAX_PLAYERS - #players) or 0
	if self.mode.teams or self.mode.infected then botCount = math.max(botCount, 2 - #players) end
	if botCount > 0 then self.botProfiles = Bots.makeProfiles(botCount, self.difficulty) end
	-- teams: shuffle everyone, then alternate Red / Blue
	if self.mode.teams then
		local everyone = table.clone(players)
		for _, b in self.botProfiles do table.insert(everyone, "bot:" .. b.name) end
		for i = #everyone, 2, -1 do
			local j = math.random(i)
			everyone[i], everyone[j] = everyone[j], everyone[i]
		end
		for i, key in everyone do self.teamOf[key] = (i % 2 == 1) and "Red" or "Blue" end
	end
	for _, p in players do self:add(p) end
	self:updateRoster()
	if #self.botProfiles > 0 then
		task.delay(1, function()
			local n = #self.botProfiles
			self:notify(n .. (n == 1 and " bot joined" or " bots joined") .. " your group!", Color3.fromRGB(140, 220, 255))
		end)
	end
	task.delay(0.5, function()
		self:notify(self.mode.name .. " - " .. self.difficulty.name .. " - " .. settings.rounds .. " rounds", self.mode.color)
	end)
	task.spawn(function()
		local ok, err = pcall(self.run, self)
		if not ok then warn("[Match " .. slot .. "] " .. tostring(err)) end
		self:finish()
	end)
	return self
end

return Match
