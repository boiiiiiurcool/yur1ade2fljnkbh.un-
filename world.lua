-- world.lua  (Y1 World tab)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Five cards, two per row. Every switch is OFF each time the script starts, and turning one off
-- (or unloading) puts back the value the game had.
--   Ambience         Enable + colour square. Sets the ambient light (Ambient and OutdoorAmbient).
--   Custom Fog       Enable + colour square + three dots.
--                    Pop-up: Distance slider, Fog Glow switch, Glow slider (only works while Fog Glow is on).
--                    Fog Glow adds an Atmosphere in the fog colour so the fog looks soft and glowing.
--                    While Custom Fog is on, the game's own Atmosphere is turned down to density 0,
--                    because an Atmosphere replaces the normal fog.
--   Custom Exposure  Enable + three dots (Exposure slider).
--   Custom Brightness Enable + three dots (Brightness slider).
--   Custom Time      Enable + three dots (Time slider, shown as hh:mm).
-- The values are set again every frame, so games that keep changing the lighting cannot undo them.
--
-- Build signature: World.build(container, T, H, opts) -> { Root = ..., Unload = fn }

local WorldPage = {}

function WorldPage.build(parent, T, H, opts)
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local GuiService = game:GetService("GuiService")
	local Lighting = game:GetService("Lighting")

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH
	local RADIUS = T.RADIUS

	local running = true
	local conns = {}
	local popupList = {}
	local ATMO_NAME = "Y1FogGlow"

	---------------------------------------------------------------------
	-- the features
	---------------------------------------------------------------------
	local DEFS = {
		{ id = "ambience", title = "Ambience", swatch = true, dots = false,
			color = Color3.fromRGB(128, 128, 160) },
		{ id = "fog", title = "Custom Fog", swatch = true, dots = true,
			color = Color3.fromRGB(190, 200, 215),
			rows = {
				{ t = "slider", key = "dist", name = "Distance", min = 20, max = 5000, step = 10, fmt = "%d", value = 500 },
				{ t = "toggle", key = "glow", name = "Fog Glow", value = false },
				{ t = "slider", key = "glowAmt", name = "Glow", min = 0, max = 100, step = 5, fmt = "%d%%", value = 50, needs = "glow" },
			} },
		{ id = "exposure", title = "Custom Exposure", dots = true,
			rows = { { t = "slider", key = "value", name = "Exposure", min = -5, max = 5, step = 0.1, fmt = "%.1f", value = 0 } } },
		{ id = "brightness", title = "Custom Brightness", dots = true,
			rows = { { t = "slider", key = "value", name = "Brightness", min = 0, max = 10, step = 0.1, fmt = "%.1f", value = 3 } } },
		{ id = "time", title = "Custom Time", dots = true,
			rows = { { t = "slider", key = "value", name = "Time", min = 0, max = 24, step = 0.1, time = true, value = 12 } } },
	}

	local F = {}
	for i = 1, #DEFS do
		local d = DEFS[i]
		local f = { def = d, enabled = false, color = d.color, vals = {} }
		if d.rows then
			for r = 1, #d.rows do
				f.vals[d.rows[r].key] = d.rows[r].value
			end
		end
		F[d.id] = f
	end

	local function timeText(v)
		local h = math.floor(v)
		local m = math.floor((v - h) * 60 + 0.5)
		if m >= 60 then
			m = 0
			h = h + 1
		end
		h = h % 24
		return string.format("%02d:%02d", h, m)
	end

	---------------------------------------------------------------------
	-- pointer helpers
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

	local function pointerPos(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			local inset = GuiService:GetGuiInset()
			return Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y)
		end
		return UserInputService:GetMouseLocation()
	end

	---------------------------------------------------------------------
	-- root + floating pop-up helpers
	---------------------------------------------------------------------
	local root = new("Frame", {
		Name = "WorldRoot",
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
	-- a switch. Returns { set = fn(on) }
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
		function api.set(v)
			on = v
			paint(false)
		end
		return api
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

	---------------------------------------------------------------------
	-- colour picker (saturation / brightness, hue, hex box)
	---------------------------------------------------------------------
	local picker = {}
	local pickerEntry = nil

	do
		local PW = 244
		local PH = 238
		local PF = makeFloating("WorldColorPicker", PW, PH)
		local pop = PF.frame

		local h = 0
		local s = 0
		local v = 1
		local onChange = nil
		local dragging = nil
		local WHITE = Color3.new(1, 1, 1)

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

		local valBox = new("Frame", {
			Position = UDim2.fromOffset(12, 198),
			Size = UDim2.fromOffset(220, 28),
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

		local function hexText()
			local c = Color3.fromHSV(h, s, v)
			return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5),
				math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
		end

		local function refresh(fire)
			local c = Color3.fromHSV(h, s, v)
			svClip.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svKnob.Position = UDim2.new(s, 0, 1 - v, 0)
			svKnob.BackgroundColor3 = c
			hueKnob.Position = UDim2.new(h, 0, 0.5, 0)
			hueKnob.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			miniSwatch.BackgroundColor3 = c
			if not valText:IsFocused() then
				valText.Text = hexText()
			end
			if fire and onChange then
				onChange(c)
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

		valText.FocusLost:Connect(function()
			local hex = string.match(valText.Text, "^%s*#?(%x+)%s*$")
			if hex and #hex == 3 then
				hex = string.gsub(hex, ".", function(ch)
					return ch .. ch
				end)
			end
			if hex and #hex >= 6 then
				local r = tonumber(string.sub(hex, 1, 2), 16)
				local g = tonumber(string.sub(hex, 3, 4), 16)
				local b = tonumber(string.sub(hex, 5, 6), 16)
				if r and g and b then
					h, s, v = Color3.fromRGB(r, g, b):ToHSV()
				end
			end
			refresh(true)
		end)

		picker.owner = nil

		function picker.isOpen()
			return PF.isOpen()
		end

		function picker.open(anchor, color, cb, owner)
			onChange = nil
			h, s, v = color:ToHSV()
			refresh(false)
			onChange = cb
			picker.owner = owner
			local pos = placeNear(anchor, PW, PH, nil)
			if PF.isOpen() then
				PF.move(pos)
			else
				PF.open(pos)
			end
		end

		function picker.close()
			PF.close()
			dragging = nil
			picker.owner = nil
		end

		pickerEntry = {
			isOpen = function()
				return PF.isOpen()
			end,
			close = picker.close,
			hit = { pop },
		}
		popupList[#popupList + 1] = pickerEntry
	end

	---------------------------------------------------------------------
	-- the cards (two columns)
	---------------------------------------------------------------------
	local ROW_STEP = 74
	local refreshSub = nil
	local openFor = nil
	local closePop = nil
	local cur = nil   -- the feature the settings pop-up is showing

	local function subText(f)
		local state = '<font color="rgb(116,116,124)">Off</font>'
		if f.enabled then
			state = '<font color="rgb(52,199,120)">Active</font>'
		end
		return state
	end

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

		-- how much room the controls on the right take (switch 50, dots 32, swatch 30)
		local rightW = 70
		if d.dots then
			rightW = rightW + 40
		end
		if d.swatch then
			rightW = rightW + 40
		end
		f.sub = label(card, "", UDim2.fromOffset(14, 25), UDim2.new(1, -rightW, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		f.sub.RichText = true

		makeSwitch(card, false, function(on)
			f.enabled = on
			refreshSub(f)
		end, 23, 12)

		local nextX = -58
		if d.dots then
			f.dots = makeDots(card, UDim2.new(1, -58, 0, 23))
			f.dots.btn.Activated:Connect(function()
				if cur == f then
					closePop()
					return
				end
				openFor(f)
			end)
			nextX = -98
		end

		if d.swatch then
			f.swatch = makeSwatch(card, UDim2.new(1, nextX, 0, 23), f.color, function()
				if picker.isOpen() and picker.owner == f then
					picker.close()
					return
				end
				picker.open(f.swatch.btn, f.color, function(c)
					f.color = c
					f.swatch.paint(c)
				end, f)
			end)
			table.insert(pickerEntry.hit, f.swatch.btn)
		end
	end

	refreshSub = function(f)
		f.sub.Text = subText(f)
	end
	for i = 1, #DEFS do
		refreshSub(F[DEFS[i].id])
	end

	---------------------------------------------------------------------
	-- the shared settings pop-up (sliders + one switch, filled in per feature)
	---------------------------------------------------------------------
	local PW = 280
	local P = makeFloating("WorldSettings", PW, 120)
	local pop = P.frame

	local popTitle = label(pop, "", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)
	new("Frame", {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, pop)

	-- a slider widget that can be pointed at any slider row
	local function makeSliderWidget()
		local S = { row = nil, f = nil, dragging = false }
		S.box = new("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
		}, pop)
		S.name = label(S.box, "", UDim2.fromOffset(16, 2), UDim2.fromOffset(76, 20),
			Enum.Font.GothamMedium, 12, T.ICON)
		S.val = label(S.box, "", UDim2.new(1, -62, 0, 2), UDim2.fromOffset(48, 20),
			Enum.Font.GothamMedium, 12, T.TEXT_COLOR, Enum.TextXAlignment.Right)

		local X0 = 16 + 76 + 6
		local track = new("Frame", {
			Position = UDim2.fromOffset(X0, 9),
			Size = UDim2.new(1, -(X0 + 68), 0, 6),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, S.box)
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
		local hit = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(X0, 2),
			Size = UDim2.new(1, -(X0 + 68), 0, 20),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, S.box)

		function S.refresh()
			if not S.row then
				return
			end
			local r = S.row
			local value = S.f.vals[r.key]
			local fr = (value - r.min) / (r.max - r.min)
			fill.Size = UDim2.new(fr, 0, 1, 0)
			knob.Position = UDim2.new(fr, 0, 0.5, 0)
			if r.time then
				S.val.Text = timeText(value)
			else
				S.val.Text = string.format(r.fmt, value)
			end
		end

		function S.dim(on)
			local colr = T.DIM_TEXT
			if on then
				colr = T.ICON_HOVER
			end
			TweenService:Create(fill, FAST, { BackgroundColor3 = colr }):Play()
		end

		local function setFromX(px)
			if not S.row then
				return
			end
			local r = S.row
			local w = hit.AbsoluteSize.X
			if w <= 0 then
				return
			end
			local fr = math.clamp((px - hit.AbsolutePosition.X) / w, 0, 1)
			local v = r.min + math.floor(fr * (r.max - r.min) / r.step + 0.5) * r.step
			S.f.vals[r.key] = math.clamp(v, r.min, r.max)
			S.refresh()
		end

		hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				S.dragging = true
				setFromX(input.Position.X)
			end
		end)
		conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
			if not S.dragging then
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
				S.dragging = false
			end
		end)

		return S
	end

	local sliders = { makeSliderWidget(), makeSliderWidget() }

	-- the one switch row (Fog Glow)
	local tg = { row = nil, f = nil }
	tg.box = new("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, pop)
	tg.name = label(tg.box, "", UDim2.fromOffset(16, 0), UDim2.new(1, -90, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)

	local function dimSliders()
		for i = 1, #sliders do
			local S = sliders[i]
			if S.row and S.row.needs and S.f then
				S.dim(S.f.vals[S.row.needs] == true)
			elseif S.row then
				S.dim(true)
			end
		end
	end

	tg.switch = makeSwitch(tg.box, false, function(on)
		if tg.f and tg.row then
			tg.f.vals[tg.row.key] = on
			dimSliders()
		end
	end, 14, 16)

	local popEntry = nil

	local function paintAllDots()
		for i = 1, #DEFS do
			local f = F[DEFS[i].id]
			if f.dots then
				f.dots.open = (f == cur) and P.isOpen()
				f.dots.paint()
			end
		end
	end

	openFor = function(f)
		cur = f
		popTitle.Text = f.def.title

		for i = 1, #sliders do
			sliders[i].box.Visible = false
			sliders[i].row = nil
		end
		tg.box.Visible = false
		tg.row = nil

		local y = 50
		local si = 0
		local rows = f.def.rows or {}
		for r = 1, #rows do
			local row = rows[r]
			if row.t == "slider" then
				si = si + 1
				local S = sliders[si]
				S.f = f
				S.row = row
				S.name.Text = row.name
				S.box.Position = UDim2.fromOffset(0, y)
				S.box.Visible = true
				S.refresh()
				y = y + 30
			else
				tg.f = f
				tg.row = row
				tg.name.Text = row.name
				tg.switch.set(f.vals[row.key] == true)
				tg.box.Position = UDim2.fromOffset(0, y)
				tg.box.Visible = true
				y = y + 34
			end
		end
		dimSliders()

		local height = y + 10
		pop.Size = UDim2.fromOffset(PW, height)
		popEntry.hit[2] = f.dots.btn
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
		for i = 1, #sliders do
			sliders[i].dragging = false
		end
		cur = nil
		paintAllDots()
	end

	popEntry = {
		isOpen = function()
			return P.isOpen()
		end,
		close = closePop,
		hit = { pop, pop },
	}
	popupList[#popupList + 1] = popEntry

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

	-- leaving this page (or the tab) closes the pop-ups
	do
		local a = parent
		while a and a:IsA("GuiObject") do
			local node = a
			conns[#conns + 1] = node:GetPropertyChangedSignal("Visible"):Connect(function()
				if not node.Visible then
					if P.isOpen() then
						closePop()
					end
					if picker.isOpen() then
						picker.close()
					end
				end
			end)
			a = a.Parent
		end
	end

	---------------------------------------------------------------------
	-- THE LIGHTING CODE
	---------------------------------------------------------------------
	local origAmb = nil
	local origFog = nil
	local origExp = nil
	local origBright = nil
	local origTime = nil
	local atmoOrig = {}     -- the game's own Atmosphere objects -> their original density
	local ourAtmo = nil

	local function removeOurAtmo()
		if ourAtmo then
			pcall(function()
				ourAtmo:Destroy()
			end)
			ourAtmo = nil
		end
		local old = Lighting:FindFirstChild(ATMO_NAME)
		if old then
			pcall(function()
				old:Destroy()
			end)
		end
	end

	local function restoreAtmos()
		for a, dens in pairs(atmoOrig) do
			if a and a.Parent then
				pcall(function()
					a.Density = dens
				end)
			end
		end
		atmoOrig = {}
	end

	local function step()
		-- ambience
		if F.ambience.enabled then
			if origAmb == nil then
				origAmb = { a = Lighting.Ambient, o = Lighting.OutdoorAmbient }
			end
			Lighting.Ambient = F.ambience.color
			Lighting.OutdoorAmbient = F.ambience.color
		elseif origAmb ~= nil then
			Lighting.Ambient = origAmb.a
			Lighting.OutdoorAmbient = origAmb.o
			origAmb = nil
		end

		-- fog (+ optional glow)
		local fog = F.fog
		if fog.enabled then
			if origFog == nil then
				origFog = { c = Lighting.FogColor, s = Lighting.FogStart, e = Lighting.FogEnd }
			end
			local dist = fog.vals.dist
			Lighting.FogColor = fog.color
			Lighting.FogStart = 0
			Lighting.FogEnd = dist

			-- an Atmosphere replaces the normal fog, so the game's own ones are turned down while this is on
			local kids = Lighting:GetChildren()
			for i = 1, #kids do
				local k = kids[i]
				if k:IsA("Atmosphere") and k.Name ~= ATMO_NAME then
					if atmoOrig[k] == nil then
						atmoOrig[k] = k.Density
					end
					k.Density = 0
				end
			end

			if fog.vals.glow then
				if not ourAtmo or ourAtmo.Parent ~= Lighting then
					removeOurAtmo()
					ourAtmo = Instance.new("Atmosphere")
					ourAtmo.Name = ATMO_NAME
					ourAtmo.Parent = Lighting
				end
				local g = fog.vals.glowAmt / 100
				ourAtmo.Color = fog.color
				ourAtmo.Decay = fog.color
				ourAtmo.Density = math.clamp(60 / (dist + 60), 0.01, 0.6)
				ourAtmo.Offset = 0
				ourAtmo.Glare = g * 8
				ourAtmo.Haze = g * 6
			else
				removeOurAtmo()
			end
		elseif origFog ~= nil then
			Lighting.FogColor = origFog.c
			Lighting.FogStart = origFog.s
			Lighting.FogEnd = origFog.e
			origFog = nil
			removeOurAtmo()
			restoreAtmos()
		end

		-- exposure
		if F.exposure.enabled then
			if origExp == nil then
				origExp = Lighting.ExposureCompensation
			end
			Lighting.ExposureCompensation = F.exposure.vals.value
		elseif origExp ~= nil then
			Lighting.ExposureCompensation = origExp
			origExp = nil
		end

		-- brightness
		if F.brightness.enabled then
			if origBright == nil then
				origBright = Lighting.Brightness
			end
			Lighting.Brightness = F.brightness.vals.value
		elseif origBright ~= nil then
			Lighting.Brightness = origBright
			origBright = nil
		end

		-- time of day
		if F.time.enabled then
			if origTime == nil then
				origTime = Lighting.ClockTime
			end
			Lighting.ClockTime = F.time.vals.value
		elseif origTime ~= nil then
			Lighting.ClockTime = origTime
			origTime = nil
		end
	end

	conns[#conns + 1] = RunService.Heartbeat:Connect(function()
		if running then
			pcall(step)
		end
	end)

	---------------------------------------------------------------------
	-- UNLOAD: switch everything off and put the original values back
	---------------------------------------------------------------------
	local function unload()
		if not running then
			return
		end
		for i = 1, #DEFS do
			F[DEFS[i].id].enabled = false
		end
		pcall(step)
		removeOurAtmo()
		restoreAtmos()
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

return WorldPage
