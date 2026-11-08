-- extra.lua  (Y1 Misc tab > Extra page: BulletTracer + HitSounds, Zee Hood only)
-- ASCII only, conservative syntax (no += and no continue).
--
-- BULLET TRACER
--   Your gun script makes a "BULLET_RAYS" part for every shot. This module watches for those and
--   leaves a tracer that fades out. Only YOUR shots get a tracer (a bullet that does not start close
--   to your character is ignored).
--
-- HIT SOUNDS
--   Plays a sound effect for YOUR shots only (never for other people shooting).
--   Sound Player Option:
--     On Shot = plays every time you shoot.
--     On Hit  = plays only when your shot actually hits another character (player / humanoid).
--   It works by wrapping GunHandler.Shoot (the same function in the gun script you sent). Shoot returns
--   the instance the bullet hit, so On Hit uses the exact same result the game uses. Only calls where
--   Shooter == your character count. If GunHandler cannot be found, it falls back to watching the
--   BULLET_RAYS parts and re-checking the bullet path with a raycast.
--
-- HIT MARKERS
--   When you shoot someone, the damage you did shows as red text next to them (like -200 or -100).
--   The text is a world-size billboard, so it gets bigger when they are close and smaller when
--   they are far. The only setting is Fade Speed (how fast the text disappears).
--   The damage is measured from the target's health dropping right after your hit lands.
--
-- Each page card is a small Enable card (a switch, OFF every time the script starts, and three dots).
-- The dots open one settings pop-up. Click the dots again, or anywhere except the pop-up, to close it.
-- Tracer: Material and Fade Style: click the button to go to the next choice.
-- Hit Sounds: Sound and Sound Player Option are real drop-down menus (they open a list next to the pop-up).
--
-- FIX: pop-ups no longer close when you click inside them near the bottom. The old check compared the
-- mouse position (which includes the top bar offset) with the pop-up position (which may not), so the
-- bottom strip of a pop-up counted as "outside". The check now tries every coordinate space.
--
-- Build signature: Extra.build(container, T, H, ctx) -> { Root = ..., Unload = fn }

local ExtraPage = {}

function ExtraPage.build(parent, T, H, ctx)
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local Debris = game:GetService("Debris")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local SoundService = game:GetService("SoundService")
	local ContentProvider = game:GetService("ContentProvider")
	local player = Players.LocalPlayer

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH
	local RADIUS = T.RADIUS

	-- tracer settings
	local S = {
		enabled = false,
		color = Color3.fromRGB(255, 220, 120),
		alpha = 0.8,            -- opacity of the tracer when it appears (1 = bright)
		width = 0.08,
		fade = 2.5,             -- seconds
		material = "Neon",
		easing = "Linear",
		rainbow = false,
		rainbowSpeed = 5,
	}

	-- hit sound settings
	local SOUNDS = {
		{ "Minecraft Bow", "135478009117226" },
		{ "Undertale", "140721035016341" },
		{ "Critical", "137392628136734" },
		{ "Punch", "138208560796742" },
		{ "Rock", "82708037443413" },
		{ "DANG", "135602581462761" },
		{ "Retro", "109681634329245" },
		{ "Spear", "135278368445325" },
		{ "Doom", "137176923000279" },
	}
	local SOUND_NAMES = {}
	for i = 1, #SOUNDS do
		SOUND_NAMES[i] = SOUNDS[i][1]
	end
	local MODES = { "On Shot", "On Hit" }

	local HS = {
		enabled = false,
		soundIndex = 1,
		mode = "On Hit",
		volume = 1,
		muteGun = false,   -- mute the game's own gun sound for YOUR gun while Hit Sounds is on
	}

	-- hit marker settings (speed 1 = text stays about 3s, 10 = about 0.3s)
	local HM = {
		enabled = false,
		speed = 3,
	}

	local OWN_RANGE = 15        -- a bullet has to start this close to your character to count as yours
	local MAX_TRACERS = 100
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

	-- true when the pointer is over obj. Mouse and touch positions can be shifted by the top bar
	-- (GuiInset) compared with AbsolutePosition, so every possible space is tried. This is what
	-- fixes pop-ups closing when you click near the bottom of them.
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

	local function closeAllPopups()
		for i = 1, #popupList do
			local pp = popupList[i]
			if pp.isOpen() then
				pp.close()
			end
		end
	end

	---------------------------------------------------------------------
	-- root
	---------------------------------------------------------------------
	local root = new("Frame", {
		Name = "ExtraRoot",
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

	-- where a w x h pop-up goes: next to the anchor (right of it, or left when there is no room).
	-- With "beside" it goes to the left (or right) of that frame instead. Always kept inside the page.
	local function placeNear(anchor, w, h, beside)
		local s = uiScale()
		local rw = root.AbsoluteSize.X / s
		local rh = root.AbsoluteSize.Y / s
		local ax, ay, aw, ah = rectIn(anchor)
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

	-- three horizontal dots (lit while hovered or while open)
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

	-- a row with a title on the left and a button on the right; clicking the button goes to the next choice
	local function cycleRow(c, y, title, options, startValue, onChange)
		label(c, title, UDim2.fromOffset(16, y), UDim2.new(1, -150, 0, 28),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)

		local btn = new("TextButton", {
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, y),
			Size = UDim2.fromOffset(124, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = T.ICON_HOVER,
			Text = startValue,
		}, c)
		corner(btn, RADIUS + 2)

		local index = 1
		for i = 1, #options do
			if options[i] == startValue then
				index = i
			end
		end

		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
		end)
		btn.Activated:Connect(function()
			index = index + 1
			if index > #options then
				index = 1
			end
			btn.Text = options[index]
			onChange(options[index])
		end)
	end

	-- a real drop-down: a row with a title and a button; clicking the button opens a list of choices in
	-- its own little panel next to the settings pop-up (so nothing is cut off). Picking a choice closes
	-- the list and calls onPick(index). Returns { frame = list panel, close = fn }.
	local function dropdownRow(c, y, title, labelW, btnW, names, startIndex, onPick, besideFrame)
		label(c, title, UDim2.fromOffset(16, y), UDim2.fromOffset(labelW, 28),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)

		local btn = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, y),
			Size = UDim2.fromOffset(btnW, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, c)
		corner(btn, RADIUS + 2)

		local current = startIndex
		local nameLabel = label(btn, names[current], UDim2.fromOffset(10, 0), UDim2.new(1, -30, 1, 0),
			Enum.Font.GothamMedium, 12, T.ICON_HOVER)
		label(btn, "v", UDim2.new(1, -20, 0, 0), UDim2.fromOffset(12, 28),
			Enum.Font.GothamBold, 11, T.DIM_TEXT, Enum.TextXAlignment.Center)

		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, FAST, { BackgroundColor3 = T.HOVER_GREY }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, FAST, { BackgroundColor3 = T.CLUSTER_BG }):Play()
		end)

		local optH = 26
		local listW = math.max(btnW, 140)
		local contentH = #names * optH + 8
		local F = makeFloating("Dropdown" .. title, listW, contentH)
		F.frame.ZIndex = 70

		local sc = new("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = T.DIM_TEXT,
			CanvasSize = UDim2.fromOffset(0, contentH),
		}, F.frame)

		local optButtons = {}
		local function paintOptions()
			for i = 1, #optButtons do
				if i == current then
					optButtons[i].BackgroundTransparency = 0
				else
					optButtons[i].BackgroundTransparency = 1
				end
			end
		end

		for i = 1, #names do
			local ob = new("TextButton", {
				AutoButtonColor = false,
				Text = "",
				Position = UDim2.fromOffset(4, 4 + (i - 1) * optH),
				Size = UDim2.new(1, -8, 0, optH - 2),
				BackgroundColor3 = T.HOVER_GREY,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, sc)
			corner(ob, RADIUS)
			label(ob, names[i], UDim2.fromOffset(10, 0), UDim2.new(1, -20, 1, 0),
				Enum.Font.GothamMedium, 12, T.TEXT_COLOR)
			optButtons[i] = ob

			ob.MouseEnter:Connect(function()
				ob.BackgroundTransparency = 0
			end)
			ob.MouseLeave:Connect(function()
				if i == current then
					ob.BackgroundTransparency = 0
				else
					ob.BackgroundTransparency = 1
				end
			end)
			ob.Activated:Connect(function()
				current = i
				nameLabel.Text = names[i]
				paintOptions()
				F.close()
				onPick(i)
			end)
		end
		paintOptions()

		local function openList()
			local s = uiScale()
			local rh = root.AbsoluteSize.Y / s
			local h = math.min(contentH, math.max(60, rh - 8))
			F.frame.Size = UDim2.fromOffset(listW, h)
			sc.CanvasPosition = Vector2.new(0, 0)
			F.open(placeNear(btn, listW, h, besideFrame))
		end

		btn.Activated:Connect(function()
			if F.isOpen() then
				F.close()
			else
				openList()
			end
		end)

		-- clicking inside the list (or on its button) must never count as "outside"
		popupList[#popupList + 1] = {
			isOpen = function()
				return F.isOpen()
			end,
			close = F.close,
			hit = { F.frame, btn },
		}

		return { frame = F.frame, close = F.close }
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

		function picker.open(anchor, color, alpha, cb, beside)
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
	-- TRACER CARD (switch + three dots)   left half of the page
	---------------------------------------------------------------------
	local card = new("Frame", {
		Name = "EnableCard",
		Position = UDim2.fromOffset(2, 24),
		Size = UDim2.new(0.5, -6, 0, 46),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
	}, root)
	corner(card, RADIUS + 4)
	stroke(card, T.BORDER, 1, 0)

	label(root, "BULLET TRACER", UDim2.fromOffset(4, 6), UDim2.new(0.5, -10, 0, 14),
		Enum.Font.GothamMedium, 11, T.DIM_TEXT)

	label(card, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local enableSub = label(card, "", UDim2.fromOffset(14, 25), UDim2.new(1, -110, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	enableSub.RichText = true

	local function refreshStatus()
		local state = '<font color="rgb(116,116,124)">Off</font>'
		if S.enabled then
			state = '<font color="rgb(52,199,120)">Active</font>'
		end
		enableSub.Text = '<font color="rgb(230,230,234)"><b>Zee Hood only</b></font> - ' .. state
	end
	refreshStatus()

	makeSwitch(card, S.enabled, function(on)
		S.enabled = on
		refreshStatus()
	end, 23)

	local dots = makeDots(card, UDim2.new(1, -58, 0, 23))

	---------------------------------------------------------------------
	-- TRACER SETTINGS POP-UP (opens from the three dots)
	--   Color / Material / Fade Style / Thickness / Duration / Rainbow (+ Speed)
	---------------------------------------------------------------------
	local SW = 264
	local SH = 296
	local settings = makeFloating("TracerSettings", SW, SH)
	local pop = settings.frame
	local colorSwatch = nil

	label(pop, "Bullet Tracer", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)
	new("Frame", {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, pop)

	-- Color (+ opacity in the picker)
	label(pop, "Color", UDim2.fromOffset(16, 48), UDim2.new(1, -90, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	colorSwatch = makeSwatch(pop, UDim2.new(1, -16, 0, 62), S.color, function()
		if picker.isOpen() then
			picker.close()
			return
		end
		picker.open(colorSwatch.btn, S.color, S.alpha, function(c, al)
			S.color = c
			S.alpha = al
			colorSwatch.paint(c)
		end, settings.frame)
	end)

	cycleRow(pop, 84, "Material", MATERIALS, S.material, function(v)
		S.material = v
	end)

	cycleRow(pop, 118, "Fade Style", EASINGS, S.easing, function(v)
		S.easing = v
	end)

	makeSlider(pop, 156, "Thickness", 64, 0.01, 1, 0.01, S.width, "%.2f", function(v)
		S.width = v
	end)

	makeSlider(pop, 186, "Duration", 64, 0.1, 10, 0.1, S.fade, "%.1fs", function(v)
		S.fade = v
	end)

	new("Frame", {
		Position = UDim2.fromOffset(16, 218),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, pop)

	-- Rainbow with a Speed slider under it
	label(pop, "Rainbow", UDim2.fromOffset(16, 224), UDim2.new(1, -90, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local speedApi = makeSlider(pop, 262, "Speed", 64, 1, 20, 1, S.rainbowSpeed, "%d", function(v)
		S.rainbowSpeed = v
	end)
	speedApi.dim(S.rainbow)
	makeSwitch(pop, S.rainbow, function(on)
		S.rainbow = on
		speedApi.dim(on)
	end, 238, 16)

	local function openSettings()
		if settings.isOpen() then
			return
		end
		settings.open(placeNear(dots.btn, SW, SH, nil))
		dots.open = true
		dots.paint()
	end

	local function closeSettings()
		settings.close()
		if picker.isOpen() then
			picker.close()
		end
		dots.open = false
		dots.paint()
	end

	dots.btn.Activated:Connect(function()
		if settings.isOpen() then
			closeSettings()
		else
			openSettings()
		end
	end)

	popupList[#popupList + 1] = {
		isOpen = function()
			return settings.isOpen()
		end,
		close = closeSettings,
		hit = { pop, picker.frame, dots.btn },
	}
	-- the colour picker must not close when the colour square is clicked
	table.insert(pickerEntry.hit, colorSwatch.btn)

	---------------------------------------------------------------------
	-- HIT SOUNDS: sound playing
	---------------------------------------------------------------------
	local lastPlay = 0

	local function playHitSound(preview)
		local now = os.clock()
		if not preview and now - lastPlay < 0.05 then
			return
		end
		lastPlay = now
		local entry = SOUNDS[HS.soundIndex]
		if not entry then
			return
		end
		local snd = Instance.new("Sound")
		snd.Name = "ExtraHitSound"
		snd.SoundId = "rbxassetid://" .. entry[2]
		snd.Volume = HS.volume
		snd.Parent = SoundService
		snd.Ended:Connect(function()
			snd:Destroy()
		end)
		snd:Play()
		Debris:AddItem(snd, 15)
	end

	local function preloadCurrent()
		local entry = SOUNDS[HS.soundIndex]
		if not entry then
			return
		end
		task.spawn(function()
			local snd = Instance.new("Sound")
			snd.SoundId = "rbxassetid://" .. entry[2]
			pcall(function()
				ContentProvider:PreloadAsync({ snd })
			end)
			snd:Destroy()
		end)
	end

	---------------------------------------------------------------------
	-- HIT SOUNDS CARD (switch + three dots)   right half of the page
	---------------------------------------------------------------------
	local hsCard = new("Frame", {
		Name = "HitSoundsCard",
		Position = UDim2.new(0.5, 4, 0, 24),
		Size = UDim2.new(0.5, -6, 0, 46),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
	}, root)
	corner(hsCard, RADIUS + 4)
	stroke(hsCard, T.BORDER, 1, 0)

	label(root, "HIT SOUNDS", UDim2.new(0.5, 6, 0, 6), UDim2.new(0.5, -10, 0, 14),
		Enum.Font.GothamMedium, 11, T.DIM_TEXT)

	label(hsCard, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local hsSub = label(hsCard, "", UDim2.fromOffset(14, 25), UDim2.new(1, -110, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	hsSub.RichText = true

	local function refreshHsStatus()
		local state = '<font color="rgb(116,116,124)">Off</font>'
		if HS.enabled then
			state = '<font color="rgb(52,199,120)">Active</font>'
		end
		hsSub.Text = '<font color="rgb(230,230,234)"><b>Zee Hood only</b></font> - ' .. state
	end
	refreshHsStatus()

	makeSwitch(hsCard, HS.enabled, function(on)
		HS.enabled = on
		refreshHsStatus()
		if on then
			preloadCurrent()
		end
	end, 23)

	local hsDots = makeDots(hsCard, UDim2.new(1, -58, 0, 23))

	---------------------------------------------------------------------
	-- HIT SOUNDS SETTINGS POP-UP
	--   Sound (drop-down) / Sound Player Option (drop-down) / Volume
	---------------------------------------------------------------------
	local HSW = 320
	local HSH = 210
	local hsSettings = makeFloating("HitSoundSettings", HSW, HSH)
	local hsPop = hsSettings.frame

	label(hsPop, "Hit Sounds", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)
	new("Frame", {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, hsPop)

	local hsDropdowns = {}

	hsDropdowns[#hsDropdowns + 1] = dropdownRow(hsPop, 50, "Sound", 150, 128, SOUND_NAMES,
		HS.soundIndex, function(i)
			HS.soundIndex = i
			preloadCurrent()
			playHitSound(true) -- preview the sound you just picked
		end, hsPop)

	local modeIndex = 2
	for i = 1, #MODES do
		if MODES[i] == HS.mode then
			modeIndex = i
		end
	end
	hsDropdowns[#hsDropdowns + 1] = dropdownRow(hsPop, 86, "Sound Player Option", 150, 128, MODES,
		modeIndex, function(i)
			HS.mode = MODES[i]
		end, hsPop)

	makeSlider(hsPop, 130, "Volume", 64, 0.1, 3, 0.1, HS.volume, "%.1f", function(v)
		HS.volume = v
	end)

	-- Mute Gun Sounds: silences the game's normal shot sound for your own gun
	label(hsPop, "Mute Gun Sounds", UDim2.fromOffset(16, 166), UDim2.new(1, -90, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	makeSwitch(hsPop, HS.muteGun, function(on)
		HS.muteGun = on
	end, 180, 16)

	local function openHs()
		if hsSettings.isOpen() then
			return
		end
		hsSettings.open(placeNear(hsDots.btn, HSW, HSH, nil))
		hsDots.open = true
		hsDots.paint()
	end

	local function closeHs()
		hsSettings.close()
		for i = 1, #hsDropdowns do
			hsDropdowns[i].close()
		end
		hsDots.open = false
		hsDots.paint()
	end

	hsDots.btn.Activated:Connect(function()
		if hsSettings.isOpen() then
			closeHs()
		else
			openHs()
		end
	end)

	local hsHit = { hsPop, hsDots.btn }
	for i = 1, #hsDropdowns do
		hsHit[#hsHit + 1] = hsDropdowns[i].frame
	end
	popupList[#popupList + 1] = {
		isOpen = function()
			return hsSettings.isOpen()
		end,
		close = closeHs,
		hit = hsHit,
	}

	---------------------------------------------------------------------
	-- HIT MARKERS CARD (switch + three dots)   second row, left half
	---------------------------------------------------------------------
	local hmCard = new("Frame", {
		Name = "HitMarkersCard",
		Position = UDim2.fromOffset(2, 98),
		Size = UDim2.new(0.5, -6, 0, 46),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
	}, root)
	corner(hmCard, RADIUS + 4)
	stroke(hmCard, T.BORDER, 1, 0)

	label(root, "HIT MARKERS", UDim2.fromOffset(4, 80), UDim2.new(0.5, -10, 0, 14),
		Enum.Font.GothamMedium, 11, T.DIM_TEXT)

	label(hmCard, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local hmSub = label(hmCard, "", UDim2.fromOffset(14, 25), UDim2.new(1, -110, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	hmSub.RichText = true

	local function refreshHmStatus()
		local state = '<font color="rgb(116,116,124)">Off</font>'
		if HM.enabled then
			state = '<font color="rgb(52,199,120)">Active</font>'
		end
		hmSub.Text = '<font color="rgb(230,230,234)"><b>Zee Hood only</b></font> - ' .. state
	end
	refreshHmStatus()

	makeSwitch(hmCard, HM.enabled, function(on)
		HM.enabled = on
		refreshHmStatus()
	end, 23)

	local hmDots = makeDots(hmCard, UDim2.new(1, -58, 0, 23))

	-- settings pop-up: only the Fade Speed
	local HMW = 280
	local HMH = 92
	local hmSettings = makeFloating("HitMarkerSettings", HMW, HMH)
	local hmPop = hmSettings.frame

	label(hmPop, "Hit Markers", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)
	new("Frame", {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, hmPop)

	makeSlider(hmPop, 56, "Fade Speed", 76, 1, 10, 1, HM.speed, "%d", function(v)
		HM.speed = v
	end)

	local function openHm()
		if hmSettings.isOpen() then
			return
		end
		hmSettings.open(placeNear(hmDots.btn, HMW, HMH, nil))
		hmDots.open = true
		hmDots.paint()
	end

	local function closeHm()
		hmSettings.close()
		hmDots.open = false
		hmDots.paint()
	end

	hmDots.btn.Activated:Connect(function()
		if hmSettings.isOpen() then
			closeHm()
		else
			openHm()
		end
	end)

	popupList[#popupList + 1] = {
		isOpen = function()
			return hmSettings.isOpen()
		end,
		close = closeHm,
		hit = { hmPop, hmDots.btn },
	}

	---------------------------------------------------------------------
	-- HIT SOUNDS: detecting YOUR shots / YOUR hits
	---------------------------------------------------------------------
	local hooked = false
	local trackHit = nil   -- filled in below (the hit marker code); called by both hit detectors
	local gspTable = nil
	local gspOriginal = nil
	local gspFn = nil
	local hookGH = nil
	local hookOriginal = nil
	local hookFn = nil

	-- the Humanoid of the living character inst belongs to (not you), or nil
	local function enemyHumanoid(inst)
		if typeof(inst) ~= "Instance" then
			return nil
		end
		local myChar = player.Character
		if myChar and inst:IsDescendantOf(myChar) then
			return nil
		end
		local m = inst
		while m and m ~= workspace and m ~= game do
			if m:IsA("Model") then
				local hum = m:FindFirstChildOfClass("Humanoid")
				if hum then
					if hum.Health > 0 then
						return hum
					end
					return nil
				end
			end
			m = m.Parent
		end
		return nil
	end

	local function isEnemyHit(inst)
		return enemyHumanoid(inst) ~= nil
	end

	-- the params table passed to GunHandler.Shoot (it has a Shooter field)
	local function findParams(...)
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			if type(v) == "table" and v.Shooter ~= nil then
				return v
			end
		end
		return nil
	end

	-- true when this Shoot call is a real shot fired by YOUR character
	local function isMyShot(params)
		local myChar = player.Character
		if not myChar then
			return false
		end
		if params.Shooter ~= myChar then
			return false
		end
		if params.Replay == true or params.IsReflecting then
			return false
		end
		return true
	end

	-- wrap GunHandler.Shoot (the gun script you sent). Done in the background so the page appears at once.
	task.spawn(function()
		local ok, gh = pcall(function()
			local mods = ReplicatedStorage:WaitForChild("Modules", 10)
			local m = mods:WaitForChild("GunHandler", 10)
			return require(m)
		end)
		if not running then
			return
		end
		if not ok or type(gh) ~= "table" or type(gh.Shoot) ~= "function" then
			return -- the BULLET_RAYS fallback below will be used instead
		end

		local original = gh.Shoot
		local function hook(...)
			local params = findParams(...)
			local mine = false
			if running and (HS.enabled or HM.enabled) and params ~= nil then
				mine = isMyShot(params)
			end

			-- On Shot: play right away, before the gun script does its (slow) effects work
			if mine and HS.enabled and HS.mode == "On Shot" then
				pcall(playHitSound, false)
			end

			-- Shoot returns: hit position, the instance that was hit, hit normal
			local r1, r2, r3 = original(...)

			-- only when MY shot hit another character: hit sound (On Hit) and hit marker
			if mine then
				local hum = enemyHumanoid(r2)
				if hum then
					if HS.enabled and HS.mode == "On Hit" then
						pcall(playHitSound, false)
					end
					if HM.enabled and trackHit then
						pcall(trackHit, hum, r2)
					end
				end
			end

			return r1, r2, r3
		end

		hookGH = gh
		hookOriginal = original
		hookFn = hook
		gh.Shoot = hook
		hooked = true
	end)

	-- wrap GunSoundPlay.SoundPlay (the gun script calls it for every shot). While Mute Gun Sounds is on,
	-- shots from YOUR gun make no normal sound, so only your hit sound plays. Other players' guns are untouched.
	task.spawn(function()
		local ok, gsp = pcall(function()
			return require(ReplicatedStorage:WaitForChild("GunSoundPlay", 10))
		end)
		if not running then
			return
		end
		if not ok or type(gsp) ~= "table" or type(gsp.SoundPlay) ~= "function" then
			return
		end
		local origSound = gsp.SoundPlay
		local function muted(handle, ...)
			if running and HS.enabled and HS.muteGun and typeof(handle) == "Instance" then
				local myChar = player.Character
				if myChar and handle:IsDescendantOf(myChar) then
					return
				end
			end
			return origSound(handle, ...)
		end
		gspTable = gsp
		gspOriginal = origSound
		gspFn = muted
		gsp.SoundPlay = muted
	end)

	-- fallback when GunHandler could not be wrapped: watch BULLET_RAYS parts and re-check the path
	local function onBulletForSound(bulletPart)
		task.wait()
		if not running or not (HS.enabled or HM.enabled) or hooked or not bulletPart.Parent then
			return
		end
		local char = player.Character
		if not char then
			return
		end

		local mine = false
		local owner = bulletPart:GetAttribute("OwnerCharacter")
		if owner ~= nil then
			mine = (owner == char.Name)
		else
			local rp = char:FindFirstChild("HumanoidRootPart")
			if rp and (rp.Position - bulletPart.Position).Magnitude <= OWN_RANGE then
				mine = true
			end
		end
		if not mine then
			return
		end

		if HS.enabled and HS.mode == "On Shot" then
			playHitSound(false)
		end
		local wantHit = HM.enabled or (HS.enabled and HS.mode == "On Hit")
		if not wantHit then
			return
		end

		-- On Hit: how long is the bullet, then raycast along it
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
		local rayParams = RaycastParams.new()
		local exclude = { char }
		local ign = workspace:FindFirstChild("Ignored")
		if ign then
			exclude[#exclude + 1] = ign
		end
		rayParams.FilterDescendantsInstances = exclude
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.IgnoreWater = true
		local res = workspace:Raycast(bulletPart.Position, bulletPart.CFrame.LookVector * (distance + 1), rayParams)
		local hum = nil
		if res then
			hum = enemyHumanoid(res.Instance)
		end
		if hum then
			if HS.enabled and HS.mode == "On Hit" then
				playHitSound(false)
			end
			if HM.enabled and trackHit then
				pcall(trackHit, hum, res.Instance)
			end
		end
	end

	conns[#conns + 1] = workspace.DescendantAdded:Connect(function(d)
		if running and (HS.enabled or HM.enabled) and not hooked and d.Name == "BULLET_RAYS" and d:IsA("BasePart") then
			task.spawn(onBulletForSound, d)
		end
	end)

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

	-- HIT MARKERS: red damage text next to the player you hit.
	-- The text lives in a BillboardGui whose size is in studs, so it shrinks with distance and grows
	-- when the target is close.
	local pendingHits = setmetatable({}, { __mode = "k" })

	local function showMarker(target, dmg)
		local cam = workspace.CurrentCamera
		local right = Vector3.new(1, 0, 0)
		if cam then
			right = cam.CFrame.RightVector
		end
		local side = 2.6 + (math.random() - 0.5) * 0.8
		local up = 1.4 + math.random() * 0.7
		local startPos = target.Position + right * side + Vector3.new(0, up, 0)
		local dur = 3 / math.max(1, HM.speed)

		local anchor = Instance.new("Part")
		anchor.Name = "HitMarker"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Position = startPos
		anchor.Parent = effectsParent()

		local gui = Instance.new("BillboardGui")
		gui.Name = "HitMarkerGui"
		gui.Adornee = anchor
		gui.Size = UDim2.fromScale(5, 2.2)   -- scale = studs, that is what makes it size with distance
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Parent = anchor

		local txt = Instance.new("TextLabel")
		txt.BackgroundTransparency = 1
		txt.Size = UDim2.fromScale(1, 1)
		txt.Font = Enum.Font.GothamBlack
		txt.TextScaled = true
		txt.Text = "-" .. tostring(math.floor(dmg + 0.5))
		txt.TextColor3 = Color3.fromRGB(255, 50, 50)
		txt.TextStrokeColor3 = Color3.fromRGB(20, 0, 0)
		txt.TextStrokeTransparency = 0.25
		txt.Parent = gui

		TweenService:Create(txt, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		TweenService:Create(anchor, TweenInfo.new(dur, Enum.EasingStyle.Linear), {
			Position = startPos + Vector3.new(0, 1.5, 0),
		}):Play()
		Debris:AddItem(anchor, dur + 0.2)
	end

	-- called when one of YOUR shots hits a character: watch its health for a moment and show every
	-- drop as a number (shotgun pellets that land one after another each get their own number)
	trackHit = function(hum, part)
		if not HM.enabled then
			return
		end
		local target = part
		local model = hum.Parent
		if model then
			local hrp2 = model:FindFirstChild("HumanoidRootPart")
			if hrp2 and hrp2:IsA("BasePart") then
				target = hrp2
			end
		end
		if not target or not target:IsA("BasePart") then
			return
		end

		local now = os.clock()
		local rec = pendingHits[hum]
		if rec then
			rec.expire = now + 0.8
			rec.target = target
			return
		end

		rec = { last = hum.Health, expire = now + 0.8, target = target }
		pendingHits[hum] = rec
		local c = hum.HealthChanged:Connect(function(newHealth)
			local d = rec.last - newHealth
			rec.last = newHealth
			if running and HM.enabled and d >= 1 and os.clock() <= rec.expire then
				pcall(showMarker, rec.target, d)
			end
		end)
		task.spawn(function()
			while running and hum.Parent and os.clock() < rec.expire do
				task.wait(0.05)
			end
			c:Disconnect()
			pendingHits[hum] = nil
		end)
	end

	-- cf = the middle of the tracer (already moved halfway along the shot)
	local function spawnTracer(cf, length)
		local mat = Enum.Material.Neon
		pcall(function()
			mat = Enum.Material[S.material]
		end)
		local style = Enum.EasingStyle.Linear
		pcall(function()
			style = Enum.EasingStyle[S.easing]
		end)

		local color = S.color
		if S.rainbow then
			color = Color3.fromHSV((os.clock() * S.rainbowSpeed * 0.1) % 1, 1, 1)
		end

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
		while #tracers > MAX_TRACERS do
			local old = table.remove(tracers, 1)
			if old and old.Parent then
				old:Destroy()
			end
		end

		TweenService:Create(t, TweenInfo.new(S.fade, style, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
		Debris:AddItem(t, S.fade + 0.1)
	end

	local function onBullet(bulletPart)
		-- wait a frame so the gun script finishes adding its attachments
		task.wait()
		if not running or not S.enabled or not bulletPart.Parent then
			return
		end

		-- only your own shots: the bullet has to start next to your character
		local char = player.Character
		local rp = nil
		if char then
			rp = char:FindFirstChild("HumanoidRootPart")
		end
		if not rp or (rp.Position - bulletPart.Position).Magnitude > OWN_RANGE then
			return
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

		spawnTracer(bulletPart.CFrame * CFrame.new(0, 0, -distance / 2), distance)
	end

	conns[#conns + 1] = workspace.DescendantAdded:Connect(function(d)
		if running and S.enabled and d.Name == "BULLET_RAYS" and d:IsA("BasePart") then
			task.spawn(onBullet, d)
		end
	end)

	---------------------------------------------------------------------
	-- INPUT: a click or tap anywhere except inside an open pop-up (or its button) closes it
	---------------------------------------------------------------------
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

	-- leaving this page (or the Misc tab) closes every pop-up: watch the page and everything above it
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
	-- UNLOAD
	---------------------------------------------------------------------
	local function unload()
		if not running then
			return
		end
		running = false
		S.enabled = false
		HS.enabled = false
		HM.enabled = false
		-- put GunHandler.Shoot back the way it was (only if nobody wrapped it after us)
		if hookGH and hookFn and hookGH.Shoot == hookFn then
			pcall(function()
				hookGH.Shoot = hookOriginal
			end)
		end
		-- put GunSoundPlay.SoundPlay back the way it was
		if gspTable and gspFn and gspTable.SoundPlay == gspFn then
			pcall(function()
				gspTable.SoundPlay = gspOriginal
			end)
		end
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

	conns[#conns + 1] = root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(game) then
			unload()
		end
	end)

	return { Root = root, Unload = unload }
end

return ExtraPage
