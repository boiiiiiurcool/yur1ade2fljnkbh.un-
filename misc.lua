-- misc.lua  (Y1 Misc tab: a Movement / Extra / Auto Buy switch at the bottom, as its own module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Misc tab INTO win.MiscPage (ui.lua loads it through opts.MiscModule).
-- Same idea as aimbot.lua: a small switch at the bottom, [ Movement | Extra | Auto Buy ], swaps the page above it.
--
--   MovementModule = movement.lua   (empty for now)
--   ExtraModule    = extra.lua      (BulletTracer + HitSounds)
--   Extra1Module   = extra1.lua     (Auto Buy: armor / stim / food)
--
-- main.lua loads them and hands them over through opts.MovementModule / opts.ExtraModule /
-- opts.Extra1Module (ui.lua passes opts.Misc to this file). Each one is called as
-- <module>.build(container, T, H, ctx) inside a pcall, so a broken module cannot break the tab.
-- If it returns a table with an Unload function, that is called when the window is unloaded.
--
-- The pages here are plain frames on purpose (not CanvasGroups): the Misc page of the window is
-- already a CanvasGroup, and nesting more of them breaks pop-ups (they come out solid white).

local MiscPage = {}

function MiscPage.build(parent, T, H, opts)
	opts = opts or {}

	local TweenService = game:GetService("TweenService")
	local new, corner, stroke = H.new, H.corner, H.stroke
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH
	local RADIUS = T.RADIUS

	local BOTTOM_H = 44
	local conns = {}
	local handles = {}
	local running = true

	local root = new("Frame", {
		Name = "MiscRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	local function makeBox(name, visible)
		return new("Frame", {
			Name = name,
			Size = UDim2.new(1, 0, 1, -BOTTOM_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = visible,
		}, root)
	end

	local order = { "Movement", "Extra", "Auto Buy" }
	local boxes = {
		Movement = makeBox("MovementModule", true),
		Extra = makeBox("ExtraModule", false),
		["Auto Buy"] = makeBox("AutoBuyModule", false),
	}
	local mods = {
		Movement = opts.MovementModule,
		Extra = opts.ExtraModule,
		["Auto Buy"] = opts.Extra1Module,
	}
	local fileNames = {
		Movement = "movement.lua",
		Extra = "extra.lua",
		["Auto Buy"] = "extra1.lua",
	}

	local ctx = { Settings = opts.Settings or {}, AnimationModule = opts.AnimationModule }

	for i = 1, #order do
		local name = order[i]
		local mod = mods[name]
		if type(mod) == "table" and type(mod.build) == "function" then
			local ok, res = pcall(mod.build, boxes[name], T, H, ctx)
			if not ok then
				warn("[misc] " .. fileNames[name] .. " failed: " .. tostring(res))
			elseif type(res) == "table" then
				handles[#handles + 1] = res
			end
		end
	end

	-- the switch at the bottom
	local current = "Movement"
	local COUNT = #order

	local tray = new("Frame", {
		Name = "ModeSwitch",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(300, 32),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
	}, root)
	corner(tray, RADIUS + 4)
	stroke(tray, T.BORDER, 1, 0)

	local inner = new("Frame", {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 1, -8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, tray)

	local slider = new("Frame", {
		Size = UDim2.new(1 / COUNT, 0, 1, 0),
		BackgroundColor3 = T.HOVER_GREY,
		BorderSizePixel = 0,
	}, inner)
	corner(slider, RADIUS + 1)

	local tabBtns = {}

	local function paintTabs(animate)
		local index = 1
		for i = 1, COUNT do
			if order[i] == current then
				index = i
			end
		end
		local pos = UDim2.new((index - 1) / COUNT, 0, 0, 0)
		if animate then
			TweenService:Create(slider, SMOOTH, { Position = pos }):Play()
		else
			slider.Position = pos
		end
		for i = 1, COUNT do
			local colr = T.ICON
			if i == index then
				colr = T.ICON_HOVER
			end
			TweenService:Create(tabBtns[i], FAST, { TextColor3 = colr }):Play()
		end
	end

	local function showSub(name)
		if name == current or not boxes[name] then
			return
		end
		current = name
		for n, b in pairs(boxes) do
			b.Visible = (n == name)
		end
	end

	for i = 1, COUNT do
		local b = new("TextButton", {
			AutoButtonColor = false,
			Position = UDim2.new((i - 1) / COUNT, 0, 0, 0),
			Size = UDim2.new(1 / COUNT, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = order[i],
			TextColor3 = T.ICON,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
		}, inner)
		tabBtns[i] = b
		b.Activated:Connect(function()
			showSub(order[i])
			paintTabs(true)
		end)
	end
	paintTabs(false)

	local function unload()
		if not running then
			return
		end
		running = false
		for i = 1, #handles do
			local h = handles[i]
			if type(h.Unload) == "function" then
				pcall(h.Unload)
			end
		end
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

	if type(opts.OnUnload) == "function" then
		opts.OnUnload(unload)
	end

	return { Root = root, Unload = unload }
end

return MiscPage
