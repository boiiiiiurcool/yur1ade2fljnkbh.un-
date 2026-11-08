-- triggerbot.lua  (Y1 Combat tab: the Triggerbot page, as its own module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- aimbot.lua builds this module into its Triggerbot page (the third button of the switch at the bottom of
-- the Combat tab). main.lua loads this file next to aimbot.lua and hands it over, so nothing else has to change.
--
--   local Triggerbot = <this file>
--   Triggerbot.build(container, themeTable, helperTable, ctx)
--   ctx = { Settings = the aimbot settings table (read only), Targeting = { ... } }   (both optional)
--   returns { Root = ..., Unload = fn }  (aimbot.lua calls Unload when the Y1 window is unloaded)
--
-- The page is laid out like the aimbot page: two columns of cards.
--   Left column   Enable row   a switch (OFF every time the script starts) and a "..." (three dots) button.
--                              The line under "Enable" says Active while it is on (Off when it is off).
--                              The dots open one small settings panel (Key, Mode).
--                              Click the dots again, or anywhere else, to close it.
--                 Hit Part     a drop-down: Any / Head / Body = which part of a player the crosshair has to be on
--                 Timing       Delay   = ms the crosshair has to stay on a target before it fires
--                              Release = ms the fire button is held before it lets go (0 = hold until
--                                        the crosshair leaves the target)
--                 FILTERS      Team Check  ON = never fires at players on your team
--   Right column  Distance     Min / Max studs (from your character) the target has to be between
--                 Moving Targets   Hitbox = extra pixels around the crosshair (9 rays instead of 1)
--                                  Lead   = ms ahead it predicts where a moving player will be
--                                  Grace  = ms it keeps the lock when the target flickers off for a moment
--
--   Key / Mode   Click the key button, then press a key or a mouse button (default: T).
--                Hold = armed while you hold the key, Toggle = press once to arm, press again to disarm.
--                The key only does something while Enable is on.
--
-- HOW IT DECIDES: it casts a ray from the cursor (or from the screen middle in shift lock / first person /
-- when the aimbot's Aim Type is Camera). The ray ignores your own character and skips invisible,
-- non-collidable parts, so thin triggers or invisible walls do not block it, but real walls do.
-- It only fires when the first real thing the ray hits belongs to a living player.
--
-- HOW IT FIRES: it calls Activate() / Deactivate() on the Tool you are holding. If your game
-- has its own fire function, change pressFire() and releaseFire() below.
--
-- It runs one step after the aimbot (so it uses the camera after the aimbot has moved it) and
-- switches itself off and cleans up when the Y1 window is unloaded.

local TriggerbotPage = {}

function TriggerbotPage.build(parent, T, H, ctx)
	ctx = ctx or {}
	local A = ctx.Settings or {}   -- the aimbot settings: only A.aim is read (Camera = crosshair is the screen middle)

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
	local STEP_NAME = string.format("Y1TriggerStep_%d_%d", math.floor(os.clock() * 1000), math.random(1, 1000000))

	---------------------------------------------------------------------
	-- SETTINGS + STATE
	---------------------------------------------------------------------
	local S = {
		enabled = false,      -- starts OFF every time the script runs
		keybind = Enum.KeyCode.T,
		mode = "Hold",
		part = "Any",
		delayMs = 0,
		releaseMs = 15,
		minDist = 0,
		maxDist = 1000,
		teamCheck = true,
		tolPx = 6,            -- hitbox grow in pixels (extra rays + extra on-screen size)
		leadMs = 40,          -- how far ahead to predict moving targets
		graceMs = 50,         -- keep the lock this long after the target flickers off
	}

	local active = false      -- armed (the key is held / toggled on)
	local firing = false      -- fire button is down right now
	local firingTool = nil
	local waitStart = nil     -- when the crosshair first landed on a target
	local fireStart = 0
	local lastHit = 0         -- last time the crosshair was on a target
	local listening = nil
	local running = true
	local conns = {}
	local popupList = {}      -- every popup registers here so one click outside can close them all

	---------------------------------------------------------------------
	-- FIRE HOOKS (change these if your game fires some other way)
	---------------------------------------------------------------------
	local function pressFire()
		local char = player.Character
		if not char then
			return false
		end
		local tool = char:FindFirstChildOfClass("Tool")
		if not tool then
			return false
		end
		firingTool = tool
		tool:Activate()
		return true
	end

	local function releaseFire()
		local tool = firingTool
		firingTool = nil
		if tool and tool.Parent then
			tool:Deactivate()
		end
	end

	local function stopFiring()
		if firing then
			firing = false
			releaseFire()
		end
		waitStart = nil
	end

	local function setActive(v)
		if not S.enabled then
			v = false
		end
		active = v
		if not v then
			stopFiring()
		end
	end

	---------------------------------------------------------------------
	-- SMALL HELPERS
	---------------------------------------------------------------------
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
	-- ignores the top inset). Touch: the input position may or may not include the top inset on a
	-- given device, so both readings are tried.
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
	-- PAGE LAYOUT: a scrolling page with two columns of cards (same as the aimbot page)
	---------------------------------------------------------------------
	local BODY_Y = 2
	local GAP = 8

	local scroll = new("ScrollingFrame", {
		Name = "TriggerbotRoot",
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

	-- size the page to its content
	local function finish()
		local bodyH = math.max(colY[1], colY[2]) - GAP
		body.Size = UDim2.new(1, -12, 0, bodyH)
		scroll.CanvasSize = UDim2.new(0, 0, 0, BODY_Y + bodyH + 8)
	end

	---------------------------------------------------------------------
	-- CONTROLS (the same look as the aimbot page)
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

	-- a slider row inside a card; returns { dim = fn(enabled), set = fn(value) }
	local function makeSlider(c, y, name, labelW, minV, maxV, stepV, startValue, fmt, setValue)
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

	-- a small filter card: title + a dim line under it on the left, a switch on the right
	local function filterCard(col, title, subText, startOn, onChange)
		local c = place(col, 46)
		label(c, title, UDim2.fromOffset(14, 7), UDim2.new(1, -70, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		label(c, subText, UDim2.fromOffset(14, 25), UDim2.new(1, -70, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		makeSwitch(c, startOn, onChange, 23)
		return c
	end

	-- the Distance card (Min / Max)
	local function rangeCard(col)
		local c = place(col, 104)
		label(c, "Distance", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 0, 36),
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

	-- a drop-down card: the title on the left, a button with the current value on the right.
	-- Clicking the button opens a small vertical list (a pop-up). Pick one, or click anywhere else to close it.
	local function dropdownCard(col, title, options, startValue, onChange)
		local c = place(col, 46)
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
	-- THE PAGE
	--   left : Enable (switch + three dots), Hit Part, Timing, FILTERS (Team Check)
	--   right: Distance, Moving Targets
	---------------------------------------------------------------------
	section(1, "TRIGGERBOT")

	local enableCard = place(1, 46)
	enableCard.ZIndex = 30   -- the settings panel opens from this card, so it must draw above the other cards

	label(enableCard, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local enableSub = label(enableCard, "", UDim2.fromOffset(14, 25), UDim2.new(1, -140, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)

	-- the small line under "Enable": Active while the triggerbot is on, Off while it is off
	local function refreshStatus()
		if S.enabled then
			enableSub.Text = "Active"
			enableSub.TextColor3 = T.GREEN
		else
			enableSub.Text = "Off"
			enableSub.TextColor3 = T.DIM_TEXT
		end
	end

	makeSwitch(enableCard, S.enabled, function(on)
		S.enabled = on
		setActive(false)
		refreshStatus()
	end, 23)

	-- three horizontal dots, left of the switch
	local enableDots = makeDots(enableCard, UDim2.new(1, -58, 0, 23))

	dropdownCard(1, "Hit Part", { "Any", "Head", "Body" }, S.part, function(v)
		S.part = v
	end)

	-- Timing: delay before firing, how long the button is held
	do
		local c = place(1, 106)
		label(c, "Timing (ms)", UDim2.fromOffset(14, 6), UDim2.new(1, -28, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		label(c, "Release 0 = hold until the crosshair leaves", UDim2.fromOffset(14, 23), UDim2.new(1, -28, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		local delayApi = makeSlider(c, 44, "Delay", 50, 0, 500, 1, S.delayMs, "%d", function(v)
			S.delayMs = v
		end)
		local releaseApi = makeSlider(c, 74, "Release", 50, 0, 500, 1, S.releaseMs, "%d", function(v)
			S.releaseMs = v
		end)
		delayApi.dim(true)
		releaseApi.dim(true)
	end

	section(1, "FILTERS")

	filterCard(1, "Team Check", "Never fire at your team", S.teamCheck, function(on)
		S.teamCheck = on
	end)

	-- right column
	section(2, "RANGE")
	rangeCard(2)

	section(2, "ASSIST")

	-- Moving Targets: tuning for players that are moving
	do
		local c = place(2, 136)
		label(c, "Moving Targets", UDim2.fromOffset(14, 6), UDim2.new(1, -28, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		label(c, "Hitbox px, Lead ms, Grace ms", UDim2.fromOffset(14, 23), UDim2.new(1, -28, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		local hitboxApi = makeSlider(c, 44, "Hitbox", 50, 0, 30, 1, S.tolPx, "%d", function(v)
			S.tolPx = v
		end)
		local leadApi = makeSlider(c, 74, "Lead", 50, 0, 150, 1, S.leadMs, "%d", function(v)
			S.leadMs = v
		end)
		local graceApi = makeSlider(c, 104, "Grace", 50, 0, 150, 1, S.graceMs, "%d", function(v)
			S.graceMs = v
		end)
		hitboxApi.dim(true)
		leadApi.dim(true)
		graceApi.dim(true)
	end

	finish()

	---------------------------------------------------------------------
	-- SETTINGS PANEL (opens from the three dots; ONE background for everything inside)
	--   Triggerbot (title) / Key / Mode
	---------------------------------------------------------------------
	local POP_W = 264
	local POP_H = 152
	-- it sits right next to the dots (the dots end 58px from the right edge of the card)
	local POP_SHOWN = UDim2.new(1, -50, 0, -8)
	local POP_HIDDEN = UDim2.new(1, -60, 0, -8)
	local OPEN_INFO = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local CLOSE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local popup = new("CanvasGroup", {
		Name = "TriggerbotSettings",
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

	-- top left: "Triggerbot"
	label(popup, "Triggerbot", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)

	new("Frame", {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, popup)

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
	-- DETECTION (raycast)
	---------------------------------------------------------------------
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

	-- where the ray goes through the screen: the cursor, or the middle when the mouse is locked
	-- (shift lock / first person) or when the aimbot's Aim Type is Camera
	local function refPoint(cam)
		if A.aim == "Camera" or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			local vs = cam.ViewportSize
			return Vector2.new(vs.X / 2, vs.Y / 2)
		end
		return UserInputService:GetMouseLocation()
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

	-- a part we should look through: invisible and not solid (trigger zones, invisible markers)
	local function seeThrough(inst)
		return inst.Transparency >= 0.95 and not inst.CanCollide
	end

	local function isHeadPart(inst)
		if inst.Name == "Head" then
			return true
		end
		-- hats / hair: the accessory weld is attached to the head
		if inst:FindFirstAncestorOfClass("Accessory") then
			local weld = inst:FindFirstChildWhichIsA("Weld")
			if weld and weld.Part1 and weld.Part1.Name == "Head" then
				return true
			end
		end
		return false
	end

	-- returns true when the crosshair is on a valid, living, in-range enemy player
	local function castHit(rayOrigin, rayDir, origin)
		local dir = rayDir.Unit * (S.maxDist + 100)

		local exclude = {}
		if player.Character then
			exclude[1] = player.Character
		end

		for i = 1, 16 do
			rayParams.FilterDescendantsInstances = exclude
			local res = workspace:Raycast(rayOrigin, dir, rayParams)
			if res == nil then
				return false
			end
			local inst = res.Instance
			local model = inst:FindFirstAncestorOfClass("Model")
			local hum = nil
			if model then
				hum = model:FindFirstChildOfClass("Humanoid")
			end

			if hum then
				-- a character: is it a living player we are allowed to shoot?
				local plr = Players:GetPlayerFromCharacter(model)
				if plr == nil or plr == player then
					return false
				end
				if hum.Health <= 0 then
					-- dead body: look through it
					exclude[#exclude + 1] = model
				else
					if S.teamCheck and plr.Team ~= nil and plr.Team == player.Team then
						return false
					end
					local d = (res.Position - origin).Magnitude
					if d < S.minDist or d > S.maxDist then
						return false
					end
					if S.part == "Head" then
						return isHeadPart(inst)
					elseif S.part == "Body" then
						return not isHeadPart(inst)
					end
					return true
				end
			elseif seeThrough(inst) then
				exclude[#exclude + 1] = inst
			else
				-- a real wall, floor or object is in the way
				return false
			end
		end
		return false
	end

	-- extra rays in a ring around the crosshair (grows the hitbox, catches moving targets)
	local OFFSETS = {
		{ 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
		{ 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 },
	}

	-- is there a clear line (walls only) from the camera to a point on this character?
	local function lineClear(camPos, point, char)
		local exclude = {}
		if player.Character then
			exclude[1] = player.Character
		end
		local dir = point - camPos
		for i = 1, 12 do
			rayParams.FilterDescendantsInstances = exclude
			local res = workspace:Raycast(camPos, dir, rayParams)
			if res == nil then
				return true
			end
			local inst = res.Instance
			if inst:IsDescendantOf(char) then
				return true
			end
			local model = inst:FindFirstAncestorOfClass("Model")
			local hum = nil
			if model then
				hum = model:FindFirstChildOfClass("Humanoid")
			end
			if hum and hum.Health <= 0 then
				exclude[#exclude + 1] = model
			elseif seeThrough(inst) then
				exclude[#exclude + 1] = inst
			else
				return false
			end
		end
		return false
	end

	-- screen-space check, works at any distance: project the target (a few ms ahead if it is
	-- moving) onto the screen and see if the crosshair is inside its on-screen size plus the
	-- Hitbox pixels. Ray hits get tiny and unreliable far away; this does not. A wall-only ray
	-- to the target makes sure nothing solid is in the way.
	local function candidateParts(char)
		local list = {}
		local head = char:FindFirstChild("Head")
		local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
			or char:FindFirstChild("HumanoidRootPart")
		-- only real parts go in the list (a missing head or torso would leave a nil hole)
		if S.part ~= "Body" and head and head:IsA("BasePart") then
			list[#list + 1] = head
		end
		if S.part ~= "Head" and torso and torso:IsA("BasePart") then
			list[#list + 1] = torso
		end
		return list
	end

	local function predictedHit(cam, ref, origin)
		local lead = S.leadMs / 1000
		local vs = cam.ViewportSize
		local tanHalf = math.tan(math.rad(cam.FieldOfView) / 2)
		local camPos = cam.CFrame.Position
		local all = Players:GetPlayers()
		for i = 1, #all do
			local plr = all[i]
			if plr ~= player then
				local char = plr.Character
				local hum = nil
				local rootPart = nil
				if char then
					hum = char:FindFirstChildOfClass("Humanoid")
					rootPart = char:FindFirstChild("HumanoidRootPart")
				end
				local teamBlocked = S.teamCheck and plr.Team ~= nil and plr.Team == player.Team
				if hum and rootPart and hum.Health > 0 and not teamBlocked then
					local d = (rootPart.Position - origin).Magnitude
					if d >= S.minDist and d <= S.maxDist then
						local vel = rootPart.AssemblyLinearVelocity
						local ahead = Vector3.new(0, 0, 0)
						if vel.Magnitude > 1 then
							ahead = vel * lead
						end
						local parts = candidateParts(char)
						for k = 1, #parts do
							local part = parts[k]
							local pp = part.Position + ahead
							local v, onScreen = cam:WorldToViewportPoint(pp)
							if onScreen and v.Z > 0 then
								local pxPerStud = vs.Y / (2 * v.Z * tanHalf)
								local r = (part.Size.X + part.Size.Y) * 0.25
								local rpx = r * pxPerStud + S.tolPx
								local off = (Vector2.new(v.X, v.Y) - ref).Magnitude
								if off <= rpx and lineClear(camPos, pp, char) then
									return true
								end
							end
						end
					end
				end
			end
		end
		return false
	end

	-- true when the crosshair is on a valid target right now (or about to be, for movers)
	local function onTarget(cam)
		local ref = refPoint(cam)
		local origin = originPos(cam)
		local tol = S.tolPx
		local n = 1
		if tol > 0 then
			n = #OFFSETS
		end
		for i = 1, n do
			local o = OFFSETS[i]
			local ray = cam:ViewportPointToRay(ref.X + o[1] * tol, ref.Y + o[2] * tol)
			if castHit(ray.Origin, ray.Direction, origin) then
				return true
			end
		end
		return predictedHit(cam, ref, origin)
	end

	---------------------------------------------------------------------
	-- MAIN STEP
	---------------------------------------------------------------------
	local function step(dt)
		if not running or not active then
			return
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end

		local now = os.clock()
		local hit = onTarget(cam)
		if hit then
			lastHit = now
		end
		-- "near" = on target now, or was a moment ago (jitter, strafing, lag spikes)
		local near = hit or (now - lastHit) * 1000 <= S.graceMs

		if firing then
			local done = false
			local held = (now - fireStart) * 1000
			if S.releaseMs > 0 then
				if held >= S.releaseMs then
					done = true
				end
			else
				if not near then
					done = true
				end
			end
			-- the tool was unequipped or removed
			if firingTool == nil or firingTool.Parent ~= player.Character then
				done = true
			end
			if done then
				stopFiring()
				-- still on the target: the next shot needs no new delay
				if hit then
					waitStart = now - S.delayMs / 1000
				end
			end
			return
		end

		if not near then
			waitStart = nil
			return
		end
		-- the grace time only keeps an existing lock alive, it never starts a new one
		if not hit and waitStart == nil then
			return
		end

		if waitStart == nil then
			waitStart = now
		end
		if (now - waitStart) * 1000 >= S.delayMs then
			if pressFire() then
				firing = true
				fireStart = now
				waitStart = nil
			end
		end
	end

	pcall(function()
		RunService:UnbindFromRenderStep(STEP_NAME)
	end)
	-- one step after the aimbot (Camera + 1) so it uses the camera after it has been moved
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, step)

	-- also check again right after physics every frame: twice as many checks per frame,
	-- so it reacts sooner and the release timing is more exact
	conns[#conns + 1] = RunService.Heartbeat:Connect(step)

	---------------------------------------------------------------------
	-- INPUT
	---------------------------------------------------------------------
	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if not running then
			return
		end

		-- recording a new key for the bind button
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

		-- keys respect "processed" (typing in chat); mouse buttons ignore it
		local isMouseBind = S.keybind.EnumType ~= Enum.KeyCode
		if processed and not isMouseBind then
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

	-- leaving this page (or the Combat tab) closes every pop-up: watch the page and everything above it
	do
		local a = parent
		while a and a:IsA("GuiObject") do
			local node = a
			conns[#conns + 1] = node:GetPropertyChangedSignal("Visible"):Connect(function()
				if not node.Visible then
					closeAllPopups()
				end
			end)
			a = a.Parent
		end
	end

	---------------------------------------------------------------------
	-- UNLOAD (aimbot.lua calls this when the Y1 window is unloaded)
	---------------------------------------------------------------------
	local function unload()
		if not running then
			return
		end
		stopFiring()
		running = false
		active = false
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
	conns[#conns + 1] = parent.AncestryChanged:Connect(function()
		if not parent:IsDescendantOf(game) then
			unload()
		end
	end)

	return { Root = scroll, Unload = unload }
end

return TriggerbotPage
