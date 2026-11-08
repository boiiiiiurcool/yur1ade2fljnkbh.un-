-- extra.lua  (Y1 Misc tab > Extra page: BulletTracer)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Your gun script makes a "BULLET_RAYS" part for every shot. This module watches for those and
-- leaves a tracer that fades out. Same layout style as aimbot.lua (cards in two columns, switches,
-- sliders, drop-downs and a colour picker).
--
-- LEFT   TRACER   Enable (off every time the script starts), Color (+ opacity), Thickness, Duration
--        FILTERS  Own Shots Only, Max Tracers, Preview (fires a test tracer from your camera)
-- RIGHT  STYLE    Material, Fade Style, Shrink While Fading, Rainbow (+ Speed), Use Bullet Color
--
-- Build signature: Extra.build(container, T, H, ctx) -> { Unload = fn }

local ExtraPage = {}

function ExtraPage.build(parent, T, H, ctx)
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local Debris = game:GetService("Debris")
	local player = Players.LocalPlayer

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH
	local RADIUS = T.RADIUS

	local S = {
		enabled = false,
		color = Color3.fromRGB(255, 220, 120),
		alpha = 0.8,            -- opacity of the tracer when it appears (1 = bright)
		width = 0.08,
		fade = 2.5,             -- seconds
		material = "Neon",
		easing = "Linear",
		shrink = false,
		rainbow = false,
		rainbowSpeed = 5,
		useBullet = false,      -- take the colour the gun script gave the bullet
		ownOnly = false,
		maxCount = 100,
	}

	local MATERIALS = { "Neon", "Glass", "SmoothPlastic", "ForceField" }
	local EASINGS = { "Linear", "Quad", "Sine", "Exponential" }

	local running = true
	local conns = {}
	local popupList = {}
	local tracers = {}

	---------------------------------------------------------------------
	-- pointer helpers
	---------------------------------------------------------------------
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

	local function pointerPos(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			local inset = GuiService:GetGuiInset()
			return Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y)
		end
		return UserInputService:GetMouseLocation()
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
	-- page layout: one scrolling page with two columns of cards
	---------------------------------------------------------------------
	local BODY_Y = 2
	local GAP = 8

	local root = new("Frame", {
		Name = "ExtraRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	local P = {}
	P.scroll = new("ScrollingFrame", {
		Name = "ExtraScroll",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.ICON,
		ScrollBarImageTransparency = 0.5,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ElasticBehavior = Enum.ElasticBehavior.Never,
	}, root)
	P.body = new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(2, BODY_Y),
		Size = UDim2.new(1, -12, 0, 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, P.scroll)

	local colY = { 0, 0 }

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

	function P.section(col, text)
		label(P.body, text, UDim2.new((col - 1) * 0.5, (col - 1) * 6 + 2, 0, colY[col]),
			UDim2.new(0.5, -10, 0, 14), Enum.Font.GothamMedium, 11, T.DIM_TEXT)
		colY[col] = colY[col] + 22
	end

	function P.finish()
		local bodyH = math.max(colY[1], colY[2]) - GAP
		P.body.Size = UDim2.new(1, -12, 0, bodyH)
		P.scroll.CanvasSize = UDim2.new(0, 0, 0, BODY_Y + bodyH + 8)
	end

	---------------------------------------------------------------------
	-- floating pop-ups (sit on the whole page so a scrolling page never cuts them off)
	---------------------------------------------------------------------
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

	local function placeNear(anchor, w, h)
		local s = uiScale()
		local rw = root.AbsoluteSize.X / s
		local rh = root.AbsoluteSize.Y / s
		local rp = root.AbsolutePosition
		local ap = anchor.AbsolutePosition
		local az = anchor.AbsoluteSize
		local ax = (ap.X - rp.X) / s
		local ay = (ap.Y - rp.Y) / s
		local aw = az.X / s
		local ah = az.Y / s
		local x = ax + aw - w
		local y = ay + ah + 6
		if y + h > rh - 4 then
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

		local api = {}
		function api.dim(enabled)
			local colr = T.DIM_TEXT
			if enabled then
				colr = T.ICON_HOVER
			end
			TweenService:Create(fill, FAST, { BackgroundColor3 = colr }):Play()
		end
		api.dim(true)
		return api
	end

	-- a card with only a slider
	local function sliderCard(col, title, minV, maxV, stepV, startValue, fmt, setValue)
		local c = P.place(col, 46)
		makeSlider(c, 13, title, 70, minV, maxV, stepV, startValue, fmt, setValue)
		return c
	end

	-- a small card: title + dim line on the left, a switch on the right
	local function toggleCard(col, title, subText, startOn, onChange)
		local c = P.place(col, 46)
		label(c, title, UDim2.fromOffset(14, 7), UDim2.new(1, -70, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		label(c, subText, UDim2.fromOffset(14, 25), UDim2.new(1, -70, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		makeSwitch(c, startOn, onChange, 23)
		return c
	end

	-- a drop-down card: title on the left, a button with the current value on the right
	local function dropdownCard(col, title, options, startValue, onChange, z)
		local c = P.place(col, 46)
		c.ZIndex = z

		label(c, title, UDim2.fromOffset(14, 0), UDim2.new(1, -150, 1, 0),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)

		local trigger = new("TextButton", {
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

		local chev = {}
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
			chev[#chev + 1] = f
		end
		chevBar(-15, 45)
		chevBar(-11, -45)

		local ITEM_H = 28
		local PAD_P = 4
		local LIST_H = #options * ITEM_H + PAD_P * 2
		local SHOWN = UDim2.new(1, -12, 0, 40)
		local HIDDEN = UDim2.new(1, -12, 0, 34)
		local OPEN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local CLOSE_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		local popup = new("CanvasGroup", {
			Name = "DropdownList",
			AnchorPoint = Vector2.new(1, 0),
			Position = HIDDEN,
			Size = UDim2.fromOffset(150, LIST_H),
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
			for i = 1, #chev do
				TweenService:Create(chev[i], FAST, { BackgroundColor3 = colr }):Play()
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
			popup.Position = HIDDEN
			popup.GroupTransparency = 1
			popup.Visible = true
			TweenService:Create(popup, OPEN_INFO, { Position = SHOWN, GroupTransparency = 0 }):Play()
			paintTrigger()
		end

		local function closeList()
			if not isOpen then
				return
			end
			isOpen = false
			token = token + 1
			local tk = token
			TweenService:Create(popup, CLOSE_INFO, { Position = HIDDEN, GroupTransparency = 1 }):Play()
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
	-- colour picker (saturation / brightness, hue, opacity, hex + opacity text)
	---------------------------------------------------------------------
	local picker = {}
	local pickerEntry = nil

	do
		local PW = 244
		local PH = 262
		local F = makeFloating("TracerColorPicker", PW, PH)
		local pop = F.frame

		local h = 0
		local s = 0
		local v = 1
		local a = 1
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

		-- bottom row: colour + hex text | opacity text
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

		function picker.isOpen()
			return F.isOpen()
		end

		function picker.open(anchor, color, alpha, cb)
			onChange = nil
			h, s, v = color:ToHSV()
			a = alpha
			refresh(false)
			onChange = cb
			local pos = placeNear(anchor, PW, PH)
			if F.isOpen() then
				F.move(pos)
			else
				F.open(pos)
			end
		end

		function picker.close()
			F.close()
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
	-- THE TRACER
	---------------------------------------------------------------------
	local function effectsParent()
		local ignored = workspace:FindFirstChild("Ignored")
		if not ignored then
			return workspace
		end
		local fx = ignored:FindFirstChild("BulletEffects")
		if not fx then
			fx = Instance.new("Folder")
			fx.Name = "BulletEffects"
			fx.Parent = ignored
		end
		return fx
	end

	-- cf = the middle of the tracer (already moved halfway along the shot), length = how long it is
	local function spawnTracer(cf, length, color)
		local mat = Enum.Material.Neon
		pcall(function()
			mat = Enum.Material[S.material]
		end)
		local style = Enum.EasingStyle.Linear
		pcall(function()
			style = Enum.EasingStyle[S.easing]
		end)

		local t = Instance.new("Part")
		t.Name = "BulletTracer"
		t.Anchored = true
		t.CanCollide = false
		t.CanTouch = false
		t.CanQuery = false
		t.CastShadow = false
		t.Material = mat
		t.Color = color
		t.Transparency = 1 - S.alpha
		t.Size = Vector3.new(S.width, S.width, length)
		t.CFrame = cf
		t.Parent = effectsParent()

		tracers[#tracers + 1] = t
		while #tracers > S.maxCount do
			local old = table.remove(tracers, 1)
			if old and old.Parent then
				old:Destroy()
			end
		end

		local goal = { Transparency = 1 }
		if S.shrink then
			goal.Size = Vector3.new(0.001, 0.001, length)
		end
		TweenService:Create(t, TweenInfo.new(S.fade, style, Enum.EasingDirection.Out), goal):Play()
		Debris:AddItem(t, S.fade + 0.1)
	end

	local function pickColor(bulletPart)
		if S.rainbow then
			return Color3.fromHSV((os.clock() * S.rainbowSpeed * 0.1) % 1, 1, 1)
		end
		if S.useBullet and bulletPart then
			local beam = bulletPart:FindFirstChild("NewGunBeam")
			if beam and beam:IsA("Beam") and beam.Color.Keypoints[1] then
				return beam.Color.Keypoints[1].Value
			end
		end
		return S.color
	end

	local function onBullet(bulletPart)
		-- wait a frame so the gun script finishes adding its attachments
		task.wait()
		if not running or not S.enabled or not bulletPart.Parent then
			return
		end

		if S.ownOnly then
			local char = player.Character
			local rp = nil
			if char then
				rp = char:FindFirstChild("HumanoidRootPart")
			end
			if not rp or (rp.Position - bulletPart.Position).Magnitude > 15 then
				return
			end
		end

		-- the end attachment sits at Z = -distance from the muzzle
		local distance = 0
		local kids = bulletPart:GetChildren()
		for i = 1, #kids do
			if kids[i]:IsA("Attachment") then
				distance = math.max(distance, math.abs(kids[i].Position.Z))
			end
		end
		if distance < 1 then
			return
		end

		spawnTracer(bulletPart.CFrame * CFrame.new(0, 0, -distance / 2), distance, pickColor(bulletPart))
	end

	conns[#conns + 1] = workspace.DescendantAdded:Connect(function(d)
		if running and S.enabled and d.Name == "BULLET_RAYS" and d:IsA("BasePart") then
			task.spawn(onBullet, d)
		end
	end)

	local function preview()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local origin = cam.CFrame * CFrame.new(1.5, -1, -2)
		spawnTracer(origin * CFrame.new(0, 0, -30), 60, pickColor(nil))
	end

	---------------------------------------------------------------------
	-- THE CARDS
	---------------------------------------------------------------------
	local outlineSwatch = nil

	-- LEFT: TRACER
	P.section(1, "TRACER")

	local enableCard = P.place(1, 46)
	label(enableCard, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -70, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local enableSub = label(enableCard, "", UDim2.fromOffset(14, 25), UDim2.new(1, -70, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	local function refreshStatus()
		if S.enabled then
			enableSub.Text = "Active"
			enableSub.TextColor3 = T.GREEN
		else
			enableSub.Text = "Off"
			enableSub.TextColor3 = T.DIM_TEXT
		end
	end
	refreshStatus()
	makeSwitch(enableCard, S.enabled, function(on)
		S.enabled = on
		refreshStatus()
	end, 23)

	-- Color card: colour square on the right opens the picker (opacity is in the picker)
	local colorCard = P.place(1, 46)
	label(colorCard, "Color", UDim2.fromOffset(14, 7), UDim2.new(1, -70, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	label(colorCard, "Colour and opacity", UDim2.fromOffset(14, 25), UDim2.new(1, -70, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	outlineSwatch = makeSwatch(colorCard, UDim2.new(1, -12, 0.5, 0), S.color, function()
		if picker.isOpen() then
			picker.close()
			return
		end
		picker.open(outlineSwatch.btn, S.color, S.alpha, function(c, al)
			S.color = c
			S.alpha = al
			outlineSwatch.paint(c)
		end)
	end)
	table.insert(pickerEntry.hit, outlineSwatch.btn)

	sliderCard(1, "Thickness", 0.01, 1, 0.01, S.width, "%.2f", function(v)
		S.width = v
	end)

	sliderCard(1, "Duration", 0.1, 10, 0.1, S.fade, "%.1fs", function(v)
		S.fade = v
	end)

	P.section(1, "FILTERS")

	toggleCard(1, "Own Shots Only", "Skip other players' tracers", S.ownOnly, function(on)
		S.ownOnly = on
	end)

	sliderCard(1, "Max Tracers", 10, 300, 10, S.maxCount, "%d", function(v)
		S.maxCount = v
	end)

	local prevCard = P.place(1, 46)
	label(prevCard, "Preview", UDim2.fromOffset(14, 7), UDim2.new(1, -110, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	label(prevCard, "Fire a test tracer", UDim2.fromOffset(14, 25), UDim2.new(1, -110, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	local prevBtn = new("TextButton", {
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(76, 28),
		BackgroundColor3 = T.CLUSTER_BG,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = T.ICON_HOVER,
		Text = "Fire",
	}, prevCard)
	corner(prevBtn, RADIUS + 2)
	prevBtn.MouseEnter:Connect(function()
		TweenService:Create(prevBtn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
	end)
	prevBtn.MouseLeave:Connect(function()
		TweenService:Create(prevBtn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
	end)
	prevBtn.Activated:Connect(preview)

	-- RIGHT: STYLE
	P.section(2, "STYLE")

	dropdownCard(2, "Material", MATERIALS, S.material, function(v)
		S.material = v
	end, 26)

	dropdownCard(2, "Fade Style", EASINGS, S.easing, function(v)
		S.easing = v
	end, 25)

	toggleCard(2, "Shrink", "Gets thinner while fading", S.shrink, function(on)
		S.shrink = on
	end)

	toggleCard(2, "Use Bullet Color", "Colour from the gun script", S.useBullet, function(on)
		S.useBullet = on
	end)

	-- Rainbow with a Speed slider under it
	do
		local rc = P.place(2, 82)
		label(rc, "Rainbow", UDim2.fromOffset(14, 7), UDim2.new(1, -70, 0, 16),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
		label(rc, "Colour cycles every shot", UDim2.fromOffset(14, 25), UDim2.new(1, -70, 0, 14),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
		local sp = makeSlider(rc, 50, "Speed", 40, 1, 20, 1, S.rainbowSpeed, "%d", function(v)
			S.rainbowSpeed = v
		end)
		sp.dim(S.rainbow)
		makeSwitch(rc, S.rainbow, function(on)
			S.rainbow = on
			sp.dim(on)
		end, 23)
	end

	P.finish()

	-- the floating pop-ups stay where they opened, so they close when the page is scrolled
	conns[#conns + 1] = P.scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(closeAllPopups)

	-- a click or tap anywhere except inside an open pop-up (or its button) closes that pop-up
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

	-- leaving the page closes every pop-up
	if parent:IsA("GuiObject") then
		conns[#conns + 1] = parent:GetPropertyChangedSignal("Visible"):Connect(function()
			if not parent.Visible then
				closeAllPopups()
			end
		end)
	end

	---------------------------------------------------------------------
	-- UNLOAD
	---------------------------------------------------------------------
	local function unload()
		if not running then
			return
		end
		running = false
		S.enabled = false
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		for i = 1, #tracers do
			local t = tracers[i]
			if t and t.Parent then
				pcall(function()
					t:Destroy()
				end)
			end
		end
		tracers = {}
	end

	return { Root = root, Unload = unload }
end

return ExtraPage
