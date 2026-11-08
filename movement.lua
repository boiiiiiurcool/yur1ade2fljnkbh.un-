-- movement.lua  (Y1 Misc tab > Movement page)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Ten cards, two per row. Every card is an Enable switch + three dots (same style as the Extra page).
-- The dots open ONE shared pop-up with:
--   Keybind : click it, then press a key (Escape or Backspace clears it)
--   Mode    : Always = on the moment the switch is on, no key needed
--             Toggle = the keybind turns it on / off
--             Hold   = on only while the keybind is held down
--   slider  : only for the features that have a value (not No Clip, Inf Jump, Spider Man)
-- Every switch is OFF each time the script starts. Turning a feature off (or unloading) puts back
-- what it changed (walk speed, jump power, gravity, hip height, collisions, fps cap...).
--
-- Features:
--   Walk Speed  - sets your WalkSpeed
--   Fly         - fly where the camera looks (W A S D, Space = up, Left Ctrl or Q = down)
--   Jump Power  - sets your jump power
--   Gravity     - changes workspace gravity
--   Tickrate    - sets how often your client updates (the fps cap). The server's own tick rate
--                 cannot be changed from a client, so this only changes your side.
--                 Needs an executor with setfpscap.
--   Bunny Hop   - holding Space keeps you jumping the moment you land, at the speed on the slider
--   No Clip     - walk through walls
--   Inf Jump    - jump again in mid air
--   Spider Man  - walk into a wall and you climb it
--   Float       - changes your hip height so you hover above the ground
--
-- Build signature: Movement.build(container, T, H, ctx) -> { Root = ..., Unload = fn }

local MovementPage = {}

function MovementPage.build(parent, T, H, ctx)
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local GuiService = game:GetService("GuiService")
	local player = Players.LocalPlayer

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH
	local RADIUS = T.RADIUS

	local running = true
	local conns = {}
	local popupList = {}

	local MODES = { "Always", "Toggle", "Hold" }

	---------------------------------------------------------------------
	-- the features
	---------------------------------------------------------------------
	local DEFS = {
		{ id = "walkspeed", title = "Walk Speed",
			slider = { name = "Speed", min = 16, max = 250, step = 1, value = 50, fmt = "%d" } },
		{ id = "fly", title = "Fly",
			slider = { name = "Speed", min = 10, max = 300, step = 5, value = 60, fmt = "%d" } },
		{ id = "jumppower", title = "Jump Power",
			slider = { name = "Power", min = 50, max = 500, step = 5, value = 100, fmt = "%d" } },
		{ id = "gravity", title = "Gravity",
			slider = { name = "Gravity", min = 0, max = 300, step = 1, value = 98, fmt = "%d" } },
		{ id = "tickrate", title = "Tickrate",
			slider = { name = "Rate", min = 5, max = 360, step = 5, value = 60, fmt = "%d" },
			warn = function()
				if type(setfpscap) ~= "function" then
					return "Your executor has no setfpscap, so this does nothing."
				end
				return nil
			end },
		{ id = "bhop", title = "Bunny Hop",
			slider = { name = "Speed", min = 16, max = 120, step = 1, value = 40, fmt = "%d" } },
		{ id = "noclip", title = "No Clip" },
		{ id = "infjump", title = "Inf Jump" },
		{ id = "spider", title = "Spider Man" },
		{ id = "float", title = "Float",
			slider = { name = "Height", min = 0, max = 30, step = 0.5, value = 6, fmt = "%.1f" } },
	}

	local F = {}   -- feature state by id
	for i = 1, #DEFS do
		local d = DEFS[i]
		local v = 0
		if d.slider then
			v = d.slider.value
		end
		F[d.id] = {
			def = d,
			enabled = false,
			mode = "Always",
			key = nil,
			value = v,
			toggled = false,
			held = false,
		}
	end

	local function isActive(f)
		if not f.enabled then
			return false
		end
		if f.mode == "Always" then
			return true
		end
		if f.mode == "Toggle" then
			return f.toggled
		end
		return f.held
	end

	---------------------------------------------------------------------
	-- pointer helpers (same idea as extra.lua)
	---------------------------------------------------------------------
	local function inRect(obj, x, y)
		local p = obj.AbsolutePosition
		local sz = obj.AbsoluteSize
		return x >= p.X and x <= p.X + sz.X and y >= p.Y and y <= p.Y + sz.Y
	end

	local function pointerOver(obj, input)
		local inset = GuiService:GetGuiInset()
		local ix = input.Position.X
		local iy = input.Position.Y
		if input.UserInputType == Enum.UserInputType.Touch then
			return inRect(obj, ix, iy) or inRect(obj, ix + inset.X, iy + inset.Y)
		end
		local m = UserInputService:GetMouseLocation()
		return inRect(obj, m.X, m.Y)
			or inRect(obj, m.X - inset.X, m.Y - inset.Y)
			or inRect(obj, ix, iy)
			or inRect(obj, ix + inset.X, iy + inset.Y)
	end

	---------------------------------------------------------------------
	-- root + pop-up helpers
	---------------------------------------------------------------------
	local root = new("Frame", {
		Name = "MovementRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

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

	local function rectIn(obj)
		local s = uiScale()
		local rp = root.AbsolutePosition
		local p = obj.AbsolutePosition
		local z = obj.AbsoluteSize
		return (p.X - rp.X) / s, (p.Y - rp.Y) / s, z.X / s, z.Y / s
	end

	local function placeNear(anchor, w, h, beside)
		local s = uiScale()
		local rw = root.AbsoluteSize.X / s
		local rh = root.AbsoluteSize.Y / s
		local ax, ay, aw = rectIn(anchor)
		local x = ax + aw + 8
		local y = ay
		if x + w > rw - 4 then
			x = ax - 8 - w
		end
		if beside then
			local bx, by, bw = rectIn(beside)
			if bx - 8 - w >= 4 then
				x = bx - 8 - w
			else
				x = bx + bw + 8
			end
			y = by
		end
		x = math.clamp(x, 4, math.max(4, rw - w - 4))
		y = math.clamp(y, 4, math.max(4, rh - h - 4))
		return UDim2.fromOffset(math.floor(x), math.floor(y))
	end

	local FL_OPEN = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local FL_CLOSE = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local function makeFloating(name, w, h)
		local P = { flag = false, token = 0 }
		P.frame = new("CanvasGroup", {
			Name = name,
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = T.POPUP_BG,
			BorderSizePixel = 0,
			GroupTransparency = 1,
			Visible = false,
			ZIndex = 60,
		}, root)
		corner(P.frame, RADIUS + 4)
		stroke(P.frame, T.BORDER, 1, 0)

		function P.isOpen()
			return P.flag
		end
		function P.open(pos)
			P.token = P.token + 1
			P.flag = true
			P.frame.Position = pos + UDim2.fromOffset(0, 6)
			P.frame.GroupTransparency = 1
			P.frame.Visible = true
			TweenService:Create(P.frame, FL_OPEN, { Position = pos, GroupTransparency = 0 }):Play()
		end
		function P.move(pos)
			TweenService:Create(P.frame, SMOOTH, { Position = pos }):Play()
		end
		function P.close()
			if not P.flag then
				return
			end
			P.flag = false
			P.token = P.token + 1
			local tk = P.token
			TweenService:Create(P.frame, FL_CLOSE, {
				Position = P.frame.Position + UDim2.fromOffset(0, 6),
				GroupTransparency = 1,
			}):Play()
			task.delay(FL_CLOSE.Time + 0.02, function()
				if tk == P.token then
					P.frame.Visible = false
				end
			end)
		end
		return P
	end

	---------------------------------------------------------------------
	-- small controls
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

	---------------------------------------------------------------------
	-- cards (two columns, five rows)
	---------------------------------------------------------------------
	local ROW_STEP = 74
	local refreshSub = nil
	local openFor = nil
	local closePop = nil
	local cur = nil   -- the feature the pop-up is showing

	for i = 1, #DEFS do
		local d = DEFS[i]
		local f = F[d.id]
		local col = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		local cardY = 24 + row * ROW_STEP

		local pos = UDim2.fromOffset(2, cardY)
		local capPos = UDim2.fromOffset(4, cardY - 18)
		if col == 1 then
			pos = UDim2.new(0.5, 4, 0, cardY)
			capPos = UDim2.new(0.5, 6, 0, cardY - 18)
		end

		local card = new("Frame", {
			Name = d.id .. "Card",
			Position = pos,
			Size = UDim2.new(0.5, -6, 0, 46),
			BackgroundColor3 = T.SIDEBAR_BG,
			BorderSizePixel = 0,
		}, root)
		corner(card, RADIUS + 4)
		stroke(card, T.BORDER, 1, 0)

		label(root, string.upper(d.title), capPos, UDim2.new(0.5, -10, 0, 14),
			Enum.Font.GothamMedium, 11, T.DIM_TEXT)

		label(card, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		f.sub = label(card, "", UDim2.fromOffset(14, 25), UDim2.new(1, -100, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		f.sub.RichText = true

		makeSwitch(card, false, function(on)
			f.enabled = on
			f.toggled = false
			f.held = false
			refreshSub(f)
		end, 23)

		f.dots = makeDots(card, UDim2.new(1, -58, 0, 23))
		f.dots.btn.Activated:Connect(function()
			if cur == f then
				closePop()
				return
			end
			openFor(f)
		end)
	end

	local function keyName(f)
		if f.key then
			return f.key.Name
		end
		return "None"
	end

	refreshSub = function(f)
		local state = '<font color="rgb(116,116,124)">Off</font>'
		if f.enabled then
			if isActive(f) then
				state = '<font color="rgb(52,199,120)">Active</font>'
			else
				state = '<font color="rgb(230,230,234)">Ready</font>'
			end
		end
		local modeText = f.mode
		if f.mode ~= "Always" then
			modeText = f.mode .. " [" .. keyName(f) .. "]"
		end
		f.sub.Text = '<font color="rgb(230,230,234)"><b>' .. modeText .. '</b></font> - ' .. state
	end
	for i = 1, #DEFS do
		refreshSub(F[DEFS[i].id])
	end

	---------------------------------------------------------------------
	-- the shared settings pop-up
	---------------------------------------------------------------------
	local PW = 280
	local P = makeFloating("MovementSettings", PW, 168)
	local pop = P.frame
	local listening = nil   -- the feature waiting for a key

	local popTitle = label(pop, "", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)
	new("Frame", {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, pop)

	-- keybind row
	label(pop, "Keybind", UDim2.fromOffset(16, 50), UDim2.fromOffset(100, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local keyBtn = new("TextButton", {
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 50),
		Size = UDim2.fromOffset(112, 28),
		BackgroundColor3 = T.CLUSTER_BG,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = T.ICON_HOVER,
		Text = "None",
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, pop)
	corner(keyBtn, RADIUS + 2)
	keyBtn.MouseEnter:Connect(function()
		TweenService:Create(keyBtn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
	end)
	keyBtn.MouseLeave:Connect(function()
		TweenService:Create(keyBtn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
	end)
	keyBtn.Activated:Connect(function()
		if not cur then
			return
		end
		listening = cur
		keyBtn.Text = "Press a key..."
	end)

	-- mode row (drop-down with a drawn chevron)
	label(pop, "Mode", UDim2.fromOffset(16, 86), UDim2.fromOffset(100, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local modeBtn = new("TextButton", {
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 86),
		Size = UDim2.fromOffset(112, 28),
		BackgroundColor3 = T.CLUSTER_BG,
		BorderSizePixel = 0,
	}, pop)
	corner(modeBtn, RADIUS + 2)
	local modeLabel = label(modeBtn, "Always", UDim2.fromOffset(10, 0), UDim2.new(1, -34, 1, 0),
		Enum.Font.GothamMedium, 12, T.ICON_HOVER)

	local arrow = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -15, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, modeBtn)
	local arms = {}
	local function addArm(x, rot)
		local a = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, x, 0.5, 0),
			Size = UDim2.fromOffset(7, 2),
			Rotation = rot,
			BackgroundColor3 = T.DIM_TEXT,
			BorderSizePixel = 0,
		}, arrow)
		corner(a, 1)
		arms[#arms + 1] = a
	end
	addArm(-2.5, 45)
	addArm(2.5, -45)

	local modeOver = false
	local modeOpen = false
	local function paintArrow()
		local colr = T.DIM_TEXT
		if modeOver or modeOpen then
			colr = T.ICON_HOVER
		end
		for i = 1, #arms do
			TweenService:Create(arms[i], FAST, { BackgroundColor3 = colr }):Play()
		end
		local rot = 0
		if modeOpen then
			rot = 180
		end
		TweenService:Create(arrow, SMOOTH, { Rotation = rot }):Play()
	end
	modeBtn.MouseEnter:Connect(function()
		modeOver = true
		paintArrow()
		TweenService:Create(modeBtn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
	end)
	modeBtn.MouseLeave:Connect(function()
		modeOver = false
		paintArrow()
		TweenService:Create(modeBtn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
	end)

	local OPT_H = 26
	local LIST_W = 112
	local LIST_H = #MODES * OPT_H + 8
	local ML = makeFloating("MovementModeList", LIST_W, LIST_H)
	ML.frame.ZIndex = 70
	local optButtons = {}

	local function paintOptions()
		for i = 1, #optButtons do
			if cur and MODES[i] == cur.mode then
				optButtons[i].BackgroundTransparency = 0
			else
				optButtons[i].BackgroundTransparency = 1
			end
		end
	end

	local function closeMode()
		if ML.isOpen() then
			ML.close()
		end
		modeOpen = false
		paintArrow()
	end

	for i = 1, #MODES do
		local ob = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(4, 4 + (i - 1) * OPT_H),
			Size = UDim2.new(1, -8, 0, OPT_H - 2),
			BackgroundColor3 = T.HOVER_GREY,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, ML.frame)
		corner(ob, RADIUS)
		label(ob, MODES[i], UDim2.fromOffset(10, 0), UDim2.new(1, -20, 1, 0),
			Enum.Font.GothamMedium, 12, T.TEXT_COLOR)
		optButtons[i] = ob
		ob.MouseEnter:Connect(function()
			ob.BackgroundTransparency = 0
		end)
		ob.MouseLeave:Connect(function()
			if cur and MODES[i] == cur.mode then
				ob.BackgroundTransparency = 0
			else
				ob.BackgroundTransparency = 1
			end
		end)
		ob.Activated:Connect(function()
			if cur then
				cur.mode = MODES[i]
				cur.toggled = false
				cur.held = false
				modeLabel.Text = cur.mode
				refreshSub(cur)
			end
			paintOptions()
			closeMode()
		end)
	end

	modeBtn.Activated:Connect(function()
		if ML.isOpen() then
			closeMode()
			return
		end
		paintOptions()
		ML.open(placeNear(modeBtn, LIST_W, LIST_H, pop))
		modeOpen = true
		paintArrow()
	end)

	-- slider row (only shown for features that have a value)
	local sb = new("Frame", {
		Position = UDim2.fromOffset(0, 128),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, pop)
	local sbName = label(sb, "", UDim2.fromOffset(16, 2), UDim2.fromOffset(64, 20),
		Enum.Font.GothamMedium, 12, T.ICON)
	local sbVal = label(sb, "", UDim2.new(1, -60, 0, 2), UDim2.fromOffset(46, 20),
		Enum.Font.GothamMedium, 12, T.TEXT_COLOR, Enum.TextXAlignment.Right)
	local SX0 = 16 + 64 + 6
	local track = new("Frame", {
		Position = UDim2.fromOffset(SX0, 9),
		Size = UDim2.new(1, -(SX0 + 68), 0, 6),
		BackgroundColor3 = T.CLUSTER_BG,
		BorderSizePixel = 0,
	}, sb)
	corner(track, 3)
	local fill = new("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = T.ICON_HOVER,
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
	local sbHit = new("TextButton", {
		AutoButtonColor = false,
		Text = "",
		Position = UDim2.fromOffset(SX0, 2),
		Size = UDim2.new(1, -(SX0 + 68), 0, 20),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, sb)

	local dragging = false

	local function refreshSlider()
		if not cur or not cur.def.slider then
			return
		end
		local sl = cur.def.slider
		local fr = (cur.value - sl.min) / (sl.max - sl.min)
		fill.Size = UDim2.new(fr, 0, 1, 0)
		knob.Position = UDim2.new(fr, 0, 0.5, 0)
		sbVal.Text = string.format(sl.fmt, cur.value)
	end

	local function setFromX(px)
		if not cur or not cur.def.slider then
			return
		end
		local sl = cur.def.slider
		local w = sbHit.AbsoluteSize.X
		if w <= 0 then
			return
		end
		local fr = math.clamp((px - sbHit.AbsolutePosition.X) / w, 0, 1)
		local v = sl.min + math.floor(fr * (sl.max - sl.min) / sl.step + 0.5) * sl.step
		cur.value = math.clamp(v, sl.min, sl.max)
		refreshSlider()
	end

	sbHit.InputBegan:Connect(function(input)
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

	local warnLbl = label(pop, "", UDim2.fromOffset(16, 156), UDim2.new(1, -32, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)

	-- pop-up open / close
	local popEntry = nil

	local function paintAllDots()
		for i = 1, #DEFS do
			local f = F[DEFS[i].id]
			f.dots.open = (f == cur) and P.isOpen()
			f.dots.paint()
		end
	end

	openFor = function(f)
		cur = f
		listening = nil
		closeMode()
		popTitle.Text = f.def.title
		keyBtn.Text = keyName(f)
		modeLabel.Text = f.mode

		local height = 128
		local sl = f.def.slider
		sb.Visible = (sl ~= nil)
		if sl then
			sbName.Text = sl.name
			refreshSlider()
			height = 166
		end
		local warnText = nil
		if f.def.warn then
			warnText = f.def.warn()
		end
		if warnText then
			warnLbl.Text = warnText
			warnLbl.Position = UDim2.fromOffset(16, height - 8)
			warnLbl.Visible = true
			height = height + 22
		else
			warnLbl.Visible = false
		end
		pop.Size = UDim2.fromOffset(PW, height)

		popEntry.hit[3] = f.dots.btn
		local target = placeNear(f.dots.btn, PW, height, nil)
		if P.isOpen() then
			P.move(target)
		else
			P.open(target)
		end
		paintAllDots()
	end

	closePop = function()
		P.close()
		closeMode()
		listening = nil
		dragging = false
		cur = nil
		paintAllDots()
	end

	popEntry = {
		isOpen = function()
			return P.isOpen()
		end,
		close = closePop,
		hit = { pop, ML.frame, pop },
	}
	popupList[#popupList + 1] = popEntry
	popupList[#popupList + 1] = {
		isOpen = function()
			return ML.isOpen()
		end,
		close = closeMode,
		hit = { ML.frame, modeBtn },
	}

	-- a click or tap anywhere outside an open pop-up closes it
	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input)
		if not running then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
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
	end)

	-- leaving this page (or the Misc tab) closes the pop-up
	do
		local a = parent
		while a and a:IsA("GuiObject") do
			local node = a
			conns[#conns + 1] = node:GetPropertyChangedSignal("Visible"):Connect(function()
				if not node.Visible and P.isOpen() then
					closePop()
				end
			end)
			a = a.Parent
		end
	end

	---------------------------------------------------------------------
	-- keybinds
	---------------------------------------------------------------------
	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if not running then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		-- waiting for a key to bind
		if listening then
			local f = listening
			listening = nil
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
				f.key = nil
			elseif input.KeyCode ~= Enum.KeyCode.Unknown then
				f.key = input.KeyCode
			end
			f.toggled = false
			f.held = false
			if cur == f then
				keyBtn.Text = keyName(f)
			end
			refreshSub(f)
			return
		end

		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		for i = 1, #DEFS do
			local f = F[DEFS[i].id]
			if f.key and f.key == input.KeyCode then
				if f.mode == "Toggle" then
					f.toggled = not f.toggled
					refreshSub(f)
				elseif f.mode == "Hold" then
					f.held = true
					refreshSub(f)
				end
			end
		end
	end)

	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		for i = 1, #DEFS do
			local f = F[DEFS[i].id]
			if f.key and f.key == input.KeyCode and f.mode == "Hold" and f.held then
				f.held = false
				refreshSub(f)
			end
		end
	end)

	---------------------------------------------------------------------
	-- THE MOVEMENT CODE
	---------------------------------------------------------------------
	local act = {}            -- which features are active this frame
	local origWS = nil
	local origJump = nil
	local origHip = nil
	local origGravity = nil
	local origCap = nil
	local lastCap = nil
	local flyBV = nil
	local flyBG = nil
	local flyPS = nil
	local ncParts = {}
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

	local function getChar()
		local char = player.Character
		if not char then
			return nil, nil, nil
		end
		return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
	end

	local function flyStop(hum)
		if flyBV then
			pcall(function()
				flyBV:Destroy()
			end)
			flyBV = nil
		end
		if flyBG then
			pcall(function()
				flyBG:Destroy()
			end)
			flyBG = nil
		end
		if flyPS ~= nil and hum then
			pcall(function()
				hum.PlatformStand = flyPS
			end)
		end
		flyPS = nil
	end

	local function ncRestore()
		for part, _ in pairs(ncParts) do
			if part and part.Parent then
				pcall(function()
					part.CanCollide = true
				end)
			end
		end
		ncParts = {}
	end

	-- every frame: work out what is active, apply it, and put back whatever is not active any more
	local function step()
		local a = {}
		for i = 1, #DEFS do
			local id = DEFS[i].id
			a[id] = isActive(F[id])
		end
		act = a

		local char, hum, hrp = getChar()
		local alive = (hum ~= nil) and (hrp ~= nil) and hum.Health > 0

		-- gravity (world setting)
		if a.gravity then
			if origGravity == nil then
				origGravity = workspace.Gravity
			end
			workspace.Gravity = F.gravity.value
		elseif origGravity ~= nil then
			workspace.Gravity = origGravity
			origGravity = nil
		end

		-- tickrate (your fps cap)
		if type(setfpscap) == "function" then
			if a.tickrate then
				if origCap == nil then
					origCap = 0
					if type(getfpscap) == "function" then
						local ok, v = pcall(getfpscap)
						if ok and type(v) == "number" then
							origCap = v
						end
					end
				end
				if lastCap ~= F.tickrate.value then
					lastCap = F.tickrate.value
					pcall(setfpscap, lastCap)
				end
			elseif origCap ~= nil then
				pcall(setfpscap, origCap)
				origCap = nil
				lastCap = nil
			end
		end

		-- no clip restore (the collision loop itself runs on Stepped below)
		if not a.noclip then
			ncRestore()
		end

		if not alive then
			if flyBV or flyBG then
				flyStop(nil)
			end
			return
		end

		local spaceDown = UserInputService:IsKeyDown(Enum.KeyCode.Space) or hum.Jump

		-- walk speed (bunny hop can take over while Space is held)
		local wantWS = nil
		if a.walkspeed then
			wantWS = F.walkspeed.value
		elseif a.bhop and spaceDown then
			wantWS = F.bhop.value
		end
		if wantWS then
			if origWS == nil then
				origWS = hum.WalkSpeed
			end
			hum.WalkSpeed = wantWS
		elseif origWS ~= nil then
			hum.WalkSpeed = origWS
			origWS = nil
		end

		-- jump power
		if a.jumppower then
			if origJump == nil then
				origJump = { use = hum.UseJumpPower, power = hum.JumpPower }
			end
			hum.UseJumpPower = true
			hum.JumpPower = F.jumppower.value
		elseif origJump ~= nil then
			hum.UseJumpPower = origJump.use
			hum.JumpPower = origJump.power
			origJump = nil
		end

		-- float (hip height)
		if a.float then
			if origHip == nil then
				origHip = hum.HipHeight
			end
			hum.HipHeight = F.float.value
		elseif origHip ~= nil then
			hum.HipHeight = origHip
			origHip = nil
		end

		-- bunny hop: jump again the moment you land
		if a.bhop and spaceDown and hum.FloorMaterial ~= Enum.Material.Air then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end

		-- fly
		if a.fly then
			if not flyBV or flyBV.Parent ~= hrp then
				flyStop(hum)
				flyBV = Instance.new("BodyVelocity")
				flyBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
				flyBV.Velocity = Vector3.new(0, 0, 0)
				flyBV.Parent = hrp
				flyBG = Instance.new("BodyGyro")
				flyBG.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
				flyBG.P = 90000
				flyBG.CFrame = hrp.CFrame
				flyBG.Parent = hrp
				flyPS = hum.PlatformStand
				hum.PlatformStand = true
			end
			local cam = workspace.CurrentCamera
			if cam then
				local lv = cam.CFrame:VectorToObjectSpace(hum.MoveDirection)
				local vel = cam.CFrame.LookVector * (-lv.Z) + cam.CFrame.RightVector * lv.X
				if spaceDown then
					vel = vel + Vector3.new(0, 1, 0)
				end
				if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
					or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
					vel = vel - Vector3.new(0, 1, 0)
				end
				if vel.Magnitude > 1 then
					vel = vel.Unit
				end
				flyBV.Velocity = vel * F.fly.value
				local look = cam.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude > 0.01 then
					flyBG.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
				end
			end
		elseif flyBV or flyBG then
			flyStop(hum)
		end

		-- spider man: walk into a wall and climb it
		if a.spider then
			local md = hum.MoveDirection
			if md.Magnitude > 0.1 then
				rayParams.FilterDescendantsInstances = { char }
				local res = workspace:Raycast(hrp.Position, md.Unit * 3, rayParams)
				if res and res.Instance.CanCollide then
					hrp.AssemblyLinearVelocity = Vector3.new(0, 40, 0) - res.Normal * 4
					hum:ChangeState(Enum.HumanoidStateType.Climbing)
				end
			end
		end
	end

	conns[#conns + 1] = RunService.Heartbeat:Connect(function()
		if running then
			pcall(step)
		end
	end)

	-- no clip runs on Stepped because collisions are reset every physics step
	conns[#conns + 1] = RunService.Stepped:Connect(function()
		if not running or not act.noclip then
			return
		end
		local char = player.Character
		if not char then
			return
		end
		local parts = char:GetDescendants()
		for i = 1, #parts do
			local p = parts[i]
			if p:IsA("BasePart") and p.CanCollide then
				ncParts[p] = true
				p.CanCollide = false
			end
		end
	end)

	-- inf jump
	conns[#conns + 1] = UserInputService.JumpRequest:Connect(function()
		if not running or not act.infjump then
			return
		end
		local _, hum = getChar()
		if hum and hum.Health > 0 then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)

	-- a new character starts clean (the old values belonged to the old one)
	conns[#conns + 1] = player.CharacterAdded:Connect(function()
		origWS = nil
		origJump = nil
		origHip = nil
		flyBV = nil
		flyBG = nil
		flyPS = nil
		ncParts = {}
	end)

	---------------------------------------------------------------------
	-- UNLOAD: switch everything off and put the original values back
	---------------------------------------------------------------------
	local function unload()
		if not running then
			return
		end
		for i = 1, #DEFS do
			local f = F[DEFS[i].id]
			f.enabled = false
			f.toggled = false
			f.held = false
		end
		pcall(step)
		running = false
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
	end

	conns[#conns + 1] = root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(game) then
			unload()
		end
	end)

	return { Root = root, Unload = unload }
end

return MovementPage
