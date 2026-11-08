-- aimbot.lua  (Y1 Combat tab: the aimbot + a Silent page + an empty Triggerbot page, as its own module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Combat tab INTO win.CombatPage. It makes no window of its own (the only other thing it
-- adds is one transparent overlay gui, "Y1AimbotFov", that draws the FOV shape on the screen).
-- ui.lua already loads it through opts.CombatModule, so nothing in ui.lua has to change.
--
--   local Aimbot = <this file>
--   Aimbot.build(parentFrame, themeTable, helperTable, opts)
--
-- At the BOTTOM of the tab there is a small switch: [ Aimbot | Silent | Triggerbot ]. It swaps the page above it.
--
-- AIMBOT page
--   Left column   Enable row   a switch (it is OFF every time the script starts) and a "..." (three dots)
--                              button. The line under "Enable" says Active while the aimbot is on (Off when
--                              it is off). The dots open one small settings panel (Key, Mode, Aim Type,
--                              Target Lock). Click the dots again, or anywhere else, to close it.
--                 Hit Part     a drop-down (click it, pick from the vertical list, click anywhere else to close it)
--                              Head (default) / Body / Left Leg / Right Leg / Left Arm / Right Arm / Closest Part
--                 FILTERS      Team Check     skips players on your team
--                              Visible Check  skips players you cannot see (a raycast from the camera to the
--                                             hit part; a wall or any other model in the way = not visible)
--                              Health Check   skips players whose health is below the Min slider (in percent).
--                                             Dead players are always skipped.
--                              All three are off every time the script starts.
--   Right column  Distance     Min / Max (on top)
--                 Prediction / Smoothness   X / Y  0-20
--                 FOV          a small row: a colour square (the outline colour, click it for the colour
--                              picker) and three dots. The dots open the FOV settings:
--                                Enabled   off every time the script starts
--                                Filled    on / off, with its own colour square left of the switch
--                                Glow      on / off
--                                Size      radius of the FOV in pixels
--                                Angles    3 = triangle, 4 = square, ... up to Circle (the maximum)
--                                Dynamic FOV   on / off: the FOV grows when players are close and
--                                              shrinks when they are far (0.5x - 2x), so it always covers
--                                              about the same part of a player
--                                Spin          on / off, with a Speed slider (degrees per second). The shape
--                                              turns around its middle, and the target check turns with it,
--                                              so only what is inside the turning shape can be picked.
--                                              (A circle looks the same while it spins.)
--                              While the FOV is enabled the aimbot only picks targets whose hit part is
--                              inside the shape (around the cursor, or the screen middle for Camera aim).
--                              The fill of a polygon (anything except a circle) is drawn with many thin
--                              strips. The number of strips follows the size of the FOV (about one per two
--                              pixels), so the edges stay smooth, and it is rebuilt a moment after you stop
--                              dragging the Size slider.
--
--   Colour picker  Click a colour square: saturation / brightness square, hue bar, opacity bar and a text row
--                  (format button HEX / RGB / HSV, the value, and the opacity in %). Click the square again,
--                  or anywhere else, to close it.
--
--   Aim Type   Mouse  = MOVES THE CURSOR (mousemoverel) toward the target. The camera is not touched.
--                       Only while the mouse is locked (shift lock, first person, or holding the right
--                       mouse button to look around) the cursor cannot move, so then and only then the
--                       camera is turned instead, so the target ends up under the locked cursor / crosshair.
--              Camera = the camera turns so the target moves to the SCREEN MIDDLE
--   Mode       Hold = on while the key is held, Toggle = press to switch on / off
--
--   How the cursor mover works (so it does not swing across the screen): the cursor shows its new
--   position a frame or two after it was moved, so a move is only sent after the last one has shown up.
--   It never asks for more than half of the remaining distance at once, never more than 200 pixels in
--   one move, and it measures how far the cursor really went for what it asked (pointer acceleration or
--   display scaling) and corrects for it.
--
-- SILENT page
--   The warning screen lives in this file ("yur1 warning", a shield, a note, an "I accept any risk" box
--   and a Confirm button). It sits on top of silent.lua's controls (hidden and faded out behind it); once
--   the box is ticked and Confirm is pressed, the warning fades away and silent.lua fades in.
--   The page content itself is its own module, silent.lua, which this file builds into the page.
--
-- TRIGGERBOT page
--   Empty, no warning. Its content is its own module, triggerbot.lua, which this file builds into the page.
--
-- SILENT / TRIGGERBOT MODULES
--   main.lua loads silent.lua and triggerbot.lua next to this file and hands them over through
--   opts.SilentModule and opts.TriggerbotModule (ui.lua passes opts.Combat to this file). This file calls
--   <module>.build(container, T, H, ctx) for each one, inside a pcall, so a broken module cannot break the
--   aimbot. ctx = { Settings = the aimbot settings table, Targeting = { refPoint, validTarget, acquire,
--   bestPart, aimPosition, isVisible, originPos } }. If the module returns a table with an Unload function,
--   it is called when the window is unloaded. silent.lua uses this to run its own targeting + firing;
--   triggerbot.lua is still empty for now.
--
-- The aimbot switches itself off and cleans up (including the FOV overlay) when the Y1 window is unloaded.

local AimbotPage = {}

function AimbotPage.build(parent, T, H, opts)
	opts = opts or {}

	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local player = Players.LocalPlayer

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

	local FOV_MIN_SIDES = 3     -- a triangle
	local FOV_CIRCLE = 24       -- the Angles slider's maximum is a true circle
	local DYN_REF = 80          -- Dynamic FOV: at this distance (studs) the FOV has its normal size

	-- aimbot settings
	local S = {
		enabled = false,        -- the aimbot starts OFF every time the script runs
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
		-- filters (all off every time the script runs)
		teamCheck = false,
		visCheck = false,
		healthCheck = false,
		minHealth = 20,         -- percent; used while Health Check is on
		-- FOV
		fovOn = false,          -- off every time the script runs
		fovFilled = false,
		fovGlow = false,
		fovSize = 120,          -- radius in pixels
		fovSides = FOV_CIRCLE,
		fovDynamic = false,
		fovSpin = false,        -- turn the shape around its middle
		fovSpinSpeed = 90,      -- degrees per second
		fovColor = Color3.fromRGB(255, 255, 255),
		fovAlpha = 1,
		fillColor = Color3.fromRGB(255, 255, 255),
		fillAlpha = 0.25,
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
	local fovScale = 1        -- Dynamic FOV: the current size multiplier
	local fovAngle = 0        -- Spin: the current turn of the shape in degrees
	-- bookkeeping for the cursor mover: what was sent last, and how far the cursor really went for it
	local cur = { waiting = false, waitFrames = 0, lastX = 0, lastY = 0, cmdX = 0, cmdY = 0, gain = 1 }

	local function resetCursor()
		accX = 0
		accY = 0
		cur.waiting = false
		cur.waitFrames = 0
	end

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

	-- where the pointer of this input is, in the same screen space as AbsolutePosition
	local function pointerPos(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			local inset = GuiService:GetGuiInset()
			return Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y)
		end
		return UserInputService:GetMouseLocation()
	end

	---------------------------------------------------------------------
	-- PAGE LAYOUT: the root holds the pages and the switch at the bottom.
	-- Each page is a scrolling page with two columns of cards.
	---------------------------------------------------------------------
	local BODY_Y = 2
	local GAP = 8
	local BOTTOM_H = 44   -- room at the bottom for the Aimbot / Silent / Triggerbot switch

	local root = new("Frame", {
		Name = "CombatRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	-- one page holder (a canvas group, so the page can fade in and out)
	local function makeHolder(name, visible)
		local gt = 1
		if visible then
			gt = 0
		end
		return new("CanvasGroup", {
			Name = name .. "Holder",
			Size = UDim2.new(1, 0, 1, -BOTTOM_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			GroupTransparency = gt,
			Visible = visible,
		}, root)
	end

	local function makePage(name, visible)
		local P = {}
		P.holder = makeHolder(name, visible)

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
	local silP = { holder = makeHolder("Silent", false) }       -- the Silent page: the warning screen (here) + silent.lua
	local trigP = { holder = makeHolder("Triggerbot", false) }  -- the Triggerbot page: triggerbot.lua only

	-- a full size, transparent container on each of those two pages: the module is built into it.
	-- Both are plain frames, not CanvasGroups: silP.holder is already a CanvasGroup, and a CanvasGroup
	-- nested inside another CanvasGroup does not render right in Roblox (pop-ups and dropdowns built
	-- inside it come out solid white), so nothing else in this chain may be one. The Silent one starts
	-- hidden (the warning sits on top of it until Confirm is pressed); the Triggerbot one has no
	-- warning to hide behind, so it starts visible.
	local function makeContainer(holder, name, startVisible)
		return new("Frame", {
			Name = name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = startVisible,
		}, holder)
	end
	silP.box = makeContainer(silP.holder, "SilentModule", false)
	trigP.box = makeContainer(trigP.holder, "TriggerbotModule", true)

	---------------------------------------------------------------------
	-- FLOATING POP-UPS (they sit on the whole Combat tab, so they are never cut off by a scrolling page)
	---------------------------------------------------------------------
	-- invisible 100x100 box: its on-screen size tells us the scale of the window
	local probe = new("Frame", {
		Position = UDim2.fromOffset(-300, -300),
		Size = UDim2.fromOffset(100, 100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, root)

	local function uiScale()
		local s = probe.AbsoluteSize.X / 100
		if s <= 0 then
			s = 1
		end
		return s
	end

	-- position and size of a gui object in the local units of root
	local function rectIn(obj)
		local s = uiScale()
		local rp = root.AbsolutePosition
		local p = obj.AbsolutePosition
		local z = obj.AbsoluteSize
		return (p.X - rp.X) / s, (p.Y - rp.Y) / s, z.X / s, z.Y / s
	end

	-- where a w x h pop-up goes: under the anchor (above it when there is no room), right edges lined up.
	-- With "beside" it goes to the left (or right) of that frame instead. Always kept inside the tab.
	local function placeNear(anchor, w, h, beside)
		local s = uiScale()
		local rw = root.AbsoluteSize.X / s
		local rh = root.AbsoluteSize.Y / s
		local ax, ay, aw, ah = rectIn(anchor)
		local x = ax + aw - w
		local y = ay + ah + 6
		if beside then
			local bx, by, bw = rectIn(beside)
			if bx - 8 - w >= 4 then
				x = bx - 8 - w
			else
				x = bx + bw + 8
			end
			y = by
		elseif y + h > rh - 4 then
			y = ay - h - 6
		end
		x = math.clamp(x, 4, math.max(4, rw - w - 4))
		y = math.clamp(y, 4, math.max(4, rh - h - 4))
		return UDim2.fromOffset(math.floor(x), math.floor(y))
	end

	local FL_OPEN = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local FL_CLOSE = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	-- a pop-up frame (canvas group) with open / close animations
	local function makeFloating(name, w, h)
		local F = { flag = false, token = 0 }
		F.frame = new("CanvasGroup", {
			Name = name,
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = T.POPUP_BG,
			BorderSizePixel = 0,
			GroupTransparency = 1,
			Visible = false,
			ZIndex = 60,
		}, root)
		corner(F.frame, RADIUS + 4)
		stroke(F.frame, T.BORDER, 1, 0)

		function F.isOpen()
			return F.flag
		end

		function F.open(pos)
			F.token = F.token + 1
			F.flag = true
			F.frame.Position = pos + UDim2.fromOffset(0, 6)
			F.frame.GroupTransparency = 1
			F.frame.Visible = true
			TweenService:Create(F.frame, FL_OPEN, { Position = pos, GroupTransparency = 0 }):Play()
		end

		function F.move(pos)
			TweenService:Create(F.frame, SMOOTH, { Position = pos }):Play()
		end

		function F.close()
			if not F.flag then
				return
			end
			F.flag = false
			F.token = F.token + 1
			local tk = F.token
			TweenService:Create(F.frame, FL_CLOSE, {
				Position = F.frame.Position + UDim2.fromOffset(0, 6),
				GroupTransparency = 1,
			}):Play()
			task.delay(FL_CLOSE.Time + 0.02, function()
				if tk == F.token then
					F.frame.Visible = false
				end
			end)
		end

		return F
	end

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

	-- a small rounded square that shows a colour. pos = where its right-centre edge goes. Click = onClick().
	-- returns { btn = the button, paint = fn(color3) }
	local function makeSwatch(c, pos, startColor, onClick)
		local btn = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = pos,
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = startColor,
			BorderSizePixel = 0,
		}, c)
		corner(btn, 6)
		local st = stroke(btn, T.BORDER, 1, 0)
		btn.MouseEnter:Connect(function()
			TweenService:Create(st, FAST, { Color = T.ICON }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(st, FAST, { Color = T.BORDER }):Play()
		end)
		btn.Activated:Connect(onClick)
		local api = { btn = btn }
		function api.paint(col)
			btn.BackgroundColor3 = col
		end
		return api
	end

	-- three horizontal dots (no background, only the dots change colour: lit while hovered or while open)
	-- set D.open = true / false and call D.paint() from the code that opens the panel
	local function makeDots(c, pos)
		local D = { over = false, open = false, parts = {} }
		D.btn = new("TextButton", {
			Name = "MoreButton",
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = pos,
			Size = UDim2.fromOffset(32, 26),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, c)
		for i = 1, 3 do
			local d = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, (i - 2) * 7, 0.5, 0),
				Size = UDim2.fromOffset(4, 4),
				BackgroundColor3 = T.ICON,
				BorderSizePixel = 0,
			}, D.btn)
			corner(d, 100)
			D.parts[i] = d
		end
		function D.paint()
			local colr = T.ICON
			if D.open or D.over then
				colr = T.ICON_HOVER
			end
			for i = 1, #D.parts do
				TweenService:Create(D.parts[i], FAST, { BackgroundColor3 = colr }):Play()
			end
		end
		D.btn.MouseEnter:Connect(function()
			D.over = true
			D.paint()
		end)
		D.btn.MouseLeave:Connect(function()
			D.over = false
			D.paint()
		end)
		return D
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

	-- a slider row inside a card or pop-up; returns { dim = fn(enabled), set = fn(value) }
	-- fmt is a string.format pattern; fmtFn (optional) is a function(value) -> text that replaces it
	local function makeSlider(c, y, name, labelW, minV, maxV, stepV, startValue, fmt, setValue, fmtFn)
		label(c, name, UDim2.fromOffset(14, y), UDim2.fromOffset(labelW, 20),
			Enum.Font.GothamMedium, 12, T.ICON)
		local valueLabel = label(c, "", UDim2.new(1, -58, 0, y), UDim2.fromOffset(46, 20),
			Enum.Font.GothamMedium, 12, T.TEXT_COLOR, Enum.TextXAlignment.Right)

		local x0 = 14 + labelW + 6

		local track = new("Frame", {
			Position = UDim2.fromOffset(x0, y + 7),
			Size = UDim2.new(1, -(x0 + 66), 0, 6),
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
			Size = UDim2.new(1, -(x0 + 66), 0, 20),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, c)

		local value = startValue
		local dragging = false

		local function refresh()
			local f = (value - minV) / (maxV - minV)
			fill.Size = UDim2.new(f, 0, 1, 0)
			knob.Position = UDim2.new(f, 0, 0.5, 0)
			if fmtFn then
				valueLabel.Text = fmtFn(value)
			else
				valueLabel.Text = string.format(fmt, value)
			end
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

	-- a small filter card: title + a dim line under it on the left, a switch on the right
	local function filterCard(P, col, title, subText, startOn, onChange)
		local c = P.place(col, 46)
		label(c, title, UDim2.fromOffset(14, 7), UDim2.new(1, -70, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		label(c, subText, UDim2.fromOffset(14, 25), UDim2.new(1, -70, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		makeSwitch(c, startOn, onChange, 23)
		return c
	end

	-- the Distance card (Min / Max). cfg = S
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
	-- FOV: helpers shared by the targeting and the drawing
	---------------------------------------------------------------------
	-- the current radius in pixels (Dynamic FOV changes fovScale, otherwise it stays 1)
	local function fovRadius()
		return S.fovSize * fovScale
	end

	-- is the screen point (px, py) inside the FOV shape that is centred on (cx, cy)?
	-- a regular polygon with its first corner pointing up, or a circle at the maximum angle count
	local function insideFov(px, py, cx, cy, radius, sides, rot)
		local dx = px - cx
		local dy = py - cy
		if sides >= FOV_CIRCLE then
			return dx * dx + dy * dy <= radius * radius
		end
		-- the shape may be turned (Spin): turn the point back by the same angle instead
		if rot and rot ~= 0 then
			local r = math.rad(rot)
			local cr = math.cos(r)
			local sr = math.sin(r)
			dx, dy = dx * cr + dy * sr, -dx * sr + dy * cr
		end
		local apothem = radius * math.cos(math.pi / sides)
		for k = 0, sides - 1 do
			local ang = math.rad(-90 + 360 / sides * (k + 0.5))
			if dx * math.cos(ang) + dy * math.sin(ang) > apothem then
				return false
			end
		end
		return true
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

	-- every check that does not need a raycast: alive, team, health, distance
	local function validTarget(plr, origin, cfg)
		if plr.Parent == nil then
			return false
		end
		-- Team Check: skip players on your own team
		if cfg.teamCheck and plr.Team ~= nil and plr.Team == player.Team then
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
		-- Health Check: skip players whose health is under the Min slider (percent)
		if cfg.healthCheck then
			local maxHp = hum.MaxHealth
			if maxHp <= 0 then
				maxHp = 100
			end
			if hum.Health / maxHp * 100 < cfg.minHealth then
				return false
			end
		end
		local rootPart = char:FindFirstChild("HumanoidRootPart")
		if rootPart == nil then
			return false
		end
		local d = (rootPart.Position - origin).Magnitude
		return d >= cfg.minDist and d <= cfg.maxDist
	end

	-- Visible Check (raycast): a ray from the camera to the part. Nothing in the way, or only
	-- pieces of the target's own character in the way, means the part is visible.
	-- Your own character is ignored by the ray.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

	local function isVisible(cam, part, targetChar)
		local ignore = {}
		if player.Character then
			ignore[1] = player.Character
		end
		rayParams.FilterDescendantsInstances = ignore
		local from = cam.CFrame.Position
		local hit = workspace:Raycast(from, part.Position - from, rayParams)
		if hit == nil then
			return true
		end
		if targetChar and hit.Instance:IsDescendantOf(targetChar) then
			return true
		end
		return false
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

	-- the player whose hit part is nearest to ref. While the FOV is enabled only players whose
	-- hit part is inside the FOV shape count. With Visible Check on, players behind walls are skipped.
	local function acquire(cam, ref, origin, cfg, maxScreenDist)
		local bestPlr = nil
		local bestD = nil
		local radius = fovRadius()
		local all = Players:GetPlayers()
		for i = 1, #all do
			local plr = all[i]
			if plr ~= player and validTarget(plr, origin, cfg) then
				local part, d = bestPart(plr.Character, cam, ref, true, cfg.part)
				if part and cfg.fovOn then
					local v = cam:WorldToViewportPoint(part.Position)
					if not insideFov(v.X, v.Y, ref.X, ref.Y, radius, cfg.fovSides, fovAngle) then
						part = nil
					end
				end
				if part and (maxScreenDist == nil or d <= maxScreenDist) then
					if bestD == nil or d < bestD then
						-- the raycast is only done for a player that would win anyway
						if (not cfg.visCheck) or isVisible(cam, part, plr.Character) then
							bestPlr = plr
							bestD = d
						end
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
	-- FOV: the shape on the screen (a transparent overlay gui)
	---------------------------------------------------------------------
	local outlineSwatch = nil   -- the colour square on the FOV card (made when the card is built)
	local fillSwatch = nil      -- the colour square next to "Filled" in the FOV settings

	local fovGui = new("ScreenGui", {
		Name = "Y1AimbotFov",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 998,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	-- the box is centred on the cursor / screen middle. Everything inside is sized with scale,
	-- so resizing the box (Size slider, Dynamic FOV) resizes the shape without rebuilding it.
	local fovBox = new("Frame", {
		Name = "FovBox",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(240, 240),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, fovGui)

	-- the fill lives in a canvas group so the overlapping pieces of a filled polygon never show seams
	local fovFill = new("CanvasGroup", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 0.75,
		ZIndex = 1,
	}, fovBox)

	local fovLine = new("Frame", {
		Name = "Line",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, fovBox)

	local lineParts = {}   -- { inst, isStroke, mult } for every outline / glow piece
	local fillParts = {}   -- every frame of the fill

	-- the colours / opacity of everything already built
	local function recolor()
		for i = 1, #lineParts do
			local p = lineParts[i]
			local t = 1 - S.fovAlpha * p.mult
			if p.isStroke then
				p.inst.Color = S.fovColor
				p.inst.Transparency = t
			else
				p.inst.BackgroundColor3 = S.fovColor
				p.inst.BackgroundTransparency = t
			end
		end
		for i = 1, #fillParts do
			fillParts[i].BackgroundColor3 = S.fillColor
		end
		fovFill.GroupTransparency = 1 - S.fillAlpha
	end

	-- the x range of a regular polygon (first corner up, size 1x1) at height y; nil when y is outside it
	local function polyRange(n, y)
		local xmin = nil
		local xmax = nil
		for k = 0, n - 1 do
			local a1 = math.rad(-90 + 360 / n * k)
			local a2 = math.rad(-90 + 360 / n * (k + 1))
			local x1 = 0.5 + 0.5 * math.cos(a1)
			local y1 = 0.5 + 0.5 * math.sin(a1)
			local x2 = 0.5 + 0.5 * math.cos(a2)
			local y2 = 0.5 + 0.5 * math.sin(a2)
			if (y1 <= y and y2 >= y) or (y2 <= y and y1 >= y) then
				if math.abs(y2 - y1) < 1e-9 then
					xmin = math.min(xmin or x1, x1, x2)
					xmax = math.max(xmax or x1, x1, x2)
				else
					local x = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
					xmin = math.min(xmin or x, x)
					xmax = math.max(xmax or x, x)
				end
			end
		end
		return xmin, xmax
	end

	-- one outline (or glow) layer of a polygon: a thin rounded bar for every side
	local function addPolygonLayer(n, thickness, mult)
		for k = 0, n - 1 do
			local a1 = math.rad(-90 + 360 / n * k)
			local a2 = math.rad(-90 + 360 / n * (k + 1))
			local x1 = 0.5 + 0.5 * math.cos(a1)
			local y1 = 0.5 + 0.5 * math.sin(a1)
			local x2 = 0.5 + 0.5 * math.cos(a2)
			local y2 = 0.5 + 0.5 * math.sin(a2)
			local dx = x2 - x1
			local dy = y2 - y1
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2),
				Size = UDim2.new(math.sqrt(dx * dx + dy * dy), thickness, 0, thickness),
				Rotation = math.deg(math.atan2(dy, dx)),
				BorderSizePixel = 0,
			}, fovLine)
			corner(f, 100)
			lineParts[#lineParts + 1] = { inst = f, isStroke = false, mult = mult }
		end
	end

	-- builds the shape for the current angle count / filled / glow settings
	local function rebuildShape()
		fovFill:ClearAllChildren()
		fovLine:ClearAllChildren()
		lineParts = {}
		fillParts = {}
		local n = S.fovSides
		local circle = (n >= FOV_CIRCLE)

		-- the glow layers go first so the sharp line ends up on top
		local layers = { { t = 2, mult = 1 } }
		if S.fovGlow then
			layers = { { t = 11, mult = 0.12 }, { t = 6, mult = 0.28 }, { t = 2, mult = 1 } }
		end
		for li = 1, #layers do
			local L = layers[li]
			if circle then
				local ring = new("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
				}, fovLine)
				corner(ring, 1000)
				local st = Instance.new("UIStroke")
				st.Thickness = L.t
				st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				st.Parent = ring
				lineParts[#lineParts + 1] = { inst = st, isStroke = true, mult = L.mult }
			else
				addPolygonLayer(n, L.t, L.mult)
			end
		end

		if S.fovFilled then
			if circle then
				local f = new("Frame", {
					Size = UDim2.fromScale(1, 1),
					BorderSizePixel = 0,
				}, fovFill)
				corner(f, 1000)
				fillParts[#fillParts + 1] = f
			else
				-- a polygon is filled with thin horizontal strips. The number of strips follows the
				-- current size on the screen (about one strip per two pixels, at least 60, at most 240),
				-- so the slanted edges only have tiny steps that the outline covers.
				local M = math.clamp(math.ceil(fovRadius()), 60, 240)
				for i = 1, M do
					local xmin, xmax = polyRange(n, (i - 0.5) / M)
					if xmin and xmax then
						local f = new("Frame", {
							Position = UDim2.fromScale(xmin, (i - 1) / M),
							Size = UDim2.new(xmax - xmin, 0, 1 / M, 1),
							BorderSizePixel = 0,
						}, fovFill)
						fillParts[#fillParts + 1] = f
					end
				end
			end
		end
		recolor()
	end

	rebuildShape()

	-- the strips of a filled polygon depend on the size, so after the Size slider moves the shape is
	-- rebuilt once, a moment after the last change (not on every step of the drag)
	local rebuildToken = 0
	local function rebuildSoon()
		if not (S.fovFilled and S.fovSides < FOV_CIRCLE) then
			return
		end
		rebuildToken = rebuildToken + 1
		local tk = rebuildToken
		task.delay(0.2, function()
			if running and tk == rebuildToken then
				rebuildShape()
			end
		end)
	end

	-- follows the cursor (or the screen middle), keeps the size, runs Dynamic FOV
	local function fovStep(dt)
		if not running then
			return
		end
		if not S.fovOn then
			fovBox.Visible = false
			return
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local ref = refPoint(cam, S.aim == "Camera")

		if S.fovDynamic then
			local origin = originPos(cam)
			local nearest = nil
			local all = Players:GetPlayers()
			for i = 1, #all do
				local plr = all[i]
				if plr ~= player and validTarget(plr, origin, S) then
					local rp = plr.Character:FindFirstChild("HumanoidRootPart")
					if rp then
						local d = (rp.Position - origin).Magnitude
						if nearest == nil or d < nearest then
							nearest = d
						end
					end
				end
			end
			local goal = 1
			if nearest then
				goal = math.clamp(DYN_REF / math.max(nearest, 1), 0.5, 2)
			end
			fovScale = fovScale + (goal - fovScale) * math.min(1, dt * 8)
		else
			fovScale = 1
		end

		-- Spin: turn the shape; when it is off the shape stands upright again
		if S.fovSpin then
			fovAngle = (fovAngle + S.fovSpinSpeed * dt) % 360
		else
			fovAngle = 0
		end
		fovBox.Rotation = fovAngle

		local r = fovRadius()
		fovBox.Size = UDim2.fromOffset(r * 2, r * 2)
		fovBox.Position = UDim2.fromOffset(ref.X, ref.Y)
		fovBox.Visible = true
	end

	conns[#conns + 1] = RunService.RenderStepped:Connect(fovStep)

	---------------------------------------------------------------------
	-- COLOUR PICKER (one pop-up, shared by the outline colour and the fill colour)
	---------------------------------------------------------------------
	local picker = {}
	local pickerEntry = nil

	do
		local PW = 244
		local PH = 262
		local F = makeFloating("FovColorPicker", PW, PH)
		local pop = F.frame

		local h = 0
		local s = 0
		local v = 1
		local a = 1
		local onChange = nil
		local fmt = "HEX"
		local dragging = nil   -- "sv" / "hue" / "alpha" while the pointer is held down
		local WHITE = Color3.new(1, 1, 1)

		-- ----- saturation / brightness square -----
		local svBox = new("Frame", {
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(220, 150),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, pop)
		local svClip = new("CanvasGroup", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromHSV(0, 1, 1),
			BorderSizePixel = 0,
		}, svBox)
		corner(svClip, 8)
		local whiteOv = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, svClip)
		new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		}, whiteOv)
		local blackOv = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		}, svClip)
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		}, blackOv)
		local svKnob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, svBox)
		corner(svKnob, 100)
		stroke(svKnob, WHITE, 2, 0)
		local svHit = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, svBox)

		-- ----- hue bar -----
		local hueBox = new("Frame", {
			Position = UDim2.fromOffset(12, 172),
			Size = UDim2.fromOffset(220, 14),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, pop)
		local hueClip = new("CanvasGroup", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, hueBox)
		corner(hueClip, 7)
		new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
			}),
		}, hueClip)
		local hueKnob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(10, 22),
			BackgroundColor3 = Color3.fromRGB(255, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 3,
		}, hueBox)
		corner(hueKnob, 5)
		stroke(hueKnob, WHITE, 2, 0)
		local hueHit = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(-4, -4),
			Size = UDim2.new(1, 8, 1, 8),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, hueBox)

		-- ----- opacity bar (checkerboard + colour fading in) -----
		local alphaBox = new("Frame", {
			Position = UDim2.fromOffset(12, 196),
			Size = UDim2.fromOffset(220, 14),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, pop)
		local alphaClip = new("CanvasGroup", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(58, 58, 62),
			BorderSizePixel = 0,
		}, alphaBox)
		corner(alphaClip, 7)
		for row = 0, 1 do
			for col = 0, 31 do
				if (row + col) % 2 == 0 then
					new("Frame", {
						Position = UDim2.fromOffset(col * 7, row * 7),
						Size = UDim2.fromOffset(7, 7),
						BackgroundColor3 = Color3.fromRGB(92, 92, 98),
						BorderSizePixel = 0,
					}, alphaClip)
				end
			end
		end
		local alphaOverlay = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, alphaClip)
		new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		}, alphaOverlay)
		local alphaKnob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, alphaBox)
		corner(alphaKnob, 100)
		stroke(alphaKnob, Color3.fromRGB(40, 40, 44), 1, 0)
		local alphaHit = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(-4, -4),
			Size = UDim2.new(1, 8, 1, 8),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, alphaBox)

		-- ----- bottom row: format button | colour + value | opacity -----
		local fmtBtn = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(12, 222),
			Size = UDim2.fromOffset(58, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, pop)
		corner(fmtBtn, 8)
		local fmtLabel = label(fmtBtn, "HEX", UDim2.fromOffset(24, 0), UDim2.new(1, -28, 1, 0),
			Enum.Font.GothamMedium, 12, T.ICON_HOVER)
		local fmtChev = {}
		local function fmtBar(x, rot)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, x, 0.5, 0),
				Size = UDim2.fromOffset(6, 2),
				Rotation = rot,
				BackgroundColor3 = T.ICON,
				BorderSizePixel = 0,
			}, fmtBtn)
			corner(f, 1)
			fmtChev[#fmtChev + 1] = f
		end
		fmtBar(11, 45)
		fmtBar(15, -45)

		local valBox = new("Frame", {
			Position = UDim2.fromOffset(76, 222),
			Size = UDim2.fromOffset(100, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, pop)
		corner(valBox, 8)
		local miniSwatch = new("Frame", {
			Position = UDim2.fromOffset(8, 6),
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, valBox)
		corner(miniSwatch, 4)
		stroke(miniSwatch, T.BORDER, 1, 0)
		local valText = new("TextBox", {
			Position = UDim2.fromOffset(30, 0),
			Size = UDim2.new(1, -34, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Text = "",
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = T.TEXT_COLOR,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, valBox)

		local alphaBoxIn = new("Frame", {
			Position = UDim2.fromOffset(182, 222),
			Size = UDim2.fromOffset(50, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, pop)
		corner(alphaBoxIn, 8)
		local alphaText = new("TextBox", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Text = "100%",
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = T.TEXT_COLOR,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, alphaBoxIn)

		-- ----- logic -----
		local function textFor()
			local c = Color3.fromHSV(h, s, v)
			local r = math.floor(c.R * 255 + 0.5)
			local g = math.floor(c.G * 255 + 0.5)
			local b = math.floor(c.B * 255 + 0.5)
			if fmt == "HEX" then
				return string.format("#%02X%02X%02X%02X", r, g, b, math.floor(a * 255 + 0.5))
			elseif fmt == "RGB" then
				return r .. ", " .. g .. ", " .. b
			end
			return math.floor(h * 360 + 0.5) .. ", " .. math.floor(s * 100 + 0.5) .. ", " .. math.floor(v * 100 + 0.5)
		end

		-- draws everything for the current h / s / v / a. fire = also tell the owner about the new colour
		local function refresh(fire)
			local c = Color3.fromHSV(h, s, v)
			svClip.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svKnob.Position = UDim2.new(s, 0, 1 - v, 0)
			svKnob.BackgroundColor3 = c
			hueKnob.Position = UDim2.new(h, 0, 0.5, 0)
			hueKnob.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			alphaOverlay.BackgroundColor3 = c
			alphaKnob.Position = UDim2.new(a, 0, 0.5, 0)
			miniSwatch.BackgroundColor3 = c
			if not valText:IsFocused() then
				valText.Text = textFor()
			end
			if not alphaText:IsFocused() then
				alphaText.Text = math.floor(a * 100 + 0.5) .. "%"
			end
			if fire and onChange then
				onChange(c, a)
			end
		end

		local function fromPointer(p)
			if dragging == "sv" then
				local pos = svBox.AbsolutePosition
				local sz = svBox.AbsoluteSize
				if sz.X > 0 and sz.Y > 0 then
					s = math.clamp((p.X - pos.X) / sz.X, 0, 1)
					v = 1 - math.clamp((p.Y - pos.Y) / sz.Y, 0, 1)
				end
			elseif dragging == "hue" then
				local pos = hueBox.AbsolutePosition
				local sz = hueBox.AbsoluteSize
				if sz.X > 0 then
					h = math.clamp((p.X - pos.X) / sz.X, 0, 1)
				end
			elseif dragging == "alpha" then
				local pos = alphaBox.AbsolutePosition
				local sz = alphaBox.AbsoluteSize
				if sz.X > 0 then
					a = math.clamp((p.X - pos.X) / sz.X, 0, 1)
				end
			end
			refresh(true)
		end

		local function bindDrag(btn, name)
			btn.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					dragging = name
					fromPointer(pointerPos(input))
				end
			end)
		end
		bindDrag(svHit, "sv")
		bindDrag(hueHit, "hue")
		bindDrag(alphaHit, "alpha")

		conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
			if not dragging then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				fromPointer(pointerPos(input))
			end
		end)
		conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = nil
			end
		end)

		-- typed value
		valText.FocusLost:Connect(function()
			local txt = valText.Text
			if fmt == "HEX" then
				local hex = string.match(txt, "^%s*#?(%x+)%s*$")
				if hex and #hex == 3 then
					hex = string.gsub(hex, ".", function(ch)
						return ch .. ch
					end)
				end
				if hex and (#hex == 6 or #hex == 8) then
					local r = tonumber(string.sub(hex, 1, 2), 16)
					local g = tonumber(string.sub(hex, 3, 4), 16)
					local b = tonumber(string.sub(hex, 5, 6), 16)
					if r and g and b then
						h, s, v = Color3.fromRGB(r, g, b):ToHSV()
						if #hex == 8 then
							local al = tonumber(string.sub(hex, 7, 8), 16)
							if al then
								a = al / 255
							end
						end
					end
				end
			elseif fmt == "RGB" then
				local rs, gs, bs = string.match(txt, "^%s*(%d+)[%s,]+(%d+)[%s,]+(%d+)%s*$")
				if rs then
					h, s, v = Color3.fromRGB(math.clamp(tonumber(rs), 0, 255), math.clamp(tonumber(gs), 0, 255), math.clamp(tonumber(bs), 0, 255)):ToHSV()
				end
			else
				local hs, ss, vs = string.match(txt, "^%s*(%d+)[%s,]+(%d+)[%s,]+(%d+)%s*$")
				if hs then
					h = math.clamp(tonumber(hs), 0, 360) / 360
					s = math.clamp(tonumber(ss), 0, 100) / 100
					v = math.clamp(tonumber(vs), 0, 100) / 100
				end
			end
			refresh(true)
		end)

		alphaText.FocusLost:Connect(function()
			local n = tonumber(string.match(alphaText.Text, "[%d%.]+"))
			if n then
				a = math.clamp(n / 100, 0, 1)
			end
			refresh(true)
		end)

		-- the format button cycles HEX -> RGB -> HSV
		local fmtOver = false
		local function paintFmt()
			local bg = T.CLUSTER_BG
			local colr = T.ICON
			if fmtOver then
				bg = T.HOVER_GREY
				colr = T.ICON_HOVER
			end
			TweenService:Create(fmtBtn, FAST, { BackgroundColor3 = bg }):Play()
			for i = 1, #fmtChev do
				TweenService:Create(fmtChev[i], FAST, { BackgroundColor3 = colr }):Play()
			end
		end
		fmtBtn.MouseEnter:Connect(function()
			fmtOver = true
			paintFmt()
		end)
		fmtBtn.MouseLeave:Connect(function()
			fmtOver = false
			paintFmt()
		end)
		fmtBtn.Activated:Connect(function()
			if fmt == "HEX" then
				fmt = "RGB"
			elseif fmt == "RGB" then
				fmt = "HSV"
			else
				fmt = "HEX"
			end
			fmtLabel.Text = fmt
			refresh(false)
		end)

		-- ----- public -----
		picker.frame = pop
		picker.target = nil

		function picker.isOpen()
			return F.isOpen()
		end

		-- key = "outline" / "fill", anchor = the square that was clicked, color / alpha = what it shows now,
		-- cb(color3, alpha) is called while the colour changes, beside = a frame to sit next to (optional)
		function picker.open(key, anchor, color, alpha, cb, beside)
			picker.target = key
			onChange = nil
			h, s, v = color:ToHSV()
			a = alpha
			refresh(false)
			onChange = cb
			local pos = placeNear(anchor, PW, PH, beside)
			if F.isOpen() then
				F.move(pos)
			else
				F.open(pos)
			end
		end

		function picker.close()
			F.close()
			picker.target = nil
			dragging = nil
		end

		pickerEntry = {
			isOpen = function()
				return F.isOpen()
			end,
			close = picker.close,
			hit = { pop },
		}
		popupList[#popupList + 1] = pickerEntry
	end

	---------------------------------------------------------------------
	-- FOV SETTINGS (the pop-up behind the three dots on the FOV card)
	--   Enabled / Filled (+ colour square) / Glow / Size / Angles / Dynamic FOV
	---------------------------------------------------------------------
	local fovSettings = nil
	local fovDots = nil        -- the three dots on the FOV card (made when the card is built)
	local fovSub = nil         -- the line under "FOV" on the card
	local fovEntry = nil

	local function refreshFovStatus()
		if not fovSub then
			return
		end
		if S.fovOn then
			fovSub.Text = "On"
			fovSub.TextColor3 = T.GREEN
		else
			fovSub.Text = "Off"
			fovSub.TextColor3 = T.DIM_TEXT
		end
	end

	-- opens / closes the colour picker for "outline" or "fill"
	local function togglePicker(key, anchor)
		if picker.isOpen() and picker.target == key then
			picker.close()
			return
		end
		local color = S.fovColor
		local alpha = S.fovAlpha
		local cb = function(c, al)
			S.fovColor = c
			S.fovAlpha = al
			if outlineSwatch then
				outlineSwatch.paint(c)
			end
			recolor()
		end
		local beside = nil
		if key == "fill" then
			color = S.fillColor
			alpha = S.fillAlpha
			cb = function(c, al)
				S.fillColor = c
				S.fillAlpha = al
				if fillSwatch then
					fillSwatch.paint(c)
				end
				recolor()
			end
			if fovSettings.isOpen() then
				beside = fovSettings.frame
			end
		end
		picker.open(key, anchor, color, alpha, cb, beside)
	end

	do
		local FW = 264
		local FH = 312
		fovSettings = makeFloating("FovSettings", FW, FH)
		local pop = fovSettings.frame

		label(pop, "FOV", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
			Enum.Font.GothamBold, 14, T.TEXT_COLOR)
		new("Frame", {
			Position = UDim2.fromOffset(16, 40),
			Size = UDim2.new(1, -32, 0, 1),
			BackgroundColor3 = T.BORDER,
			BorderSizePixel = 0,
		}, pop)

		-- Enabled (off every time the script starts)
		label(pop, "Enabled", UDim2.fromOffset(16, 46), UDim2.new(1, -90, 0, 32),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		makeSwitch(pop, S.fovOn, function(on)
			S.fovOn = on
			refreshFovStatus()
		end, 62, 16)

		-- Filled: switch on the right, the fill colour square on its left
		label(pop, "Filled", UDim2.fromOffset(16, 80), UDim2.new(1, -120, 0, 32),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		makeSwitch(pop, S.fovFilled, function(on)
			S.fovFilled = on
			rebuildShape()
		end, 96, 16)
		fillSwatch = makeSwatch(pop, UDim2.new(1, -(16 + 38 + 10), 0, 96), S.fillColor, function()
			togglePicker("fill", fillSwatch.btn)
		end)

		-- Glow
		label(pop, "Glow", UDim2.fromOffset(16, 114), UDim2.new(1, -90, 0, 32),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		makeSwitch(pop, S.fovGlow, function(on)
			S.fovGlow = on
			rebuildShape()
		end, 130, 16)

		-- Size (radius in pixels). A filled polygon is rebuilt a moment after the slider stops.
		local sizeApi = makeSlider(pop, 152, "Size", 40, 20, 400, 5, S.fovSize, "%d", function(v)
			S.fovSize = v
			rebuildSoon()
		end)
		sizeApi.dim(true)

		-- Angles: 3 = triangle ... up to the maximum = circle
		local anglesApi = makeSlider(pop, 184, "Angles", 48, FOV_MIN_SIDES, FOV_CIRCLE, 1, S.fovSides, "%d", function(v)
			S.fovSides = v
			rebuildShape()
		end, function(v)
			if v >= FOV_CIRCLE then
				return "Circle"
			end
			return tostring(v)
		end)
		anglesApi.dim(true)

		-- Dynamic FOV
		label(pop, "Dynamic FOV", UDim2.fromOffset(16, 212), UDim2.new(1, -90, 0, 32),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		makeSwitch(pop, S.fovDynamic, function(on)
			S.fovDynamic = on
		end, 228, 16)

		-- Spin (turns the shape) with its own Speed slider (degrees per second)
		local spinApi = nil
		label(pop, "Spin", UDim2.fromOffset(16, 244), UDim2.new(1, -90, 0, 32),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		makeSwitch(pop, S.fovSpin, function(on)
			S.fovSpin = on
			if spinApi then
				spinApi.dim(on)
			end
		end, 260, 16)
		spinApi = makeSlider(pop, 280, "Speed", 44, 10, 720, 10, S.fovSpinSpeed, "%d", function(v)
			S.fovSpinSpeed = v
		end)
		spinApi.dim(S.fovSpin)

		local function openFov(anchor)
			if fovSettings.isOpen() then
				return
			end
			fovSettings.open(placeNear(anchor, FW, FH, nil))
			if fovDots then
				fovDots.open = true
				fovDots.paint()
			end
		end

		local function closeFov()
			fovSettings.close()
			if picker.isOpen() and picker.target == "fill" then
				picker.close()
			end
			if fovDots then
				fovDots.open = false
				fovDots.paint()
			end
		end

		fovSettings.openAt = openFov
		fovSettings.closeAll = closeFov

		fovEntry = {
			isOpen = function()
				return fovSettings.isOpen()
			end,
			close = closeFov,
			hit = { pop, picker.frame },
		}
		popupList[#popupList + 1] = fovEntry

		-- the colour picker must not close when the fill square is clicked
		table.insert(pickerEntry.hit, fillSwatch.btn)
	end

	---------------------------------------------------------------------
	-- AIMBOT PAGE
	--   left : Enable (switch + three dots), Hit Part, FILTERS (Team / Visible / Health)
	--   right: Distance (on top), Prediction, Smoothness, FOV
	---------------------------------------------------------------------
	aimP.section(1, "AIMBOT")

	local enableCard = aimP.place(1, 46)
	enableCard.ZIndex = 30   -- the settings panel opens from this card, so it must draw above the other cards

	label(enableCard, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local enableSub = label(enableCard, "", UDim2.fromOffset(14, 25), UDim2.new(1, -140, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)

	-- the small line under "Enable": Active while the aimbot is on, Off while it is off
	local function refreshStatus()
		if S.enabled then
			enableSub.Text = "Active"
			enableSub.TextColor3 = T.GREEN
		else
			enableSub.Text = "Off"
			enableSub.TextColor3 = T.DIM_TEXT
		end
	end

	setActive = function(v)
		if not S.enabled then
			v = false
		end
		active = v
		if not v then
			locked = nil
			resetCursor()
		end
		refreshStatus()
	end

	makeSwitch(enableCard, S.enabled, function(on)
		S.enabled = on
		setActive(false)
		refreshStatus()
	end, 23)

	-- three horizontal dots, left of the switch
	local enableDots = makeDots(enableCard, UDim2.new(1, -58, 0, 23))

	dropdownCard(aimP, 1, "Hit Part", PART_OPTIONS, S.part, function(v)
		S.part = v
		locked = nil
	end)

	-- left column: the filters
	aimP.section(1, "FILTERS")

	filterCard(aimP, 1, "Team Check", "Skip your teammates", S.teamCheck, function(on)
		S.teamCheck = on
		locked = nil
	end)

	filterCard(aimP, 1, "Visible Check", "Skip targets behind walls", S.visCheck, function(on)
		S.visCheck = on
		locked = nil
	end)

	-- Health Check has a slider under it: players below that health (in percent) are skipped
	do
		local hc = aimP.place(1, 82)
		label(hc, "Health Check", UDim2.fromOffset(14, 7), UDim2.new(1, -70, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		label(hc, "Skip low health targets", UDim2.fromOffset(14, 25), UDim2.new(1, -70, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		local hpApi = makeSlider(hc, 50, "Min", 28, 0, 100, 5, S.minHealth, "%d%%", function(v)
			S.minHealth = v
		end)
		hpApi.dim(S.healthCheck)
		makeSwitch(hc, S.healthCheck, function(on)
			S.healthCheck = on
			hpApi.dim(on)
			locked = nil
		end, 23)
	end

	-- right column, top: Distance
	aimP.section(2, "RANGE")
	rangeCard(aimP, 2, S)

	aimP.section(2, "ASSIST")

	switchSliders(aimP, 2, "Prediction", S.predOn, S.predX, S.predY,
		function(on) S.predOn = on end,
		function(v) S.predX = v end,
		function(v) S.predY = v end)

	switchSliders(aimP, 2, "Smoothness", S.smoothOn, S.smoothX, S.smoothY,
		function(on) S.smoothOn = on end,
		function(v) S.smoothX = v end,
		function(v) S.smoothY = v end)

	-- FOV: colour square + three dots (the settings are in the pop-up behind the dots)
	aimP.section(2, "FOV")

	local fovCard = aimP.place(2, 46)
	label(fovCard, "FOV", UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	fovSub = label(fovCard, "", UDim2.fromOffset(14, 25), UDim2.new(1, -140, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	refreshFovStatus()

	fovDots = makeDots(fovCard, UDim2.new(1, -12, 0.5, 0))
	outlineSwatch = makeSwatch(fovCard, UDim2.new(1, -(12 + 32 + 6), 0.5, 0), S.fovColor, function()
		togglePicker("outline", outlineSwatch.btn)
	end)

	fovDots.btn.Activated:Connect(function()
		if fovSettings.isOpen() then
			fovSettings.closeAll()
		else
			fovSettings.openAt(fovDots.btn)
		end
	end)

	-- clicks on the dots / the outline square must not count as "outside" for these pop-ups
	table.insert(fovEntry.hit, fovDots.btn)
	table.insert(pickerEntry.hit, outlineSwatch.btn)

	aimP.finish()

	-- the floating pop-ups stay where they opened, so they close when the page is scrolled
	conns[#conns + 1] = aimP.scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if fovEntry.isOpen() then
			fovEntry.close()
		end
		if pickerEntry.isOpen() then
			pickerEntry.close()
		end
	end)

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
		resetCursor()
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
		enableDots.open = true
		enableDots.paint()
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
		enableDots.open = false
		enableDots.paint()
	end

	enableDots.btn.Activated:Connect(function()
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
		hit = { popup, enableDots.btn },
	}

	refreshStatus()

	---------------------------------------------------------------------
	-- SILENT PAGE: a warning screen, built on top of the silent.lua module (silP.box, built further
	-- down this file)
	--   "yur1 warning" / shield / note / "I accept any risk" box / Confirm button
	-- Confirm looks disabled until the box is ticked. Once ticked and pressed, the warning fades out
	-- and the silent.lua controls (hidden behind it until now) fade in.
	---------------------------------------------------------------------
	do
		local GATE_W = 380
		local GATE_H = 236

		-- this is the one CanvasGroup under silP.holder (so it can fade as a whole) - its own
		-- children are plain shapes and labels, never another CanvasGroup, for the same reason
		-- silP.box above is not one
		local gate = new("CanvasGroup", {
			Name = "SilentWarning",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(GATE_W, GATE_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			GroupTransparency = 0,
		}, silP.holder)

		-- title
		label(gate, "yur1 warning", UDim2.fromOffset(0, 0), UDim2.fromOffset(GATE_W, 24),
			Enum.Font.GothamBold, 17, T.TEXT_COLOR, Enum.TextXAlignment.Center)

		-- security shield: a rounded block on top, a rounded square turned 45 degrees for the point,
		-- and an exclamation mark cut out of it (cut-outs use the window colour)
		local shield = new("Frame", {
			Name = "Shield",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 34),
			Size = UDim2.fromOffset(48, 50),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, gate)

		local SHIELD_COLOR = T.ICON_HOVER
		local blockTop = new("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(48, 26),
			BackgroundColor3 = SHIELD_COLOR,
			BorderSizePixel = 0,
		}, shield)
		corner(blockTop, 8)
		-- square corners for the lower part of the block so it flows straight into the point
		new("Frame", {
			Position = UDim2.fromOffset(0, 14),
			Size = UDim2.fromOffset(48, 12),
			BackgroundColor3 = SHIELD_COLOR,
			BorderSizePixel = 0,
		}, shield)
		local point = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(24, 26),
			Size = UDim2.fromOffset(36, 36),
			Rotation = 45,
			BackgroundColor3 = SHIELD_COLOR,
			BorderSizePixel = 0,
		}, shield)
		corner(point, 3)

		local exBar = new("Frame", {
			Position = UDim2.fromOffset(22, 11),
			Size = UDim2.fromOffset(4, 16),
			BackgroundColor3 = T.BLACK,
			BorderSizePixel = 0,
		}, shield)
		corner(exBar, 2)
		local exDot = new("Frame", {
			Position = UDim2.fromOffset(22, 31),
			Size = UDim2.fromOffset(4, 4),
			BackgroundColor3 = T.BLACK,
			BorderSizePixel = 0,
		}, shield)
		corner(exDot, 2)

		-- the note
		local note = label(gate,
			"<b>Note:</b> this module can get you banned due to it being easily detected in many games please go back if you dont want to get banned off this game",
			UDim2.fromOffset(0, 98), UDim2.fromOffset(GATE_W, 52), Enum.Font.Gotham, 12, T.ICON,
			Enum.TextXAlignment.Center)
		note.RichText = true
		note.TextWrapped = true
		note.TextTruncate = Enum.TextTruncate.None
		note.TextYAlignment = Enum.TextYAlignment.Top

		-- "I accept any risk" with a box you can tick
		local accepted = false
		local rowOver = false

		local row = new("TextButton", {
			Name = "AcceptRow",
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 164),
			Size = UDim2.fromOffset(150, 22),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, gate)

		local box = new("Frame", {
			Position = UDim2.fromOffset(0, 2),
			Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, row)
		corner(box, 5)
		local boxStroke = stroke(box, T.BORDER, 1, 0)

		-- tick mark: two bars
		local tickParts = {}
		local function tickBar(w, x, y, rot)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(w, 2),
				Rotation = rot,
				BackgroundColor3 = T.BLACK,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, box)
			corner(f, 1)
			tickParts[#tickParts + 1] = f
		end
		tickBar(5, 6, 11, 45)
		tickBar(9, 10, 9, -45)

		local acceptLabel = label(row, "I accept any risk", UDim2.fromOffset(28, 0), UDim2.new(1, -28, 1, 0),
			Enum.Font.GothamMedium, 13, T.ICON)

		-- the Confirm button: looks disabled until the box is ticked
		local confirm = new("TextButton", {
			Name = "Confirm",
			AutoButtonColor = false,
			Text = "Confirm",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 200),
			Size = UDim2.fromOffset(220, 34),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			TextColor3 = T.DIM_TEXT,
			TextTransparency = 0.35,
		}, gate)
		corner(confirm, 8)
		local confirmStroke = stroke(confirm, T.BORDER, 1, 0)
		local confirmOver = false

		local function paintBox()
			local fillColor = T.CLUSTER_BG
			local strokeColor = T.BORDER
			local tickT = 1
			local textColor = T.ICON
			if accepted then
				fillColor = T.JOIN_BG
				strokeColor = T.JOIN_BG
				tickT = 0
				textColor = T.TEXT_COLOR
			elseif rowOver then
				strokeColor = T.HOVER_GREY
				textColor = T.ICON_HOVER
			end
			TweenService:Create(box, FAST, { BackgroundColor3 = fillColor }):Play()
			TweenService:Create(boxStroke, FAST, { Color = strokeColor }):Play()
			TweenService:Create(acceptLabel, FAST, { TextColor3 = textColor }):Play()
			for i = 1, #tickParts do
				TweenService:Create(tickParts[i], FAST, { BackgroundTransparency = tickT }):Play()
			end
		end

		local function paintConfirm()
			if accepted then
				local bg = T.JOIN_BG
				if confirmOver then
					bg = Color3.fromRGB(255, 255, 255)
				end
				TweenService:Create(confirm, FAST, { BackgroundColor3 = bg, TextColor3 = T.BLACK, TextTransparency = 0 }):Play()
				TweenService:Create(confirmStroke, FAST, { Color = T.JOIN_BG }):Play()
			else
				TweenService:Create(confirm, FAST, { BackgroundColor3 = T.CLUSTER_BG, TextColor3 = T.DIM_TEXT, TextTransparency = 0.35 }):Play()
				TweenService:Create(confirmStroke, FAST, { Color = T.BORDER }):Play()
			end
		end

		row.MouseEnter:Connect(function()
			rowOver = true
			paintBox()
		end)
		row.MouseLeave:Connect(function()
			rowOver = false
			paintBox()
		end)
		row.Activated:Connect(function()
			accepted = not accepted
			paintBox()
			paintConfirm()
		end)

		confirm.MouseEnter:Connect(function()
			confirmOver = true
			paintConfirm()
		end)
		confirm.MouseLeave:Connect(function()
			confirmOver = false
			paintConfirm()
		end)
		confirm.Activated:Connect(function()
			if not accepted then
				return
			end
			-- the warning fades out and is hidden; the silent.lua module (built into silP.box,
			-- a plain frame, further down) is simply revealed behind it
			TweenService:Create(gate, FAST, { GroupTransparency = 1 }):Play()
			task.delay(FAST.Time + 0.02, function()
				gate.Visible = false
				silP.box.Visible = true
			end)
		end)
	end

	---------------------------------------------------------------------
	-- TRIGGERBOT PAGE: no warning and nothing on it here. Its content is triggerbot.lua (see below).
	---------------------------------------------------------------------

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

		-- a locked target that walked behind a wall is let go (Visible Check)
		if S.lockOn and S.visCheck and not isVisible(cam, part, locked.Character) then
			locked = nil
			return
		end

		local pos = aimPosition(part, S)
		local ax = alphaFor(S.smoothX, dt)
		local ay = alphaFor(S.smoothY, dt)

		-- MOUSE aim with a free cursor: move the real cursor, never touch the camera.
		-- The cursor only shows its new position a frame or two after it was moved, so a move is only
		-- sent once the last one has shown up. Never more than half of the remaining distance is asked
		-- for at once, and how far the cursor really goes for what we ask is measured and corrected for
		-- (pointer acceleration and display scaling would otherwise make it swing across the screen).
		if S.aim == "Mouse" and not mouseIsLocked() then
			if moveRel == nil then
				if not warnedMove then
					warnedMove = true
					warn("[aimbot] this executor has no mousemoverel, so Mouse aim cannot move the cursor. Use Aim Type: Camera.")
				end
				return
			end
			local v, onScreen = cam:WorldToViewportPoint(pos)
			if not onScreen then
				return   -- off the screen or behind the camera
			end

			-- the last move has not shown up yet: wait (at most 3 frames), then learn from it
			if cur.waiting then
				local movedX = ref.X - cur.lastX
				local movedY = ref.Y - cur.lastY
				if movedX == 0 and movedY == 0 and cur.waitFrames < 3 then
					cur.waitFrames = cur.waitFrames + 1
					return
				end
				cur.waiting = false
				local denom = cur.cmdX * cur.cmdX + cur.cmdY * cur.cmdY
				if denom > 0 then
					local g = (movedX * cur.cmdX + movedY * cur.cmdY) / denom
					if g > 0.2 and g < 6 then
						cur.gain = cur.gain * 0.5 + g * 0.5
					end
				end
			end

			local dx = v.X - ref.X
			local dy = v.Y - ref.Y
			if math.sqrt(dx * dx + dy * dy) < 2 then
				accX = 0
				accY = 0
				return
			end

			-- cover part of the distance now (never more than half), and never more than 200 pixels
			local wantX = dx * math.min(ax, 0.5)
			local wantY = dy * math.min(ay, 0.5)
			local wantLen = math.sqrt(wantX * wantX + wantY * wantY)
			if wantLen > 200 then
				wantX = wantX * 200 / wantLen
				wantY = wantY * 200 / wantLen
			end

			-- ask for a bit more or less if the cursor has been going further or less far than asked
			accX = accX + wantX / cur.gain
			accY = accY + wantY / cur.gain
			local mx = wholePart(accX)
			local my = wholePart(accY)
			if mx ~= 0 or my ~= 0 then
				accX = accX - mx
				accY = accY - my
				cur.lastX = ref.X
				cur.lastY = ref.Y
				cur.cmdX = mx
				cur.cmdY = my
				cur.waitFrames = 0
				cur.waiting = (math.abs(mx) + math.abs(my)) >= 4
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
	-- SILENT + TRIGGERBOT MODULES (silent.lua and triggerbot.lua)
	-- They are loaded by main.lua and built from here, each into the container of its own page.
	-- A module that is missing or breaks is skipped (a warning is printed), the aimbot is not affected.
	---------------------------------------------------------------------
	local subHandles = {}
	do
		local ctx = {
			Settings = S,
			Targeting = {
				refPoint = refPoint,
				validTarget = validTarget,
				acquire = acquire,
				bestPart = bestPart,
				aimPosition = aimPosition,
				isVisible = isVisible,
				originPos = originPos,
			},
		}

		local function loadSub(mod, box, name)
			if type(mod) ~= "table" or type(mod.build) ~= "function" then
				return
			end
			local ok, res = pcall(mod.build, box, T, H, ctx)
			if not ok then
				warn("[aimbot] " .. name .. " failed: " .. tostring(res))
			elseif type(res) == "table" then
				subHandles[#subHandles + 1] = res
			end
		end

		loadSub(opts.SilentModule, silP.box, "silent.lua")
		loadSub(opts.TriggerbotModule, trigP.box, "triggerbot.lua")
	end

	---------------------------------------------------------------------
	-- THE AIMBOT / SILENT / TRIGGERBOT SWITCH AT THE BOTTOM
	---------------------------------------------------------------------
	local subOrder = { "Aimbot", "Silent", "Triggerbot" }
	local subPages = { Aimbot = aimP, Silent = silP, Triggerbot = trigP }
	local currentSub = "Aimbot"
	local subToken = 0

	local function showSub(name)
		if name == currentSub or not subPages[name] then
			return
		end
		currentSub = name
		closeAllPopups()
		subToken = subToken + 1
		local tk = subToken

		-- every other page fades out
		for pageName, pg in pairs(subPages) do
			if pageName ~= name then
				TweenService:Create(pg.holder, FAST, { GroupTransparency = 1 }):Play()
				task.delay(0.14, function()
					if tk == subToken then
						pg.holder.Visible = false
					end
				end)
			end
		end

		-- the chosen page fades in and slides up a little
		local showP = subPages[name]
		showP.holder.Position = UDim2.fromOffset(0, 8)
		showP.holder.GroupTransparency = 1
		showP.holder.Visible = true
		TweenService:Create(showP.holder, SMOOTH, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }):Play()
	end

	do
		local COUNT = #subOrder

		local tray = new("Frame", {
			Name = "ModeSwitch",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.fromOffset(300, 32),
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
			Size = UDim2.new(1 / COUNT, 0, 1, 0),
			BackgroundColor3 = T.HOVER_GREY,
			BorderSizePixel = 0,
		}, inner)
		corner(slider, RADIUS + 1)

		local tabBtns = {}

		local function paintTabs(animate)
			local index = 1
			for i = 1, COUNT do
				if subOrder[i] == currentSub then
					index = i
				end
			end
			local pos = UDim2.new((index - 1) / COUNT, 0, 0, 0)
			if animate then
				TweenService:Create(slider, SMOOTH, { Position = pos }):Play()
			else
				slider.Position = pos
			end
			for i = 1, COUNT do
				local colr = T.ICON
				if i == index then
					colr = T.ICON_HOVER
				end
				TweenService:Create(tabBtns[i], FAST, { TextColor3 = colr }):Play()
			end
		end

		for i = 1, COUNT do
			local b = new("TextButton", {
				AutoButtonColor = false,
				Position = UDim2.new((i - 1) / COUNT, 0, 0, 0),
				Size = UDim2.new(1 / COUNT, 0, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = subOrder[i],
				TextColor3 = T.ICON,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
			}, inner)
			tabBtns[i] = b
			b.Activated:Connect(function()
				showSub(subOrder[i])
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
		for i = 1, #subHandles do
			local h = subHandles[i]
			if type(h.Unload) == "function" then
				pcall(h.Unload)
			end
		end
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
