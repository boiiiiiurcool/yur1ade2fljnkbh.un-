-- homepage.lua  (Y1 Home tab content, separate module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Home screen INTO a frame (the Home tab of ui.lua). It does not make its own window.
--
--   local HomePage = <this file>
--   HomePage.build(parentFrame, themeTable, helperTable, {
--       Product = "yur1",
--       Subtitle = "yur1 is built for a amazing person like you :)",
--       Access = "Lifetime access",
--       Build = "Beta 0.6",
--       Component = "Rock and Roll by reruinz",
--       OnNext = function() end,      -- the Next button (ui.lua opens the Info tab)
--       OnEnable = function() end,    -- the Enable button (main.lua runs disable.lua here)
--   })
--
-- Inside: the game name, a green "Ready" pill, "yur1 is ready", a small line of text and
-- Access / Build / Component at the bottom left. On the right a card with the game image.
-- The game image also shows very dim behind the page. Layout follows the window size.
--
-- In the empty space on the left there is a small notice for Zee Hood players with an
-- Enable button. The button works ONCE: it calls opts.OnEnable, and when that finishes the
-- button turns into a greyed-out "Enabled" and cannot be pressed again. If OnEnable fails
-- (for example the download failed) the button becomes "Try again" so you can retry.

local HomePage = {}

function HomePage.build(parent, T, H, opts)
	opts = opts or {}
	local product = opts.Product or "yur1"
	local subtitle = opts.Subtitle or "yur1 is built for a amazing person like you :)"
	local accessText = opts.Access or "Lifetime access"
	local buildText = tostring(opts.Build or "Beta 0.6")
	local componentText = tostring(opts.Component or "Rock and Roll by reruinz")

	local MarketplaceService = game:GetService("MarketplaceService")
	local TweenService = game:GetService("TweenService")
	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label

	local CARD_S = 200
	local gameIconUrl = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=256&h=256"

	local root = new("Frame", {
		Name = "HomeRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	-- very dim game image over the whole page. Four black fades (left, right, top, bottom)
	-- melt it into the window, so no hard edge is visible. Everything is scale based,
	-- so it follows the window when it is resized or maximized.
	local bgImage = new("ImageLabel", {
		Name = "GameBackdrop",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = gameIconUrl,
		ScaleType = Enum.ScaleType.Crop,
		ImageTransparency = 0.7,
		ZIndex = 1,
	}, root)

	local function fadeEdge(name, pos, size, rotation, seq)
		local f = new("Frame", {
			Name = name,
			Position = pos,
			Size = size,
			BackgroundColor3 = T.BLACK,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, root)
		new("UIGradient", { Rotation = rotation, Transparency = seq }, f)
		return f
	end

	-- left: solid black on the far left so the text stays clean, then softly into the image
	fadeEdge("FadeLeft", UDim2.fromScale(0, 0), UDim2.fromScale(0.7, 1), 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.35, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	}))
	-- right: image melts into black at the right edge
	fadeEdge("FadeRight", UDim2.fromScale(0.6, 0), UDim2.fromScale(0.4, 1), 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	}))
	-- top
	fadeEdge("FadeTop", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.45), 90, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	}))
	-- bottom
	fadeEdge("FadeBottom", UDim2.fromScale(0, 0.55), UDim2.fromScale(1, 0.45), 90, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	}))

	-- LEFT: game name, Ready pill, "<product> is ready", small text
	local leftW = UDim2.new(1, -(CARD_S + 24 + 28 + 10), 0, 30)

	local gameName = new("TextLabel", {
		Name = "GameName",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 16),
		Size = leftW,
		Font = Enum.Font.GothamBlack,
		Text = game.Name,
		TextSize = 22,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	}, root)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 138)),
		}),
	}, gameName)

	-- the real game name comes from the marketplace (background)
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(game.PlaceId)
		end)
		if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
			if gameName.Parent then
				gameName.Text = info.Name
			end
		end
	end)

	local pill = new("Frame", {
		Name = "ReadyPill",
		Position = UDim2.fromOffset(26, 52),
		Size = UDim2.fromOffset(50, 20),
		BackgroundColor3 = Color3.fromRGB(22, 52, 38),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)
	corner(pill, 10)
	stroke(pill, Color3.fromRGB(36, 92, 62), 1, 0)
	local pillText = label(pill, "Ready", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1),
		Enum.Font.GothamBold, 11, T.GREEN, Enum.TextXAlignment.Center)
	pillText.ZIndex = 4

	local ready = label(root, product .. " is ready", UDim2.fromOffset(24, 84),
		UDim2.new(1, -(CARD_S + 24 + 28 + 10), 0, 36), Enum.Font.GothamBold, 28, T.TEXT_COLOR)
	ready.ZIndex = 3

	local sub = label(root, subtitle, UDim2.fromOffset(24, 124),
		UDim2.new(1, -(CARD_S + 24 + 28 + 10), 0, 34), Enum.Font.Gotham, 12, T.DIM_TEXT)
	sub.TextWrapped = true
	sub.TextTruncate = Enum.TextTruncate.None
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.ZIndex = 3

	-- ZEE HOOD NOTICE: in the empty space on the left, under the subtitle.
	-- The Enable button works once (see the header of this file).
	local notice = new("Frame", {
		Name = "ZeeHoodNotice",
		Position = UDim2.fromOffset(24, 176),
		Size = UDim2.new(1, -(CARD_S + 24 + 28 + 10), 0, 104),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)
	corner(notice, 10)
	stroke(notice, T.BORDER, 1, 0)

	local noticeText = label(notice, "Hey? are you on zee hood perchance, if you are turn this on before you get kicked..",
		UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 38), Enum.Font.Gotham, 13, T.TEXT_COLOR)
	noticeText.TextWrapped = true
	noticeText.TextTruncate = Enum.TextTruncate.None
	noticeText.TextYAlignment = Enum.TextYAlignment.Top
	noticeText.ZIndex = 4

	local enableBtn = new("TextButton", {
		Name = "EnableButton",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(16, 62),
		Size = UDim2.fromOffset(120, 30),
		BackgroundColor3 = T.JOIN_BG,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = "Enable",
		TextSize = 13,
		TextColor3 = T.BLACK,
		ZIndex = 4,
	}, notice)
	corner(enableBtn, 8)

	-- small line next to the button: what is happening / what went wrong
	local enableNote = label(notice, "", UDim2.fromOffset(148, 62), UDim2.new(1, -164, 0, 30),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	enableNote.ZIndex = 4

	-- states: "idle" (can press), "busy" (running), "done" (used up, never again), "failed" (can retry)
	local enableState = "idle"
	local enableHover = false
	local enableInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function paintEnable()
		local bg = T.JOIN_BG
		local tc = T.BLACK
		local txt = "Enable"
		if enableState == "busy" then
			bg = T.CLUSTER_BG
			tc = T.DIM_TEXT
			txt = "Enabling..."
		elseif enableState == "done" then
			bg = T.CLUSTER_BG
			tc = T.DIM_TEXT
			txt = "Enabled"
		elseif enableState == "failed" then
			txt = "Try again"
		end
		if enableHover and (enableState == "idle" or enableState == "failed") then
			bg = Color3.fromRGB(255, 255, 255)
		end
		enableBtn.Text = txt
		TweenService:Create(enableBtn, enableInfo, { BackgroundColor3 = bg, TextColor3 = tc }):Play()
	end

	enableBtn.MouseEnter:Connect(function()
		enableHover = true
		paintEnable()
	end)
	enableBtn.MouseLeave:Connect(function()
		enableHover = false
		paintEnable()
	end)

	enableBtn.Activated:Connect(function()
		-- once it ran, or while it is running, the button does nothing
		if enableState == "busy" or enableState == "done" then
			return
		end
		if type(opts.OnEnable) ~= "function" then
			enableNote.Text = "Not connected"
			enableNote.TextColor3 = T.HOVER_RED
			return
		end
		enableState = "busy"
		enableNote.Text = "Running..."
		enableNote.TextColor3 = T.DIM_TEXT
		paintEnable()
		task.spawn(function()
			local ok, err = pcall(opts.OnEnable)
			if not enableBtn.Parent then
				return
			end
			if ok then
				enableState = "done"
				enableNote.Text = "Done"
				enableNote.TextColor3 = T.GREEN
			else
				enableState = "failed"
				local msg = tostring(err)
				if #msg > 60 then
					msg = string.sub(msg, 1, 57) .. "..."
				end
				enableNote.Text = msg
				enableNote.TextColor3 = T.HOVER_RED
				warn("[Y1] Enable failed: " .. tostring(err))
			end
			paintEnable()
		end)
	end)

	-- BOTTOM LEFT: Access / Build / Component
	local stats = new("Frame", {
		Name = "Stats",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -16),
		Size = UDim2.new(1, -48, 0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)

	local function stat(x, caption, value, w)
		local c = label(stats, caption, UDim2.fromOffset(x, 0), UDim2.fromOffset(w, 14),
			Enum.Font.Gotham, 10, T.DIM_TEXT)
		c.ZIndex = 3
		local v = label(stats, value, UDim2.fromOffset(x, 18), UDim2.fromOffset(w, 18),
			Enum.Font.GothamBold, 12, T.TEXT_COLOR)
		v.ZIndex = 3
	end
	stat(0, "Access", accessText, 130)
	stat(150, "Build", buildText, 100)
	stat(270, "Component", componentText, 200)

	-- RIGHT: the game image card
	local card = new("Frame", {
		Name = "GameCard",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -28, 0.5, -30),
		Size = UDim2.fromOffset(CARD_S, CARD_S),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)
	corner(card, 16)
	stroke(card, T.BORDER, 1, 0)

	local cardImage = new("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.CARD_BG,
		BorderSizePixel = 0,
		Image = gameIconUrl,
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 4,
	}, card)
	corner(cardImage, 16)

	-- NEXT button under the game card, same width as the card (opens the Info tab via opts.OnNext)
	local nextBtn = new("TextButton", {
		Name = "NextButton",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0.5, 92),
		Size = UDim2.fromOffset(CARD_S, 38),
		BackgroundColor3 = T.JOIN_BG,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = "Next",
		TextSize = 14,
		TextColor3 = T.BLACK,
		ZIndex = 3,
	}, root)
	corner(nextBtn, 8)
	local nextScale = new("UIScale", { Scale = 1 }, nextBtn)
	local nextInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	nextBtn.MouseEnter:Connect(function()
		TweenService:Create(nextBtn, nextInfo, { BackgroundColor3 = Color3.fromRGB(255, 255, 255) }):Play()
	end)
	nextBtn.MouseLeave:Connect(function()
		TweenService:Create(nextBtn, nextInfo, { BackgroundColor3 = T.JOIN_BG }):Play()
		TweenService:Create(nextScale, nextInfo, { Scale = 1 }):Play()
	end)
	nextBtn.Activated:Connect(function()
		if type(opts.OnNext) == "function" then
			opts.OnNext()
		end
	end)
	nextBtn.MouseButton1Down:Connect(function()
		TweenService:Create(nextScale, nextInfo, { Scale = 0.97 }):Play()
	end)
	nextBtn.MouseButton1Up:Connect(function()
		TweenService:Create(nextScale, nextInfo, { Scale = 1 }):Play()
	end)

	return { Root = root, NextButton = nextBtn, EnableButton = enableBtn }
end

return HomePage
