-- world.lua  (Y1 World tab)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Twelve cards, two per row (the page scrolls). Every switch is OFF each time the script starts, and turning one off
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
--   Color Correction Enable + colour square (tint) + three dots (Saturation, Contrast, Brightness).
--   Bloom            Enable + three dots (Intensity, Size, Threshold).
--   Sun Rays         Enable + three dots (Intensity, Spread). Takes over the game's own SunRaysEffect when it
--                    has one (so the two do not fight), otherwise makes its own. Rays only show while the sun is
--                    in front of you and it is daytime (use Custom Time to set noon).
--   Blur / Depth of Field  Enable + three dots (Blur size, Depth of Field switch, Focus Distance, Amount).
--   No Shadows       Enable only. Turns the world's shadows off (more FPS). It is forced every frame and the
--                    moment the game switches shadows back on.
--   X-Ray            Enable + three dots (Transparency). Makes the map see-through on YOUR screen only
--                    (players and Terrain are left alone).
--   Weather          Enable + three dots (Type: Rain / Snow / Wind, Amount, Wind). Particles that follow
--                    your camera. Wind also pushes the world's wind (workspace.GlobalWind).
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
		{ id = "colorcorr", title = "Color Correction", swatch = true, dots = true,
			color = Color3.fromRGB(255, 255, 255),
			rows = {
				{ t = "slider", key = "sat", name = "Saturation", min = -1, max = 2, step = 0.05, fmt = "%.2f", value = 0 },
				{ t = "slider", key = "con", name = "Contrast", min = -1, max = 1, step = 0.05, fmt = "%.2f", value = 0 },
				{ t = "slider", key = "bri", name = "Brightness", min = -1, max = 1, step = 0.05, fmt = "%.2f", value = 0 },
			} },
		{ id = "bloom", title = "Bloom", dots = true,
			rows = {
				{ t = "slider", key = "inten", name = "Intensity", min = 0, max = 5, step = 0.1, fmt = "%.1f", value = 1 },
				{ t = "slider", key = "size", name = "Size", min = 0, max = 56, step = 1, fmt = "%d", value = 24 },
				{ t = "slider", key = "thresh", name = "Threshold", min = 0, max = 4, step = 0.1, fmt = "%.1f", value = 0.8 },
			} },
		{ id = "sunrays", title = "Sun Rays", dots = true,
			rows = {
				{ t = "slider", key = "inten", name = "Intensity", min = 0, max = 1, step = 0.05, fmt = "%.2f", value = 0.5 },
				{ t = "slider", key = "spread", name = "Spread", min = 0, max = 1, step = 0.05, fmt = "%.2f", value = 1 },
			} },
		{ id = "blur", title = "Blur / Depth of Field", dots = true,
			rows = {
				{ t = "slider", key = "blur", name = "Blur", min = 0, max = 56, step = 1, fmt = "%d", value = 12 },
				{ t = "toggle", key = "dof", name = "Depth of Field", value = false },
				{ t = "slider", key = "focus", name = "Focus", min = 5, max = 300, step = 5, fmt = "%d", value = 30, needs = "dof" },
				{ t = "slider", key = "amt", name = "Amount", min = 0, max = 100, step = 5, fmt = "%d%%", value = 60, needs = "dof" },
			} },
		{ id = "shadows", title = "No Shadows", dots = false },
		{ id = "xray", title = "X-Ray", dots = true,
			rows = { { t = "slider", key = "value", name = "Transparency", min = 0, max = 1, step = 0.05, fmt = "%.2f", value = 0.7 } } },
		{ id = "weather", title = "Weather", dots = true,
			rows = {
				{ t = "cycle", key = "kind", name = "Type", options = { "Rain", "Snow", "Wind" }, value = "Rain" },
				{ t = "slider", key = "amount", name = "Amount", min = 1, max = 100, step = 1, fmt = "%d", value = 50 },
				{ t = "slider", key = "wind", name = "Wind", min = 0, max = 100, step = 1, fmt = "%d", value = 10 },
			} },
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

	-- the cards live in a scrolling frame so the lower rows (Sun Rays, No Shadows, X-Ray, Weather) are
	-- always reachable, however tall the window is
	local scroll = new("ScrollingFrame", {
		Name = "WorldScroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.DIM_TEXT,
		CanvasSize = UDim2.fromOffset(0, 600),
		ScrollingDirection = Enum.ScrollingDirection.Y,
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
	local ROW_STEP = 68
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
		}, scroll)
		corner(card, RADIUS + 4)
		stroke(card, T.BORDER, 1, 0)

		label(scroll, string.upper(d.title), capPos, UDim2.new(0.5, -10, 0, 14),
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

	scroll.CanvasSize = UDim2.fromOffset(0, 24 + math.ceil(#DEFS / 2) * ROW_STEP + 8)

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

	local sliders = { makeSliderWidget(), makeSliderWidget(), makeSliderWidget(), makeSliderWidget() }

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

	-- the one cycle row (Weather type): click the button to go to the next choice
	local cyc = { row = nil, f = nil }
	cyc.box = new("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, pop)
	cyc.name = label(cyc.box, "", UDim2.fromOffset(16, 0), UDim2.new(1, -150, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	cyc.btn = new("TextButton", {
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 0),
		Size = UDim2.fromOffset(112, 28),
		BackgroundColor3 = T.CLUSTER_BG,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = T.ICON_HOVER,
		Text = "",
	}, cyc.box)
	corner(cyc.btn, RADIUS + 2)
	cyc.btn.MouseEnter:Connect(function()
		TweenService:Create(cyc.btn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
	end)
	cyc.btn.MouseLeave:Connect(function()
		TweenService:Create(cyc.btn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
	end)
	cyc.btn.Activated:Connect(function()
		if not cyc.row or not cyc.f then
			return
		end
		local choices = cyc.row.options
		local idx = 1
		for i = 1, #choices do
			if choices[i] == cyc.f.vals[cyc.row.key] then
				idx = i
			end
		end
		idx = idx + 1
		if idx > #choices then
			idx = 1
		end
		cyc.f.vals[cyc.row.key] = choices[idx]
		cyc.btn.Text = choices[idx]
	end)

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
		cyc.box.Visible = false
		cyc.row = nil

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
			elseif row.t == "toggle" then
				tg.f = f
				tg.row = row
				tg.name.Text = row.name
				tg.switch.set(f.vals[row.key] == true)
				tg.box.Position = UDim2.fromOffset(0, y)
				tg.box.Visible = true
				y = y + 34
			else
				cyc.f = f
				cyc.row = row
				cyc.name.Text = row.name
				cyc.btn.Text = f.vals[row.key]
				cyc.box.Position = UDim2.fromOffset(0, y)
				cyc.box.Visible = true
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

	-- scrolling the page closes any open pop-up (it would stay behind while the cards move)
	conns[#conns + 1] = scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if P.isOpen() then
			closePop()
		end
		if picker.isOpen() then
			picker.close()
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

	-- extra effects (each one only exists while its feature is on)
	local ccE = nil
	local bloomE = nil
	local raysE = nil
	local blurE = nil
	local dofE = nil
	local origShadows = nil
	local origWind = nil
	local raysSaved = nil   -- the game's own SunRaysEffect we are controlling: { inst, en, inten, spread }

	local EFFECT_NAMES = { "Y1ColorCorrection", "Y1Bloom", "Y1SunRays", "Y1Blur", "Y1DOF" }
	for i = 1, #EFFECT_NAMES do
		local old = Lighting:FindFirstChild(EFFECT_NAMES[i])
		if old then
			pcall(function()
				old:Destroy()
			end)
		end
	end
	do
		local cam0 = workspace.CurrentCamera
		local oldW = cam0 and cam0:FindFirstChild("Y1Weather")
		if oldW then
			pcall(function()
				oldW:Destroy()
			end)
		end
	end

	local function ensureEffect(ref, class, name)
		if ref and ref.Parent == Lighting then
			return ref
		end
		if ref then
			pcall(function()
				ref:Destroy()
			end)
		end
		local e = Instance.new(class)
		e.Name = name
		e.Parent = Lighting
		return e
	end

	local function dropEffect(ref)
		if ref then
			pcall(function()
				ref:Destroy()
			end)
		end
		return nil
	end

	-- SUN RAYS: use the game's own SunRaysEffect when there is one (two of them would fight each other)
	local function findGameRays()
		local kids = Lighting:GetChildren()
		for i = 1, #kids do
			if kids[i]:IsA("SunRaysEffect") and kids[i].Name ~= "Y1SunRays" then
				return kids[i]
			end
		end
		local cam = workspace.CurrentCamera
		if cam then
			local ck = cam:GetChildren()
			for i = 1, #ck do
				if ck[i]:IsA("SunRaysEffect") then
					return ck[i]
				end
			end
		end
		return nil
	end

	local function restoreRays()
		if raysSaved then
			local r = raysSaved
			raysSaved = nil
			if r.inst and r.inst.Parent then
				pcall(function()
					r.inst.Enabled = r.en
					r.inst.Intensity = r.inten
					r.inst.Spread = r.spread
				end)
			end
		end
	end

	-- NO SHADOWS: runs every frame (RenderStepped, so it wins over the game) and instantly whenever
	-- the game changes GlobalShadows back
	local function applyShadows()
		if F.shadows.enabled then
			if origShadows == nil then
				origShadows = Lighting.GlobalShadows
			end
			if Lighting.GlobalShadows ~= false then
				Lighting.GlobalShadows = false
			end
		elseif origShadows ~= nil then
			Lighting.GlobalShadows = origShadows
			origShadows = nil
		end
	end

	-- X-RAY: LocalTransparencyModifier only changes what YOU see, never the real part
	local xrayParts = setmetatable({}, { __mode = "k" })
	local xrayOn = false
	local xrayToken = 0
	local xrayApplied = nil

	local function isCharPart(p)
		local m = p.Parent
		while m and m ~= workspace do
			if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
				return true
			end
			m = m.Parent
		end
		return false
	end

	local function xrayAdd(p)
		if not p:IsA("BasePart") or p:IsA("Terrain") then
			return
		end
		if p.Transparency >= 1 or string.sub(p.Name, 1, 2) == "Y1" then
			return
		end
		if isCharPart(p) then
			return
		end
		xrayParts[p] = true
		p.LocalTransparencyModifier = xrayApplied or 0
	end

	local function xrayScan(token)
		local list = workspace:GetDescendants()
		local n = 0
		for i = 1, #list do
			if token ~= xrayToken or not xrayOn then
				return
			end
			pcall(xrayAdd, list[i])
			n = n + 1
			if n % 400 == 0 then
				task.wait()
			end
		end
	end

	conns[#conns + 1] = workspace.DescendantAdded:Connect(function(d)
		if running and xrayOn then
			pcall(xrayAdd, d)
		end
	end)

	-- WEATHER: a see-through part that follows your camera and carries one particle emitter
	local wPart = nil
	local wEmitter = nil
	local wKind = nil

	local function weatherStop()
		if wPart then
			pcall(function()
				wPart:Destroy()
			end)
		end
		wPart = nil
		wEmitter = nil
		wKind = nil
	end

	local function weatherBuild(kind)
		weatherStop()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local part = Instance.new("Part")
		part.Name = "Y1Weather"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(70, 1, 70)

		local em = Instance.new("ParticleEmitter")
		em.Name = "Y1WeatherEmitter"
		em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		em.LightInfluence = 0
		em.Enabled = true
		em.Rate = 0
		if kind == "Rain" then
			em.EmissionDirection = Enum.NormalId.Bottom
			em.Speed = NumberRange.new(70, 90)
			em.Lifetime = NumberRange.new(0.9, 1.0)
			em.Size = NumberSequence.new(0.35)
			em.Color = ColorSequence.new(Color3.fromRGB(205, 225, 255))
			em.Transparency = NumberSequence.new(0.15)
			em.LightEmission = 0.8
			em.SpreadAngle = Vector2.new(1, 1)
			pcall(function()
				em.Orientation = Enum.ParticleOrientation.VelocityParallel
			end)
		elseif kind == "Snow" then
			em.EmissionDirection = Enum.NormalId.Bottom
			em.Speed = NumberRange.new(4, 7)
			em.Lifetime = NumberRange.new(7, 8)
			em.Size = NumberSequence.new(0.45)
			em.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
			em.Transparency = NumberSequence.new(0.1)
			em.LightEmission = 0.7
			em.SpreadAngle = Vector2.new(25, 25)
			em.RotSpeed = NumberRange.new(-60, 60)
		else
			part.Size = Vector3.new(1, 50, 70)
			em.EmissionDirection = Enum.NormalId.Right
			em.Speed = NumberRange.new(45, 60)
			em.Lifetime = NumberRange.new(1.6, 1.8)
			em.Size = NumberSequence.new(0.3)
			em.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
			em.Transparency = NumberSequence.new(0.35)
			em.LightEmission = 0.5
			em.SpreadAngle = Vector2.new(4, 4)
			pcall(function()
				em.Orientation = Enum.ParticleOrientation.VelocityParallel
			end)
		end
		em.Parent = part
		part.CFrame = CFrame.new(cam.CFrame.Position)
		part.Parent = cam
		wPart = part
		wEmitter = em
		wKind = kind
	end

	-- keeps the weather box on top of the camera (runs every frame before drawing, so it never lags behind)
	local function weatherFollow()
		local cam = workspace.CurrentCamera
		if not cam or not wPart or not wPart.Parent then
			return
		end
		local cp = cam.CFrame.Position
		if wKind == "Wind" then
			wPart.CFrame = CFrame.new(cp + Vector3.new(-45, 8, 0))
		else
			wPart.CFrame = CFrame.new(cp + Vector3.new(0, 30, 0))
		end
	end

	local function weatherUpdate(amount, wind)
		if not wPart or not wEmitter then
			return
		end
		weatherFollow()
		if wKind == "Wind" then
			wEmitter.Rate = amount * 3
			wEmitter.Speed = NumberRange.new(20 + wind * 0.6, 30 + wind * 0.8)
		else
			local per = 18
			if wKind == "Snow" then
				per = 6
			end
			wEmitter.Rate = amount * per
			wEmitter.Acceleration = Vector3.new(wind * 0.5, 0, wind * 0.2)
		end
	end

	local function stepA()
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

	local function stepB()
		-- color correction
		local cc = F.colorcorr
		if cc.enabled then
			ccE = ensureEffect(ccE, "ColorCorrectionEffect", "Y1ColorCorrection")
			ccE.Saturation = cc.vals.sat
			ccE.Contrast = cc.vals.con
			ccE.Brightness = cc.vals.bri
			ccE.TintColor = cc.color
		elseif ccE then
			ccE = dropEffect(ccE)
		end

		-- bloom
		local bl = F.bloom
		if bl.enabled then
			bloomE = ensureEffect(bloomE, "BloomEffect", "Y1Bloom")
			bloomE.Intensity = bl.vals.inten
			bloomE.Size = bl.vals.size
			bloomE.Threshold = bl.vals.thresh
		elseif bloomE then
			bloomE = dropEffect(bloomE)
		end

		-- sun rays: take over the game's own SunRaysEffect when it has one, otherwise make our own
		local sr = F.sunrays
		if sr.enabled then
			local g = findGameRays()
			if g then
				if raysSaved == nil or raysSaved.inst ~= g then
					restoreRays()
					raysSaved = { inst = g, en = g.Enabled, inten = g.Intensity, spread = g.Spread }
				end
				g.Enabled = true
				g.Intensity = sr.vals.inten
				g.Spread = sr.vals.spread
				if raysE then
					raysE = dropEffect(raysE)
				end
			else
				restoreRays()
				raysE = ensureEffect(raysE, "SunRaysEffect", "Y1SunRays")
				raysE.Enabled = true
				raysE.Intensity = sr.vals.inten
				raysE.Spread = sr.vals.spread
			end
		else
			restoreRays()
			if raysE then
				raysE = dropEffect(raysE)
			end
		end

		-- blur + depth of field
		local bd = F.blur
		if bd.enabled then
			blurE = ensureEffect(blurE, "BlurEffect", "Y1Blur")
			blurE.Size = bd.vals.blur
			if bd.vals.dof then
				dofE = ensureEffect(dofE, "DepthOfFieldEffect", "Y1DOF")
				dofE.FarIntensity = bd.vals.amt / 100
				dofE.NearIntensity = 0
				dofE.FocusDistance = bd.vals.focus
				dofE.InFocusRadius = 20
			elseif dofE then
				dofE = dropEffect(dofE)
			end
		else
			if blurE then
				blurE = dropEffect(blurE)
			end
			if dofE then
				dofE = dropEffect(dofE)
			end
		end

	end

	local function stepC()
		-- shadows off
		applyShadows()

		-- x-ray
		local xr = F.xray
		if xr.enabled then
			local v = xr.vals.value
			if not xrayOn then
				xrayOn = true
				xrayApplied = v
				xrayToken = xrayToken + 1
				task.spawn(xrayScan, xrayToken)
			elseif v ~= xrayApplied then
				xrayApplied = v
				for part, _ in pairs(xrayParts) do
					if part and part.Parent then
						part.LocalTransparencyModifier = v
					end
				end
			end
		elseif xrayOn then
			xrayOn = false
			xrayToken = xrayToken + 1
			for part, _ in pairs(xrayParts) do
				if part and part.Parent then
					pcall(function()
						part.LocalTransparencyModifier = 0
					end)
				end
			end
			xrayParts = setmetatable({}, { __mode = "k" })
			xrayApplied = nil
		end

	end

	local function stepD()
		-- weather
		local wt = F.weather
		if wt.enabled then
			local kind = wt.vals.kind
			if wKind ~= kind or not wPart or wPart.Parent ~= workspace.CurrentCamera then
				weatherBuild(kind)
			end
			weatherUpdate(wt.vals.amount, wt.vals.wind)
			pcall(function()
				if origWind == nil then
					origWind = workspace.GlobalWind
				end
				workspace.GlobalWind = Vector3.new(wt.vals.wind, 0, wt.vals.wind * 0.3)
			end)
		else
			if wKind ~= nil then
				weatherStop()
			end
			if origWind ~= nil then
				pcall(function()
					workspace.GlobalWind = origWind
				end)
				origWind = nil
			end
		end
	end

	-- every section runs on its own, so an error in one can never stop the others
	local function step()
		pcall(stepA)
		pcall(stepB)
		pcall(stepC)
		pcall(stepD)
	end

	conns[#conns + 1] = RunService.Heartbeat:Connect(function()
		if running then
			step()
		end
	end)

	-- right before each frame is drawn: keep shadows off and keep the weather box on the camera
	conns[#conns + 1] = RunService.RenderStepped:Connect(function()
		if running then
			pcall(applyShadows)
			pcall(weatherFollow)
		end
	end)

	-- the instant the game switches shadows back on, switch them off again
	conns[#conns + 1] = Lighting:GetPropertyChangedSignal("GlobalShadows"):Connect(function()
		if running then
			pcall(applyShadows)
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
		weatherStop()
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
