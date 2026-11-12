-- movement.lua  (Y1 Misc tab > Movement page)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Three connected backgrounds (the page scrolls if it has to):
--   left  : "Main Movements"  = Walk Speed, Jump Power, Inf Jump, Fly, Gravity
--   left  : "Zee Hood Movements" = No Slowdown, No Jump Cooldown (below Main Movements)
--   right : "Extra Movements" = Tickrate, Bunny Hop, No Clip, Spider Man, Float
-- Every row of a group has the feature name, a switch and three dots.
-- The dots open ONE shared pop-up with:
--   Keybind : click it, then press a key (Escape or Backspace clears it)
--   Mode    : Always = on the moment the switch is on, no key needed
--             Toggle = the keybind turns it on / off
--             Hold   = on only while the keybind is held down
--   Type    : Walk Speed only (Velocity / Position / Slippery)
--   sliders : the values of that feature (No Clip, Inf Jump and Spider Man have none)
--   a short description of what the feature does
-- Every switch is OFF each time the script starts. Turning a feature off (or unloading) puts back
-- what it changed.
--
-- Features:
--   Walk Speed   Velocity  = pushes your horizontal velocity to the speed (does not touch WalkSpeed,
--                            so a game that resets WalkSpeed cannot stop it)
--                Position  = moves your position a little every frame (works even when velocity is ignored)
--                Slippery  = velocity with momentum: you speed up and slow down slowly, like on ice
--                            (the Slide slider: more = more sliding)
--   Fly          Fly where the camera looks (W A S D, Space = up, Left Ctrl or Q = down)
--   Jump Power   Sets your jump power AND adds the jump speed itself on every jump, so it still works
--                when the game keeps resetting Humanoid.JumpPower
--   Gravity      A force on your character (mass x (196.2 - wanted gravity)) instead of Workspace.Gravity,
--                so the change is big and the game cannot just set it back
--   Tickrate     Your client FPS cap (setfpscap, or setfflag as a fallback). The popup shows the FPS it
--                measures so you can see if it worked. The server tick rate cannot be changed from a client.
--   Bunny Hop    Hold Space: you jump the moment you land and gain speed on every hop (Gain) up to the
--                Max Speed. Steer in the air with W A S D.
--   No Clip      Walk through walls
--   Inf Jump     Press Space in the air: a REAL jump (sets your upward speed to the jump speed)
--   Spider Man   Walk into a wall and you climb it
--   Float        Changes your hip height so you hover above the ground
--   No Slowdown  ZEE HOOD ONLY. Removes the slowdown from crouching, reloading, shooting and melee:
--                it clears the slow effects the game puts in BodyEffects.Movement (NoWalkSpeed, ReduceWalk,
--                ...) and gives your walk speed back. (Names taken from Da Hood scripts - Zee Hood is built
--                the same way, but if it names things differently only the walk speed part works.)
--   No Jump Cooldown  ZEE HOOD ONLY. Removes the jump cooldown / jump limit: clears BodyEffects.Movement.NoJumping,
--                keeps the Jumping state on and puts JumpPower back the moment the game lowers it (and blocks
--                the game's write with a hook when your executor has hookmetamethod).
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
	local WALK_TYPES = { "Velocity", "Position", "Slippery" }

	---------------------------------------------------------------------
	-- the features
	---------------------------------------------------------------------
	local function capNote()
		if type(setfpscap) ~= "function" and type(setfflag) ~= "function" then
			return "Your executor has no setfpscap / setfflag, so this does nothing."
		end
		return nil
	end

	local DEFS = {
		{ id = "walkspeed", title = "Walk Speed", types = WALK_TYPES,
			desc = "Velocity pushes you at that speed. Position moves your position every frame. Slippery is velocity with momentum, so you slide like on ice (more Slide = more sliding).",
			sliders = {
				{ key = "speed", name = "Speed", min = 16, max = 250, step = 1, value = 50, fmt = "%d" },
				{ key = "slide", name = "Slide", min = 1, max = 10, step = 1, value = 4, fmt = "%d",
					show = function(f) return f.type == "Slippery" end },
			} },
		{ id = "fly", title = "Fly",
			desc = "Fly where the camera looks. W A S D to move, Space = up, Left Ctrl or Q = down.",
			sliders = { { key = "speed", name = "Speed", min = 10, max = 300, step = 5, value = 60, fmt = "%d" } } },
		{ id = "jumppower", title = "Jump Power",
			desc = "Sets how high you jump. It also adds the jump speed on every jump, so it works even when the game keeps resetting JumpPower.",
			sliders = { { key = "power", name = "Power", min = 20, max = 500, step = 5, value = 100, fmt = "%d" } } },
		{ id = "gravity", title = "Gravity",
			desc = "The normal gravity is 196. Lower = floaty, higher = heavy. Done with a force on your character, so the change is big and the game cannot just set it back.",
			sliders = { { key = "grav", name = "Gravity", min = 0, max = 400, step = 1, value = 60, fmt = "%d" } } },
		{ id = "tickrate", title = "Tickrate",
			desc = "Sets your client FPS cap (more updates per second from your side). The server's own tick rate cannot be changed from a client.",
			note = capNote,
			sliders = { { key = "rate", name = "Rate", min = 15, max = 360, step = 5, value = 144, fmt = "%d" } } },
		{ id = "bhop", title = "Bunny Hop",
			desc = "Hold Space: you jump the moment you land and gain speed on every hop (Gain) up to Max Speed. Steer in the air with W A S D.",
			sliders = {
				{ key = "speed", name = "Max Speed", min = 16, max = 150, step = 1, value = 60, fmt = "%d" },
				{ key = "gain", name = "Gain", min = 0, max = 10, step = 1, value = 3, fmt = "%d" },
			} },
		{ id = "noclip", title = "No Clip",
			desc = "Walk through walls." },
		{ id = "infjump", title = "Inf Jump",
			desc = "Press Space in the air for a real extra jump (your upward speed is set to the jump speed)." },
		{ id = "spider", title = "Spider Man",
			desc = "Walk into a wall and you climb it." },
		{ id = "float", title = "Float",
			desc = "Raises your hip height so you hover above the ground.",
			sliders = { { key = "height", name = "Height", min = 0, max = 30, step = 0.5, value = 6, fmt = "%.1f" } } },
		{ id = "noslow", title = "No Slowdown", zee = true,
			desc = "Removes the slowdown from crouching, reloading, shooting and melee. Speed = the walk speed you get back.",
			sliders = { { key = "speed", name = "Speed", min = 8, max = 60, step = 1, value = 16, fmt = "%d" } } },
		{ id = "nojumpcd", title = "No Jump Cooldown", zee = true,
			desc = "Removes the jump cooldown / jump limit, so you can jump as often as normal. Power = your normal jump power.",
			sliders = { { key = "power", name = "Power", min = 20, max = 150, step = 1, value = 50, fmt = "%d" } } },
	}

	local F = {}   -- feature state by id
	for i = 1, #DEFS do
		local d = DEFS[i]
		local vals = {}
		if d.sliders then
			for k = 1, #d.sliders do
				vals[d.sliders[k].key] = d.sliders[k].value
			end
		end
		local t = nil
		if d.types then
			t = d.types[1]
		end
		F[d.id] = {
			def = d,
			enabled = false,
			mode = "Always",
			key = nil,
			v = vals,
			type = t,
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

	---------------------------------------------------------------------
	-- root, scrolling page and pop-up helpers
	---------------------------------------------------------------------
	local root = new("Frame", {
		Name = "MovementRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	local scroll = new("ScrollingFrame", {
		Name = "MovementScroll",
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

	local body = new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -12, 0, 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, scroll)

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

	-- next to the anchor (right of it, left when there is no room), kept inside the page
	local function placeNear(anchor, w, h)
		local s = uiScale()
		local rw = root.AbsoluteSize.X / s
		local rh = root.AbsoluteSize.Y / s
		local ax, ay, aw = rectIn(anchor)
		local x = ax + aw + 8
		local y = ay
		if x + w > rw - 4 then
			x = ax - 8 - w
		end
		x = math.clamp(x, 4, math.max(4, rw - w - 4))
		y = math.clamp(y, 4, math.max(4, rh - h - 4))
		return UDim2.fromOffset(math.floor(x), math.floor(y))
	end

	-- right under the anchor (above it when there is no room), right edges lined up
	local function placeBelow(anchor, w, h)
		local s = uiScale()
		local rw = root.AbsoluteSize.X / s
		local rh = root.AbsoluteSize.Y / s
		local ax, ay, aw, ah = rectIn(anchor)
		local x = ax + aw - w
		local y = ay + ah + 4
		if y + h > rh - 4 then
			y = ay - h - 4
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
	-- cards (two columns, the page scrolls)
	---------------------------------------------------------------------
	local ROW_STEP = 74
	local CARD_TOP = 22
	local refreshSub = nil
	local openFor = nil
	local closePop = nil
	local cur = nil   -- the feature the pop-up is showing

	-- three connected backgrounds: every group is ONE card with a row per feature
	local ROW_H = 46
	local GROUPS = {
		{ title = "Main Movements", col = 0, ids = { "walkspeed", "jumppower", "infjump", "fly", "gravity" } },
		{ title = "Zee Hood Movements", col = 0, ids = { "noslow", "nojumpcd" } },
		{ title = "Extra Movements", col = 1, ids = { "tickrate", "bhop", "noclip", "spider", "float" } },
	}
	local colY = { [0] = CARD_TOP, [1] = CARD_TOP }
	local bodyBottom = 0

	for gi = 1, #GROUPS do
		local g = GROUPS[gi]
		local gy = colY[g.col]
		local gh = #g.ids * ROW_H
		local gpos = UDim2.new(0, 2, 0, gy)
		local capPos = UDim2.new(0, 4, 0, gy - 18)
		if g.col == 1 then
			gpos = UDim2.new(0.5, 4, 0, gy)
			capPos = UDim2.new(0.5, 6, 0, gy - 18)
		end

		local group = new("Frame", {
			Name = "Group" .. gi,
			Position = gpos,
			Size = UDim2.new(0.5, -6, 0, gh),
			BackgroundColor3 = T.SIDEBAR_BG,
			BorderSizePixel = 0,
		}, body)
		corner(group, RADIUS + 4)
		stroke(group, T.BORDER, 1, 0)

		label(body, g.title, capPos, UDim2.new(0.5, -10, 0, 14),
			Enum.Font.GothamMedium, 11, T.DIM_TEXT)

		for k = 1, #g.ids do
			local f = F[g.ids[k]]
			local d = f.def

			local row = new("Frame", {
				Name = d.id .. "Row",
				Position = UDim2.fromOffset(0, (k - 1) * ROW_H),
				Size = UDim2.new(1, 0, 0, ROW_H),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, group)

			-- thin divider between the rows of a group
			if k > 1 then
				new("Frame", {
					Position = UDim2.fromOffset(12, 0),
					Size = UDim2.new(1, -24, 0, 1),
					BackgroundColor3 = T.BORDER,
					BorderSizePixel = 0,
				}, row)
			end

			label(row, d.title, UDim2.fromOffset(14, 7), UDim2.new(1, -110, 0, 16),
				Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
			f.sub = label(row, "", UDim2.fromOffset(14, 25), UDim2.new(1, -100, 0, 14),
				Enum.Font.Gotham, 11, T.DIM_TEXT)
			f.sub.RichText = true

			makeSwitch(row, false, function(on)
				f.enabled = on
				f.toggled = false
				f.held = false
				refreshSub(f)
			end, 23)

			f.dots = makeDots(row, UDim2.new(1, -58, 0, 23))
			f.dots.btn.Activated:Connect(function()
				if cur == f and closePop then
					closePop()
					return
				end
				openFor(f)
			end)
		end

		colY[g.col] = gy + gh + 30   -- the next group in this column (room for its title)
		bodyBottom = math.max(bodyBottom, gy + gh)
	end

	body.Size = UDim2.new(1, -12, 0, bodyBottom)
	scroll.CanvasSize = UDim2.new(0, 0, 0, bodyBottom + 12)

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
		if f.def.zee then
			f.sub.Text = '<font color="rgb(230,230,234)"><b>Zee Hood only</b></font> - ' .. state
			return
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
	local P = makeFloating("MovementSettings", PW, 200)
	local pop = P.frame
	local listening = nil   -- the feature waiting for a key
	local layoutPop = nil
	local closeChoices = nil
	local slipVel = nil     -- (declared early: the Type row resets it)
	local fpsValue = 0      -- (declared early: the Tickrate pop-up shows it)

	local popTitle = label(pop, "", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)
	new("Frame", {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, pop)

	local function newRow(h)
		return new("Frame", {
			Size = UDim2.new(1, 0, 0, h),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
		}, pop)
	end

	-- keybind row
	local keyRow = newRow(28)
	label(keyRow, "Keybind", UDim2.fromOffset(16, 0), UDim2.fromOffset(100, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local keyBtn = new("TextButton", {
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 0),
		Size = UDim2.fromOffset(112, 28),
		BackgroundColor3 = T.CLUSTER_BG,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = T.ICON_HOVER,
		Text = "None",
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, keyRow)
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

	-- a row with a title and a drop-down button (used for Mode and Type)
	local choiceRows = {}
	local OPT_H = 26

	local function makeChoiceRow(title, options, getValue, setValue)
		local R = {}
		R.row = newRow(28)
		label(R.row, title, UDim2.fromOffset(16, 0), UDim2.fromOffset(100, 28),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)

		local btn = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 0),
			Size = UDim2.fromOffset(112, 28),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, R.row)
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
		R.list = makeFloating(title .. "List", listW, listH)
		R.list.frame.ZIndex = 70
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

		function R.refresh()
			valLbl.Text = tostring(getValue())
			paintOptions()
		end

		function R.close()
			if R.list.isOpen() then
				R.list.close()
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
			}, R.list.frame)
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
			if R.list.isOpen() then
				R.close()
				return
			end
			closeChoices()
			R.refresh()
			R.list.open(placeBelow(btn, listW, listH))
			isOpen = true
			paintArrow()
		end)

		popupList[#popupList + 1] = {
			isOpen = function()
				return R.list.isOpen()
			end,
			close = R.close,
			hit = { R.list.frame, btn },
		}
		choiceRows[#choiceRows + 1] = R
		return R
	end

	closeChoices = function()
		for i = 1, #choiceRows do
			choiceRows[i].close()
		end
	end

	local modeRow = makeChoiceRow("Mode", MODES,
		function()
			if cur then
				return cur.mode
			end
			return "Always"
		end,
		function(v)
			if cur then
				cur.mode = v
				cur.toggled = false
				cur.held = false
				refreshSub(cur)
			end
		end)

	local typeRow = makeChoiceRow("Type", WALK_TYPES,
		function()
			if cur and cur.type then
				return cur.type
			end
			return WALK_TYPES[1]
		end,
		function(v)
			if cur then
				cur.type = v
				slipVel = nil
				layoutPop(cur)
			end
		end)

	-- slider rows (up to two per feature)
	local function makeSliderRow()
		local R = { f = nil, sl = nil }
		R.row = newRow(24)
		local nameLbl = label(R.row, "", UDim2.fromOffset(16, 2), UDim2.fromOffset(64, 20),
			Enum.Font.GothamMedium, 12, T.ICON)
		local valLbl = label(R.row, "", UDim2.new(1, -60, 0, 2), UDim2.fromOffset(46, 20),
			Enum.Font.GothamMedium, 12, T.TEXT_COLOR, Enum.TextXAlignment.Right)
		local SX0 = 16 + 64 + 6
		local track = new("Frame", {
			Position = UDim2.fromOffset(SX0, 9),
			Size = UDim2.new(1, -(SX0 + 68), 0, 6),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, R.row)
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
			Position = UDim2.fromOffset(SX0, 2),
			Size = UDim2.new(1, -(SX0 + 68), 0, 20),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, R.row)

		local dragging = false

		local function refresh()
			if not R.f or not R.sl then
				return
			end
			local sl = R.sl
			local v = R.f.v[sl.key]
			local fr = (v - sl.min) / (sl.max - sl.min)
			fill.Size = UDim2.new(fr, 0, 1, 0)
			knob.Position = UDim2.new(fr, 0, 0.5, 0)
			valLbl.Text = string.format(sl.fmt, v)
		end

		local function setFromX(px)
			if not R.f or not R.sl then
				return
			end
			local sl = R.sl
			local w = hit.AbsoluteSize.X
			if w <= 0 then
				return
			end
			local fr = math.clamp((px - hit.AbsolutePosition.X) / w, 0, 1)
			local v = sl.min + math.floor(fr * (sl.max - sl.min) / sl.step + 0.5) * sl.step
			R.f.v[sl.key] = math.clamp(v, sl.min, sl.max)
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

		function R.bind(f, sl)
			R.f = f
			R.sl = sl
			nameLbl.Text = sl.name
			refresh()
		end
		function R.stop()
			dragging = false
		end
		return R
	end

	local sliderRows = { makeSliderRow(), makeSliderRow() }

	-- info labels at the bottom of the pop-up
	local fpsLbl = label(pop, "", UDim2.fromOffset(16, 0), UDim2.new(1, -32, 0, 16),
		Enum.Font.GothamMedium, 12, T.TEXT_COLOR)
	fpsLbl.Visible = false
	local noteLbl = label(pop, "", UDim2.fromOffset(16, 0), UDim2.new(1, -32, 0, 14),
		Enum.Font.Gotham, 11, T.HOVER_RED)
	noteLbl.TextTruncate = Enum.TextTruncate.None
	noteLbl.TextWrapped = true
	noteLbl.Visible = false
	local descLbl = label(pop, "", UDim2.fromOffset(16, 0), UDim2.new(1, -32, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	descLbl.TextTruncate = Enum.TextTruncate.None
	descLbl.TextWrapped = true
	descLbl.TextYAlignment = Enum.TextYAlignment.Top

	-- puts the rows of the pop-up in place for this feature and returns the height of the pop-up
	layoutPop = function(f)
		local y = 50
		keyRow.Position = UDim2.fromOffset(0, y)
		keyRow.Visible = true
		y = y + 36

		modeRow.row.Position = UDim2.fromOffset(0, y)
		modeRow.row.Visible = true
		y = y + 36

		if f.def.types then
			typeRow.row.Position = UDim2.fromOffset(0, y)
			typeRow.row.Visible = true
			y = y + 36
		else
			typeRow.row.Visible = false
		end

		local list = {}
		if f.def.sliders then
			for i = 1, #f.def.sliders do
				local sl = f.def.sliders[i]
				if sl.show == nil or sl.show(f) then
					list[#list + 1] = sl
				end
			end
		end
		for i = 1, #sliderRows do
			local sr = sliderRows[i]
			if list[i] then
				sr.bind(f, list[i])
				sr.row.Position = UDim2.fromOffset(0, y)
				sr.row.Visible = true
				y = y + 30
			else
				sr.row.Visible = false
			end
		end

		y = y + 2
		fpsLbl.Visible = (f.def.id == "tickrate")
		if fpsLbl.Visible then
			fpsLbl.Text = string.format("Measured: %d fps", math.floor(fpsValue + 0.5))
			fpsLbl.Position = UDim2.fromOffset(16, y)
			y = y + 20
		end

		local note = nil
		if f.def.note then
			note = f.def.note()
		end
		if note then
			noteLbl.Text = note
			noteLbl.Size = UDim2.new(1, -32, 0, 28)
			noteLbl.Position = UDim2.fromOffset(16, y)
			noteLbl.Visible = true
			y = y + 30
		else
			noteLbl.Visible = false
		end

		descLbl.Text = f.def.desc or ""
		local lines = math.max(1, math.ceil(#descLbl.Text / 38))
		descLbl.Size = UDim2.new(1, -32, 0, lines * 14)
		descLbl.Position = UDim2.fromOffset(16, y + 2)
		y = y + lines * 14 + 16

		pop.Size = UDim2.fromOffset(PW, y)
		if P.isOpen() and f.dots then
			P.move(placeNear(f.dots.btn, PW, y))
		end
		return y
	end

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
		closeChoices()
		popTitle.Text = f.def.title
		keyBtn.Text = keyName(f)
		modeRow.refresh()
		typeRow.refresh()
		local h = layoutPop(f)

		popEntry.hit[4] = f.dots.btn
		local target = placeNear(f.dots.btn, PW, h)
		if P.isOpen() then
			P.move(target)
		else
			P.open(target)
		end
		paintAllDots()
	end

	closePop = function()
		P.close()
		closeChoices()
		listening = nil
		for i = 1, #sliderRows do
			sliderRows[i].stop()
		end
		cur = nil
		paintAllDots()
	end

	popEntry = {
		isOpen = function()
			return P.isOpen()
		end,
		close = closePop,
		hit = { pop, modeRow.list.frame, typeRow.list.frame, pop },
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

	-- the pop-up stays where it opened, so it closes when the page is scrolled
	conns[#conns + 1] = scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if P.isOpen() then
			closePop()
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
	local lastChar = nil
	local boundHum = nil
	local humConns = {}
	local origJump = nil
	local origHip = nil
	local gravAtt = nil
	local gravVF = nil
	local flyBV = nil
	local flyBG = nil
	local flyPS = nil
	local ncParts = {}
	local bhopSpeed = nil
	local bhopAir = false
	local pendingJump = false
	local lastAirJump = 0
	local origCap = nil
	local lastCap = nil
	local fpsFrames = 0
	local fpsTime = 0
	local hookOn = false
	local hookFloor = 50
	local hookInstalled = false
	local hookOld = nil
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

	-- the jump speed to use: the Jump Power slider, or what the humanoid has
	local function jumpVelocity(hum)
		if act.jumppower then
			return F.jumppower.v.power
		end
		if hum.UseJumpPower then
			if hum.JumpPower >= 1 then
				return hum.JumpPower
			end
		elseif hum.JumpHeight > 0 then
			return math.sqrt(2 * workspace.Gravity * hum.JumpHeight)
		end
		return 50
	end

	-- the lowest jump power No Jump Cooldown allows
	local function jumpFloor()
		local fl = F.nojumpcd.v.power
		if act.jumppower then
			fl = math.min(fl, F.jumppower.v.power)
		end
		return fl
	end

	-- the BodyEffects folder of this character (Zee Hood: also looked up in workspace.Players)
	local function getEffects(char)
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
		return be
	end

	-- No Slowdown: clear the slow effects and give the walk speed back
	local function clearSlow(char, hum)
		local be = getEffects(char)
		if be then
			local mv = be:FindFirstChild("Movement")
			if mv then
				local kids = mv:GetChildren()
				for i = 1, #kids do
					if kids[i].Name ~= "NoJumping" then
						pcall(function()
							kids[i]:Destroy()
						end)
					end
				end
			end
			-- knocked out players stay slow
			local ko = be:FindFirstChild("K.O")
			if ko and ko:IsA("BoolValue") and ko.Value then
				return
			end
		end
		if hum.WalkSpeed < F.noslow.v.speed then
			hum.WalkSpeed = F.noslow.v.speed
		end
	end

	-- No Jump Cooldown: clear the block and put the jump power back
	local function fixJump(char, hum)
		local be = getEffects(char)
		if be then
			local mv = be:FindFirstChild("Movement")
			if mv then
				local nj = mv:FindFirstChild("NoJumping")
				if nj then
					pcall(function()
						nj:Destroy()
					end)
				end
			end
		end
		if not hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
		local fl = jumpFloor()
		if hum.UseJumpPower then
			if hum.JumpPower < fl then
				hum.JumpPower = fl
			end
		else
			local need = (fl * fl) / (2 * workspace.Gravity)
			if hum.JumpHeight < need then
				hum.JumpHeight = need
			end
		end
	end

	-- blocks the game's own writes of a lower JumpPower (only when the executor can hook metamethods)
	local function installHook()
		if hookInstalled then
			return
		end
		hookInstalled = true
		pcall(function()
			if type(hookmetamethod) == "function" and type(newcclosure) == "function" then
				hookOld = hookmetamethod(game, "__newindex", newcclosure(function(self, key, value)
					if hookOn and key == "JumpPower" and type(value) == "number" and typeof(self) == "Instance" then
						local ours = false
						if type(checkcaller) == "function" then
							ours = checkcaller()
						end
						if not ours and value < hookFloor and self:IsA("Humanoid") then
							value = hookFloor
						end
					end
					return hookOld(self, key, value)
				end))
			end
		end)
	end

	-- both ways are tried: some executors have a setfpscap that does nothing
	local function applyCap(v)
		if type(setfpscap) == "function" then
			pcall(setfpscap, v)
		end
		if type(setfflag) == "function" then
			pcall(setfflag, "DFIntTaskSchedulerTargetFps", tostring(v))
		end
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

	local function gravStop()
		if gravVF then
			pcall(function()
				gravVF:Destroy()
			end)
			gravVF = nil
		end
		if gravAtt then
			pcall(function()
				gravAtt:Destroy()
			end)
			gravAtt = nil
		end
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

	local function resetCharState()
		origJump = nil
		origHip = nil
		flyBV = nil
		flyBG = nil
		flyPS = nil
		gravAtt = nil
		gravVF = nil
		ncParts = {}
		slipVel = nil
		bhopSpeed = nil
		bhopAir = false
		pendingJump = false
	end

	local function bindHum(hum)
		for i = 1, #humConns do
			pcall(function()
				humConns[i]:Disconnect()
			end)
		end
		humConns = {}
		humConns[#humConns + 1] = hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping and act.jumppower then
				pendingJump = true
			end
		end)
		humConns[#humConns + 1] = hum:GetPropertyChangedSignal("JumpPower"):Connect(function()
			if act.nojumpcd and hum.UseJumpPower then
				local fl = jumpFloor()
				if hum.JumpPower < fl then
					hum.JumpPower = fl
				end
			end
		end)
		humConns[#humConns + 1] = hum:GetPropertyChangedSignal("JumpHeight"):Connect(function()
			if act.nojumpcd and not hum.UseJumpPower then
				local need = (jumpFloor() ^ 2) / (2 * workspace.Gravity)
				if hum.JumpHeight < need then
					hum.JumpHeight = need
				end
			end
		end)
	end

	local function computeActive()
		local a = {}
		for i = 1, #DEFS do
			local id = DEFS[i].id
			a[id] = isActive(F[id])
		end
		act = a
		return a
	end

	-- Heartbeat: switches, forces, fly, float, jump power, tickrate, no slowdown, no jump cooldown
	local function stepHB(dt)
		local a = computeActive()

		-- measured FPS (shown in the Tickrate pop-up)
		fpsFrames = fpsFrames + 1
		fpsTime = fpsTime + dt
		if fpsTime >= 0.5 then
			fpsValue = fpsFrames / fpsTime
			fpsFrames = 0
			fpsTime = 0
			if fpsLbl.Visible then
				fpsLbl.Text = string.format("Measured: %d fps", math.floor(fpsValue + 0.5))
			end
		end

		-- tickrate (your fps cap)
		if a.tickrate then
			if origCap == nil then
				origCap = 60
				if type(getfpscap) == "function" then
					local ok, v = pcall(getfpscap)
					if ok and type(v) == "number" and v >= 0 then
						origCap = v
					end
				end
				lastCap = nil
			end
			if lastCap ~= F.tickrate.v.rate then
				lastCap = F.tickrate.v.rate
				applyCap(lastCap)
			end
		elseif origCap ~= nil then
			applyCap(origCap)
			origCap = nil
			lastCap = nil
		end

		-- jump cooldown hook
		if a.nojumpcd then
			installHook()
		end
		hookOn = a.nojumpcd
		hookFloor = jumpFloor()

		local char, hum, hrp = getChar()
		if char ~= lastChar then
			lastChar = char
			boundHum = nil
			resetCharState()
		end
		local alive = (hum ~= nil) and (hrp ~= nil) and hum.Health > 0

		if not a.noclip then
			ncRestore()
		end

		if not alive then
			flyStop(nil)
			gravStop()
			return
		end

		if hum ~= boundHum then
			boundHum = hum
			bindHum(hum)
		end

		local spaceDown = UserInputService:IsKeyDown(Enum.KeyCode.Space) or hum.Jump

		-- gravity: a force on the character that cancels the world gravity and adds the wanted one
		if a.gravity then
			if gravVF == nil or gravVF.Parent ~= hrp then
				gravStop()
				gravAtt = Instance.new("Attachment")
				gravAtt.Name = "Y1GravAtt"
				gravAtt.Parent = hrp
				gravVF = Instance.new("VectorForce")
				gravVF.Name = "Y1Grav"
				gravVF.Attachment0 = gravAtt
				gravVF.RelativeTo = Enum.ActuatorRelativeTo.World
				gravVF.ApplyAtCenterOfMass = true
				gravVF.Force = Vector3.new(0, 0, 0)
				gravVF.Parent = hrp
			end
			gravVF.Force = Vector3.new(0, hrp.AssemblyMass * (workspace.Gravity - F.gravity.v.grav), 0)
		elseif gravVF or gravAtt then
			gravStop()
		end

		-- jump power (the property; the real boost happens on every jump in stepPhys)
		if a.jumppower then
			if origJump == nil then
				origJump = { use = hum.UseJumpPower, power = hum.JumpPower }
			end
			hum.UseJumpPower = true
			hum.JumpPower = F.jumppower.v.power
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
			hum.HipHeight = F.float.v.height
		elseif origHip ~= nil then
			hum.HipHeight = origHip
			origHip = nil
		end

		-- zee hood: no slowdown / no jump cooldown
		if a.noslow then
			clearSlow(char, hum)
		end
		if a.nojumpcd then
			fixJump(char, hum)
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
				flyBV.Velocity = vel * F.fly.v.speed
				local look = cam.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude > 0.01 then
					flyBG.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
				end
			end
		elseif flyBV or flyBG then
			flyStop(hum)
		end

		-- walk speed: Velocity / Slippery are set again here (the physics step also sets them)
		if a.walkspeed and not a.fly then
			local md = hum.MoveDirection
			local t = F.walkspeed.type
			if t == "Velocity" and md.Magnitude > 0.1 then
				local vel = hrp.AssemblyLinearVelocity
				local sp = F.walkspeed.v.speed
				hrp.AssemblyLinearVelocity = Vector3.new(md.X * sp, vel.Y, md.Z * sp)
			elseif t == "Slippery" and slipVel then
				local vel = hrp.AssemblyLinearVelocity
				hrp.AssemblyLinearVelocity = Vector3.new(slipVel.X, vel.Y, slipVel.Z)
			end
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

	-- Stepped (right before physics): walk speed, bunny hop, jump boost, no clip
	local function stepPhys(dt)
		local a = act
		local char, hum, hrp = getChar()
		if not char or not hum or not hrp or hum.Health <= 0 then
			return
		end

		-- no clip: collisions are reset every physics step, so this runs here
		if a.noclip then
			local parts = char:GetDescendants()
			for i = 1, #parts do
				local p = parts[i]
				if p:IsA("BasePart") and p.CanCollide then
					ncParts[p] = true
					p.CanCollide = false
				end
			end
		end

		if a.noslow then
			clearSlow(char, hum)
		end
		if a.nojumpcd then
			fixJump(char, hum)
		end

		local md = hum.MoveDirection
		local vel = hrp.AssemblyLinearVelocity
		local spaceDown = UserInputService:IsKeyDown(Enum.KeyCode.Space) or hum.Jump
		local grounded = hum.FloorMaterial ~= Enum.Material.Air

		-- walk speed
		if a.walkspeed and not a.fly then
			local t = F.walkspeed.type
			local speed = F.walkspeed.v.speed
			if t == "Slippery" then
				if slipVel == nil then
					slipVel = Vector3.new(vel.X, 0, vel.Z)
				end
				local actual = Vector3.new(vel.X, 0, vel.Z)
				-- hit a wall: the real speed is much lower, so do not keep pushing
				if actual.Magnitude < slipVel.Magnitude * 0.5 then
					slipVel = actual
				end
				local slide = F.walkspeed.v.slide
				local target = Vector3.new(0, 0, 0)
				local rate = 10 / slide
				if md.Magnitude > 0.1 then
					target = md * speed
					rate = 12 / slide
				end
				slipVel = slipVel:Lerp(target, 1 - math.exp(-rate * dt))
				hrp.AssemblyLinearVelocity = Vector3.new(slipVel.X, vel.Y, slipVel.Z)
				vel = hrp.AssemblyLinearVelocity
			else
				slipVel = nil
				if md.Magnitude > 0.1 then
					if t == "Position" then
						local extra = math.max(0, speed - hum.WalkSpeed)
						hrp.CFrame = hrp.CFrame + md * extra * dt
					else
						hrp.AssemblyLinearVelocity = Vector3.new(md.X * speed, vel.Y, md.Z * speed)
						vel = hrp.AssemblyLinearVelocity
					end
				end
			end
		else
			slipVel = nil
		end

		-- bunny hop
		if a.bhop and not a.fly then
			if spaceDown then
				local maxSp = F.bhop.v.speed
				if bhopSpeed == nil then
					bhopSpeed = math.max(hum.WalkSpeed, 16)
				end
				if grounded then
					if bhopAir then
						bhopAir = false
						bhopSpeed = bhopSpeed + F.bhop.v.gain
					end
					hum:ChangeState(Enum.HumanoidStateType.Jumping)
				else
					bhopAir = true
				end
				if bhopSpeed > maxSp then
					bhopSpeed = maxSp
				end
				if md.Magnitude > 0.1 then
					local cv = hrp.AssemblyLinearVelocity
					local curH = Vector3.new(cv.X, 0, cv.Z)
					local target = md.Unit * bhopSpeed
					local newH = curH:Lerp(target, 1 - math.exp(-10 * dt))
					hrp.AssemblyLinearVelocity = Vector3.new(newH.X, cv.Y, newH.Z)
				end
			else
				bhopSpeed = nil
				bhopAir = false
			end
		else
			bhopSpeed = nil
			bhopAir = false
		end

		-- jump power: add the jump speed itself right after a jump started
		if pendingJump then
			pendingJump = false
			if a.jumppower then
				local cv = hrp.AssemblyLinearVelocity
				hrp.AssemblyLinearVelocity = Vector3.new(cv.X, F.jumppower.v.power, cv.Z)
			end
		end
	end

	conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
		if running then
			pcall(stepHB, dt)
		end
	end)

	conns[#conns + 1] = RunService.Stepped:Connect(function(_, dt)
		if running then
			pcall(stepPhys, dt)
		end
	end)

	-- inf jump: a REAL jump in mid air (the humanoid jumps and your upward speed is set to the jump speed)
	conns[#conns + 1] = UserInputService.JumpRequest:Connect(function()
		if not running or not act.infjump then
			return
		end
		local now = os.clock()
		if now - lastAirJump < 0.12 then
			return
		end
		local _, hum, hrp = getChar()
		if not hum or not hrp or hum.Health <= 0 then
			return
		end
		if hum.FloorMaterial ~= Enum.Material.Air then
			return
		end
		lastAirJump = now
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		local vel = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(vel.X, jumpVelocity(hum), vel.Z)
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
		pcall(stepHB, 0.016)
		hookOn = false
		running = false
		for i = 1, #humConns do
			pcall(function()
				humConns[i]:Disconnect()
			end)
		end
		humConns = {}
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
