-- Ghost mode: dead players float above their arena and throw meteors
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Meteor = require(script.Parent.Meteor)
local PlayerData = require(script.Parent.PlayerData)
local Cosmetics = require(script.Parent.Cosmetics)
local ShopItems = require(ReplicatedStorage.ShopItems)
local Util = require(script.Parent.Util)

local remotes = ReplicatedStorage.Remotes
local GOLD = Color3.fromRGB(255, 200, 40)

local Ghosts = {}

local ghostCtx = {} -- player -> round ctx the ghost belongs to
local lastThrow = {}

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

-- Turn the player's current character into a ghost above ctx's arena
function Ghosts.makeGhost(player, ctx)
	local char = player.Character
	if not char or not ctx.isRunning() then return end
	player:SetAttribute("IsGhost", true)
	ghostCtx[player] = ctx

	local root = char:WaitForChild("HumanoidRootPart", 5)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local floor = ctx.arena:FindFirstChild("GhostFloor")
	if not root or not hum or not floor or ghostCtx[player] ~= ctx then return end

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
	hum.WalkSpeed = Config.GHOST_WALKSPEED

	local r = ctx.halfSize - 8
	local pos = floor.Floor.Position + Vector3.new(math.random(-r, r), 4, math.random(-r, r))
	char:PivotTo(CFrame.new(pos))
	remotes.Notify:FireClient(player, "You're a ghost! Click the arena to throw meteors!", Cosmetics.ghostColor(player))
end

-- Ghost state off (caller decides where the player respawns)
function Ghosts.release(player)
	ghostCtx[player] = nil
	lastThrow[player] = nil
	player:SetAttribute("IsGhost", nil)
	player:SetAttribute("StunnedUntil", nil)
end

remotes.GhostThrow.OnServerEvent:Connect(function(player, target)
	local ctx = ghostCtx[player]
	if not ctx or not ctx.isRunning() or not Ghosts.isGhost(player) then return end
	if typeof(target) ~= "Vector3" then return end
	if (player:GetAttribute("StunnedUntil") or 0) > workspace:GetServerTimeNow() then return end

	local now = os.clock()
	local cooldown = math.max(1, Config.GHOST_COOLDOWN - ShopItems.upgradeValue("ghost", ShopItems.upgradeLevel(player, "ghost")))
	if lastThrow[player] and now - lastThrow[player] < cooldown - 0.1 then return end

	local offset = target - ctx.center
	if math.abs(offset.X) > ctx.halfSize or math.abs(offset.Z) > ctx.halfSize then return end
	lastThrow[player] = now

	Meteor.spawn(ctx, Vector3.new(target.X, ctx.center.Y, target.Z), {
		radius = Config.GHOST_BLAST_RADIUS,
		warnTime = Config.GHOST_WARN_TIME,
		height = 35,
		speed = 70,
		color = Cosmetics.ghostColor(player),
		onKill = function(victim)
			if not player.Parent then return end
			if victim:GetAttribute("IsChampion") then
				PlayerData.addCoins(player, Config.GHOST_KILL_REWARD * Config.CHAMPION_BOUNTY_MULT * (player:GetAttribute("Pass_GhostKing") and 1.5 or 1))
				ctx.notify(player.DisplayName .. " took down champion " .. Util.nameOf(victim) .. "!", GOLD)
			else
				PlayerData.addCoins(player, Config.GHOST_KILL_REWARD * (player:GetAttribute("Pass_GhostKing") and 1.5 or 1))
				ctx.notify(player.DisplayName .. " got " .. Util.nameOf(victim) .. "!", Cosmetics.ghostColor(player))
			end
		end,
	})
end)

Players.PlayerRemoving:Connect(function(p)
	ghostCtx[p] = nil
	lastThrow[p] = nil
end)

return Ghosts
