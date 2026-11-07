-- aimbot.lua  (Y1 Combat tab: the aimbot, as its own module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the aimbot INTO the Combat tab of ui.lua (win.CombatPage). It makes no window of its own.
-- ui.lua already loads it through opts.CombatModule, so nothing in ui.lua has to change.
--
--   local Aimbot = <this file>
--   Aimbot.build(parentFrame, themeTable, helperTable, opts)
--
--   Aim Type   Mouse  = the camera turns so the target moves toward your CURSOR
--                         (also works with a locked cursor: first person / shift lock = screen middle)
--              Camera = the camera turns so the target moves to the SCREEN MIDDLE
--   Mode       Hold = on while the key is held, Toggle = press to switch on / off
--   Target     Head / Torso / Arms / Legs
--   Lock       ON = stay on one target until it dies / leaves range / you let go
--   Distance   Min / Max studs
--   Prediction X / Y  0-20   aim point += velocity * value * 0.01 s
--   Smoothness X / Y  0-20   0 = instant, higher = slower
--
-- The aimbot switches itself off and cleans up when the Y1 window is unloaded.

local AimbotPage = {}

function AimbotPage.build(parent, T, H, opts)
	opts = opts or {}

	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local player = Players.LocalPlayer

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label

	local FAST = T.FAST
	local SMOOTH = T.SMOOTH
	local RADIUS = T.RADIUS
	local PILL_ON_BG = Color3.fromRGB(22, 52, 38)
	local PILL_ON_LINE = Color3.fromRGB(36, 92, 62)

	-- every render step gets its own name, so a re-run can never unbind a newer copy
	local STEP_NAME = string.format("Y1AimbotStep_%d_%d", math.floor(os.clock() * 1000), math.random(1, 1000000))

	---------------------------------------------------------------------
	-- SETTINGS + STATE
	---------------------------------------------------------------------
	local S = {
		enabled = true,
		keybind = Enum.UserInputType.MouseButton2,
		mode = "Hold",
		aim = "Mouse",
		part = "Head",
		lockOn = false,
		minDist = 0,
		maxDist = 1000,
		predOn = false,
		predX = 0,
		predY = 0,
		smoothOn = false,
		smoothX = 0,
		smoothY = 0,
	}

	local MAX_VALUE = 20
	local STEP = 0.5

	local active = false
	local locked = nil
	local listening = nil
	local running = true
	local conns = {}
	local setActive = function(_v) end

	local function bindName(b)
		if b == Enum.UserInputType.MouseButton1 then
			return "Mouse 1"
		elseif b == Enum.UserInputType.MouseButton2 then
			return "Mouse 2"
		elseif b == Enum.UserInputType.MouseButton3 then
			return "Mouse 3"
		end
		return b.Name
	end

	local function matches(input, bind)
		if bind.EnumType == Enum.KeyCode then
			return input.KeyCode == bind
		end
		return input.UserInputType == bind
	end

	---------------------------------------------------------------------
	-- PAGE LAYOUT: a scrolling page, a header card, then two columns of cards
	---------------------------------------------------------------------
	local scroll = new("ScrollingFrame", {
		Name = "AimbotRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.ICON,
		ScrollBarImageTransparency = 0.5,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ElasticBehavior = Enum.ElasticBehavior.Never,
	}, parent)

	local HEADER_H = 58
	local BODY_Y = 2 + HEADER_H + 14
	local GAP = 8

	local header = new("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -12, 0, HEADER_H),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
	}, scroll)
	corner(header, RADIUS + 4)
	stroke(header, T.BORDER, 1, 0)

	local body = new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(2, BODY_Y),
		Size = UDim2.new(1, -12, 0, 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, scroll)

	local colY = { 0, 0 }

	-- a card in column 1 (left) or 2 (right), stacked under the previous one
	local function place(col, h)
		local f = new("Frame", {
			Position = UDim2.new((col - 1) * 0.5, (col - 1) * 6, 0, colY[col]),
			Size = UDim2.new(0.5, -6, 0, h),
			BackgroundColor3 = T.SIDEBAR_BG,
			BorderSizePixel = 0,
		}, body)
		corner(f, RADIUS + 4)
		stroke(f, T.BORDER, 1, 0)
		colY[col] = colY[col] + h + GAP
		return f
	end

	-- small dim header above a group of cards (same style as the Settings page)
	local function section(col, text)
		label(body, text, UDim2.new((col - 1) * 0.5, (col - 1) * 6 + 2, 0, colY[col]),
			UDim2.new(0.5, -10, 0, 14), Enum.Font.GothamMedium, 11, T.DIM_TEXT)
		colY[col] = colY[col] + 22
	end

	---------------------------------------------------------------------
	-- CONTROLS
	---------------------------------------------------------------------
	local function makeSwitch(c, startOn, onChange, cy)
		local on = startOn
		local track = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0, cy),
			Size = UDim2.fromOffset(38, 20),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, c)
		corner(track, 100)
		stroke(track, T.BORDER, 1, 0)

		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = T.DIM_TEXT,
			BorderSizePixel = 0,
		}, track)
		corner(knob, 100)

		local function paint(animate)
			local pos = UDim2.new(0, 3, 0.5, 0)
			local trackColor = T.CLUSTER_BG
			local knobColor = T.DIM_TEXT
			if on then
				pos = UDim2.new(0, 21, 0.5, 0)
				trackColor = T.JOIN_BG
				knobColor = T.BLACK
			end
			if animate then
				TweenService:Create(knob, SMOOTH, { Position = pos }):Play()
			else
				knob.Position = pos
			end
			TweenService:Create(knob, FAST, { BackgroundColor3 = knobColor }):Play()
			TweenService:Create(track, FAST, { BackgroundColor3 = trackColor }):Play()
		end
		paint(false)

		track.Activated:Connect(function()
			on = not on
			paint(true)
			onChange(on)
		end)
	end

	-- title + sub text on the left, a button on the right that records the next key / mouse button
	local function bindRow(col, title, sub, getBind, setBind, allowMouse)
		local c = place(col, 46)
		label(c, title, UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		label(c, sub, UDim2.fromOffset(14, 25), UDim2.new(1, -140, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)

		local btn = new("TextButton", {
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(100, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = T.ICON_HOVER,
			Text = bindName(getBind()),
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, c)
		corner(btn, RADIUS + 2)

		local over = false
		local function paint()
			local bg = T.CLUSTER_BG
			if over or (listening and listening.btn == btn) then
				bg = T.HOVER_GREY
			end
			TweenService:Create(btn, FAST, { BackgroundColor3 = bg }):Play()
		end
		btn.MouseEnter:Connect(function()
			over = true
			paint()
		end)
		btn.MouseLeave:Connect(function()
			over = false
			paint()
		end)
		btn.Activated:Connect(function()
			if listening and listening.btn == btn then
				listening = nil
				btn.Text = bindName(getBind())
			else
				if listening then
					listening.btn.Text = listening.restore()
				end
				listening = {
					btn = btn,
					allowMouse = allowMouse,
					set = function(b)
						setBind(b)
						btn.Text = bindName(b)
					end,
					restore = function()
						return bindName(getBind())
					end,
				}
				btn.Text = "Press a key..."
			end
			paint()
		end)
	end

	-- a row of options with a sliding highlight
	local function segmented(col, title, options, startValue, onChange)
		local c = place(col, 62)
		label(c, title, UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 12),
			Enum.Font.Gotham, 11, T.DIM_TEXT)

		local tray = new("Frame", {
			Position = UDim2.fromOffset(12, 26),
			Size = UDim2.new(1, -24, 0, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, c)
		corner(tray, RADIUS + 2)

		local inner = new("Frame", {
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.new(1, -6, 1, -6),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, tray)

		local n = #options
		local slider = new("Frame", {
			Size = UDim2.new(1 / n, 0, 1, 0),
			BackgroundColor3 = T.HOVER_GREY,
			BorderSizePixel = 0,
		}, inner)
		corner(slider, 4)

		local buttons = {}
		local function choose(index, animate)
			local pos = UDim2.new((index - 1) / n, 0, 0, 0)
			if animate then
				TweenService:Create(slider, SMOOTH, { Position = pos }):Play()
			else
				slider.Position = pos
			end
			for i = 1, n do
				local colr = T.ICON
				if i == index then
					colr = T.ICON_HOVER
				end
				TweenService:Create(buttons[i], FAST, { TextColor3 = colr }):Play()
			end
		end

		local current = 1
		for i = 1, n do
			if options[i] == startValue then
				current = i
			end
		end

		for i = 1, n do
			local b = new("TextButton", {
				AutoButtonColor = false,
				Position = UDim2.new((i - 1) / n, 0, 0, 0),
				Size = UDim2.new(1 / n, 0, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = options[i],
				TextColor3 = T.ICON,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
			}, inner)
			buttons[i] = b
			b.Activated:Connect(function()
				if current == i then
					return
				end
				current = i
				choose(i, true)
				onChange(options[i])
			end)
		end
		choose(current, false)
	end

	-- a slider row inside a card; returns { dim = fn(enabled), set = fn(value) }
	local function makeSlider(c, y, name, labelW, minV, maxV, stepV, startValue, fmt, setValue)
		label(c, name, UDim2.fromOffset(14, y), UDim2.fromOffset(labelW, 20),
			Enum.Font.GothamMedium, 12, T.ICON)
		local valueLabel = label(c, "", UDim2.new(1, -52, 0, y), UDim2.fromOffset(40, 20),
			Enum.Font.GothamMedium, 12, T.TEXT_COLOR, Enum.TextXAlignment.Right)

		local x0 = 14 + labelW + 6

		local track = new("Frame", {
			Position = UDim2.fromOffset(x0, y + 7),
			Size = UDim2.new(1, -(x0 + 60), 0, 6),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, c)
		corner(track, 3)

		local fill = new("Frame", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = T.DIM_TEXT,
			BorderSizePixel = 0,
		}, track)
		corner(fill, 3)

		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = T.ICON_HOVER,
			BorderSizePixel = 0,
		}, track)
		corner(knob, 100)

		local hit = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(x0, y),
			Size = UDim2.new(1, -(x0 + 60), 0, 20),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, c)

		local value = startValue
		local dragging = false

		local function refresh()
			local f = (value - minV) / (maxV - minV)
			fill.Size = UDim2.new(f, 0, 1, 0)
			knob.Position = UDim2.new(f, 0, 0.5, 0)
			valueLabel.Text = string.format(fmt, value)
		end
		refresh()

		local function setFromX(px)
			local w = hit.AbsoluteSize.X
			if w <= 0 then
				return
			end
			local f = math.clamp((px - hit.AbsolutePosition.X) / w, 0, 1)
			value = minV + math.floor(f * (maxV - minV) / stepV + 0.5) * stepV
			setValue(value)
			refresh()
		end

		hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				setFromX(input.Position.X)
			end
		end)
		conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
			if not dragging then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				setFromX(input.Position.X)
			end
		end)
		conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)

		local api = {}
		function api.dim(enabled)
			local colr = T.DIM_TEXT
			if enabled then
				colr = T.ICON_HOVER
			end
			TweenService:Create(fill, FAST, { BackgroundColor3 = colr }):Play()
		end
		function api.set(v)
			value = v
			refresh()
		end
		return api
	end

	-- a card with a switch on top and an X and a Y slider under it
	local function switchSliders(col, title, startOn, startX, startY, onSwitch, setX, setY)
		local c = place(col, 106)
		label(c, title, UDim2.fromOffset(14, 0), UDim2.new(1, -70, 0, 38),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		local sx = makeSlider(c, 40, "X", 16, 0, MAX_VALUE, STEP, startX, "%.1f", setX)
		local sy = makeSlider(c, 72, "Y", 16, 0, MAX_VALUE, STEP, startY, "%.1f", setY)
		sx.dim(startOn)
		sy.dim(startOn)
		makeSwitch(c, startOn, function(on)
			sx.dim(on)
			sy.dim(on)
			onSwitch(on)
		end, 19)
	end

	---------------------------------------------------------------------
	-- HEADER: title, status pill and the master switch
	---------------------------------------------------------------------
	label(header, "Aimbot", UDim2.fromOffset(14, 11), UDim2.new(1, -150, 0, 18),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)
	label(header, "Hold the aim key to lock onto a target", UDim2.fromOffset(14, 31), UDim2.new(1, -150, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)

	local pill = new("Frame", {
		Name = "StatusPill",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -66, 0.5, 0),
		Size = UDim2.fromOffset(54, 22),
		BackgroundColor3 = T.CLUSTER_BG,
		BorderSizePixel = 0,
	}, header)
	corner(pill, 11)
	local pillStroke = stroke(pill, T.BORDER, 1, 0)
	local pillText = label(pill, "Idle", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1),
		Enum.Font.GothamBold, 11, T.DIM_TEXT, Enum.TextXAlignment.Center)

	local function refreshStatus()
		local text = "Idle"
		local isOn = false
		if not S.enabled then
			text = "Off"
		elseif active then
			text = "Active"
			isOn = true
		end
		pillText.Text = text
		local bg = T.CLUSTER_BG
		local line = T.BORDER
		local txt = T.DIM_TEXT
		if isOn then
			bg = PILL_ON_BG
			line = PILL_ON_LINE
			txt = T.GREEN
		end
		TweenService:Create(pill, FAST, { BackgroundColor3 = bg }):Play()
		TweenService:Create(pillStroke, FAST, { Color = line }):Play()
		TweenService:Create(pillText, FAST, { TextColor3 = txt }):Play()
	end

	setActive = function(v)
		if not S.enabled then
			v = false
		end
		active = v
		if not v then
			locked = nil
		end
		refreshStatus()
	end

	makeSwitch(header, S.enabled, function(on)
		S.enabled = on
		setActive(false)
		refreshStatus()
	end, HEADER_H / 2)

	---------------------------------------------------------------------
	-- BUILD THE CARDS
	---------------------------------------------------------------------
	-- left column
	section(1, "AIMING")

	bindRow(1, "Aim Key", "Click, then press a key",
		function() return S.keybind end,
		function(b)
			S.keybind = b
			setActive(false)
		end,
		true)

	segmented(1, "Mode", { "Hold", "Toggle" }, S.mode, function(v)
		S.mode = v
		setActive(false)
	end)

	segmented(1, "Aim Type", { "Mouse", "Camera" }, S.aim, function(v)
		S.aim = v
	end)

	segmented(1, "Target", { "Head", "Torso", "Arms", "Legs" }, S.part, function(v)
		S.part = v
	end)

	do
		local c = place(1, 46)
		label(c, "Target Lock", UDim2.fromOffset(14, 7), UDim2.new(1, -80, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		label(c, "Stay on one target until it is gone", UDim2.fromOffset(14, 25), UDim2.new(1, -80, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		makeSwitch(c, S.lockOn, function(on)
			S.lockOn = on
			locked = nil
		end, 23)
	end

	-- right column
	section(2, "RANGE")

	do
		local c = place(2, 104)
		label(c, "Distance (studs)", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 0, 36),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		local minApi = nil
		local maxApi = nil
		minApi = makeSlider(c, 38, "Min", 28, 0, 1000, 5, S.minDist, "%d", function(v)
			S.minDist = v
			if S.maxDist < v then
				S.maxDist = v
				maxApi.set(v)
			end
		end)
		maxApi = makeSlider(c, 68, "Max", 28, 0, 1000, 5, S.maxDist, "%d", function(v)
			S.maxDist = v
			if S.minDist > v then
				S.minDist = v
				minApi.set(v)
			end
		end)
		minApi.dim(true)
		maxApi.dim(true)
	end

	section(2, "ASSIST")

	switchSliders(2, "Prediction", S.predOn, S.predX, S.predY,
		function(on) S.predOn = on end,
		function(v) S.predX = v end,
		function(v) S.predY = v end)

	switchSliders(2, "Smoothness", S.smoothOn, S.smoothX, S.smoothY,
		function(on) S.smoothOn = on end,
		function(v) S.smoothX = v end,
		function(v) S.smoothY = v end)

	-- size the page to its content
	do
		local bodyH = math.max(colY[1], colY[2]) - GAP
		body.Size = UDim2.new(1, -12, 0, bodyH)
		scroll.CanvasSize = UDim2.new(0, 0, 0, BODY_Y + bodyH + 8)
	end

	---------------------------------------------------------------------
	-- TARGETING
	---------------------------------------------------------------------
	local PARTS = {
		Head = { names = { "Head" }, nearest = false },
		Torso = { names = { "UpperTorso", "Torso", "HumanoidRootPart" }, nearest = false },
		Arms = { names = { "RightUpperArm", "LeftUpperArm", "Right Arm", "Left Arm" }, nearest = true },
		Legs = { names = { "RightUpperLeg", "LeftUpperLeg", "Right Leg", "Left Leg" }, nearest = true },
	}

	-- the screen point we measure "near" from: the cursor (Mouse) or the middle of the screen (Camera)
	local function refPoint(cam)
		local vs = cam.ViewportSize
		-- Camera mode, and any time the mouse is locked to the middle (shift lock, first person):
		-- the "cursor" is the screen middle. GetMouseLocation can return a stale position while
		-- the mouse is locked, so we do not trust it in that case.
		if S.aim == "Camera" or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			return Vector2.new(vs.X / 2, vs.Y / 2)
		end
		return UserInputService:GetMouseLocation()
	end

	local function originPos(cam)
		local char = player.Character
		local root = nil
		if char then
			root = char:FindFirstChild("HumanoidRootPart")
		end
		if root then
			return root.Position
		end
		return cam.CFrame.Position
	end

	local function validTarget(plr, origin)
		if plr.Parent == nil then
			return false
		end
		local char = plr.Character
		if not char then
			return false
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum == nil or hum.Health <= 0 then
			return false
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if root == nil then
			return false
		end
		local d = (root.Position - origin).Magnitude
		return d >= S.minDist and d <= S.maxDist
	end

	local function bestPart(char, cam, ref, needScreen)
		local def = PARTS[S.part]
		local best = nil
		local bestD = nil
		for i = 1, #def.names do
			local p = char:FindFirstChild(def.names[i])
			if p and p:IsA("BasePart") then
				local v, onScreen = cam:WorldToViewportPoint(p.Position)
				local d = 1e9
				if onScreen then
					d = (Vector2.new(v.X, v.Y) - ref).Magnitude
				end
				if onScreen or not needScreen then
					if best == nil or d < bestD then
						best = p
						bestD = d
					end
					if not def.nearest then
						break
					end
				end
			end
		end
		return best, bestD
	end

	local function acquire(cam, ref, origin)
		local bestPlr = nil
		local bestD = nil
		local all = Players:GetPlayers()
		for i = 1, #all do
			local plr = all[i]
			if plr ~= player and validTarget(plr, origin) then
				local part, d = bestPart(plr.Character, cam, ref, true)
				if part and (bestD == nil or d < bestD) then
					bestPlr = plr
					bestD = d
				end
			end
		end
		return bestPlr
	end

	local function alphaFor(s, dt)
		if not S.smoothOn then
			return 1
		end
		local a = 1 / (1 + s)
		return 1 - (1 - a) ^ (dt * 60)
	end

	local function yawOf(v)
		return math.atan2(-v.X, -v.Z)
	end

	local function pitchOf(v)
		return math.asin(math.clamp(v.Y, -1, 1))
	end

	local function step(dt)
		if not running or not active then
			return
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end

		local ref = refPoint(cam)
		local origin = originPos(cam)

		-- pick the target
		if S.lockOn then
			if locked and not validTarget(locked, origin) then
				locked = nil
			end
			if locked == nil then
				locked = acquire(cam, ref, origin)
			end
		else
			locked = acquire(cam, ref, origin)
		end
		if locked == nil or locked.Character == nil then
			return
		end

		local part = bestPart(locked.Character, cam, ref, false)
		if part == nil then
			return
		end

		local pos = part.Position
		if S.predOn then
			local v = part.AssemblyLinearVelocity
			pos = pos + Vector3.new(v.X * S.predX, v.Y * S.predY, v.Z * S.predX) * 0.01
		end

		local camCF = cam.CFrame
		local toTarget = pos - camCF.Position
		if toTarget.Magnitude < 0.001 then
			return
		end
		toTarget = toTarget.Unit

		-- the direction that should end up on the target:
		--   Camera = where the camera looks (screen middle)
		--   Mouse  = the ray through the cursor
		local refDir = camCF.LookVector
		if S.aim == "Mouse" then
			local ray = cam:ViewportPointToRay(ref.X, ref.Y)
			refDir = ray.Direction.Unit
		end

		-- how far the target direction is from the reference direction, as yaw and pitch angles
		local dYaw = yawOf(toTarget) - yawOf(refDir)
		while dYaw > math.pi do
			dYaw = dYaw - 2 * math.pi
		end
		while dYaw < -math.pi do
			dYaw = dYaw + 2 * math.pi
		end
		local dPitch = pitchOf(toTarget) - pitchOf(refDir)

		local ax = alphaFor(S.smoothX, dt)
		local ay = alphaFor(S.smoothY, dt)

		-- turn the camera by that error (works in a normal game, no cursor movement needed)
		local look = camCF.LookVector
		local yaw = yawOf(look) + dYaw * ax
		local pitch = math.clamp(pitchOf(look) + dPitch * ay, -1.5, 1.5)
		cam.CFrame = CFrame.new(camCF.Position) * CFrame.fromOrientation(pitch, yaw, 0)
	end

	pcall(function()
		RunService:UnbindFromRenderStep(STEP_NAME)
	end)
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, step)

	---------------------------------------------------------------------
	-- INPUT
	---------------------------------------------------------------------
	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if not running then
			return
		end

		-- recording a new key for one of the bind buttons
		if listening then
			local L = listening
			local it = input.UserInputType
			if input.KeyCode == Enum.KeyCode.Escape then
				L.btn.Text = L.restore()
				listening = nil
				return
			end
			if it == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
				L.set(input.KeyCode)
				listening = nil
				return
			end
			if L.allowMouse and (it == Enum.UserInputType.MouseButton1
				or it == Enum.UserInputType.MouseButton2
				or it == Enum.UserInputType.MouseButton3) then
				L.set(it)
				listening = nil
				return
			end
			return
		end

		if not S.enabled or not matches(input, S.keybind) then
			return
		end

		-- right / middle mouse are often "processed" by the default camera script, so those two
		-- ignore the flag. Keys and left mouse respect it (typing in chat, clicking a button).
		local ignoreProcessed = (S.keybind == Enum.UserInputType.MouseButton2
			or S.keybind == Enum.UserInputType.MouseButton3)
		if processed and not ignoreProcessed then
			return
		end

		if S.mode == "Hold" then
			setActive(true)
		else
			setActive(not active)
		end
	end)

	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		if running and S.mode == "Hold" and matches(input, S.keybind) then
			setActive(false)
		end
	end)

	---------------------------------------------------------------------
	-- UNLOAD (runs when the Y1 window is unloaded)
	---------------------------------------------------------------------
	local function unload()
		if not running then
			return
		end
		running = false
		active = false
		locked = nil
		listening = nil
		pcall(function()
			RunService:UnbindFromRenderStep(STEP_NAME)
		end)
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
	end

	-- the window destroys its gui when it unloads: that takes this page with it
	conns[#conns + 1] = scroll.AncestryChanged:Connect(function()
		if not scroll:IsDescendantOf(game) then
			unload()
		end
	end)

	-- ui.lua versions that offer a hook can call it directly as well
	if type(opts.OnUnload) == "function" then
		opts.OnUnload(unload)
	end

	return { Root = scroll, Unload = unload }
end

return AimbotPage
