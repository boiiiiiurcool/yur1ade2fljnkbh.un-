-- silent.lua  (Y1 Combat tab: the Silent Aim page content, as its own module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- aimbot.lua builds this module into its Silent page, behind the "yur1 warning" screen: the page starts
-- hidden and faded out, and only fades in once the box is ticked and Confirm is pressed (aimbot.lua
-- handles the warning itself; this file only has to assume it may already be visible when it is built).
-- main.lua loads this file next to aimbot.lua and hands it over, so nothing else has to change.
--
--   local SilentPage = <this file>
--   SilentPage.build(container, themeTable, helperTable, ctx)
--   ctx = { Settings = the aimbot settings table (read only, not used here),
--           Targeting = { refPoint, validTarget, acquire, bestPart, aimPosition, isVisible, originPos } }
--   returns { Root = ..., Unload = fn }  (aimbot.lua calls Unload when the Y1 window is unloaded)
--
-- HOW SILENT AIM WORKS HERE: instead of moving the camera or the cursor (like the Aimbot tab), it simply
-- fires at whichever valid target it finds, while the fire key is held - there is nothing to aim. A target
-- counts as valid once it passes every filter below, including a raycast "wall check" (Visible Check) that
-- makes sure a real shot would actually reach them. This reuses the same target-picking helpers the Aimbot
-- tab uses (ctx.Targeting: validTarget, bestPart, isVisible, refPoint, originPos), with a Knocked Check
-- added on top (the one filter those helpers do not already do).
--
-- The page is laid out exactly like the Aimbot / Triggerbot pages: two columns of cards, the same switches,
-- dots panel, sliders and drop-downs.
--   Left column   Enable row   a switch (OFF every time the script starts) and a "..." (three dots) button.
--                              The line under "Enable" says Active while it is on (Off when it is off).
--                              The dots open one small settings panel (Key, Mode, Target Lock).
--                              Click the dots again, or anywhere else, to close it.
--                 Hit Part     a drop-down: Head (default) / Body / Left Leg / Right Leg / Left Arm /
--                              Right Arm / Closest Part - which part of a player it fires at
--                 FILTERS      Team Check     ON = never fires at players on your team
--                              Visible Check  ON = the wall check: a raycast from the camera to the hit
--                                             part has to be clear, so it never fires at someone it
--                                             cannot really hit
--                              Health Check   ON = skips players below the Min slider (percent of max health)
--                              Knocked Check  ON = skips players who are knocked out. ZEE HOOD ONLY: it
--                                             reads the K.O bool at workspace.Players.<name>.BodyEffects
--                                             ["K.O"] (true = knocked out). In other games it never finds
--                                             that value, so it does nothing.
--                              All four are off every time the script runs.
--   Right column  Distance     Min / Max studs (from your character) the target has to be between
--
--   Key / Mode / Target Lock (in the dots panel)
--     Key          click it, then press a key or a mouse button (default: Mouse 2)
--     Mode         Hold = armed while you hold the key, Toggle = press once to arm, press again to disarm
--     Target Lock  ON = keeps firing at the same target instead of picking the nearest one every frame
--                  (it still lets go the moment that target is no longer valid)
--
-- HOW IT FIRES: it holds the Tool you are wielding Activated for as long as a target stays valid
-- (Activate() when one appears, Deactivate() the moment it does not). If your game fires some other
-- way, change pressFire() and releaseFire() below.
--
-- It switches itself off and cleans up when the Y1 window is unloaded.

local SilentPage = {}

function SilentPage.build(container, T, H, ctx)
	ctx = ctx or {}
	local Targeting = ctx.Targeting or {}

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
	local STEP_NAME = string.format("Y1SilentStep_%d_%d", math.floor(os.clock() * 1000), math.random(1, 1000000))

	---------------------------------------------------------------------
	-- SETTINGS + STATE
	---------------------------------------------------------------------
	local PART_OPTIONS = { "Head", "Body", "Left Leg", "Right Leg", "Left Arm", "Right Arm", "Closest Part" }

	local S = {
		enabled = false,      -- starts OFF every time the script runs
		keybind = Enum.UserInputType.MouseButton2,
		mode = "Hold",
		lockOn = false,       -- Target Lock
		part = "Head",
		minDist = 0,
		maxDist = 1000,
		teamCheck = false,
		visCheck = false,     -- Wall Check, off every time the script runs
		healthCheck = false,
		minHealth = 20,       -- percent; used while Health Check is on
		knockedCheck = false, -- Zee Hood only, off every time the script runs
	}

	local active = false      -- armed (the key is held / toggled on)
	local locked = nil        -- the current target while Target Lock is on
	local firing = false
	local firingTool = nil
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
	end

	local function setActive(v)
		if not S.enabled then
			v = false
		end
		active = v
		if not v then
			locked = nil
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
	-- Mouse: GetMouseLocation is in the same screen space as AbsolutePosition. Touch: the input position
	-- may or may not include the top inset on a given device, so both readings are tried.
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
	-- PAGE LAYOUT: a scrolling page with two columns of cards (same as aimbot.lua / triggerbot.lua)
	---------------------------------------------------------------------
	local BODY_Y = 2
	local GAP = 8

	local scroll = new("ScrollingFrame", {
		Name = "SilentRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.ICON,
		ScrollBarImageTransparency = 0.5,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ElasticBehavior = Enum.ElasticBehavior.Never,
	}, container)

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
	-- CONTROLS (the same look as aimbot.lua / triggerbot.lua)
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
	-- y0 = top of the caption, inset = space left and right. "cnt" (not "container") so it never
	-- shadows this module's own container parameter.
	local function segmented(cnt, y0, inset, title, options, startValue, onChange)
		label(cnt, title, UDim2.fromOffset(inset + 2, y0), UDim2.new(1, -(inset * 2), 0, 12),
			Enum.Font.Gotham, 11, T.DIM_TEXT)

		local tray = new("Frame", {
			Position = UDim2.fromOffset(inset, y0 + 18),
			Size = UDim2.new(1, -(inset * 2), 0, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, cnt)
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
	local dropZ = 29   -- each drop-down card sits one step under the one above it, so its list is never covered
	local function dropdownCard(col, title, options, startValue, onChange)
		local c = place(col, 46)
		c.ZIndex = dropZ
		dropZ = dropZ - 1

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
	--   left : Enable (switch + three dots), Hit Part, FILTERS
	--   right: Distance
	---------------------------------------------------------------------
	section(1, "SILENT AIM")

	local enableCard = place(1, 46)
	enableCard.ZIndex = 30   -- the settings panel opens from this card, so it must draw above the other cards

	label(enableCard, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local enableSub = label(enableCard, "", UDim2.fromOffset(14, 25), UDim2.new(1, -140, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)

	-- the small line under "Enable": Active while silent aim is on, Off while it is off
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

	dropdownCard(1, "Hit Part", PART_OPTIONS, S.part, function(v)
		S.part = v
		locked = nil
	end)

	section(1, "FILTERS")

	filterCard(1, "Team Check", "Never fire at your team", S.teamCheck, function(on)
		S.teamCheck = on
		locked = nil
	end)

	-- Visible Check doubles as the "wall check": a raycast from the camera to the hit part has to be
	-- clear, so it never fires at someone it cannot really hit
	filterCard(1, "Visible Check", "Wall check - skip targets a wall blocks", S.visCheck, function(on)
		S.visCheck = on
		locked = nil
	end)

	-- Health Check has a slider under it: players below that health (in percent) are skipped
	do
		local hc = place(1, 82)
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

	-- Knocked Check: Zee Hood only (the line under the title says so)
	do
		local kc = place(1, 46)
		label(kc, "Knocked Check", UDim2.fromOffset(14, 7), UDim2.new(1, -70, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		local kSub = label(kc, '<font color="rgb(230,230,234)"><b>Zee Hood only</b></font> - skips K.O players',
			UDim2.fromOffset(14, 25), UDim2.new(1, -70, 0, 14), Enum.Font.Gotham, 11, T.DIM_TEXT)
		kSub.RichText = true
		makeSwitch(kc, S.knockedCheck, function(on)
			S.knockedCheck = on
			locked = nil
		end, 23)
	end

	-- right column
	section(2, "RANGE")
	rangeCard(2)

	finish()

	---------------------------------------------------------------------
	-- SETTINGS PANEL (opens from the three dots; ONE background for everything inside)
	--   Silent Aim (title) / Key / Mode / Target Lock
	---------------------------------------------------------------------
	local POP_W = 264
	local POP_H = 204
	-- it sits right next to the dots (the dots end 58px from the right edge of the card)
	local POP_SHOWN = UDim2.new(1, -50, 0, -8)
	local POP_HIDDEN = UDim2.new(1, -60, 0, -8)
	local OPEN_INFO = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local CLOSE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local popup = new("CanvasGroup", {
		Name = "SilentSettings",
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

	-- top left: "Silent Aim"
	label(popup, "Silent Aim", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
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

	line(146)

	-- Target Lock (one line, switch on the right)
	label(popup, "Target Lock", UDim2.fromOffset(16, 156), UDim2.new(1, -90, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	makeSwitch(popup, S.lockOn, function(on)
		S.lockOn = on
		locked = nil
	end, 170, 16)

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
	-- KNOCKED CHECK (ZEE HOOD ONLY) - the one filter ctx.Targeting does not already do
	---------------------------------------------------------------------
	local function isKnocked(char)
		local be = char:FindFirstChild("BodyEffects")
		if be == nil then
			local folder = workspace:FindFirstChild("Players")
			local model = nil
			if folder then
				model = folder:FindFirstChild(char.Name)
			end
			if model then
				be = model:FindFirstChild("BodyEffects")
			end
		end
		if be then
			local ko = be:FindFirstChild("K.O")
			if ko and ko:IsA("BoolValue") then
				return ko.Value
			end
		end
		return false
	end

	---------------------------------------------------------------------
	-- TARGETING: built on top of ctx.Targeting (the same raycast / filter helpers the Aimbot tab
	-- uses), with Knocked Check added on top
	---------------------------------------------------------------------
	local function pickTarget(cam, ref, origin)
		local cfg = {
			teamCheck = S.teamCheck,
			visCheck = S.visCheck,
			healthCheck = S.healthCheck,
			minHealth = S.minHealth,
			minDist = S.minDist,
			maxDist = S.maxDist,
			part = S.part,
			fovOn = false,   -- silent aim has no FOV shape; it does not need the crosshair at all
		}

		local function ok(plr)
			if not Targeting.validTarget(plr, origin, cfg) then
				return false
			end
			if S.knockedCheck and plr.Character and isKnocked(plr.Character) then
				return false
			end
			return true
		end

		-- Target Lock: keep the current target while it is still valid and (if Visible Check is on)
		-- still has a clear raycast
		if S.lockOn and locked and locked.Parent and ok(locked) then
			local part = Targeting.bestPart(locked.Character, cam, ref, false, S.part)
			if part and ((not S.visCheck) or Targeting.isVisible(cam, part, locked.Character)) then
				return locked, part
			end
		end

		-- otherwise: whichever valid target's hit part is nearest to the cursor on screen
		local bestPlr = nil
		local bestHitPart = nil
		local bestD = nil
		local all = Players:GetPlayers()
		for i = 1, #all do
			local plr = all[i]
			if plr ~= player and ok(plr) then
				local part, d = Targeting.bestPart(plr.Character, cam, ref, true, S.part)
				if part and ((not S.visCheck) or Targeting.isVisible(cam, part, plr.Character)) then
					if bestD == nil or d < bestD then
						bestPlr = plr
						bestHitPart = part
						bestD = d
					end
				end
			end
		end

		if S.lockOn then
			locked = bestPlr
		end
		return bestPlr, bestHitPart
	end

	---------------------------------------------------------------------
	-- MAIN STEP: fires at whatever pickTarget() returns - no delay, no release timer. It holds the
	-- Tool Activated for as long as a target stays valid and lets go the moment it is not.
	---------------------------------------------------------------------
	local function step(dt)
		if not running or not active then
			return
		end
		local cam = workspace.CurrentCamera
		if not cam or not Targeting.refPoint or not Targeting.originPos or not Targeting.validTarget
			or not Targeting.bestPart then
			return
		end

		local ref = Targeting.refPoint(cam, false)
		local origin = Targeting.originPos(cam)
		local target = pickTarget(cam, ref, origin)
		local near = target ~= nil

		if near and not firing then
			if pressFire() then
				firing = true
			end
		elseif (not near) and firing then
			stopFiring()
		elseif firing and (firingTool == nil or firingTool.Parent ~= player.Character) then
			-- the tool was unequipped or removed while we were firing
			stopFiring()
		end
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
		local a = container
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
	conns[#conns + 1] = container.AncestryChanged:Connect(function()
		if not container:IsDescendantOf(game) then
			unload()
		end
	end)

	return { Root = scroll, Unload = unload }
end

return SilentPage
