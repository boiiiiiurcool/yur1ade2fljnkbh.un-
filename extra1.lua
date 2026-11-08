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
-- Build signature: Extra1.build(container, T, H, ctx) -> { Root = ..., Unload = fn }

local Extra1Page = {}

function Extra1Page.build(parent, T, H, ctx)
	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local player = Players.LocalPlayer

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH
	local RADIUS = T.RADIUS

	local ARMOR_TAG = "[Full Armor]"
	local STIM_TAG = "[Stim]"
	local COOLDOWN = 1.0     -- seconds before the same model can be bought again
	local TICK = 0.2         -- how often the shop is checked

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
	-- page
	---------------------------------------------------------------------
	local root = new("Frame", {
		Name = "Extra1Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	label(root, "AUTO BUY", UDim2.fromOffset(4, 6), UDim2.new(1, -10, 0, 14),
		Enum.Font.GothamMedium, 11, T.DIM_TEXT)

	local ROW_H = 60
	local CARD_H = 6 + #OPTIONS * ROW_H

	local card = new("Frame", {
		Name = "AutoBuyCard",
		Position = UDim2.fromOffset(2, 24),
		Size = UDim2.new(1, -6, 0, CARD_H),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
	}, root)
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

		makeSlider(card, y + 32, "Range", 44, 3, 50, 1, st.range, "%d", function(v)
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
		label(root, "Your executor has no fireclickdetector, so buying will not work.",
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

		local now = os.clock()
		local kids = shop:GetChildren()
		for i = 1, #kids do
			local model = kids[i]
			if model:IsA("Model") then
				local st = S[kindOf(model.Name)]
				if st.enabled then
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

	task.spawn(function()
		while running do
			pcall(step)
			task.wait(TICK)
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
		S.armor.enabled = false
		S.stim.enabled = false
		S.food.enabled = false
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
