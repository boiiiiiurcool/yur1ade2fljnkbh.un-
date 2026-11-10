-- visuals.lua  (Y1 Visuals tab: ESP)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Visuals tab INTO win.VisualsPage (ui.lua loads it through opts.VisualsModule).
-- Same look as the Misc tab: cards with an Enable switch and three dots; the dots open a pop-up.
-- Click the dots again, or anywhere except the pop-up, to close it. Everything starts OFF.
--
--   OUTLINE ESP   Enable + dots. Pop-up: Outline (switch + colour/opacity), Glow (switch + colour/opacity).
--                 Drawn with Roblox Highlights (Roblox shows at most 31 highlights at once).
--   TEAM CHECK    Enable + dots. Pop-up: Action = Hide ESP (teammates get no ESP) or Set Color (teammates
--                 are drawn in the colour you pick).
--   VISIBLE CHECK Enable + dots. Pop-up: Action = Hide ESP (players you cannot see get no ESP) or
--                 Set Color (players you CAN see are drawn in the colour you pick).
--   FILTERS       Only dots. Pop-up: Self ESP (switch) and Render Distance (slider, studs).
--   BOX ESP       A colour square (box colour + opacity) and dots. Pop-up: Enable, Fill Box (switch + fill
--                 colour/opacity), Box Type = 2D / 3D / Corners (3D has no fill).
--                 Boxes are drawn with plain gui frames (no Drawing library needed).
--   Colour picker  Click a colour square: saturation / brightness square, hue bar, opacity bar and a
--                  hex + opacity box. The opacity bar is the transparency picker.
--
-- Build signature: Visuals.build(container, T, H, opts) -> { Root = ..., Unload = fn }

local VisualsPage = {}

function VisualsPage.build(parent, T, H, opts)
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

	local running = true
	local conns = {}
	local popupList = {}
	local pops = {}

	local WHITE = Color3.fromRGB(255, 255, 255)

	local S = {
		-- outline esp
		hlOn = false,
		outlineOn = true,
		outlineColor = WHITE,
		outlineAlpha = 1,
		glowOn = false,
		glowColor = Color3.fromRGB(255, 255, 255),
		glowAlpha = 0.35,
		-- team check
		teamOn = false,
		teamAction = "Set Color",
		teamColor = Color3.fromRGB(80, 160, 255),
		-- visible check
		visOn = false,
		visAction = "Set Color",
		visColor = Color3.fromRGB(80, 230, 120),
		-- filters
		selfEsp = false,
		dist = 1000,
		-- box esp
		boxOn = false,
		boxColor = WHITE,
		boxAlpha = 1,
		fillOn = false,
		fillColor = Color3.fromRGB(255, 255, 255),
		fillAlpha = 0.3,
		boxType = "2D",
	}

	local ACTIONS = { "Hide ESP", "Set Color" }
	local BOX_TYPES = { "2D", "3D", "Corners" }

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
		Name = "VisualsRoot",
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

	-- under the anchor (above it when there is no room), right edges lined up.
	-- With "beside" it goes to the left (or right) of that frame instead. Always kept inside the page.
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

	local function closeAllPopups()
		for i = 1, #popupList do
			local pp = popupList[i]
			if pp.isOpen() then
				pp.close()
			end
		end
	end

	---------------------------------------------------------------------
	-- controls
	---------------------------------------------------------------------
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

	local function makeSlider(c, y, name, labelW, minV, maxV, stepV, startValue, fmt, setValue)
		label(c, name, UDim2.fromOffset(16, y), UDim2.fromOffset(labelW, 20),
			Enum.Font.GothamMedium, 12, T.ICON)
		local valueLabel = label(c, "", UDim2.new(1, -60, 0, y), UDim2.fromOffset(46, 20),
			Enum.Font.GothamMedium, 12, T.TEXT_COLOR, Enum.TextXAlignment.Right)

		local x0 = 16 + labelW + 6

		local track = new("Frame", {
			Position = UDim2.fromOffset(x0, y + 7),
			Size = UDim2.new(1, -(x0 + 68), 0, 6),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, c)
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
			Position = UDim2.fromOffset(x0, y),
			Size = UDim2.new(1, -(x0 + 68), 0, 20),
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
			value = math.clamp(value, minV, maxV)
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
	end

	---------------------------------------------------------------------
	-- colour picker (saturation / brightness, hue, opacity, hex + opacity text)
	---------------------------------------------------------------------
	local picker = {}
	local pickerEntry = nil

	do
		local PW = 244
		local PH = 262
		local F = makeFloating("EspColorPicker", PW, PH)
		local pop = F.frame

		local h = 0
		local s = 0
		local v = 1
		local a = 1
		local onChange = nil
		local dragging = nil

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

		local valBox = new("Frame", {
			Position = UDim2.fromOffset(12, 222),
			Size = UDim2.fromOffset(164, 28),
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
			alphaOverlay.BackgroundColor3 = c
			alphaKnob.Position = UDim2.new(a, 0, 0.5, 0)
			miniSwatch.BackgroundColor3 = c
			if not valText:IsFocused() then
				valText.Text = hexText()
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

		alphaText.FocusLost:Connect(function()
			local n = tonumber(string.match(alphaText.Text, "[%d%.]+"))
			if n then
				a = math.clamp(n / 100, 0, 1)
			end
			refresh(true)
		end)

		picker.frame = pop
		picker.target = nil

		function picker.isOpen()
			return F.isOpen()
		end

		-- key names the square that opened it, so a second click on the same square closes it
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

	-- a colour square: opens / closes the picker for one colour (and its opacity)
	local function colorSquare(c, pos, key, getColor, getAlpha, setColor, besideFrame)
		local sw = nil
		sw = makeSwatch(c, pos, getColor(), function()
			if picker.isOpen() and picker.target == key then
				picker.close()
				return
			end
			picker.open(key, sw.btn, getColor(), getAlpha(), function(col, al)
				setColor(col, al)
				sw.paint(col)
			end, besideFrame)
		end)
		table.insert(pickerEntry.hit, sw.btn)
		return sw
	end

	---------------------------------------------------------------------
	-- pop-ups
	---------------------------------------------------------------------
	-- a pop-up behind a three dots button: title + line, opens under the dots
	local function makePopup(name, title, w, h, dots)
		local P = makeFloating(name, w, h)
		P.w = w
		P.h = h
		P.dots = dots
		P.hits = { P.frame, picker.frame, dots.btn }
		label(P.frame, title, UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
			Enum.Font.GothamBold, 14, T.TEXT_COLOR)
		new("Frame", {
			Position = UDim2.fromOffset(16, 40),
			Size = UDim2.new(1, -32, 0, 1),
			BackgroundColor3 = T.BORDER,
			BorderSizePixel = 0,
		}, P.frame)

		P.lists = {}

		function P.closeAll()
			P.close()
			for i = 1, #P.lists do
				P.lists[i].close()
			end
			if picker.isOpen() then
				picker.close()
			end
			dots.open = false
			dots.paint()
		end

		dots.btn.Activated:Connect(function()
			if P.isOpen() then
				P.closeAll()
				return
			end
			for i = 1, #pops do
				if pops[i] ~= P and pops[i].isOpen() then
					pops[i].closeAll()
				end
			end
			if picker.isOpen() then
				picker.close()
			end
			P.open(placeNear(dots.btn, w, h, nil))
			dots.open = true
			dots.paint()
		end)

		pops[#pops + 1] = P
		popupList[#popupList + 1] = {
			isOpen = function()
				return P.isOpen()
			end,
			close = function()
				P.closeAll()
			end,
			hit = P.hits,
		}
		return P
	end

	-- a row with a title and a drop-down button; the list floats on the page so it is never cut off
	local OPT_H = 26
	local function makeChoiceRow(P, y, title, options, getValue, setValue)
		label(P.frame, title, UDim2.fromOffset(16, y), UDim2.fromOffset(100, 28),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)

		local btn = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, y),
			Size = UDim2.fromOffset(112, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, P.frame)
		corner(btn, RADIUS + 2)
		local valLbl = label(btn, "", UDim2.fromOffset(10, 0), UDim2.new(1, -34, 1, 0),
			Enum.Font.GothamMedium, 12, T.ICON_HOVER)

		local arrow = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -15, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, btn)
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

		local over = false
		local isOpen = false
		local function paintArrow()
			local colr = T.DIM_TEXT
			if over or isOpen then
				colr = T.ICON_HOVER
			end
			for i = 1, #arms do
				TweenService:Create(arms[i], FAST, { BackgroundColor3 = colr }):Play()
			end
			local rot = 0
			if isOpen then
				rot = 180
			end
			TweenService:Create(arrow, SMOOTH, { Rotation = rot }):Play()
		end
		btn.MouseEnter:Connect(function()
			over = true
			paintArrow()
			TweenService:Create(btn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
		end)
		btn.MouseLeave:Connect(function()
			over = false
			paintArrow()
			TweenService:Create(btn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
		end)

		local listW = 112
		local listH = #options * OPT_H + 8
		local list = makeFloating(title .. "List", listW, listH)
		list.frame.ZIndex = 70
		local optBtns = {}

		local function paintOptions()
			local now = getValue()
			for i = 1, #optBtns do
				if options[i] == now then
					optBtns[i].BackgroundTransparency = 0
				else
					optBtns[i].BackgroundTransparency = 1
				end
			end
		end

		local R = {}
		function R.refresh()
			valLbl.Text = tostring(getValue())
			paintOptions()
		end
		function R.close()
			if list.isOpen() then
				list.close()
			end
			isOpen = false
			paintArrow()
		end

		for i = 1, #options do
			local ob = new("TextButton", {
				AutoButtonColor = false,
				Text = "",
				Position = UDim2.fromOffset(4, 4 + (i - 1) * OPT_H),
				Size = UDim2.new(1, -8, 0, OPT_H - 2),
				BackgroundColor3 = T.HOVER_GREY,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, list.frame)
			corner(ob, RADIUS)
			label(ob, options[i], UDim2.fromOffset(10, 0), UDim2.new(1, -20, 1, 0),
				Enum.Font.GothamMedium, 12, T.TEXT_COLOR)
			optBtns[i] = ob
			ob.MouseEnter:Connect(function()
				ob.BackgroundTransparency = 0
			end)
			ob.MouseLeave:Connect(function()
				if options[i] == getValue() then
					ob.BackgroundTransparency = 0
				else
					ob.BackgroundTransparency = 1
				end
			end)
			ob.Activated:Connect(function()
				setValue(options[i])
				R.refresh()
				R.close()
			end)
		end

		btn.Activated:Connect(function()
			if list.isOpen() then
				R.close()
				return
			end
			R.refresh()
			-- under the button, right edges lined up
			local s = uiScale()
			local rh = root.AbsoluteSize.Y / s
			local bx, by, bw, bh = rectIn(btn)
			local ly = by + bh + 4
			if ly + listH > rh - 4 then
				ly = by - listH - 4
			end
			list.open(UDim2.fromOffset(math.floor(bx + bw - listW), math.floor(ly)))
			isOpen = true
			paintArrow()
		end)

		table.insert(P.hits, list.frame)
		table.insert(P.hits, btn)
		P.lists[#P.lists + 1] = R
		popupList[#popupList + 1] = {
			isOpen = function()
				return list.isOpen()
			end,
			close = R.close,
			hit = { list.frame, btn },
		}
		R.refresh()
		return R
	end

	-- a row: title on the left, optional colour square, switch on the right
	local function switchRow(P, y, title, startOn, onChange)
		label(P.frame, title, UDim2.fromOffset(16, y), UDim2.new(1, -120, 0, 28),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		makeSwitch(P.frame, startOn, onChange, y + 14, 16)
	end

	local function swatchPos(y)
		return UDim2.new(1, -(16 + 38 + 10), 0, y + 14)
	end

	local function noteText(P, text, y)
		local l = label(P.frame, text, UDim2.fromOffset(16, y), UDim2.new(1, -32, 0, 28),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		l.TextWrapped = true
		l.TextTruncate = Enum.TextTruncate.None
		l.TextYAlignment = Enum.TextYAlignment.Top
		return l
	end

	---------------------------------------------------------------------
	-- cards (two columns)
	---------------------------------------------------------------------
	local ROW_STEP = 74
	local CARD_TOP = 22
	local cardCount = 0

	-- makes a card (with a caption above it) and returns the card frame
	local function makeCard(caption)
		local i = cardCount
		cardCount = cardCount + 1
		local col = i % 2
		local row = math.floor(i / 2)
		local cardY = CARD_TOP + row * ROW_STEP
		local pos = UDim2.new(0, 2, 0, cardY)
		local capPos = UDim2.new(0, 4, 0, cardY - 18)
		if col == 1 then
			pos = UDim2.new(0.5, 4, 0, cardY)
			capPos = UDim2.new(0.5, 6, 0, cardY - 18)
		end
		local card = new("Frame", {
			Name = caption .. "Card",
			Position = pos,
			Size = UDim2.new(0.5, -6, 0, 46),
			BackgroundColor3 = T.SIDEBAR_BG,
			BorderSizePixel = 0,
		}, root)
		corner(card, RADIUS + 4)
		stroke(card, T.BORDER, 1, 0)
		label(root, string.upper(caption), capPos, UDim2.new(0.5, -10, 0, 14),
			Enum.Font.GothamMedium, 11, T.DIM_TEXT)
		return card
	end

	local function cardTitle(card, title)
		label(card, title, UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		local sub = label(card, "", UDim2.fromOffset(14, 25), UDim2.new(1, -110, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		return sub
	end

	local function setSub(sub, text, on)
		sub.Text = text
		if on then
			sub.TextColor3 = T.GREEN
		else
			sub.TextColor3 = T.DIM_TEXT
		end
	end

	-- 1) OUTLINE ESP -----------------------------------------------------
	local hlCard = makeCard("Outline ESP")
	local hlSub = cardTitle(hlCard, "Enable")
	local function refreshHl()
		if S.hlOn then
			setSub(hlSub, "Active", true)
		else
			setSub(hlSub, "Off", false)
		end
	end
	refreshHl()
	makeSwitch(hlCard, S.hlOn, function(on)
		S.hlOn = on
		refreshHl()
	end, 23)
	local hlDots = makeDots(hlCard, UDim2.new(1, -58, 0, 23))

	do
		local P = makePopup("OutlinePopup", "Outline ESP", 264, 132, hlDots)
		switchRow(P, 50, "Outline", S.outlineOn, function(on)
			S.outlineOn = on
		end)
		colorSquare(P.frame, swatchPos(50), "outline",
			function() return S.outlineColor end,
			function() return S.outlineAlpha end,
			function(c, al)
				S.outlineColor = c
				S.outlineAlpha = al
			end, P.frame)

		switchRow(P, 86, "Glow", S.glowOn, function(on)
			S.glowOn = on
		end)
		colorSquare(P.frame, swatchPos(86), "glow",
			function() return S.glowColor end,
			function() return S.glowAlpha end,
			function(c, al)
				S.glowColor = c
				S.glowAlpha = al
			end, P.frame)
	end

	-- 2) TEAM CHECK ------------------------------------------------------
	local teamCard = makeCard("Team Check")
	local teamSub = cardTitle(teamCard, "Enable")
	local function refreshTeam()
		if S.teamOn then
			setSub(teamSub, S.teamAction, true)
		else
			setSub(teamSub, "Off", false)
		end
	end
	refreshTeam()
	makeSwitch(teamCard, S.teamOn, function(on)
		S.teamOn = on
		refreshTeam()
	end, 23)
	local teamDots = makeDots(teamCard, UDim2.new(1, -58, 0, 23))

	do
		local P = makePopup("TeamPopup", "Team Check", 264, 182, teamDots)
		makeChoiceRow(P, 50, "Action", ACTIONS,
			function() return S.teamAction end,
			function(v)
				S.teamAction = v
				refreshTeam()
			end)
		label(P.frame, "Color", UDim2.fromOffset(16, 86), UDim2.new(1, -90, 0, 28),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		colorSquare(P.frame, UDim2.new(1, -16, 0, 100), "team",
			function() return S.teamColor end,
			function() return 1 end,
			function(c)
				S.teamColor = c
			end, P.frame)
		noteText(P, "Hide ESP: your teammates get no ESP. Set Color: your teammates are drawn in this color.", 126)
	end

	-- 3) VISIBLE CHECK ---------------------------------------------------
	local visCard = makeCard("Visible Check")
	local visSub = cardTitle(visCard, "Enable")
	local function refreshVis()
		if S.visOn then
			setSub(visSub, S.visAction, true)
		else
			setSub(visSub, "Off", false)
		end
	end
	refreshVis()
	makeSwitch(visCard, S.visOn, function(on)
		S.visOn = on
		refreshVis()
	end, 23)
	local visDots = makeDots(visCard, UDim2.new(1, -58, 0, 23))

	do
		local P = makePopup("VisiblePopup", "Visible Check", 264, 182, visDots)
		makeChoiceRow(P, 50, "Action", ACTIONS,
			function() return S.visAction end,
			function(v)
				S.visAction = v
				refreshVis()
			end)
		label(P.frame, "Color", UDim2.fromOffset(16, 86), UDim2.new(1, -90, 0, 28),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		colorSquare(P.frame, UDim2.new(1, -16, 0, 100), "visible",
			function() return S.visColor end,
			function() return 1 end,
			function(c)
				S.visColor = c
			end, P.frame)
		noteText(P, "Hide ESP: players you cannot see get no ESP. Set Color: players you can see are drawn in this color.", 126)
	end

	-- 4) FILTERS (only the dots) ----------------------------------------
	local filCard = makeCard("Filters")
	local filSub = cardTitle(filCard, "Filters")
	local function refreshFil()
		local selfText = "Self ESP off"
		if S.selfEsp then
			selfText = "Self ESP on"
		end
		filSub.Text = selfText .. " - " .. S.dist .. " studs"
		filSub.TextColor3 = T.DIM_TEXT
	end
	refreshFil()
	local filDots = makeDots(filCard, UDim2.new(1, -12, 0.5, 0))

	do
		local P = makePopup("FiltersPopup", "Filters", 264, 124, filDots)
		switchRow(P, 50, "Self ESP", S.selfEsp, function(on)
			S.selfEsp = on
			refreshFil()
		end)
		makeSlider(P.frame, 90, "Distance", 60, 50, 5000, 50, S.dist, "%d", function(v)
			S.dist = v
			refreshFil()
		end)
	end

	-- 5) BOX ESP (colour square + dots) ----------------------------------
	local boxCard = makeCard("Box ESP")
	local boxSub = cardTitle(boxCard, "Box ESP")
	local function refreshBox()
		if S.boxOn then
			setSub(boxSub, "On - " .. S.boxType, true)
		else
			setSub(boxSub, "Off - " .. S.boxType, false)
		end
	end
	refreshBox()
	local boxDots = makeDots(boxCard, UDim2.new(1, -12, 0.5, 0))
	colorSquare(boxCard, UDim2.new(1, -(12 + 32 + 6), 0.5, 0), "box",
		function() return S.boxColor end,
		function() return S.boxAlpha end,
		function(c, al)
			S.boxColor = c
			S.boxAlpha = al
		end, nil)

	do
		local P = makePopup("BoxPopup", "Box ESP", 264, 190, boxDots)
		switchRow(P, 50, "Enable", S.boxOn, function(on)
			S.boxOn = on
			refreshBox()
		end)
		switchRow(P, 86, "Fill Box", S.fillOn, function(on)
			S.fillOn = on
		end)
		colorSquare(P.frame, swatchPos(86), "fill",
			function() return S.fillColor end,
			function() return S.fillAlpha end,
			function(c, al)
				S.fillColor = c
				S.fillAlpha = al
			end, P.frame)
		makeChoiceRow(P, 122, "Box Type", BOX_TYPES,
			function() return S.boxType end,
			function(v)
				S.boxType = v
				refreshBox()
			end)
		noteText(P, "3D boxes have no fill. The opacity bar in the color picker is the transparency.", 156)
	end

	-- a click or tap anywhere outside an open pop-up (or its button) closes it
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

	-- leaving this page (or the Visuals tab) closes every pop-up
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
	-- THE ESP
	---------------------------------------------------------------------
	local espGui = new("ScreenGui", {
		Name = "Y1Esp",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 997,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	local entries = {}   -- player -> { rect, stroke, corners, lines, hl, mode }

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

	local function makeLines(n)
		local list = {}
		for i = 1, n do
			list[i] = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Visible = false,
			}, espGui)
		end
		return list
	end

	local function newEntry()
		local E = { mode = nil, corners = nil, lines = nil, hl = nil }
		E.rect = new("Frame", {
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
		}, espGui)
		E.stroke = Instance.new("UIStroke")
		E.stroke.Thickness = 1.5
		E.stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		E.stroke.Parent = E.rect
		return E
	end

	local function setGroupVisible(list, v)
		if list then
			for i = 1, #list do
				list[i].Visible = v
			end
		end
	end

	local function hideBox(E)
		E.rect.Visible = false
		setGroupVisible(E.corners, false)
		setGroupVisible(E.lines, false)
		E.mode = nil
	end

	local function destroyEntry(E)
		pcall(function()
			E.rect:Destroy()
		end)
		if E.corners then
			for i = 1, #E.corners do
				pcall(function()
					E.corners[i]:Destroy()
				end)
			end
		end
		if E.lines then
			for i = 1, #E.lines do
				pcall(function()
					E.lines[i]:Destroy()
				end)
			end
		end
		if E.hl then
			pcall(function()
				E.hl:Destroy()
			end)
		end
	end

	-- a 1.5px line between two screen points, drawn with a rotated frame
	local function setLine(f, ax, ay, bx, by, th, color, transp)
		local dx = bx - ax
		local dy = by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		f.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
		f.Size = UDim2.fromOffset(len + th, th)
		f.Rotation = math.deg(math.atan2(dy, dx))
		f.BackgroundColor3 = color
		f.BackgroundTransparency = transp
		f.Visible = true
	end

	local function canSee(cam, char, hrp)
		local part = char:FindFirstChild("Head")
		if part == nil then
			part = hrp
		end
		local ignore = { char }
		if player.Character then
			ignore[2] = player.Character
		end
		rayParams.FilterDescendantsInstances = ignore
		local from = cam.CFrame.Position
		return workspace:Raycast(from, part.Position - from, rayParams) == nil
	end

	local function updateHighlight(E, char, override, show)
		if not show then
			if E.hl then
				E.hl.Enabled = false
			end
			return
		end
		if E.hl == nil or E.hl.Parent ~= char then
			if E.hl then
				pcall(function()
					E.hl:Destroy()
				end)
			end
			local hl = Instance.new("Highlight")
			hl.Name = "Y1Hl"
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Adornee = char
			hl.Parent = char
			E.hl = hl
		end
		local hl = E.hl
		if not S.outlineOn and not S.glowOn then
			hl.Enabled = false
			return
		end
		hl.Enabled = true
		hl.OutlineColor = override or S.outlineColor
		hl.FillColor = override or S.glowColor
		if S.outlineOn then
			hl.OutlineTransparency = 1 - S.outlineAlpha
		else
			hl.OutlineTransparency = 1
		end
		if S.glowOn then
			hl.FillTransparency = 1 - S.glowAlpha
		else
			hl.FillTransparency = 1
		end
	end

	local function updateBox(E, cam, hrp, override)
		local mode = S.boxType
		local color = override or S.boxColor
		local fillColor = override or S.fillColor
		local lineT = 1 - S.boxAlpha
		local pos = hrp.Position

		-- hide the pieces of the other box types when the type changes
		if E.mode ~= mode then
			E.rect.Visible = false
			setGroupVisible(E.corners, false)
			setGroupVisible(E.lines, false)
			E.mode = mode
		end

		if mode == "3D" then
			E.lines = E.lines or makeLines(12)
			local _, yaw = hrp.CFrame:ToOrientation()
			local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
			local pts = {}
			for i = 0, 7 do
				local sx = -1
				if i % 2 == 1 then
					sx = 1
				end
				local sy = -1
				if math.floor(i / 2) % 2 == 1 then
					sy = 1
				end
				local sz = -1
				if math.floor(i / 4) % 2 == 1 then
					sz = 1
				end
				local wp = cf:PointToWorldSpace(Vector3.new(sx * 1.6, -0.2 + sy * 2.95, sz * 1.1))
				pts[i] = cam:WorldToViewportPoint(wp)
			end
			local n = 0
			local bits = { 1, 2, 4 }
			for i = 0, 7 do
				for k = 1, 3 do
					local bit = bits[k]
					if math.floor(i / bit) % 2 == 0 then
						local j = i + bit
						n = n + 1
						local ln = E.lines[n]
						local a = pts[i]
						local c = pts[j]
						if a.Z > 0 and c.Z > 0 then
							setLine(ln, a.X, a.Y, c.X, c.Y, 1.5, color, lineT)
						else
							ln.Visible = false
						end
					end
				end
			end
			return
		end

		-- 2D and Corners: a screen rectangle from the top of the head to the feet
		local topV = cam:WorldToViewportPoint(pos + Vector3.new(0, 2.8, 0))
		local botV = cam:WorldToViewportPoint(pos - Vector3.new(0, 3.2, 0))
		local h = botV.Y - topV.Y
		if topV.Z <= 0 or botV.Z <= 0 or h < 2 then
			E.rect.Visible = false
			setGroupVisible(E.corners, false)
			return
		end
		local w = h * 0.56
		local cx = (topV.X + botV.X) / 2
		local x1 = cx - w / 2
		local y1 = topV.Y
		local x2 = cx + w / 2
		local y2 = botV.Y

		E.rect.Position = UDim2.fromOffset(x1, y1)
		E.rect.Size = UDim2.fromOffset(w, h)
		E.rect.BackgroundColor3 = fillColor
		if S.fillOn then
			E.rect.BackgroundTransparency = 1 - S.fillAlpha
		else
			E.rect.BackgroundTransparency = 1
		end

		if mode == "2D" then
			E.rect.Visible = true
			E.stroke.Enabled = true
			E.stroke.Color = color
			E.stroke.Transparency = lineT
		else
			-- Corners
			E.stroke.Enabled = false
			E.rect.Visible = S.fillOn
			E.corners = E.corners or makeLines(8)
			local cl = math.max(4, w * 0.28)
			local ch = math.max(4, h * 0.2)
			local c = E.corners
			setLine(c[1], x1, y1, x1 + cl, y1, 1.5, color, lineT)
			setLine(c[2], x1, y1, x1, y1 + ch, 1.5, color, lineT)
			setLine(c[3], x2, y1, x2 - cl, y1, 1.5, color, lineT)
			setLine(c[4], x2, y1, x2, y1 + ch, 1.5, color, lineT)
			setLine(c[5], x1, y2, x1 + cl, y2, 1.5, color, lineT)
			setLine(c[6], x1, y2, x1, y2 - ch, 1.5, color, lineT)
			setLine(c[7], x2, y2, x2 - cl, y2, 1.5, color, lineT)
			setLine(c[8], x2, y2, x2, y2 - ch, 1.5, color, lineT)
		end
	end

	local function hideEntry(E)
		hideBox(E)
		if E.hl then
			E.hl.Enabled = false
		end
	end

	local function espStep()
		if not running then
			return
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local camPos = cam.CFrame.Position
		local all = Players:GetPlayers()
		for i = 1, #all do
			local plr = all[i]
			local E = entries[plr]
			local show = false
			local override = nil
			local char = nil
			local hrp = nil

			if (S.hlOn or S.boxOn) and (plr ~= player or S.selfEsp) then
				char = plr.Character
				local hum = nil
				if char then
					hum = char:FindFirstChildOfClass("Humanoid")
					hrp = char:FindFirstChild("HumanoidRootPart")
				end
				if hum and hrp and hum.Health > 0 and (hrp.Position - camPos).Magnitude <= S.dist then
					show = true
					-- team check
					if S.teamOn and plr ~= player and plr.Team ~= nil and plr.Team == player.Team then
						if S.teamAction == "Hide ESP" then
							show = false
						else
							override = S.teamColor
						end
					end
					-- visible check
					if show and S.visOn and plr ~= player then
						local vis = canSee(cam, char, hrp)
						if S.visAction == "Hide ESP" then
							if not vis then
								show = false
							end
						elseif vis and override == nil then
							override = S.visColor
						end
					end
				end
			end

			if not show then
				if E then
					hideEntry(E)
				end
			else
				if E == nil then
					E = newEntry()
					entries[plr] = E
				end
				updateHighlight(E, char, override, S.hlOn)
				if S.boxOn then
					updateBox(E, cam, hrp, override)
				else
					hideBox(E)
				end
			end
		end
	end

	conns[#conns + 1] = RunService.RenderStepped:Connect(function()
		if running then
			pcall(espStep)
		end
	end)

	conns[#conns + 1] = Players.PlayerRemoving:Connect(function(plr)
		local E = entries[plr]
		if E then
			destroyEntry(E)
			entries[plr] = nil
		end
	end)

	---------------------------------------------------------------------
	-- UNLOAD
	---------------------------------------------------------------------
	local function unload()
		if not running then
			return
		end
		running = false
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		for plr, E in pairs(entries) do
			destroyEntry(E)
		end
		entries = {}
		pcall(function()
			espGui:Destroy()
		end)
	end

	conns[#conns + 1] = root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(game) then
			unload()
		end
	end)

	return { Root = root, Unload = unload }
end

return VisualsPage
