-- A match = one group playing ROUNDS_PER_MATCH rounds in its own arena slot.
-- Several matches run at the same time (one per lobby portal).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Config)
local Ghosts = require(script.Parent.Ghosts)
local Champion = require(script.Parent.Champion)
local PlayerData = require(script.Parent.PlayerData)
local Cosmetics = require(script.Parent.Cosmetics)

local remotes = ReplicatedStorage.Remotes
local GOLD = Color3.fromRGB(255, 200, 40)

-- Studio solo test: a round keeps running even if everyone died
local KEEP_ROUND_ALIVE = Config.DEBUG_SOLO and RunService:IsStudio()

local disasters = {}
for _, m in ServerStorage.Disasters:GetChildren() do
	if m:IsA("ModuleScript") then
		local d = require(m)
		if type(d) == "table" and d.Run then table.insert(disasters, d) end
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

local function keys(t)
	local list = {}
	for k in t do table.insert(list, k) end
	return list
end

-- 1 disaster, from STACK_FROM_ROUND sometimes 2 (never two floor-destroying ones).
-- `previous` = disasters of the last round, they are not picked again.
local function pickDisasters(round, previous)
	local fresh = {}
	for _, d in disasters do
		if not table.find(previous, d) then table.insert(fresh, d) end
	end
	if #fresh == 0 then fresh = disasters end
	local first = fresh[math.random(#fresh)]
	if round < Config.STACK_FROM_ROUND or math.random() >= Config.STACK_CHANCE then
		return {first}
	end
	local options = {}
	for _, d in fresh do
		if d ~= first and not (d.Floor and first.Floor) then table.insert(options, d) end
	end
	if #options == 0 then return {first} end
	return {first, options[math.random(#options)]}
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

function Match:add(player)
	self.players[player] = true
	playerMatch[player] = self
	player:SetAttribute("MatchSlot", self.slot)
	self:sendToWaiting(player)
end

-- Remove a player from the match. respawn = send them back to the lobby now.
function Match:remove(player, respawn)
	if not self.players[player] then return end
	self.players[player] = nil
	self.alive[player] = nil
	playerMatch[player] = nil
	if self.champion == player then self.champion = nil end
	Ghosts.release(player)
	Champion.clear(player)
	player:SetAttribute("MatchSlot", nil)
	if respawn and player.Parent then player:LoadCharacter() end
end

-- Called by GameServer whenever a match player gets a new character
function Match:onCharacterAdded(player)
	local ctx = self.ctx
	if ctx and ctx.isRunning() and not self.alive[player] then
		task.defer(Ghosts.makeGhost, player, ctx)
	else
		task.defer(function()
			local char = player.Character
			if char and char:WaitForChild("HumanoidRootPart", 5) then
				self:sendToWaiting(player)
			end
			Champion.applyCrown(player)
		end)
		task.spawn(Cosmetics.apply, player)
	end
end

---------------------------------------------------------------- round

function Match:playRound()
	local arena = ServerStorage.ArenaTemplate:Clone()
	arena:PivotTo(arena:GetPivot() + (self.center - arena:GetAttribute("Center")))
	arena.Name = "Arena"
	arena.Parent = self.area

	local running = true
	local ctx = {
		arena = arena,
		tiles = arena.Tiles,
		hazards = arena.Hazards,
		center = self.center,
		halfSize = arena:GetAttribute("HalfSize"),
		isRunning = function() return running end,
		alivePlayers = function() return keys(self.alive) end,
		callout = function(text, color, duration) self:callout(text, color, duration) end,
		notify = function(text, color) self:notify(text, color) end,
		effect = function(kind, ...) self:effect(kind, ...) end,
	}

	-- Living players into the arena
	table.clear(self.alive)
	local conns = {}
	for p in self.players do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not Ghosts.isGhost(p) then
			local h = ctx.halfSize - 6
			local pos = self.center + Vector3.new(math.random(-h, h), 4, math.random(-h, h))
			-- face the center so nobody runs straight off the edge
			char:PivotTo(CFrame.lookAt(pos, Vector3.new(self.center.X, pos.Y, self.center.Z)))
			self.alive[p] = true
			table.insert(conns, hum.Died:Connect(function()
				self.alive[p] = nil
				local root = char:FindFirstChild("HumanoidRootPart")
				if root then self:effect("poof", root.Position) end
			end))
		end
	end
	self.ctx = ctx

	local picked = pickDisasters(self.round, self.lastPicked or {})
	self.lastPicked = picked
	local roundName = picked[1].Name
	if #picked > 1 then
		roundName = picked[1].Name .. " + " .. picked[2].Name
	end
	-- big announcement of the disaster(s)
	if #picked > 1 then
		self:callout("CHAOS: " .. roundName:upper(), Color3.fromRGB(255, 90, 40), Config.ANNOUNCE_TIME)
	else
		self:callout(roundName:upper(), Color3.fromRGB(255, 200, 60), Config.ANNOUNCE_TIME)
	end
	if self.champion and self.alive[self.champion] then
		self:notify(self.champion.DisplayName .. " is champion - ghosts get x" .. Config.CHAMPION_BOUNTY_MULT .. " coins!", GOLD)
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

	-- Round running; fall check every 0.25s
	local killY = self.center.Y - Config.FALL_KILL_DEPTH
	local endTime = os.clock() + Config.ROUND_TIME
	while os.clock() < endTime and (next(self.alive) or (KEEP_ROUND_ALIVE and self:count() > 0)) do
		self:setStatus(roundName, math.ceil(endTime - os.clock()))
		for p in self.alive do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if not root then
				self.alive[p] = nil
			elseif root.Position.Y < killY then
				local hum = p.Character:FindFirstChildOfClass("Humanoid")
				if hum then hum.Health = 0 end
				self.alive[p] = nil
			end
		end
		task.wait(0.25)
	end
	running = false
	for _, c in conns do c:Disconnect() end

	local survivors = {}
	for p in self.alive do
		if p.Parent and self.players[p] then table.insert(survivors, p) end
	end
	local previousChampion = self.champion
	Champion.afterRound(self, survivors)
	if previousChampion and self.champion ~= previousChampion and previousChampion.Parent then
		self:notify(previousChampion.DisplayName .. " lost the crown!", GOLD)
	end
	self.ctx = nil

	-- Ghosts back to the waiting platform
	for p in self.players do
		if Ghosts.isGhost(p) then
			Ghosts.release(p)
			p:LoadCharacter()
		end
	end

	-- Rewards
	for _, p in survivors do
		PlayerData.addCoins(p, Config.SURVIVE_REWARD)
		if #survivors == 1 then
			PlayerData.addCoins(p, Config.WIN_BONUS)
			PlayerData.addWin(p)
		end
	end
	if #survivors == 0 then
		self:setStatus("Nobody survived!", Config.RESULTS_TIME)
	elseif #survivors == 1 then
		self:setStatus(survivors[1].DisplayName .. " wins!", Config.RESULTS_TIME)
		local streak = survivors[1]:GetAttribute("Streak") or 1
		self:callout(survivors[1].DisplayName .. (streak > 1 and (" WINS x" .. streak .. "!") or " WINS!"), GOLD, Config.RESULTS_TIME)
	else
		self:setStatus(#survivors .. " players survived!", Config.RESULTS_TIME)
	end
	task.wait(Config.RESULTS_TIME)

	for _, p in survivors do
		if self.players[p] then self:sendToWaiting(p) end
	end
	table.clear(self.alive)
	arena:Destroy()
end

function Match:run()
	for round = 1, Config.ROUNDS_PER_MATCH do
		self.round = round
		for t = Config.ROUND_INTERMISSION, 1, -1 do
			if self:count() == 0 then return end
			self:setStatus("Round " .. round .. "/" .. Config.ROUNDS_PER_MATCH .. " starts in", t)
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
end

function Match.start(slot, players)
	local self = setmetatable({
		slot = slot,
		area = workspace.MatchAreas["Slot" .. slot],
		players = {},
		alive = {},
		round = 0,
		champion = nil,
		ctx = nil,
	}, Match)
	self.center = self.area:GetAttribute("ArenaCenter")
	active[slot] = self
	for _, p in players do self:add(p) end
	task.spawn(function()
		local ok, err = pcall(self.run, self)
		if not ok then warn("[Match " .. slot .. "] " .. tostring(err)) end
		self:finish()
	end)
	return self
end

return Match
