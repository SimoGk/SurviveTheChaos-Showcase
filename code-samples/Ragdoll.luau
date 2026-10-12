-- Ragdoll for R15 characters (players and bots).
-- The server swaps the joints (animated joints off, ball sockets on), so every client sees the floppy body.
-- The physics owner switches the humanoid into the Physics state: the player's own client
-- (it watches the "Ragdolled" attribute on its character) or the server for bots.
local Players = game:GetService("Players")

local Ragdoll = {}

-- how far each joint may bend (degrees)
local LIMITS = {
	Neck = 40, Waist = 25,
	LeftShoulder = 85, RightShoulder = 85, LeftElbow = 60, RightElbow = 60, LeftWrist = 30, RightWrist = 30,
	LeftHip = 60, RightHip = 60, LeftKnee = 60, RightKnee = 60, LeftAnkle = 25, RightAnkle = 25,
}
local LIMBS = {
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

local tokens = {} -- character -> number (the newest ragdoll call wins)

-- Two rig types exist: the new avatar joints (AnimationConstraint + BallSocketConstraint per joint,
-- the sockets are already there) and classic Motor6D joints (we add the sockets ourselves).
local function joints(char)
	local list = {}
	for _, j in char:GetDescendants() do
		if (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) and j.Name ~= "Root" then table.insert(list, j) end
	end
	return list
end

local function partsOf(j)
	if j:IsA("Motor6D") then return j.Part0, j.Part1 end
	return j.Attachment0 and j.Attachment0.Parent, j.Attachment1 and j.Attachment1.Parent
end

-- build what's missing once per character: sockets for Motor6D rigs, no-collision between neighbours
local function setup(char)
	if char:FindFirstChild("RagdollReady") then return true end
	local list = joints(char)
	if #list == 0 then return false end
	for _, j in list do
		local p0, p1 = partsOf(j)
		if p0 and p1 then
			if j:IsA("Motor6D") then
				local a0 = Instance.new("Attachment"); a0.Name = "RagA0_" .. j.Name; a0.CFrame = j:GetAttribute("BaseC0") or j.C0; a0.Parent = p0
				local a1 = Instance.new("Attachment"); a1.Name = "RagA1_" .. j.Name; a1.CFrame = j.C1; a1.Parent = p1
				local bs = Instance.new("BallSocketConstraint")
				bs.Name = "Rag_" .. j.Name; bs.Attachment0 = a0; bs.Attachment1 = a1
				bs.LimitsEnabled = true; bs.UpperAngle = LIMITS[j.Name] or 45
				bs.TwistLimitsEnabled = true; bs.TwistLowerAngle = -25; bs.TwistUpperAngle = 25
				bs.Restitution = 0; bs.Enabled = false
				bs.Parent = j.Parent
			end
			-- neighbours never push each other apart
			local nc = Instance.new("NoCollisionConstraint")
			nc.Name = "RagNC_" .. j.Name; nc.Part0 = p0; nc.Part1 = p1; nc.Parent = j.Parent
		end
	end
	local tag = Instance.new("BoolValue"); tag.Name = "RagdollReady"; tag.Parent = char
	return true
end

local function setJoints(char, ragdolled)
	for _, j in joints(char) do
		-- the new joints: switching the AnimationConstraint off leaves the limb hanging on its ball socket
		j.Enabled = not ragdolled
		if j:IsA("Motor6D") then
			local bs = j.Parent:FindFirstChild("Rag_" .. j.Name)
			if bs then bs.Enabled = ragdolled end
		end
	end
	for _, p in char:GetChildren() do
		if p:IsA("BasePart") and LIMBS[p.Name] then p.CanCollide = ragdolled end
	end
end

function Ragdoll.isRagdolled(char)
	return char ~= nil and char:GetAttribute("Ragdolled") == true
end

-- Ragdoll `char` for `duration` seconds (nil = until death/respawn). velocity: optional fling.
function Ragdoll.start(char, duration, velocity)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or root.Anchored or not setup(char) then return false end
	local player = Players:GetPlayerFromCharacter(char)
	tokens[char] = (tokens[char] or 0) + 1
	local token = tokens[char]

	setJoints(char, true)
	char:SetAttribute("Ragdolled", true)
	if player then
		-- the loose limbs belong to the player's physics too
		for _, p in char:GetDescendants() do
			if p:IsA("BasePart") and not p.Anchored then pcall(p.SetNetworkOwner, p, player) end
		end
		if velocity then
			game:GetService("ReplicatedStorage").Remotes.Knockback:FireClient(player, velocity, true)
		end
	else
		if hum.Health > 0 then hum:ChangeState(Enum.HumanoidStateType.Physics) end
		if velocity then
			for _, p in char:GetChildren() do
				if p:IsA("BasePart") then p.AssemblyLinearVelocity = velocity end
			end
		end
	end

	if duration then
		task.delay(duration, function()
			if tokens[char] ~= token or not char.Parent then return end
			Ragdoll.stop(char)
		end)
	end
	return true
end

function Ragdoll.stop(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	tokens[char] = (tokens[char] or 0) + 1
	setJoints(char, false)
	char:SetAttribute("Ragdolled", nil)
	if not Players:GetPlayerFromCharacter(char) then
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

-- Dead bodies flop over instead of breaking apart
function Ragdoll.onDeath(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	hum.BreakJointsOnDeath = false
	hum.Died:Once(function()
		if char.Parent then Ragdoll.start(char, nil) end
	end)
end

return Ragdoll
