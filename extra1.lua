-- extra1.lua  (Auto Buy page: Armor / Stim / Food)
-- ASCII only, conservative syntax (no += and no continue).
--
-- One small card with three rows. Each row has a switch (OFF every time the script starts)
-- and a Range slider (how close you have to be to the item, in studs).
--
-- Shop path: workspace.Ignored.Shop  (a folder full of models, each with a part called Head)
--   Auto Buy Armor = every model whose name starts with "[Full Armor]"   (ex: "[Full Armor] - $3639")
--   Auto Buy Stim  = every model whose name starts with "[Stim]"         (ex: "[Stim] - $67")
--   Auto Buy Food  = every OTHER model in the Shop folder
-- There can be many of each, so every model is checked, not just one.
--
-- Buying = a left click on the model's Head, done with fireclickdetector (needs an executor that has it).
-- Each model can only be bought once every COOLDOWN seconds so it does not spam.
--
-- HITBOX EXPANDER (second card under Auto Buy, Zee Hood)
--   Makes every other player's HumanoidRootPart bigger on YOUR client so bullets / raycasts hit
--   more easily. It resizes the REAL part (an extra fake part would be thrown away by the server) and
--   never uses Massless. CanCollide is forced off before every physics step. Turning it off restores
--   every part exactly as it was.
--   Enable + three dots. The pop-up has: Visualize, Team Check, Knocked Check (K.O bool at
--   workspace.Players.<name>.BodyEffects["K.O"]), Size (slider 2-50 + typed box 1-100) and Dynamic
--   (smaller hitbox when they are close: Min Size and Full At sliders).
--
-- Build signature: Extra1.build(container, T, H, ctx) -> { Root = ..., Unload = fn }

local Extra1Page = {}

function Extra1Page.build(parent, T, H, ctx)
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local RunService = game:GetService("RunService")
	local player = Players.LocalPlayer

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH
	local RADIUS = T.RADIUS

	local ARMOR_TAG = "[Full Armor]"
	local STIM_TAG = "[Stim]"
	local COOLDOWN = 0       -- 0 = click every frame (fastest). Raise it (like 0.1) if purchases get ignored.
	local ARMOR_LIMIT = 150  -- Auto Buy Armor stops while your armor is at or above this

	local OPTIONS = {
		{ key = "armor", title = "Auto Buy Armor" },
		{ key = "stim", title = "Auto Buy Stim" },
		{ key = "food", title = "Auto Buy Food" },
	}

	local S = {
		armor = { enabled = false, range = 12 },
		stim = { enabled = false, range = 12 },
		food = { enabled = false, range = 12 },
	}

	local running = true
	local conns = {}
	local lastBuy = setmetatable({}, { __mode = "k" })

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
			local f = math.clamp((value - minV) / (maxV - minV), 0, 1)
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
		function api.set(v)
			value = v
			refresh()
		end
		function api.dim(enabled)
			local colr = T.DIM_TEXT
			if enabled then
				colr = T.ICON_HOVER
			end
			TweenService:Create(fill, FAST, { BackgroundColor3 = colr }):Play()
		end
		return api
	end

	---------------------------------------------------------------------
	-- page
	---------------------------------------------------------------------
	local root = new("Frame", {
		Name = "Extra1Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	local page = new("ScrollingFrame", {
		Name = "Extra1Page",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.DIM_TEXT,
		CanvasSize = UDim2.fromOffset(0, 400),
	}, root)

	label(page, "AUTO BUY", UDim2.fromOffset(4, 6), UDim2.new(1, -10, 0, 14),
		Enum.Font.GothamMedium, 11, T.DIM_TEXT)

	local ROW_H = 60
	local CARD_H = 6 + #OPTIONS * ROW_H

	local card = new("Frame", {
		Name = "AutoBuyCard",
		Position = UDim2.fromOffset(2, 24),
		Size = UDim2.new(1, -6, 0, CARD_H),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
	}, page)
	corner(card, RADIUS + 4)
	stroke(card, T.BORDER, 1, 0)

	for i = 1, #OPTIONS do
		local opt = OPTIONS[i]
		local st = S[opt.key]
		local y = 6 + (i - 1) * ROW_H

		label(card, opt.title, UDim2.fromOffset(14, y + 6), UDim2.new(1, -90, 0, 18),
			Enum.Font.GothamMedium, 13, T.TEXT_COLOR)

		makeSwitch(card, st.enabled, function(on)
			st.enabled = on
		end, y + 16, 14)

		makeSlider(card, y + 32, "Range", 44, 3, 15, 1, st.range, "%d", function(v)
			st.range = v
		end)

		if i < #OPTIONS then
			new("Frame", {
				Position = UDim2.fromOffset(14, y + ROW_H - 2),
				Size = UDim2.new(1, -28, 0, 1),
				BackgroundColor3 = T.BORDER,
				BorderSizePixel = 0,
			}, card)
		end
	end

	local hasClick = false
	pcall(function()
		hasClick = (type(fireclickdetector) == "function")
	end)
	if not hasClick then
		label(page, "Your executor has no fireclickdetector, so buying will not work.",
			UDim2.fromOffset(4, 24 + CARD_H + 8), UDim2.new(1, -10, 0, 16),
			Enum.Font.Gotham, 11, T.DIM_TEXT)
	end

	---------------------------------------------------------------------
	-- the buying
	---------------------------------------------------------------------
	local function kindOf(name)
		if string.sub(name, 1, #ARMOR_TAG) == ARMOR_TAG then
			return "armor"
		end
		if string.sub(name, 1, #STIM_TAG) == STIM_TAG then
			return "stim"
		end
		return "food"
	end

	-- left click on the model's Head
	local function clickHead(model, head)
		local cd = head:FindFirstChildOfClass("ClickDetector")
		if not cd then
			cd = model:FindFirstChildWhichIsA("ClickDetector", true)
		end
		if not cd then
			return
		end
		pcall(function()
			fireclickdetector(cd)
		end)
	end

	-- your armor: workspace.Players.<your name>.BodyEffects.Armor (falls back to your character)
	local function armorValue()
		local me = nil
		local folder = workspace:FindFirstChild("Players")
		if folder then
			me = folder:FindFirstChild(player.Name)
		end
		if not me then
			me = player.Character
		end
		local be = nil
		if me then
			be = me:FindFirstChild("BodyEffects")
		end
		local armor = nil
		if be then
			armor = be:FindFirstChild("Armor")
		end
		if armor and type(armor.Value) == "number" then
			return armor.Value
		end
		return 0
	end

	local function step()
		if not (S.armor.enabled or S.stim.enabled or S.food.enabled) then
			return
		end
		local char = player.Character
		if not char then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or hum.Health <= 0 then
			return
		end

		local ignored = workspace:FindFirstChild("Ignored")
		local shop = nil
		if ignored then
			shop = ignored:FindFirstChild("Shop")
		end
		if not shop then
			return
		end

		-- armor buying pauses while your armor is at or above the limit (starts again when it drops)
		local armorFull = false
		if S.armor.enabled and armorValue() >= ARMOR_LIMIT then
			armorFull = true
		end

		local now = os.clock()
		local kids = shop:GetChildren()
		for i = 1, #kids do
			local model = kids[i]
			if model:IsA("Model") then
				local kind = kindOf(model.Name)
				local st = S[kind]
				if st.enabled and not (kind == "armor" and armorFull) then
					local head = model:FindFirstChild("Head")
					if head and head:IsA("BasePart") then
						local last = lastBuy[model]
						if (not last or now - last >= COOLDOWN)
							and (head.Position - hrp.Position).Magnitude <= st.range then
							lastBuy[model] = now
							clickHead(model, head)
						end
					end
				end
			end
		end
	end

	-- checked every frame so it reacts the moment you are in range
	conns[#conns + 1] = game:GetService("RunService").Heartbeat:Connect(function()
		if running then
			pcall(step)
		end
	end)

	---------------------------------------------------------------------
	-- HITBOX EXPANDER
	---------------------------------------------------------------------
	local HB = {
		enabled = false,
		visualize = false,
		teamCheck = false,
		knockedCheck = false,
		dynamic = false,
		dynMin = 2,
		dynFar = 60,
		size = 8,
	}
	local DYN_NEAR = 4
	local FILL_COLOR = Color3.fromRGB(120, 200, 255)
	local FILL_ALPHA = 0.86
	local LINE_COLOR = Color3.fromRGB(165, 220, 255)
	local DASHES = 8
	local DASH_FILL = 0.55

	local records = {}   -- [player] = { part, size, transparency, canCollide, box, wire }
	local activeCount = 0

	local function teamSkip(p)
		if not HB.teamCheck then
			return false
		end
		if p.Team ~= nil and player.Team ~= nil and p.Team == player.Team then
			return true
		end
		return false
	end

	-- Zee Hood: the K.O bool lives at <character>.BodyEffects["K.O"] (characters are in workspace.Players)
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

	local function sizeFor(d)
		local sz = HB.size
		if not HB.dynamic then
			return sz
		end
		local lo = math.min(HB.dynMin, sz)
		local far = math.max(HB.dynFar, DYN_NEAR + 1)
		local v = sz
		if d >= far then
			v = sz
		elseif d <= DYN_NEAR then
			v = lo
		else
			v = lo + (sz - lo) * (d - DYN_NEAR) / (far - DYN_NEAR)
		end
		return math.floor(v * 10 + 0.5) / 10
	end

	local function killVisual(r)
		if r.box then
			pcall(function()
				r.box:Destroy()
			end)
			r.box = nil
		end
		if r.wire then
			pcall(function()
				r.wire:Destroy()
			end)
			r.wire = nil
		end
	end

	local function release(p)
		local r = records[p]
		if not r then
			return
		end
		records[p] = nil
		killVisual(r)
		local part = r.part
		if part and part.Parent then
			pcall(function()
				part.Size = r.size
				part.Transparency = r.transparency
				part.CanCollide = r.canCollide
			end)
		end
	end

	local function releaseAll()
		local list = {}
		for p, _ in pairs(records) do
			list[#list + 1] = p
		end
		for i = 1, #list do
			release(list[i])
		end
	end

	local function buildDashes(wire, size)
		wire:Clear()
		local h = size / 2
		local period = size / DASHES
		local dash = period * DASH_FILL
		for axis = 1, 3 do
			for sa = -1, 1, 2 do
				for sb = -1, 1, 2 do
					for i = 0, DASHES - 1 do
						local t0 = -h + i * period
						local t1 = t0 + dash
						local a = nil
						local b = nil
						if axis == 1 then
							a = Vector3.new(t0, sa * h, sb * h)
							b = Vector3.new(t1, sa * h, sb * h)
						elseif axis == 2 then
							a = Vector3.new(sa * h, t0, sb * h)
							b = Vector3.new(sa * h, t1, sb * h)
						else
							a = Vector3.new(sa * h, sb * h, t0)
							b = Vector3.new(sa * h, sb * h, t1)
						end
						wire:AddLine(a, b)
					end
				end
			end
		end
	end

	local function makeVisual(r, part, want, sz)
		local box = Instance.new("BoxHandleAdornment")
		box.Name = "HitboxFill"
		box.Adornee = part
		box.AlwaysOnTop = true
		box.ZIndex = 1
		box.Color3 = FILL_COLOR
		box.Transparency = FILL_ALPHA
		box.Size = want
		box.Parent = part
		r.box = box

		local wire = Instance.new("WireframeHandleAdornment")
		wire.Name = "HitboxDashes"
		wire.Adornee = part
		wire.AlwaysOnTop = true
		wire.ZIndex = 2
		wire.Color3 = LINE_COLOR
		wire.Transparency = 0
		wire.Parent = part
		r.wire = wire

		-- dashes are built once at size 1 and scaled (cheap); without Scale they are redrawn at real size
		local okScale = pcall(function()
			wire.Scale = Vector3.new(sz, sz, sz)
		end)
		r.scaleOK = okScale
		if okScale then
			buildDashes(wire, 1)
		else
			buildDashes(wire, sz)
			r.dashSize = sz
			r.dashTime = os.clock()
		end
	end

	local function applyHitbox(p, origin)
		local char = p.Character
		local part = nil
		local hum = nil
		if char then
			part = char:FindFirstChild("HumanoidRootPart")
			hum = char:FindFirstChildOfClass("Humanoid")
		end
		if not part or not part:IsA("BasePart") or not hum or hum.Health <= 0 or teamSkip(p)
			or (HB.knockedCheck and isKnocked(char)) then
			release(p)
			return
		end

		local r = records[p]
		if r and r.part ~= part then
			release(p)
			r = nil
		end
		if not r then
			r = {
				part = part,
				size = part.Size,
				transparency = part.Transparency,
				canCollide = part.CanCollide,
			}
			records[p] = r
		end

		local sz = sizeFor((part.Position - origin).Magnitude)
		local want = Vector3.new(sz, sz, sz)
		if (part.Size - want).Magnitude > 0.05 then
			part.Size = want
		end
		if part.CanCollide then
			part.CanCollide = false
		end

		if HB.visualize then
			if not r.box or r.box.Parent ~= part or not r.wire or r.wire.Parent ~= part then
				killVisual(r)
				makeVisual(r, part, want, sz)
			else
				if (r.box.Size - want).Magnitude > 0.05 then
					r.box.Size = want
				end
				if r.scaleOK then
					local sc = r.wire.Scale
					if math.abs(sc.X - sz) > 0.01 then
						r.wire.Scale = Vector3.new(sz, sz, sz)
					end
				elseif r.dashSize ~= sz and os.clock() - (r.dashTime or 0) > 0.1 then
					r.dashSize = sz
					r.dashTime = os.clock()
					buildDashes(r.wire, sz)
				end
			end
		else
			killVisual(r)
		end
	end

	-- the game turns CanCollide back on during physics, so it is switched off again before every step
	local function noCollide()
		for _, r in pairs(records) do
			local part = r.part
			if part and part.Parent and part.CanCollide then
				part.CanCollide = false
			end
		end
	end

	conns[#conns + 1] = RunService.Heartbeat:Connect(function()
		if not running then
			return
		end
		if not HB.enabled then
			if next(records) ~= nil then
				releaseAll()
			end
			activeCount = 0
			return
		end
		local mine = player.Character
		local mroot = nil
		if mine then
			mroot = mine:FindFirstChild("HumanoidRootPart")
		end
		local cam = workspace.CurrentCamera
		local origin = Vector3.new(0, 0, 0)
		if mroot then
			origin = mroot.Position
		elseif cam then
			origin = cam.CFrame.Position
		end
		local list = Players:GetPlayers()
		for i = 1, #list do
			local p = list[i]
			if p ~= player then
				pcall(applyHitbox, p, origin)
			end
		end
		local n = 0
		for _, _ in pairs(records) do
			n = n + 1
		end
		activeCount = n
	end)

	conns[#conns + 1] = RunService.Stepped:Connect(function()
		if running and HB.enabled then
			noCollide()
		end
	end)

	conns[#conns + 1] = RunService.RenderStepped:Connect(function()
		if running and HB.enabled then
			noCollide()
		end
	end)

	conns[#conns + 1] = Players.PlayerRemoving:Connect(function(p)
		release(p)
	end)

	local function hitboxUnload()
		HB.enabled = false
		releaseAll()
	end

	---------------------------------------------------------------------
	-- HITBOX CARD + POP-UP
	---------------------------------------------------------------------
	local hbLabelY = 24 + CARD_H + 30
	local hbCardY = hbLabelY + 18
	page.CanvasSize = UDim2.fromOffset(0, hbCardY + 46 + 10)

	local hbCard = new("Frame", {
		Name = "HitboxCard",
		Position = UDim2.fromOffset(2, hbCardY),
		Size = UDim2.new(1, -6, 0, 46),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
	}, page)
	corner(hbCard, RADIUS + 4)
	stroke(hbCard, T.BORDER, 1, 0)

	label(page, "HITBOX EXPANDER", UDim2.fromOffset(4, hbLabelY), UDim2.new(1, -10, 0, 14),
		Enum.Font.GothamMedium, 11, T.DIM_TEXT)

	label(hbCard, "Enable", UDim2.fromOffset(14, 7), UDim2.new(1, -140, 0, 16),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local hbSub = label(hbCard, "", UDim2.fromOffset(14, 25), UDim2.new(1, -110, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	hbSub.RichText = true

	local function refreshHbStatus()
		local state = '<font color="rgb(116,116,124)">Off</font>'
		if HB.enabled then
			state = '<font color="rgb(52,199,120)">Active</font>'
		end
		hbSub.Text = '<font color="rgb(230,230,234)"><b>Zee Hood</b></font> - ' .. state
	end
	refreshHbStatus()

	makeSwitch(hbCard, HB.enabled, function(on)
		HB.enabled = on
		refreshHbStatus()
	end, 23)

	-- three dots
	local dotsOpen = false
	local dotsOver = false
	local dotsParts = {}
	local hbDots = new("TextButton", {
		Name = "MoreButton",
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -58, 0, 23),
		Size = UDim2.fromOffset(32, 26),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, hbCard)
	for i = 1, 3 do
		local d = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, (i - 2) * 7, 0.5, 0),
			Size = UDim2.fromOffset(4, 4),
			BackgroundColor3 = T.ICON,
			BorderSizePixel = 0,
		}, hbDots)
		corner(d, 100)
		dotsParts[i] = d
	end
	local function paintDots()
		local colr = T.ICON
		if dotsOpen or dotsOver then
			colr = T.ICON_HOVER
		end
		for i = 1, #dotsParts do
			TweenService:Create(dotsParts[i], FAST, { BackgroundColor3 = colr }):Play()
		end
	end
	hbDots.MouseEnter:Connect(function()
		dotsOver = true
		paintDots()
	end)
	hbDots.MouseLeave:Connect(function()
		dotsOver = false
		paintDots()
	end)

	-- pop-up (a child of root so it is never cut off by the scrolling page)
	local HBW = 290
	local HBH = 330
	local hbOpen = false
	local hbToken = 0
	local hbPop = new("CanvasGroup", {
		Name = "HitboxSettings",
		Size = UDim2.fromOffset(HBW, HBH),
		BackgroundColor3 = T.POPUP_BG,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 60,
	}, root)
	corner(hbPop, RADIUS + 4)
	stroke(hbPop, T.BORDER, 1, 0)

	label(hbPop, "Hitbox Expander", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)
	new("Frame", {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, hbPop)

	label(hbPop, "Visualize", UDim2.fromOffset(16, 50), UDim2.new(1, -90, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	makeSwitch(hbPop, HB.visualize, function(on)
		HB.visualize = on
	end, 64, 16)

	label(hbPop, "Team Check", UDim2.fromOffset(16, 84), UDim2.new(1, -90, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	makeSwitch(hbPop, HB.teamCheck, function(on)
		HB.teamCheck = on
	end, 98, 16)

	label(hbPop, "Knocked Check", UDim2.fromOffset(16, 118), UDim2.new(1, -90, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	makeSwitch(hbPop, HB.knockedCheck, function(on)
		HB.knockedCheck = on
	end, 132, 16)

	local sizeBox = nil
	local sizeApi = makeSlider(hbPop, 156, "Size", 64, 2, 50, 1, HB.size, "%d", function(v)
		HB.size = v
		if sizeBox then
			sizeBox.Text = tostring(v)
		end
	end)

	label(hbPop, "Exact Size", UDim2.fromOffset(16, 184), UDim2.new(1, -110, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local sizeBoxFrame = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 187),
		Size = UDim2.fromOffset(64, 22),
		BackgroundColor3 = T.CLUSTER_BG,
		BorderSizePixel = 0,
	}, hbPop)
	corner(sizeBoxFrame, 5)
	sizeBox = new("TextBox", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Text = tostring(HB.size),
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = T.TEXT_COLOR,
	}, sizeBoxFrame)

	sizeBox.FocusLost:Connect(function()
		local n = tonumber(sizeBox.Text)
		if n then
			HB.size = math.clamp(math.floor(n + 0.5), 1, 100)
		end
		sizeBox.Text = tostring(HB.size)
		sizeApi.set(HB.size)
	end)

	new("Frame", {
		Position = UDim2.fromOffset(16, 218),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, hbPop)

	label(hbPop, "Dynamic", UDim2.fromOffset(16, 224), UDim2.new(1, -90, 0, 28),
		Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	local minApi = makeSlider(hbPop, 258, "Min Size", 64, 1, 50, 1, HB.dynMin, "%d", function(v)
		HB.dynMin = v
	end)
	local farApi = makeSlider(hbPop, 288, "Full At", 64, 10, 300, 5, HB.dynFar, "%d", function(v)
		HB.dynFar = v
	end)
	minApi.dim(HB.dynamic)
	farApi.dim(HB.dynamic)
	makeSwitch(hbPop, HB.dynamic, function(on)
		HB.dynamic = on
		minApi.dim(on)
		farApi.dim(on)
	end, 238, 16)

	-- keeps the pop-up beside the dots, inside the page
	local function hbPosition()
		local rp = root.AbsolutePosition
		local rs = root.AbsoluteSize
		local ap = hbDots.AbsolutePosition
		local az = hbDots.AbsoluteSize
		local x = ap.X - rp.X + az.X + 8
		local y = ap.Y - rp.Y
		if x + HBW > rs.X - 4 then
			x = ap.X - rp.X - 8 - HBW
		end
		x = math.clamp(x, 4, math.max(4, rs.X - HBW - 4))
		y = math.clamp(y, 4, math.max(4, rs.Y - HBH - 4))
		return UDim2.fromOffset(math.floor(x), math.floor(y))
	end

	local HB_OPEN = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local HB_CLOSE = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local function openHb()
		if hbOpen then
			return
		end
		hbToken = hbToken + 1
		hbOpen = true
		local pos = hbPosition()
		hbPop.Position = pos + UDim2.fromOffset(0, 6)
		hbPop.GroupTransparency = 1
		hbPop.Visible = true
		TweenService:Create(hbPop, HB_OPEN, { Position = pos, GroupTransparency = 0 }):Play()
		dotsOpen = true
		paintDots()
	end

	local function closeHb()
		if not hbOpen then
			return
		end
		hbOpen = false
		hbToken = hbToken + 1
		local tk = hbToken
		TweenService:Create(hbPop, HB_CLOSE, {
			Position = hbPop.Position + UDim2.fromOffset(0, 6),
			GroupTransparency = 1,
		}):Play()
		task.delay(HB_CLOSE.Time + 0.02, function()
			if tk == hbToken then
				hbPop.Visible = false
			end
		end)
		dotsOpen = false
		paintDots()
	end

	hbDots.Activated:Connect(function()
		if hbOpen then
			closeHb()
		else
			openHb()
		end
	end)

	-- true when the pointer is over obj (tries every coordinate space, so clicks near the bottom still count)
	local function inRect(obj, x, y)
		local p = obj.AbsolutePosition
		local z = obj.AbsoluteSize
		return x >= p.X and x <= p.X + z.X and y >= p.Y and y <= p.Y + z.Y
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

	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input)
		if not hbOpen then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if pointerOver(hbPop, input) or pointerOver(hbDots, input) then
			return
		end
		closeHb()
	end)

	conns[#conns + 1] = RunService.Heartbeat:Connect(function()
		if running and HB.enabled and hbSub then
			-- show how many players are being expanded
			local txt = '<font color="rgb(230,230,234)"><b>Zee Hood</b></font> - <font color="rgb(52,199,120)">'
				.. tostring(activeCount) .. ' player(s)</font>'
			if hbSub.Text ~= txt then
				hbSub.Text = txt
			end
		end
	end)

	local function hbCleanup()
		hitboxUnload()
		pcall(function()
			hbPop:Destroy()
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
		S.armor.enabled = false
		S.stim.enabled = false
		S.food.enabled = false
		pcall(hbCleanup)
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

return Extra1Page
