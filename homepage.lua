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
--       AutoClose = 3,                -- seconds the notification stays after Enable worked (0 = stay)
--   })
--
-- Inside: the game name, a green "Ready" pill, "yur1 is ready", a small line of text and
-- Access / Build / Component at the bottom left. On the right a card with the game image.
-- The game image also shows very dim behind the page. Layout follows the window size.
--
-- In the empty space on the left a notification fades in for Zee Hood players. It is a soft
-- glass card (see-through, so the page behind it shows a little) with two ways out:
--   * the X in its corner closes it for good,
--   * Enable calls opts.OnEnable. That works ONCE: when it finishes the button turns into a
--     greyed-out "Enabled" and the notification closes by itself after opts.AutoClose seconds
--     (default 3, set 0 to keep it open).
-- If OnEnable fails (for example the download failed or the file has an error) the full error
-- text is shown inside the notification and the button becomes "Try again".

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

	-- ZEE HOOD NOTIFICATION: floats in the empty space on the left, under the subtitle.
	-- It fades in a moment after the page opens. The X closes it for good, Enable runs it once.
	-- Built as a soft glass card: a gradient that is more see-through towards the right, a very
	-- faint outline and no hard fill, so it melts into the page instead of sitting on it like a box.
	local NOTICE_H = 106        -- normal height
	local NOTICE_H_ERR = 150   -- height while an error message is showing
	local AUTO_CLOSE = opts.AutoClose
	if AUTO_CLOSE == nil then
		AUTO_CLOSE = 3
	end
	local NOTICE_X = UDim2.new(1, -(CARD_S + 24 + 28 + 10) + 4, 0, 0)   -- width (4px more for the outline room)
	local noticeBase = UDim2.fromOffset(22, 174)

	-- canvas group so the whole notification fades together; it is 2px bigger than the glass
	-- so the outline is not cut off at the edge
	local notice = new("CanvasGroup", {
		Name = "ZeeHoodNotice",
		Position = noticeBase + UDim2.fromOffset(0, 14),
		Size = UDim2.new(NOTICE_X.X.Scale, NOTICE_X.X.Offset, 0, NOTICE_H + 4),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		ZIndex = 3,
	}, root)

	local glass = new("Frame", {
		Name = "Glass",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, notice)
	corner(glass, 12)
	new("UIGradient", {
		Rotation = 0,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.55, 0.38),
			NumberSequenceKeypoint.new(1, 0.62),
		}),
	}, glass)
	stroke(glass, T.ICON_HOVER, 1, 0.88)

	-- round chip with an exclamation mark
	local chip = new("Frame", {
		Name = "Chip",
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = T.CLUSTER_BG,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, glass)
	corner(chip, 100)
	local chipText = label(chip, "!", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1),
		Enum.Font.GothamBold, 14, T.ICON_HOVER, Enum.TextXAlignment.Center)
	chipText.ZIndex = 5

	local noticeText = label(glass, "Hey? are you on zee hood perchance, if you are turn this on before you get kicked..",
		UDim2.fromOffset(52, 12), UDim2.new(1, -92, 0, 38), Enum.Font.Gotham, 13, T.TEXT_COLOR)
	noticeText.TextWrapped = true
	noticeText.TextTruncate = Enum.TextTruncate.None
	noticeText.TextYAlignment = Enum.TextYAlignment.Top
	noticeText.ZIndex = 4

	-- X (top right): closes the notification
	local closeBtn = new("TextButton", {
		Name = "NoticeClose",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = T.HOVER_GREY,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		ZIndex = 5,
	}, glass)
	corner(closeBtn, 6)
	local closeBars = {}
	local function closeBar(rot)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(10, 2),
			Rotation = rot,
			BackgroundColor3 = T.ICON,
			BorderSizePixel = 0,
			ZIndex = 6,
		}, closeBtn)
		corner(f, 1)
		closeBars[#closeBars + 1] = f
	end
	closeBar(45)
	closeBar(-45)

	local enableBtn = new("TextButton", {
		Name = "EnableButton",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(52, 60),
		Size = UDim2.fromOffset(104, 28),
		BackgroundColor3 = T.JOIN_BG,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = "Enable",
		TextSize = 13,
		TextColor3 = T.BLACK,
		ZIndex = 5,
	}, glass)
	corner(enableBtn, 8)

	-- short status next to the button ("Running...", "Done", "Failed")
	local enableNote = label(glass, "", UDim2.fromOffset(168, 60), UDim2.new(1, -184, 0, 28),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	enableNote.ZIndex = 4

	-- the full error text, under the button (only visible after a failure)
	local errorText = label(glass, "", UDim2.fromOffset(52, 98), UDim2.new(1, -68, 0, 40),
		Enum.Font.Gotham, 11, T.HOVER_RED)
	errorText.Name = "EnableError"
	errorText.TextWrapped = true
	errorText.TextTruncate = Enum.TextTruncate.None
	errorText.TextYAlignment = Enum.TextYAlignment.Top
	errorText.Visible = false
	errorText.ZIndex = 4

	local noticeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local noticeOut = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	local noticeGone = false

	local function setNoticeHeight(h)
		if noticeGone then
			return
		end
		TweenService:Create(notice, noticeInfo, {
			Size = UDim2.new(NOTICE_X.X.Scale, NOTICE_X.X.Offset, 0, h + 4),
		}):Play()
	end

	-- slides down a little and fades out, then removes itself for good
	local function closeNotice()
		if noticeGone then
			return
		end
		noticeGone = true
		TweenService:Create(notice, noticeOut, {
			Position = noticeBase + UDim2.fromOffset(0, 10),
			GroupTransparency = 1,
		}):Play()
		task.delay(0.3, function()
			notice:Destroy()
		end)
	end

	-- fades in a moment after the page opened
	task.delay(0.6, function()
		if noticeGone then
			return
		end
		TweenService:Create(notice, noticeInfo, { Position = noticeBase, GroupTransparency = 0 }):Play()
	end)

	-- X hover + click
	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, TweenInfo.new(0.12), { BackgroundTransparency = 0.4 }):Play()
		for i = 1, #closeBars do
			TweenService:Create(closeBars[i], TweenInfo.new(0.12), { BackgroundColor3 = T.ICON_HOVER }):Play()
		end
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
		for i = 1, #closeBars do
			TweenService:Create(closeBars[i], TweenInfo.new(0.12), { BackgroundColor3 = T.ICON }):Play()
		end
	end)
	closeBtn.Activated:Connect(closeNotice)

	-- states: "idle" (can press), "busy" (running), "done" (used up, never again), "failed" (can retry)
	local enableState = "idle"
	local enableHover = false
	local enableInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function paintEnable()
		if noticeGone then
			return
		end
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
		errorText.Visible = false
		setNoticeHeight(NOTICE_H)
		paintEnable()
		task.spawn(function()
			local ok, err = pcall(opts.OnEnable)
			if ok then
				enableState = "done"
				if not noticeGone then
					enableNote.Text = "Done"
					enableNote.TextColor3 = T.GREEN
				end
				paintEnable()
				-- the notification has done its job: it leaves by itself
				if AUTO_CLOSE and AUTO_CLOSE > 0 then
					task.delay(AUTO_CLOSE, closeNotice)
				end
			else
				enableState = "failed"
				local msg = tostring(err)
				if #msg > 220 then
					msg = string.sub(msg, 1, 217) .. "..."
				end
				warn("[Y1] Enable failed: " .. tostring(err))
				if not noticeGone then
					enableNote.Text = "Failed"
					enableNote.TextColor3 = T.HOVER_RED
					errorText.Text = msg
					errorText.Visible = true
					setNoticeHeight(NOTICE_H_ERR)
				end
				paintEnable()
			end
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

	return { Root = root, NextButton = nextBtn, EnableButton = enableBtn, Notice = notice }
end

return HomePage
