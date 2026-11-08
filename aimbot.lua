-- aimbot.lua  (Y1 Combat tab: Aimbot + Silent aim, as its own module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Combat tab INTO win.CombatPage. It makes no window of its own.
-- ui.lua already loads it through opts.CombatModule, so nothing in ui.lua has to change.
--
--   local Aimbot = <this file>
--   Aimbot.build(parentFrame, themeTable, helperTable, opts)
--
-- At the BOTTOM of the tab there is a small switch: [ Aimbot | Silent ]. It swaps the page above it.
--
-- AIMBOT page
--   Enable row   a switch and a "..." (three dots) button. The dots open one small settings panel
--                (Key, Mode, Aim Type, Target Lock). Click the dots again, or anywhere else, to close it.
--   Hit Part     a drop-down (click it, pick from the vertical list, click anywhere else to close it)
--                Head (default) / Body / Left Leg / Right Leg / Left Arm / Right Arm / Closest Part
--   Distance     Min / Max
--   Prediction / Smoothness   X / Y  0-20
--
--   Aim Type   Mouse  = MOVES THE CURSOR (mousemoverel) toward the target. The camera is not touched.
--                       Only while the mouse is locked (shift lock, first person, or holding the right
--                       mouse button to look around) the cursor cannot move, so then and only then the
--                       camera is turned instead, so the target ends up under the locked cursor / crosshair.
--              Camera = the camera turns so the target moves to the SCREEN MIDDLE
--   Mode       Hold = on while the key is held, Toggle = press to switch on / off
--
-- SILENT page (no key, nothing moves: the game is told you aimed at the target)
--   Enable       on = always working. The small line shows the current target.
--   Hit Part     same drop-down as above
--   Distance     Min / Max
--   Prediction   X / Y
--   FOV          Show circle switch + Size (pixels around your cursor, only players inside it are picked)
--   Needs an executor with hookmetamethod, getnamecallmethod and checkcaller. If it is missing the
--   Enable row says "Executor not supported".
--
-- Everything switches itself off and cleans up when the Y1 window is unloaded.

local AimbotPage = {}

function AimbotPage.build(parent, T, H, opts)
	opts = opts or {}

	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label

	local FAST = T.FAST
	local SMOOTH = T.SMOOTH
	local RADIUS = T.RADIUS

	-- every render step gets its own name, so a re-run can never unbind a newer copy
	local STEP_NAME = string.format("Y1AimbotStep_%d_%d", math.floor(os.clock() * 1000), math.random(1, 1000000))

	---------------------------------------------------------------------
	-- SETTINGS + STATE
	---------------------------------------------------------------------
	local PART_OPTIONS = { "Head", "Body", "Left Leg", "Right Leg", "Left Arm", "Right Arm", "Closest Part" }

	-- the first name that exists on the character is used (R15 names first, then R6 names)
	local PART_NAMES = {
		["Head"] = { "Head" },
		["Body"] = { "UpperTorso", "Torso", "HumanoidRootPart" },
		["Left Leg"] = { "LeftUpperLeg", "Left Leg" },
		["Right Leg"] = { "RightUpperLeg", "Right Leg" },
		["Left Arm"] = { "LeftUpperArm", "Left Arm" },
		["Right Arm"] = { "RightUpperArm", "Right Arm" },
	}

	-- "Closest Part" looks at all of these and takes the one nearest to the cursor / screen middle
	local CLOSEST_NAMES = {
		"Head", "UpperTorso", "LowerTorso", "Torso",
		"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
		"Left Arm", "Right Arm", "Left Leg", "Right Leg",
	}

	-- aimbot settings
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

	-- silent aim settings
	local SIL = {
		enabled = false,
		part = "Head",
		minDist = 0,
		maxDist = 1000,
		predOn = false,
		predX = 0,
		predY = 0,
		fov = 250,
		showFov = true,
	}

	local MAX_VALUE = 20
	local STEP = 0.5

	local active = false
	local locked = nil
	local listening = nil
	local running = true
	local conns = {}
	local setActive = function(_v) end
	local popupList = {}      -- every popup registers here so one click outside can close them all
	local accX = 0            -- leftover (sub-pixel) cursor movement
	local accY = 0
	local warnedMove = false

	-- the executor function that moves the real cursor (nil when it does not have one)
	local moveRel = nil
	do
		local okM, fnM = pcall(function()
			return mousemoverel
		end)
		if okM and type(fnM) == "function" then
			moveRel = fnM
		end
	end

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

	local function closeAllPopups()
		for i = 1, #popupList do
			local pp = popupList[i]
			if pp.isOpen() then
				pp.close()
			end
		end
	end

	-- true when the pointer of this input is over a gui object.
	-- Mouse: GetMouseLocation is in the same screen space as AbsolutePosition (the window gui
	-- ignores the top inset), so no inset maths is needed. Touch: the input position may or may not
	-- include the top inset on a given device, so both readings are tried.
	local function inRect(obj, x, y)
		local p = obj.AbsolutePosition
		local sz = obj.AbsoluteSize
		return x >= p.X and x <= p.X + sz.X and y >= p.Y and y <= p.Y + sz.Y
	end

	local function pointerOver(obj, input)
		if input.UserInputType == Enum.UserInputType.Touch then
			local inset = GuiService:GetGuiInset()
			return inRect(obj, input.Position.X, input.Position.Y)
				or inRect(obj, input.Position.X + inset.X, input.Position.Y + inset.Y)
		end
		local m = UserInputService:GetMouseLocation()
		return inRect(obj, m.X, m.Y)
	end

	---------------------------------------------------------------------
	-- PAGE LAYOUT: the root holds the two pages and the switch at the bottom.
	-- Each page is a scrolling page with two columns of cards.
	---------------------------------------------------------------------
	local BODY_Y = 2
	local GAP = 8
	local BOTTOM_H = 44   -- room at the bottom for the Aimbot / Silent switch

	local root = new("Frame", {
		Name = "CombatRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	local function makePage(name, visible)
		local P = {}
		local gt = 1
		if visible then
			gt = 0
		end

		P.holder = new("CanvasGroup", {
			Name = name .. "Holder",
			Size = UDim2.new(1, 0, 1, -BOTTOM_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			GroupTransparency = gt,
			Visible = visible,
		}, root)

		P.scroll = new("ScrollingFrame", {
			Name = name .. "Root",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = T.ICON,
			ScrollBarImageTransparency = 0.5,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			ElasticBehavior = Enum.ElasticBehavior.Never,
		}, P.holder)

		P.body = new("Frame", {
			Name = "Body",
			Position = UDim2.fromOffset(2, BODY_Y),
			Size = UDim2.new(1, -12, 0, 10),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, P.scroll)

		local colY = { 0, 0 }

		-- a card in column 1 (left) or 2 (right), stacked under the previous one
		function P.place(col, h)
			local f = new("Frame", {
				Position = UDim2.new((col - 1) * 0.5, (col - 1) * 6, 0, colY[col]),
				Size = UDim2.new(0.5, -6, 0, h),
				BackgroundColor3 = T.SIDEBAR_BG,
				BorderSizePixel = 0,
			}, P.body)
			corner(f, RADIUS + 4)
			stroke(f, T.BORDER, 1, 0)
			colY[col] = colY[col] + h + GAP
			return f
		end

		-- small dim header above a group of cards (same style as the Settings page)
		function P.section(col, text)
			label(P.body, text, UDim2.new((col - 1) * 0.5, (col - 1) * 6 + 2, 0, colY[col]),
				UDim2.new(0.5, -10, 0, 14), Enum.Font.GothamMedium, 11, T.DIM_TEXT)
			colY[col] = colY[col] + 22
		end

		-- size the page to its content
		function P.finish()
			local bodyH = math.max(colY[1], colY[2]) - GAP
			P.body.Size = UDim2.new(1, -12, 0, bodyH)
			P.scroll.CanvasSize = UDim2.new(0, 0, 0, BODY_Y + bodyH + 8)
		end

		return P
	end

	local aimP = makePage("Aimbot", true)
	local silP = makePage("Silent", false)

	---------------------------------------------------------------------
	-- CONTROLS
	---------------------------------------------------------------------
	-- returns { set = fn(value, animate) } so the code can flip the switch itself
	local function makeSwitch(c, startOn, onChange, cy, rightPad)
		local on = startOn
		local track = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -(rightPad or 12), 0, cy),
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

		local api = {}
		function api.set(v, animate)
			on = v
			paint(animate)
		end
		return api
	end

	-- a button that records the next key / mouse button (shows the current one on it)
	local function bindButton(c, pos, size, getBind, setBind, allowMouse)
		local btn = new("TextButton", {
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0),
			Position = pos,
			Size = size,
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
						paint()
					end,
					restore = function()
						return bindName(getBind())
					end,
				}
				btn.Text = "Press a key..."
			end
			paint()
		end)
		return btn
	end

	-- a caption and a row of options with a sliding highlight, drawn inside any container
	-- y0 = top of the caption, inset = space left and right
	local function segmented(container, y0, inset, title, options, startValue, onChange)
		label(container, title, UDim2.fromOffset(inset + 2, y0), UDim2.new(1, -(inset * 2), 0, 12),
			Enum.Font.Gotham, 11, T.DIM_TEXT)

		local tray = new("Frame", {
			Position = UDim2.fromOffset(inset, y0 + 18),
			Size = UDim2.new(1, -(inset * 2), 0, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, container)
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
	local function switchSliders(P, col, title, startOn, startX, startY, onSwitch, setX, setY)
		local c = P.place(col, 106)
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

	-- the Distance card (Min / Max), used on both pages. cfg = S or SIL
	local function rangeCard(P, col, cfg)
		local c = P.place(col, 104)
		label(c, "Distance", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 0, 36),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		local minApi = nil
		local maxApi = nil
		minApi = makeSlider(c, 38, "Min", 28, 0, 1000, 5, cfg.minDist, "%d", function(v)
			cfg.minDist = v
			if cfg.maxDist < v then
				cfg.maxDist = v
				maxApi.set(v)
			end
		end)
		maxApi = makeSlider(c, 68, "Max", 28, 0, 1000, 5, cfg.maxDist, "%d", function(v)
			cfg.maxDist = v
			if cfg.minDist > v then
				cfg.minDist = v
				minApi.set(v)
			end
		end)
		minApi.dim(true)
		maxApi.dim(true)
	end

	-- a drop-down card: the title on the left, a button with the current value on the right.
	-- Clicking the button opens a small vertical list (a pop-up). Pick one, or click anywhere else to close it.
	local function dropdownCard(P, col, title, options, startValue, onChange)
		local c = P.place(col, 46)
		c.ZIndex = 25   -- the list opens over the cards below, so this card must draw above them

		label(c, title, UDim2.fromOffset(14, 0), UDim2.new(1, -150, 1, 0),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)

		local trigger = new("TextButton", {
			Name = "DropdownButton",
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(124, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, c)
		corner(trigger, RADIUS + 2)

		local valueLabel = label(trigger, startValue, UDim2.fromOffset(10, 0), UDim2.new(1, -30, 1, 0),
			Enum.Font.GothamMedium, 12, T.ICON_HOVER)

		-- small chevron: a "v" made of two bars
		local chevParts = {}
		local function chevBar(x, rot)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, x, 0.5, 0),
				Size = UDim2.fromOffset(6, 2),
				Rotation = rot,
				BackgroundColor3 = T.ICON,
				BorderSizePixel = 0,
			}, trigger)
			corner(f, 1)
			chevParts[#chevParts + 1] = f
		end
		chevBar(-15, 45)
		chevBar(-11, -45)

		local ITEM_H = 28
		local PAD_P = 4
		local LIST_W = 150
		local LIST_H = #options * ITEM_H + PAD_P * 2
		local LIST_SHOWN = UDim2.new(1, -12, 0, 40)
		local LIST_HIDDEN = UDim2.new(1, -12, 0, 34)
		local OPEN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local CLOSE_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		local popup = new("CanvasGroup", {
			Name = "DropdownList",
			AnchorPoint = Vector2.new(1, 0),
			Position = LIST_HIDDEN,
			Size = UDim2.fromOffset(LIST_W, LIST_H),
			BackgroundColor3 = T.POPUP_BG,
			BorderSizePixel = 0,
			GroupTransparency = 1,
			Visible = false,
			ZIndex = 50,
		}, c)
		corner(popup, RADIUS + 3)
		stroke(popup, T.BORDER, 1, 0)

		local isOpen = false
		local token = 0
		local over = false
		local current = startValue
		local items = {}

		local function paintTrigger()
			local bg = T.CLUSTER_BG
			local colr = T.ICON
			if isOpen or over then
				bg = T.HOVER_GREY
				colr = T.ICON_HOVER
			end
			TweenService:Create(trigger, FAST, { BackgroundColor3 = bg }):Play()
			for i = 1, #chevParts do
				TweenService:Create(chevParts[i], FAST, { BackgroundColor3 = colr }):Play()
			end
		end

		local function refreshItems()
			for i = 1, #items do
				local it = items[i]
				local textColor = T.ICON
				local dotT = 1
				if it.value == current then
					textColor = T.ICON_HOVER
					dotT = 0
				end
				TweenService:Create(it.text, FAST, { TextColor3 = textColor }):Play()
				TweenService:Create(it.dot, FAST, { BackgroundTransparency = dotT }):Play()
			end
		end

		local function openList()
			if isOpen then
				return
			end
			isOpen = true
			token = token + 1
			popup.Position = LIST_HIDDEN
			popup.GroupTransparency = 1
			popup.Visible = true
			TweenService:Create(popup, OPEN_INFO, { Position = LIST_SHOWN, GroupTransparency = 0 }):Play()
			paintTrigger()
		end

		local function closeList()
			if not isOpen then
				return
			end
			isOpen = false
			token = token + 1
			local tk = token
			TweenService:Create(popup, CLOSE_INFO, { Position = LIST_HIDDEN, GroupTransparency = 1 }):Play()
			task.delay(CLOSE_INFO.Time + 0.02, function()
				if tk == token then
					popup.Visible = false
				end
			end)
			paintTrigger()
		end

		for i = 1, #options do
			local opt = options[i]
			local b = new("TextButton", {
				AutoButtonColor = false,
				Text = "",
				Position = UDim2.fromOffset(PAD_P, PAD_P + (i - 1) * ITEM_H),
				Size = UDim2.new(1, -(PAD_P * 2), 0, ITEM_H),
				BackgroundColor3 = T.HOVER_GREY,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, popup)
			corner(b, RADIUS + 1)
			local t = label(b, opt, UDim2.fromOffset(10, 0), UDim2.new(1, -32, 1, 0),
				Enum.Font.GothamMedium, 12, T.ICON)
			local dot = new("Frame", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(6, 6),
				BackgroundColor3 = T.ICON_HOVER,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, b)
			corner(dot, 100)
			items[i] = { value = opt, text = t, dot = dot }

			b.MouseEnter:Connect(function()
				TweenService:Create(b, FAST, { BackgroundTransparency = 0.45 }):Play()
			end)
			b.MouseLeave:Connect(function()
				TweenService:Create(b, FAST, { BackgroundTransparency = 1 }):Play()
			end)
			b.Activated:Connect(function()
				if current ~= opt then
					current = opt
					valueLabel.Text = opt
					refreshItems()
					onChange(opt)
				end
				closeList()
			end)
		end
		refreshItems()

		trigger.MouseEnter:Connect(function()
			over = true
			paintTrigger()
		end)
		trigger.MouseLeave:Connect(function()
			over = false
			paintTrigger()
		end)
		trigger.Activated:Connect(function()
			if isOpen then
				closeList()
			else
				openList()
			end
		end)

		popupList[#popupList + 1] = {
			isOpen = function()
				return isOpen
			end,
			close = closeList,
			hit = { popup, trigger },
		}
	end

	---------------------------------------------------------------------
	-- TARGETING (shared by the aimbot and silent aim)
	---------------------------------------------------------------------
	-- the screen point we measure "near" from: the cursor, or the middle of the screen
	-- (always the middle when centerOnly is set, and whenever the mouse is locked to the middle)
	local function refPoint(cam, centerOnly)
		local vs = cam.ViewportSize
		-- GetMouseLocation can return a stale position while the mouse is locked to the middle
		-- (shift lock, first person), so we do not trust it in that case.
		if centerOnly or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			return Vector2.new(vs.X / 2, vs.Y / 2)
		end
		return UserInputService:GetMouseLocation()
	end

	-- true while the mouse cannot move freely: shift lock / first person (locked to the middle)
	-- or holding the right mouse button to look around (locked in place)
	local function mouseIsLocked()
		local b = UserInputService.MouseBehavior
		return b == Enum.MouseBehavior.LockCenter or b == Enum.MouseBehavior.LockCurrentPosition
	end

	local function originPos(cam)
		local char = player.Character
		local rootPart = nil
		if char then
			rootPart = char:FindFirstChild("HumanoidRootPart")
		end
		if rootPart then
			return rootPart.Position
		end
		return cam.CFrame.Position
	end

	local function validTarget(plr, origin, cfg)
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
		local rootPart = char:FindFirstChild("HumanoidRootPart")
		if rootPart == nil then
			return false
		end
		local d = (rootPart.Position - origin).Magnitude
		return d >= cfg.minDist and d <= cfg.maxDist
	end

	-- the body part to aim at for this Hit Part choice (partName)
	-- Closest Part = whichever part is nearest to ref on the screen
	local function bestPart(char, cam, ref, needScreen, partName)
		local nearest = (partName == "Closest Part")
		local names = CLOSEST_NAMES
		if not nearest then
			names = PART_NAMES[partName] or PART_NAMES["Head"]
		end
		local best = nil
		local bestD = nil
		for i = 1, #names do
			local p = char:FindFirstChild(names[i])
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
					if not nearest then
						break
					end
				end
			end
		end
		return best, bestD
	end

	-- the player whose hit part is nearest to ref. maxScreenDist (optional) = only players inside that many pixels
	local function acquire(cam, ref, origin, cfg, maxScreenDist)
		local bestPlr = nil
		local bestD = nil
		local all = Players:GetPlayers()
		for i = 1, #all do
			local plr = all[i]
			if plr ~= player and validTarget(plr, origin, cfg) then
				local part, d = bestPart(plr.Character, cam, ref, true, cfg.part)
				if part and (maxScreenDist == nil or d <= maxScreenDist) then
					if bestD == nil or d < bestD then
						bestPlr = plr
						bestD = d
					end
				end
			end
		end
		return bestPlr
	end

	-- where to aim: the part position, moved ahead by its speed when Prediction is on
	local function aimPosition(part, cfg)
		local pos = part.Position
		if cfg.predOn then
			local v = part.AssemblyLinearVelocity
			pos = pos + Vector3.new(v.X * cfg.predX, v.Y * cfg.predY, v.Z * cfg.predX) * 0.01
		end
		return pos
	end

	---------------------------------------------------------------------
	-- AIMBOT PAGE
	--   left : Enable (switch + three dots), Hit Part, Distance
	--   right: Prediction, Smoothness
	---------------------------------------------------------------------
	aimP.section(1, "AIMBOT")

	local enableCard = aimP.place(1, 46)
	enableCard.ZIndex = 30   -- the settings panel opens from this card, so it must draw above the other cards

	label(enableCard, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local enableSub = label(enableCard, "", UDim2.fromOffset(14, 25), UDim2.new(1, -140, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)

	-- what the small line under "Enable" says: Off / the key and mode / Active
	local function refreshStatus()
		local text = S.mode .. " " .. bindName(S.keybind)
		local colr = T.DIM_TEXT
		if not S.enabled then
			text = "Off"
		elseif active then
			text = "Active"
			colr = T.GREEN
		end
		enableSub.Text = text
		enableSub.TextColor3 = colr
	end

	setActive = function(v)
		if not S.enabled then
			v = false
		end
		active = v
		if not v then
			locked = nil
			accX = 0
			accY = 0
		end
		refreshStatus()
	end

	makeSwitch(enableCard, S.enabled, function(on)
		S.enabled = on
		setActive(false)
		refreshStatus()
	end, 23)

	-- three horizontal dots, left of the switch
	local dotsBtn = new("TextButton", {
		Name = "MoreButton",
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -58, 0, 23),
		Size = UDim2.fromOffset(32, 26),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, enableCard)

	local dotParts = {}
	for i = 1, 3 do
		local d = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, (i - 2) * 7, 0.5, 0),
			Size = UDim2.fromOffset(4, 4),
			BackgroundColor3 = T.ICON,
			BorderSizePixel = 0,
		}, dotsBtn)
		corner(d, 100)
		dotParts[i] = d
	end

	dropdownCard(aimP, 1, "Hit Part", PART_OPTIONS, S.part, function(v)
		S.part = v
		locked = nil
	end)

	aimP.section(1, "RANGE")
	rangeCard(aimP, 1, S)

	aimP.section(2, "ASSIST")

	switchSliders(aimP, 2, "Prediction", S.predOn, S.predX, S.predY,
		function(on) S.predOn = on end,
		function(v) S.predX = v end,
		function(v) S.predY = v end)

	switchSliders(aimP, 2, "Smoothness", S.smoothOn, S.smoothX, S.smoothY,
		function(on) S.smoothOn = on end,
		function(v) S.smoothX = v end,
		function(v) S.smoothY = v end)

	aimP.finish()

	---------------------------------------------------------------------
	-- AIMBOT SETTINGS PANEL (opens from the three dots; ONE background for everything inside)
	--   Aimbot (title) / Key / Mode / Aim Type / Target Lock
	---------------------------------------------------------------------
	local POP_W = 264
	local POP_H = 256
	-- it sits right next to the dots (the dots end 58px from the right edge of the card)
	local POP_SHOWN = UDim2.new(1, -50, 0, -8)
	local POP_HIDDEN = UDim2.new(1, -60, 0, -8)
	local OPEN_INFO = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local CLOSE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local popup = new("CanvasGroup", {
		Name = "AimbotSettings",
		Position = POP_HIDDEN,
		Size = UDim2.fromOffset(POP_W, POP_H),
		BackgroundColor3 = T.POPUP_BG,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 50,
	}, enableCard)
	corner(popup, RADIUS + 4)
	stroke(popup, T.BORDER, 1, 0)

	-- top left: "Aimbot"
	label(popup, "Aimbot", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)

	local function line(y)
		new("Frame", {
			Position = UDim2.fromOffset(16, y),
			Size = UDim2.new(1, -32, 0, 1),
			BackgroundColor3 = T.BORDER,
			BorderSizePixel = 0,
		}, popup)
	end
	line(40)

	-- Key
	label(popup, "Key", UDim2.fromOffset(16, 50), UDim2.new(1, -150, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	bindButton(popup, UDim2.new(1, -16, 0, 50), UDim2.fromOffset(110, 28),
		function() return S.keybind end,
		function(b)
			S.keybind = b
			setActive(false)
		end,
		true)

	-- Mode
	segmented(popup, 90, 16, "Mode", { "Hold", "Toggle" }, S.mode, function(v)
		S.mode = v
		setActive(false)
	end)

	-- Aim Type
	segmented(popup, 146, 16, "Aim Type", { "Mouse", "Camera" }, S.aim, function(v)
		S.aim = v
		accX = 0
		accY = 0
	end)

	line(204)

	-- Target Lock (one line, switch on the right)
	label(popup, "Target Lock", UDim2.fromOffset(16, 214), UDim2.new(1, -90, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	makeSwitch(popup, S.lockOn, function(on)
		S.lockOn = on
		locked = nil
	end, 228, 16)

	-- open / close the settings panel
	local popupOpen = false
	local popupToken = 0
	local dotsOver = false

	-- no background: only the dots change colour (lit while hovered or while the panel is open)
	local function paintDots()
		local colr = T.ICON
		if popupOpen or dotsOver then
			colr = T.ICON_HOVER
		end
		for i = 1, #dotParts do
			TweenService:Create(dotParts[i], FAST, { BackgroundColor3 = colr }):Play()
		end
	end

	local function openSettings()
		if popupOpen then
			return
		end
		popupOpen = true
		popupToken = popupToken + 1
		popup.Position = POP_HIDDEN
		popup.GroupTransparency = 1
		popup.Visible = true
		TweenService:Create(popup, OPEN_INFO, { Position = POP_SHOWN, GroupTransparency = 0 }):Play()
		paintDots()
	end

	local function closeSettings()
		if not popupOpen then
			return
		end
		popupOpen = false
		popupToken = popupToken + 1
		local token = popupToken
		-- stop recording a key if the panel goes away in the middle of it
		if listening then
			listening.btn.Text = listening.restore()
			listening = nil
		end
		TweenService:Create(popup, CLOSE_INFO, { Position = POP_HIDDEN, GroupTransparency = 1 }):Play()
		task.delay(CLOSE_INFO.Time + 0.02, function()
			if token == popupToken then
				popup.Visible = false
			end
		end)
		paintDots()
	end

	dotsBtn.MouseEnter:Connect(function()
		dotsOver = true
		paintDots()
	end)
	dotsBtn.MouseLeave:Connect(function()
		dotsOver = false
		paintDots()
	end)
	dotsBtn.Activated:Connect(function()
		if popupOpen then
			closeSettings()
		else
			openSettings()
		end
	end)

	popupList[#popupList + 1] = {
		isOpen = function()
			return popupOpen
		end,
		close = closeSettings,
		hit = { popup, dotsBtn },
	}

	refreshStatus()

	---------------------------------------------------------------------
	-- SILENT PAGE
	--   left : Enable, Hit Part, Distance
	--   right: Prediction, FOV
	---------------------------------------------------------------------
	silP.section(1, "SILENT AIM")

	local silEnableCard = silP.place(1, 46)
	silEnableCard.ZIndex = 30

	label(silEnableCard, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -70, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local silentSub = label(silEnableCard, "Off", UDim2.fromOffset(14, 25), UDim2.new(1, -70, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)

	local silentLastText = ""
	local silentLastColor = nil
	local function setSilentStatus(text, colr)
		if text ~= silentLastText or colr ~= silentLastColor then
			silentLastText = text
			silentLastColor = colr
			silentSub.Text = text
			silentSub.TextColor3 = colr
		end
	end

	-- silent aim state (filled every frame, read by the hooks below)
	local silentPos = nil
	local silentPart = nil
	local shooterCam = nil
	local shooterRoot = nil
	local hooksReady = false
	local hooksFailed = false

	local RAY_METHODS = {
		FindPartOnRay = true,
		FindPartOnRayWithIgnoreList = true,
		FindPartOnRayWithWhitelist = true,
	}

	-- only rays that start near the camera or near your character are changed
	-- (those are the shots; random game raycasts far away are left alone)
	local function nearShooter(origin)
		if shooterCam and (origin - shooterCam).Magnitude < 25 then
			return true
		end
		if shooterRoot and (origin - shooterRoot).Magnitude < 15 then
			return true
		end
		return false
	end

	-- the two hooks are installed the first time silent aim is switched on.
	-- When it is off (or the window is unloaded) they just pass everything through.
	local function installHooks()
		if hooksReady then
			return true
		end
		if hooksFailed then
			return false
		end
		local ok, err = pcall(function()
			if type(hookmetamethod) ~= "function" then
				error("hookmetamethod is missing", 0)
			end
			if type(getnamecallmethod) ~= "function" then
				error("getnamecallmethod is missing", 0)
			end
			if type(checkcaller) ~= "function" then
				error("checkcaller is missing", 0)
			end
			local getNC = getnamecallmethod
			local checkC = checkcaller
			local wrap = newcclosure
			if type(wrap) ~= "function" then
				wrap = function(f)
					return f
				end
			end
			local mouse = player:GetMouse()

			-- 1) games that read Mouse.Hit / Mouse.Target to shoot
			local oldIndex
			oldIndex = hookmetamethod(game, "__index", wrap(function(self, key)
				if self == mouse and running and SIL.enabled and silentPos ~= nil and not checkC() then
					if key == "Hit" or key == "hit" then
						return CFrame.new(silentPos)
					elseif key == "Target" or key == "target" then
						return silentPart
					end
				end
				return oldIndex(self, key)
			end))

			-- 2) games that shoot with workspace:Raycast / FindPartOnRay...
			local oldNamecall
			oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
				local method = getNC()
				if running and SIL.enabled and silentPos ~= nil and self == workspace
					and (method == "Raycast" or RAY_METHODS[method] == true) and not checkC() then
					local n = select("#", ...)
					local args = { ... }
					if method == "Raycast" then
						local origin = args[1]
						local dir = args[2]
						if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" and nearShooter(origin) then
							local toT = silentPos - origin
							if toT.Magnitude > 0.01 then
								args[2] = toT.Unit * dir.Magnitude
								return oldNamecall(self, table.unpack(args, 1, n))
							end
						end
					else
						local ray = args[1]
						if typeof(ray) == "Ray" and nearShooter(ray.Origin) then
							local toT = silentPos - ray.Origin
							if toT.Magnitude > 0.01 then
								args[1] = Ray.new(ray.Origin, toT.Unit * ray.Direction.Magnitude)
								return oldNamecall(self, table.unpack(args, 1, n))
							end
						end
					end
				end
				return oldNamecall(self, ...)
			end))
		end)
		if ok then
			hooksReady = true
			return true
		end
		hooksFailed = true
		warn("[aimbot] silent aim is not supported by this executor: " .. tostring(err))
		return false
	end

	local silentSwitch = nil
	silentSwitch = makeSwitch(silEnableCard, SIL.enabled, function(on)
		if on and not installHooks() then
			SIL.enabled = false
			silentSwitch.set(false, true)
			return
		end
		SIL.enabled = on
		silentPos = nil
		silentPart = nil
	end, 23)

	dropdownCard(silP, 1, "Hit Part", PART_OPTIONS, SIL.part, function(v)
		SIL.part = v
	end)

	silP.section(1, "RANGE")
	rangeCard(silP, 1, SIL)

	silP.section(2, "ASSIST")

	switchSliders(silP, 2, "Prediction", SIL.predOn, SIL.predX, SIL.predY,
		function(on) SIL.predOn = on end,
		function(v) SIL.predX = v end,
		function(v) SIL.predY = v end)

	-- FOV card: a switch for the circle and one slider for its size
	do
		local c = silP.place(2, 76)
		label(c, "FOV Circle", UDim2.fromOffset(14, 0), UDim2.new(1, -70, 0, 38),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		local fovApi = makeSlider(c, 40, "Size", 28, 20, 1000, 10, SIL.fov, "%d", function(v)
			SIL.fov = v
		end)
		fovApi.dim(true)
		makeSwitch(c, SIL.showFov, function(on)
			SIL.showFov = on
		end, 19)
	end

	silP.finish()

	---------------------------------------------------------------------
	-- FOV CIRCLE (its own tiny gui, follows the cursor while silent aim is on)
	---------------------------------------------------------------------
	do
		local old = playerGui:FindFirstChild("Y1SilentFov")
		if old then
			old:Destroy()
		end
	end
	local fovGui = new("ScreenGui", {
		Name = "Y1SilentFov",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 997,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	local fovCircle = new("Frame", {
		Name = "Circle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(100, 100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, fovGui)
	corner(fovCircle, 1000)
	stroke(fovCircle, Color3.new(1, 1, 1), 1.5, 0.35)

	-- runs every frame: picks the silent target and keeps the FOV circle under the cursor
	local function silentUpdate()
		silentPos = nil
		silentPart = nil

		local cam = workspace.CurrentCamera
		if not cam then
			fovCircle.Visible = false
			return
		end

		shooterCam = cam.CFrame.Position
		shooterRoot = nil
		local myChar = player.Character
		if myChar then
			local myRoot = myChar:FindFirstChild("HumanoidRootPart")
			if myRoot then
				shooterRoot = myRoot.Position
			end
		end

		local ref = refPoint(cam, false)

		if SIL.enabled and SIL.showFov then
			fovCircle.Position = UDim2.fromOffset(ref.X, ref.Y)
			local dia = SIL.fov * 2
			fovCircle.Size = UDim2.fromOffset(dia, dia)
			fovCircle.Visible = true
		else
			fovCircle.Visible = false
		end

		if hooksFailed then
			setSilentStatus("Executor not supported", T.HOVER_RED)
			return
		end
		if not SIL.enabled then
			setSilentStatus("Off", T.DIM_TEXT)
			return
		end

		local origin = shooterRoot or shooterCam
		local plr = acquire(cam, ref, origin, SIL, SIL.fov)
		if plr == nil or plr.Character == nil then
			setSilentStatus("No target", T.DIM_TEXT)
			return
		end
		local part = bestPart(plr.Character, cam, ref, false, SIL.part)
		if part == nil then
			setSilentStatus("No target", T.DIM_TEXT)
			return
		end

		silentPart = part
		silentPos = aimPosition(part, SIL)
		setSilentStatus("Target: " .. plr.DisplayName, T.GREEN)
	end

	conns[#conns + 1] = RunService.RenderStepped:Connect(function()
		if running then
			silentUpdate()
		end
	end)

	---------------------------------------------------------------------
	-- THE AIMBOT ITSELF
	---------------------------------------------------------------------
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

	-- whole pixels towards zero (the rest is kept for the next frame)
	local function wholePart(v)
		if v >= 0 then
			return math.floor(v)
		end
		return math.ceil(v)
	end

	local function step(dt)
		if not running or not active then
			return
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end

		local ref = refPoint(cam, S.aim == "Camera")
		local origin = originPos(cam)

		-- pick the target
		if S.lockOn then
			if locked and not validTarget(locked, origin, S) then
				locked = nil
			end
			if locked == nil then
				locked = acquire(cam, ref, origin, S, nil)
			end
		else
			locked = acquire(cam, ref, origin, S, nil)
		end
		if locked == nil or locked.Character == nil then
			return
		end

		local part = bestPart(locked.Character, cam, ref, false, S.part)
		if part == nil then
			return
		end

		local pos = aimPosition(part, S)
		local ax = alphaFor(S.smoothX, dt)
		local ay = alphaFor(S.smoothY, dt)

		-- MOUSE aim with a free cursor: move the real cursor, never touch the camera
		if S.aim == "Mouse" and not mouseIsLocked() then
			if moveRel == nil then
				if not warnedMove then
					warnedMove = true
					warn("[aimbot] this executor has no mousemoverel, so Mouse aim cannot move the cursor. Use Aim Type: Camera.")
				end
				return
			end
			local v = cam:WorldToViewportPoint(pos)
			if v.Z <= 0 then
				return   -- the target is behind the camera
			end
			local dx = v.X - ref.X
			local dy = v.Y - ref.Y
			if math.abs(dx) < 0.5 and math.abs(dy) < 0.5 then
				accX = 0
				accY = 0
				return
			end
			accX = accX + dx * ax
			accY = accY + dy * ay
			local mx = wholePart(accX)
			local my = wholePart(accY)
			if mx ~= 0 or my ~= 0 then
				accX = accX - mx
				accY = accY - my
				pcall(moveRel, mx, my)
			end
			return
		end

		-- CAMERA aim, and Mouse aim while the mouse is locked (shift lock / first person / right mouse look):
		-- turn the camera so the target ends up on the reference point (screen middle or the locked cursor)
		local camCF = cam.CFrame
		local toTarget = pos - camCF.Position
		if toTarget.Magnitude < 0.001 then
			return
		end
		toTarget = toTarget.Unit

		-- the direction that should end up on the target:
		--   Camera = where the camera looks (screen middle)
		--   Mouse  = the ray through the (locked) cursor
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

		-- turn the camera by that error
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
	-- THE AIMBOT / SILENT SWITCH AT THE BOTTOM
	---------------------------------------------------------------------
	local currentSub = "Aimbot"
	local subToken = 0

	local function showSub(name)
		if name == currentSub then
			return
		end
		currentSub = name
		closeAllPopups()
		subToken = subToken + 1
		local tk = subToken

		local showP = aimP
		local hideP = silP
		if name == "Silent" then
			showP = silP
			hideP = aimP
		end

		TweenService:Create(hideP.holder, FAST, { GroupTransparency = 1 }):Play()
		task.delay(0.14, function()
			if tk == subToken then
				hideP.holder.Visible = false
			end
		end)

		showP.holder.Position = UDim2.fromOffset(0, 8)
		showP.holder.GroupTransparency = 1
		showP.holder.Visible = true
		TweenService:Create(showP.holder, SMOOTH, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }):Play()
	end

	do
		local tray = new("Frame", {
			Name = "ModeSwitch",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.fromOffset(220, 32),
			BackgroundColor3 = T.SIDEBAR_BG,
			BorderSizePixel = 0,
		}, root)
		corner(tray, RADIUS + 4)
		stroke(tray, T.BORDER, 1, 0)

		local inner = new("Frame", {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, tray)

		local slider = new("Frame", {
			Size = UDim2.new(0.5, 0, 1, 0),
			BackgroundColor3 = T.HOVER_GREY,
			BorderSizePixel = 0,
		}, inner)
		corner(slider, RADIUS + 1)

		local names = { "Aimbot", "Silent" }
		local tabBtns = {}

		local function paintTabs(animate)
			local index = 1
			if currentSub == "Silent" then
				index = 2
			end
			local pos = UDim2.new((index - 1) / 2, 0, 0, 0)
			if animate then
				TweenService:Create(slider, SMOOTH, { Position = pos }):Play()
			else
				slider.Position = pos
			end
			for i = 1, 2 do
				local colr = T.ICON
				if i == index then
					colr = T.ICON_HOVER
				end
				TweenService:Create(tabBtns[i], FAST, { TextColor3 = colr }):Play()
			end
		end

		for i = 1, 2 do
			local b = new("TextButton", {
				AutoButtonColor = false,
				Position = UDim2.new((i - 1) / 2, 0, 0, 0),
				Size = UDim2.new(0.5, 0, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = names[i],
				TextColor3 = T.ICON,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
			}, inner)
			tabBtns[i] = b
			b.Activated:Connect(function()
				showSub(names[i])
				paintTabs(true)
			end)
		end
		paintTabs(false)
	end

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

		-- a click or tap anywhere except inside an open pop-up (or its button) closes that pop-up
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			for i = 1, #popupList do
				local pp = popupList[i]
				if pp.isOpen() then
					local inside = false
					for j = 1, #pp.hit do
						if pointerOver(pp.hit[j], input) then
							inside = true
						end
					end
					if not inside then
						pp.close()
					end
				end
			end
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

	-- leaving the Combat tab closes every pop-up
	if parent:IsA("GuiObject") then
		conns[#conns + 1] = parent:GetPropertyChangedSignal("Visible"):Connect(function()
			if not parent.Visible then
				closeAllPopups()
			end
		end)
	end

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
		silentPos = nil
		silentPart = nil
		pcall(function()
			RunService:UnbindFromRenderStep(STEP_NAME)
		end)
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		pcall(function()
			fovGui:Destroy()
		end)
	end

	-- the window destroys its gui when it unloads: that takes this page with it
	conns[#conns + 1] = root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(game) then
			unload()
		end
	end)

	-- ui.lua versions that offer a hook can call it directly as well
	if type(opts.OnUnload) == "function" then
		opts.OnUnload(unload)
	end

	return { Root = root, Unload = unload }
end

return AimbotPage
