-- Shared cartoon UI style: chunky font, thick black outlines, gradients, 3D buttons
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Sounds = require(script.Parent.Sounds)

local UIKit = {}

UIKit.Font = Enum.Font.FredokaOne
UIKit.Outline = Color3.fromRGB(15, 15, 22)
UIKit.LIP = 6 -- height of the darker "3D" bottom edge on buttons

-- {top, bottom} gradient colors
UIKit.Palette = {
	Green = {Color3.fromRGB(150, 245, 80), Color3.fromRGB(45, 185, 40)},
	Blue = {Color3.fromRGB(100, 210, 255), Color3.fromRGB(25, 120, 235)},
	Yellow = {Color3.fromRGB(255, 230, 80), Color3.fromRGB(255, 160, 20)},
	Red = {Color3.fromRGB(255, 100, 85), Color3.fromRGB(210, 35, 40)},
	Pink = {Color3.fromRGB(255, 140, 215), Color3.fromRGB(220, 60, 170)},
	Purple = {Color3.fromRGB(195, 140, 255), Color3.fromRGB(120, 60, 230)},
	Gray = {Color3.fromRGB(175, 175, 185), Color3.fromRGB(105, 105, 120)},
	Panel = {Color3.fromRGB(75, 92, 62), Color3.fromRGB(42, 52, 36)},
	Dark = {Color3.fromRGB(55, 55, 72), Color3.fromRGB(30, 30, 42)},
}

local function darken(c, f)
	return Color3.new(c.R * f, c.G * f, c.B * f)
end

function UIKit.corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
	return c
end

-- Thick black border around a frame/button
function UIKit.outline(parent, thickness)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = UIKit.Outline
	s.Thickness = thickness or 3
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

function UIKit.gradient(parent, colors, rotation)
	local g = parent:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	if typeof(colors) == "ColorSequence" then
		g.Color = colors
	else
		g.Color = ColorSequence.new(colors[1], colors[2])
	end
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

-- Big outlined text
function UIKit.text(parent, text, opts)
	opts = opts or {}
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UIKit.Font
	l.Text = text
	l.TextColor3 = opts.color or Color3.new(1, 1, 1)
	l.TextScaled = true
	l.Size = opts.size or UDim2.new(1, 0, 1, 0)
	l.Position = opts.position or UDim2.new()
	l.TextXAlignment = opts.alignX or Enum.TextXAlignment.Center
	local s = Instance.new("UIStroke")
	s.Color = UIKit.Outline
	s.Thickness = opts.stroke or 2.5
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = opts.max or 28
	c.Parent = l
	l.Parent = parent
	return l
end

-- Panel with gradient + outline (no 3D lip)
function UIKit.surface(parent, colorName, opts)
	opts = opts or {}
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = opts.transparency or 0
	f.Size = opts.size or UDim2.new(1, 0, 1, 0)
	f.Position = opts.position or UDim2.new()
	if opts.anchor then f.AnchorPoint = opts.anchor end
	UIKit.gradient(f, UIKit.Palette[colorName])
	UIKit.corner(f, opts.radius or 14)
	UIKit.outline(f, opts.stroke or 3)
	f.Parent = parent
	return f
end

-- Recolor a button made with UIKit.button
function UIKit.setButtonColor(button, colorName)
	local pal = UIKit.Palette[colorName]
	button.BackgroundColor3 = darken(pal[2], 0.6)
	UIKit.gradient(button.Face, pal)
end

-- 3D cartoon button. Returns button, label.
function UIKit.button(parent, text, colorName, opts)
	opts = opts or {}
	local radius = opts.radius or 12
	local btn = Instance.new("TextButton")
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.Size = opts.size or UDim2.new(0, 160, 0, 60)
	btn.Position = opts.position or UDim2.new()
	if opts.anchor then btn.AnchorPoint = opts.anchor end
	UIKit.corner(btn, radius)
	UIKit.outline(btn, opts.stroke or 3)

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BackgroundColor3 = Color3.new(1, 1, 1)
	face.Size = UDim2.new(1, 0, 1, -UIKit.LIP)
	UIKit.corner(face, radius)
	face.Parent = btn

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.7
	shine.Position = UDim2.new(0, 6, 0, 4)
	shine.Size = UDim2.new(1, -12, 0.3, 0)
	UIKit.corner(shine, radius)
	shine.Parent = face

	local label = UIKit.text(face, text, {max = opts.textSize or 28, stroke = opts.textStroke or 2.5,
		size = UDim2.new(1, -12, 1, -8), position = UDim2.new(0, 6, 0, 4), color = opts.textColor})
	label.Name = "Label"
	if opts.icon then
		-- icon on the left, text next to it
		UIKit.icon(face, opts.icon, {size = UDim2.new(0.62, 0, 0.62, 0), anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, 10, 0.5, 0), stroke = opts.iconStroke or 2})
		label.Size = UDim2.new(1, -24, 1, -8)
		label.Position = UDim2.new(0, 18, 0, 4)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.3, 0)
		pad.Parent = label
	end
	UIKit.setButtonColor(btn, colorName)

	-- press + hover feedback
	local scale = Instance.new("UIScale")
	scale.Parent = btn
	local function press(down)
		face.Position = UDim2.new(0, 0, 0, down and UIKit.LIP - 2 or 0)
	end
	btn.MouseButton1Down:Connect(function() press(true) end)
	if RunService:IsClient() then
		btn.Activated:Connect(function() Sounds.playUI("Click") end)
	end
	btn.MouseButton1Up:Connect(function() press(false) end)
	btn.MouseLeave:Connect(function()
		press(false)
		TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 1}):Play()
	end)
	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 1.05}):Play()
	end)

	btn.Parent = parent
	return btn, label
end

-- Window with yellow header, title and red X. Returns window, body, closeButton.
function UIKit.window(parent, title, opts)
	opts = opts or {}
	local win = UIKit.surface(parent, "Panel", {radius = 20, stroke = 4, anchor = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0.5, 0), size = opts.size or UDim2.new(0.92, 0, 0.82, 0)})
	local maxSize = Instance.new("UISizeConstraint")
	maxSize.MaxSize = opts.maxSize or Vector2.new(760, 500)
	maxSize.Parent = win

	local header = UIKit.surface(win, "Yellow", {radius = 16, stroke = 3,
		position = UDim2.new(0, 8, 0, 8), size = UDim2.new(1, -16, 0, 62)})
	header.Name = "Header"
	local titleX = 16
	if opts.icon then
		UIKit.icon(header, opts.icon, {size = UDim2.new(0, 48, 0, 48), anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, 12, 0.5, 0), stroke = 3})
		titleX = 72
	end
	UIKit.text(header, title, {max = 42, stroke = 3.5, alignX = Enum.TextXAlignment.Left,
		size = UDim2.new(1, -titleX - 74, 1, -10), position = UDim2.new(0, titleX, 0, 5)})

	local close = UIKit.button(header, "X", "Red", {size = UDim2.new(0, 52, 0, 52), anchor = Vector2.new(1, 0.5),
		position = UDim2.new(1, -6, 0.5, 0), textSize = 34, stroke = 3})

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 14, 0, 82)
	body.Size = UDim2.new(1, -28, 1, -94)
	body.Parent = win
	return win, body, close
end

---------------------------------------------------------------- icons
-- Simple icons drawn from frames (no images/emojis needed).
-- UIKit.icon(parent, kind, {size, position, anchor, color}) -> square Frame

local function shape(parent, colorName, pos, size, radius, stroke)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.Position = pos
	f.Size = size
	if colorName then
		UIKit.gradient(f, typeof(colorName) == "table" and colorName or UIKit.Palette[colorName])
	else
		f.BackgroundTransparency = 1
	end
	if radius then
		local c = Instance.new("UICorner")
		c.CornerRadius = radius
		c.Parent = f
	end
	if stroke and stroke > 0 then UIKit.outline(f, stroke) end
	f.Parent = parent
	return f
end

local ROUND = UDim.new(1, 0)

local DRAW = {}

function DRAW.coin(root, o)
	shape(root, "Yellow", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0), ROUND, o.stroke)
	local inner = shape(root, {Color3.fromRGB(255, 245, 160), Color3.fromRGB(255, 200, 40)},
		UDim2.new(0.22, 0, 0.22, 0), UDim2.new(0.56, 0, 0.56, 0), ROUND, 0)
	local s = UIKit.outline(inner, math.max(1, o.stroke - 1)); s.Color = Color3.fromRGB(200, 120, 10)
end

function DRAW.trophy(root, o)
	-- handles (rings) behind the cup
	for _, x in {0.02, 0.62} do
		local h = shape(root, nil, UDim2.new(x, 0, 0.08, 0), UDim2.new(0.36, 0, 0.36, 0), ROUND, o.stroke + 2)
		h.UIStroke.Color = UIKit.Outline
		local h2 = shape(root, nil, UDim2.new(x, 0, 0.08, 0), UDim2.new(0.36, 0, 0.36, 0), ROUND, math.max(1, o.stroke - 1))
		h2.UIStroke.Color = Color3.fromRGB(255, 190, 30)
	end
	local cup = shape(root, "Yellow", UDim2.new(0.2, 0, 0.02, 0), UDim2.new(0.6, 0, 0.52, 0), UDim.new(0.45, 0), o.stroke)
	cup.ZIndex = 2
	shape(root, "Yellow", UDim2.new(0.42, 0, 0.5, 0), UDim2.new(0.16, 0, 0.26, 0), nil, o.stroke)
	shape(root, "Yellow", UDim2.new(0.22, 0, 0.74, 0), UDim2.new(0.56, 0, 0.22, 0), UDim.new(0.25, 0), o.stroke)
end

function DRAW.ghost(root, o)
	local body = shape(root, {o.color or Color3.new(1, 1, 1), (o.color or Color3.fromRGB(200, 200, 230)):Lerp(Color3.new(0, 0, 0), 0.25)},
		UDim2.new(0.12, 0, 0.04, 0), UDim2.new(0.76, 0, 0.9, 0), UDim.new(0.5, 0), o.stroke)
	for _, x in {0.26, 0.56} do
		local eye = shape(body, nil, UDim2.new(x, 0, 0.32, 0), UDim2.new(0.18, 0, 0.24, 0), ROUND, 0)
		eye.BackgroundTransparency = 0
		eye.BackgroundColor3 = UIKit.Outline
	end
end

function DRAW.crown(root, o)
	for i, x in {0.04, 0.38, 0.72} do
		shape(root, "Yellow", UDim2.new(x, 0, i == 2 and 0.06 or 0.18, 0), UDim2.new(0.24, 0, 0.24, 0), ROUND, o.stroke)
	end
	local band = shape(root, "Yellow", UDim2.new(0.06, 0, 0.36, 0), UDim2.new(0.88, 0, 0.5, 0), UDim.new(0.2, 0), o.stroke)
	band.ZIndex = 2
	local gem = shape(band, "Red", UDim2.new(0.4, 0, 0.25, 0), UDim2.new(0.2, 0, 0.5, 0), ROUND, math.max(1, o.stroke - 1))
	gem.ZIndex = 3
end

function DRAW.bag(root, o)
	local handle = shape(root, nil, UDim2.new(0.28, 0, 0.02, 0), UDim2.new(0.44, 0, 0.5, 0), ROUND, o.stroke + 1)
	handle.UIStroke.Color = UIKit.Outline
	shape(root, "Red", UDim2.new(0.08, 0, 0.3, 0), UDim2.new(0.84, 0, 0.66, 0), UDim.new(0.22, 0), o.stroke)
end

function DRAW.trail(root, o)
	for i, w in {0.9, 0.7, 0.5} do
		shape(root, {Color3.new(1, 1, 1), Color3.fromRGB(230, 230, 230)}, UDim2.new(1 - w, 0, 0.1 + (i - 1) * 0.3, 0),
			UDim2.new(w, 0, 0.2, 0), ROUND, o.stroke)
	end
end

function DRAW.aura(root, o)
	local ring = shape(root, nil, UDim2.new(0.1, 0, 0.1, 0), UDim2.new(0.8, 0, 0.8, 0), ROUND, o.stroke + 4)
	ring.UIStroke.Color = UIKit.Outline
	local ring2 = shape(root, nil, UDim2.new(0.1, 0, 0.1, 0), UDim2.new(0.8, 0, 0.8, 0), ROUND, o.stroke)
	ring2.UIStroke.Color = Color3.new(1, 1, 1)
	for _, p in {{0.42, 0}, {0, 0.42}, {0.84, 0.42}, {0.42, 0.84}} do
		shape(root, {Color3.new(1, 1, 1), Color3.fromRGB(230, 230, 230)}, UDim2.new(p[1], 0, p[2], 0), UDim2.new(0.16, 0, 0.16, 0), ROUND, math.max(1, o.stroke - 1))
	end
end

function DRAW.heart(root, o)
	local col = {Color3.fromRGB(255, 110, 120), Color3.fromRGB(220, 30, 60)}
	local tip = shape(root, col, UDim2.new(0.21, 0, 0.24, 0), UDim2.new(0.58, 0, 0.58, 0), UDim.new(0.12, 0), o.stroke)
	tip.Rotation = 45
	shape(root, col, UDim2.new(0.06, 0, 0.1, 0), UDim2.new(0.48, 0, 0.48, 0), UDim.new(1, 0), o.stroke)
	shape(root, col, UDim2.new(0.46, 0, 0.1, 0), UDim2.new(0.48, 0, 0.48, 0), UDim.new(1, 0), o.stroke)
	local cover = shape(root, col, UDim2.new(0.25, 0, 0.3, 0), UDim2.new(0.5, 0, 0.42, 0), UDim.new(0.2, 0), 0)
	cover.ZIndex = 2
end

function DRAW.shield(root, o)
	local s = shape(root, "Blue", UDim2.new(0.15, 0, 0.05, 0), UDim2.new(0.7, 0, 0.9, 0), UDim.new(0.35, 0), o.stroke)
	shape(s, {Color3.new(1, 1, 1), Color3.fromRGB(200, 230, 255)}, UDim2.new(0.42, 0, 0.15, 0), UDim2.new(0.16, 0, 0.7, 0), UDim.new(1, 0), 0)
end

function DRAW.gem(root, o)
	-- diamond: a rotated square with a light facet
	local d = shape(root, {Color3.fromRGB(120, 230, 255), Color3.fromRGB(40, 120, 240)}, UDim2.new(0.17, 0, 0.17, 0), UDim2.new(0.66, 0, 0.66, 0), UDim.new(0.18, 0), o.stroke)
	d.Rotation = 45
	local facet = shape(d, {Color3.fromRGB(230, 250, 255), Color3.fromRGB(150, 220, 255)}, UDim2.new(0.15, 0, 0.15, 0), UDim2.new(0.35, 0, 0.35, 0), UDim.new(0.2, 0), 0)
	facet.BackgroundTransparency = 0.15
end

function DRAW.bolt(root, o)
	-- two slanted bars = lightning bolt
	local top = shape(root, "Yellow", UDim2.new(0.32, 0, 0.02, 0), UDim2.new(0.3, 0, 0.55, 0), UDim.new(0.2, 0), o.stroke)
	top.Rotation = 20
	local bottom = shape(root, "Yellow", UDim2.new(0.38, 0, 0.43, 0), UDim2.new(0.3, 0, 0.55, 0), UDim.new(0.2, 0), o.stroke)
	bottom.Rotation = 20
	local mid = shape(root, "Yellow", UDim2.new(0.28, 0, 0.4, 0), UDim2.new(0.5, 0, 0.2, 0), UDim.new(0.2, 0), o.stroke)
	mid.Rotation = -10
	mid.ZIndex = 2
end

local WOOD = {Color3.fromRGB(230, 160, 90), Color3.fromRGB(150, 85, 35)}

function DRAW.target(root, o)
	shape(root, "Red", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0), ROUND, o.stroke)
	shape(root, {Color3.new(1, 1, 1), Color3.fromRGB(225, 225, 225)}, UDim2.new(0.2, 0, 0.2, 0), UDim2.new(0.6, 0, 0.6, 0), ROUND, math.max(1, o.stroke - 1))
	shape(root, "Red", UDim2.new(0.37, 0, 0.37, 0), UDim2.new(0.26, 0, 0.26, 0), ROUND, math.max(1, o.stroke - 1))
end

function DRAW.slingshot(root, o)
	local l = shape(root, WOOD, UDim2.new(0.2, 0, 0.06, 0), UDim2.new(0.16, 0, 0.5, 0), UDim.new(0.5, 0), o.stroke)
	l.Rotation = -22
	local r = shape(root, WOOD, UDim2.new(0.64, 0, 0.06, 0), UDim2.new(0.16, 0, 0.5, 0), UDim.new(0.5, 0), o.stroke)
	r.Rotation = 22
	local stem = shape(root, WOOD, UDim2.new(0.42, 0, 0.46, 0), UDim2.new(0.16, 0, 0.5, 0), UDim.new(0.5, 0), o.stroke)
	stem.ZIndex = 2
	local band = shape(root, "Red", UDim2.new(0.24, 0, 0.14, 0), UDim2.new(0.52, 0, 0.1, 0), UDim.new(0.5, 0), math.max(1, o.stroke - 1))
	band.ZIndex = 3
end

function DRAW.bow(root, o)
	-- right half of a thick ring = the bow, a string and an arrow
	local clip = Instance.new("Frame")
	clip.BackgroundTransparency = 1; clip.ClipsDescendants = true
	clip.Position = UDim2.new(0.42, 0, 0, 0); clip.Size = UDim2.new(0.58, 0, 1, 0)
	clip.Parent = root
	local arc = shape(clip, nil, UDim2.new(-0.62, 0, 0.06, 0), UDim2.new(1.5, 0, 0.88, 0), ROUND, o.stroke + 5)
	arc.UIStroke.Color = UIKit.Outline
	local arc2 = shape(clip, nil, UDim2.new(-0.62, 0, 0.06, 0), UDim2.new(1.5, 0, 0.88, 0), ROUND, o.stroke + 1)
	arc2.UIStroke.Color = Color3.fromRGB(150, 230, 100)
	local str = shape(root, {Color3.new(1, 1, 1), Color3.new(0.9, 0.9, 0.9)}, UDim2.new(0.47, 0, 0.08, 0), UDim2.new(0.04, 0, 0.84, 0), nil, 0)
	str.BackgroundTransparency = 0
	local arrow = shape(root, WOOD, UDim2.new(0.04, 0, 0.45, 0), UDim2.new(0.86, 0, 0.1, 0), UDim.new(0.5, 0), math.max(1, o.stroke - 1))
	arrow.ZIndex = 2
	local tip = shape(root, {Color3.fromRGB(230, 230, 240), Color3.fromRGB(150, 150, 170)}, UDim2.new(0.8, 0, 0.4, 0), UDim2.new(0.16, 0, 0.2, 0), UDim.new(0.2, 0), math.max(1, o.stroke - 1))
	tip.Rotation = 45; tip.ZIndex = 3
end

function DRAW.crossbow(root, o)
	local stock = shape(root, WOOD, UDim2.new(0.42, 0, 0.2, 0), UDim2.new(0.16, 0, 0.76, 0), UDim.new(0.3, 0), o.stroke)
	local limb = shape(root, "Blue", UDim2.new(0.06, 0, 0.26, 0), UDim2.new(0.88, 0, 0.16, 0), UDim.new(0.5, 0), o.stroke)
	limb.ZIndex = 2
	local bolt = shape(root, {Color3.fromRGB(230, 230, 240), Color3.fromRGB(150, 150, 170)}, UDim2.new(0.44, 0, 0.02, 0), UDim2.new(0.12, 0, 0.3, 0), UDim.new(0.5, 0), math.max(1, o.stroke - 1))
	bolt.ZIndex = 3
	stock.ZIndex = 1
end

function DRAW.blaster(root, o)
	local barrel = shape(root, {Color3.fromRGB(200, 200, 215), Color3.fromRGB(110, 110, 130)}, UDim2.new(0.5, 0, 0.26, 0), UDim2.new(0.46, 0, 0.2, 0), UDim.new(0.4, 0), o.stroke)
	local body = shape(root, "Purple", UDim2.new(0.06, 0, 0.18, 0), UDim2.new(0.58, 0, 0.36, 0), UDim.new(0.3, 0), o.stroke)
	body.ZIndex = 2
	local grip = shape(root, "Purple", UDim2.new(0.12, 0, 0.44, 0), UDim2.new(0.2, 0, 0.46, 0), UDim.new(0.3, 0), o.stroke)
	grip.Rotation = -12
	local glow = shape(root, {Color3.fromRGB(255, 200, 255), Color3.fromRGB(255, 90, 255)}, UDim2.new(0.86, 0, 0.24, 0), UDim2.new(0.14, 0, 0.24, 0), ROUND, math.max(1, o.stroke - 1))
	glow.ZIndex = 3
end

function DRAW.star(root, o)
	for _, rot in {0, 45} do
		local s = shape(root, "Yellow", UDim2.new(0.17, 0, 0.17, 0), UDim2.new(0.66, 0, 0.66, 0), UDim.new(0.12, 0), o.stroke)
		s.Rotation = rot
	end
	local c = shape(root, {Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 210, 60)}, UDim2.new(0.3, 0, 0.3, 0), UDim2.new(0.4, 0, 0.4, 0), ROUND, 0)
	c.ZIndex = 2
end

-- Painted icons (tools/draw_icons.ps1 in the repo), uploaded to Roblox
UIKit.IconImages = {
	coin = "rbxassetid://79196620485623", gem = "rbxassetid://95062803556394", heart = "rbxassetid://82434885536770",
	shield = "rbxassetid://122164622790186", star = "rbxassetid://137066561024812", bolt = "rbxassetid://76451524906277",
	trophy = "rbxassetid://128918445646232", crown = "rbxassetid://96677716896060", ghost = "rbxassetid://95799752146824",
	bag = "rbxassetid://72782200882557", trail = "rbxassetid://110294079541171", aura = "rbxassetid://124322449459303",
	target = "rbxassetid://136600022717791", slingshot = "rbxassetid://108069828891403", bow = "rbxassetid://117121008234423",
	crossbow = "rbxassetid://79182176653222", blaster = "rbxassetid://71280909155664", meteor = "rbxassetid://102430115279870",
	wind = "rbxassetid://123605748171335", snowflake = "rbxassetid://91392140740104", gift = "rbxassetid://117838594951654",
	potion = "rbxassetid://129568027125679", xp = "rbxassetid://72143148062869", rebirth = "rbxassetid://127885273893453",
	lock = "rbxassetid://108803545955268", clock = "rbxassetid://76227260696118", rocket = "rbxassetid://115622103239172",
	potion_speed = "rbxassetid://130356825475336", potion_jump = "rbxassetid://102671447998619", potion_life = "rbxassetid://98215239966066",
	potion_shield = "rbxassetid://98551089656886", potion_luck = "rbxassetid://72874031935106", potion_xp = "rbxassetid://98163970530932",
	shield_crystal = "rbxassetid://134302917473140", shield_lava = "rbxassetid://114143171858575", shield_royal = "rbxassetid://88497274030644",
	boomerang = "rbxassetid://113457150667940", staff = "rbxassetid://136001721553900", superrebirth = "rbxassetid://104769429889031",
	prestige = "rbxassetid://77604636684657", robot = "rbxassetid://86970002523561", offer = "rbxassetid://112691397255500",
	candy = "rbxassetid://89932392225989", pumpkin = "rbxassetid://73738166976051",
	fist = "rbxassetid://123072409346215", bat = "rbxassetid://90908014403546", pan = "rbxassetid://106015264857958",
	sword = "rbxassetid://129880593447256", hammer = "rbxassetid://87224486713067", blade = "rbxassetid://81852376751588",
	scythe = "rbxassetid://76221171427729", banhammer = "rbxassetid://98428223683576", hand = "rbxassetid://79012604734478",
	skull = "rbxassetid://76207245925134", friends = "rbxassetid://120808160326311", globe = "rbxassetid://120428368678643",
	play = "rbxassetid://103289836520366", flag = "rbxassetid://132822733994627", helmet = "rbxassetid://119714434535031",
	shirt = "rbxassetid://101096958911866", shoe = "rbxassetid://135355474152126", flame = "rbxassetid://94199231353899",
}

-- Icon by name. opts: size, position, anchor, color (tints the ghost icon only), stroke (fallback drawing)
function UIKit.icon(parent, kind, opts)
	opts = opts or {}
	local image = UIKit.IconImages[kind]
	local root = Instance.new(image and "ImageLabel" or "Frame")
	root.Name = "Icon"
	root.BackgroundTransparency = 1
	root.Size = opts.size or UDim2.new(0, 40, 0, 40)
	root.Position = opts.position or UDim2.new()
	if opts.anchor then root.AnchorPoint = opts.anchor end
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.Parent = root
	if image then
		root.Image = image
		root.ScaleType = Enum.ScaleType.Fit
		if kind == "ghost" and opts.color then root.ImageColor3 = Color3.new(1, 1, 1):Lerp(opts.color, 0.6) end
	else
		local draw = DRAW[kind]
		if draw then draw(root, {stroke = opts.stroke or 2, color = opts.color}) end
	end
	root.Parent = parent
	return root
end

-- Shrinks a whole ScreenGui on small screens (phones) so nothing overlaps.
-- The UI was designed for ~720px of screen height; smaller screens scale down proportionally.
UIKit.DESIGN_HEIGHT = 720
UIKit.MIN_SCALE = 0.55
function UIKit.autoScale(screenGui)
	local scale = Instance.new("UIScale")
	scale.Name = "AutoScale"
	scale.Parent = screenGui
	local function update()
		local camera = workspace.CurrentCamera
		if not camera then return end
		scale.Scale = math.clamp(camera.ViewportSize.Y / UIKit.DESIGN_HEIGHT, UIKit.MIN_SCALE, 1)
	end
	update()
	local conn
	local function hook()
		if conn then conn:Disconnect() end
		if workspace.CurrentCamera then
			conn = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end
	hook()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
	return scale
end

-- Progress bar (dark track + gradient fill). Returns track, fill.
function UIKit.bar(parent, colorName, opts)
	opts = opts or {}
	local track = UIKit.surface(parent, "Dark", {radius = 10, stroke = 3, size = opts.size, position = opts.position, anchor = opts.anchor})
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.Size = UDim2.new(1, 0, 1, 0)
	UIKit.gradient(fill, UIKit.Palette[colorName])
	UIKit.corner(fill, 10)
	fill.Parent = track
	return track, fill
end

return UIKit
