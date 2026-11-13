-- homepage.lua  (Y1 Home tab content, separate module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Home screen INTO a frame (the Home tab of Y1UI.lua). It does not make its own window.
-- Styled to match Y1UI.lua: flat dark surfaces, thin borders, small corner radius, calm red accent.
--
--   HomeModule = <this file>
--   Home = {
--       Product = "yur1",
--       Subtitle = "yur1 is built for a amazing person like you :)",
--       Access = "Lifetime access",
--       Build = "Beta 0.6",
--       Component = "Rock and Roll by reruinz",
--       OnNext = function() end,      -- optional, default: ctx.Win:ShowTab("Info")
--       OnEnable = function() end,    -- the Enable button (main.lua runs disable.lua here)
--       AutoClose = 3,                -- seconds the notification stays after Enable worked (0 = stay)
--   }
--
-- Theme notes: only colour names that exist in Y1UI's T table are used (GOOD / BAD instead of the old
-- GREEN / HOVER_RED / CARD_BG, which Y1UI would silently turn into the grey ICON colour).

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

	local R_SMALL = T.RADIUS or 4   -- buttons, chips
	local R_CARD = 8                -- cards (same as the window's content card)
	local ACCENT = T.CALM_RED
	local ACCENT_HOVER = Color3.fromRGB(214, 112, 112)
	local WHITE = Color3.new(1, 1, 1)
	local FAST = T.FAST or TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local CARD_S = 200
	local gameIconUrl = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=256&h=256"

	local alive = true

	local root = new("Frame", {
		Name = "HomeRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	-- very dim game image over the whole page. Four fades in the content card colour (WELL)
	-- melt it into the card, so no hard edge is visible. Everything is scale based.
	new("ImageLabel", {
		Name = "GameBackdrop",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = gameIconUrl,
		ScaleType = Enum.ScaleType.Crop,
		ImageTransparency = 0.78,
		ZIndex = 1,
	}, root)

	local function fadeEdge(name, pos, size, rotation, seq)
		local f = new("Frame", {
			Name = name,
			Position = pos,
			Size = size,
			BackgroundColor3 = T.WELL,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, root)
		new("UIGradient", { Rotation = rotation, Transparency = seq }, f)
		return f
	end

	fadeEdge("FadeLeft", UDim2.fromScale(0, 0), UDim2.fromScale(0.7, 1), 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.35, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	}))
	fadeEdge("FadeRight", UDim2.fromScale(0.6, 0), UDim2.fromScale(0.4, 1), 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	}))
	fadeEdge("FadeTop", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.45), 90, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	}))
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
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	}, root)
	-- same soft white gradient as the "1" in the Y1 logo
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 138)),
		}),
	}, gameName)

	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(game.PlaceId)
		end)
		if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
			if alive and gameName.Parent then
				gameName.Text = info.Name
			end
		end
	end)

	-- "Ready" pill: flat, thin green outline
	local pill = new("Frame", {
		Name = "ReadyPill",
		Position = UDim2.fromOffset(26, 52),
		Size = UDim2.fromOffset(50, 20),
		BackgroundColor3 = Color3.fromRGB(22, 40, 30),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)
	corner(pill, 100)
	stroke(pill, Color3.fromRGB(44, 96, 66), 1, 0)
	local pillText = label(pill, "Ready", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1),
		Enum.Font.GothamBold, 11, T.GOOD, Enum.TextXAlignment.Center)
	pillText.ZIndex = 4

	local ready = label(root, product .. " is ready", UDim2.fromOffset(24, 84),
		UDim2.new(1, -(CARD_S + 24 + 28 + 10), 0, 36), Enum.Font.GothamBold, 28, T.TEXT_COLOR)
	ready.ZIndex = 3

	local sub = label(root, subtitle, UDim2.fromOffset(24, 124),
		UDim2.new(1, -(CARD_S + 24 + 28 + 10), 0, 34), Enum.Font.GothamMedium, 12, T.DIM_TEXT)
	sub.TextWrapped = true
	sub.TextTruncate = Enum.TextTruncate.None
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.ZIndex = 3

	-- ZEE HOOD NOTIFICATION: a flat popup card (same look as the keybinds panel / toast):
	-- popup grey, thin border, small radius, red accent button. Floats in the empty space on the left.
	-- Two ways out: the X closes it for good, Enable runs it once.
	local NOTICE_H = 106
	local NOTICE_H_ERR = 150
	local AUTO_CLOSE = opts.AutoClose
	if AUTO_CLOSE == nil then
		AUTO_CLOSE = 3
	end
	local NOTICE_X = UDim2.new(1, -(CARD_S + 24 + 28 + 10) + 8, 0, 0)
	local MARGIN = 4
	local noticeBase = UDim2.fromOffset(22, 174)

	local notice = new("CanvasGroup", {
		Name = "ZeeHoodNotice",
		Position = noticeBase + UDim2.fromOffset(0, 14),
		Size = UDim2.new(NOTICE_X.X.Scale, NOTICE_X.X.Offset, 0, NOTICE_H + MARGIN * 2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		ZIndex = 6,
	}, root)

	-- faint shadow so the popup lifts off the page
	local shadow = new("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(MARGIN, MARGIN + 2),
		Size = UDim2.new(1, -MARGIN * 2, 1, -MARGIN * 2),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, notice)
	corner(shadow, R_CARD)

	local glass = new("Frame", {
		Name = "Glass",
		Position = UDim2.fromOffset(MARGIN, MARGIN),
		Size = UDim2.new(1, -MARGIN * 2, 1, -MARGIN * 2),
		BackgroundColor3 = T.POPUP_BG,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, notice)
	corner(glass, R_CARD)
	stroke(glass, T.BORDER, 1, 0)

	local TEXT_X = 16
	local RIGHT_PAD = 40

	local noticeText = label(glass, "Hey? are you on zee hood perchance, if you are turn this on before you get kicked..",
		UDim2.fromOffset(TEXT_X, 14), UDim2.new(1, -(TEXT_X + RIGHT_PAD), 0, 38), Enum.Font.GothamMedium, 13, T.TEXT_COLOR)
	noticeText.TextWrapped = true
	noticeText.TextTruncate = Enum.TextTruncate.None
	noticeText.TextYAlignment = Enum.TextYAlignment.Top
	noticeText.ZIndex = 7

	-- X (top right): same close button look as the keybinds panel (red square on hover)
	local closeBtn = new("TextButton", {
		Name = "NoticeClose",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(26, 24),
		BackgroundColor3 = ACCENT,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		ZIndex = 8,
	}, glass)
	corner(closeBtn, 6)
	local closeBars = {}
	local function closeBar(rot)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(11, 2),
			Rotation = rot,
			BackgroundColor3 = T.ICON,
			BorderSizePixel = 0,
			ZIndex = 9,
		}, closeBtn)
		corner(f, 1)
		closeBars[#closeBars + 1] = f
	end
	closeBar(45)
	closeBar(-45)

	local enableBtn = new("TextButton", {
		Name = "EnableButton",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(TEXT_X, 60),
		Size = UDim2.fromOffset(104, 28),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = "Enable",
		TextSize = 13,
		TextColor3 = WHITE,
		ZIndex = 8,
	}, glass)
	corner(enableBtn, R_SMALL)
	local enableStroke = stroke(enableBtn, ACCENT, 1, 1)   -- only visible on the greyed-out states

	local enableNote = label(glass, "", UDim2.fromOffset(TEXT_X + 104 + 14, 60), UDim2.new(1, -(TEXT_X + 104 + 14 + 16), 0, 28),
		Enum.Font.GothamMedium, 11, T.DIM_TEXT)
	enableNote.ZIndex = 7

	local errorText = label(glass, "", UDim2.fromOffset(TEXT_X, 98), UDim2.new(1, -(TEXT_X + 16), 0, 40),
		Enum.Font.Gotham, 11, T.BAD)
	errorText.Name = "EnableError"
	errorText.TextWrapped = true
	errorText.TextTruncate = Enum.TextTruncate.None
	errorText.TextYAlignment = Enum.TextYAlignment.Top
	errorText.Visible = false
	errorText.ZIndex = 7

	local noticeInfo = T.SMOOTH or TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local noticeOut = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	local noticeGone = false

	local function setNoticeHeight(h)
		if noticeGone then
			return
		end
		TweenService:Create(notice, noticeInfo, {
			Size = UDim2.new(NOTICE_X.X.Scale, NOTICE_X.X.Offset, 0, h + MARGIN * 2),
		}):Play()
	end

	local function closeNotice()
		if noticeGone then
			return
		end
		noticeGone = true
		TweenService:Create(notice, noticeOut, {
			Position = noticeBase + UDim2.fromOffset(0, -18),
			GroupTransparency = 1,
		}):Play()
		task.delay(noticeOut.Time + 0.05, function()
			notice:Destroy()
		end)
	end

	task.delay(0.6, function()
		if noticeGone or not alive then
			return
		end
		TweenService:Create(notice, noticeInfo, { Position = noticeBase, GroupTransparency = 0 }):Play()
	end)

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, FAST, { BackgroundTransparency = 0 }):Play()
		for i = 1, #closeBars do
			TweenService:Create(closeBars[i], FAST, { BackgroundColor3 = T.ICON_HOVER }):Play()
		end
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, FAST, { BackgroundTransparency = 1 }):Play()
		for i = 1, #closeBars do
			TweenService:Create(closeBars[i], FAST, { BackgroundColor3 = T.ICON }):Play()
		end
	end)
	closeBtn.Activated:Connect(closeNotice)

	-- states: "idle" (can press), "busy" (running), "done" (used up, never again), "failed" (can retry)
	local enableState = "idle"
	local enableHover = false

	local function paintEnable()
		if noticeGone then
			return
		end
		local bg = ACCENT
		local tc = WHITE
		local line = 1
		local txt = "Enable"
		if enableState == "busy" then
			bg = T.CLUSTER_BG
			tc = T.DIM_TEXT
			line = 0
			txt = "Enabling..."
		elseif enableState == "done" then
			bg = T.CLUSTER_BG
			tc = T.DIM_TEXT
			line = 0
			txt = "Enabled"
		elseif enableState == "failed" then
			txt = "Try again"
		end
		if enableHover and (enableState == "idle" or enableState == "failed") then
			bg = ACCENT_HOVER
		end
		-- the greyed-out states get a thin border like the other flat controls
		if line == 0 then
			enableStroke.Color = T.BORDER
		end
		enableBtn.Text = txt
		TweenService:Create(enableBtn, FAST, { BackgroundColor3 = bg, TextColor3 = tc }):Play()
		TweenService:Create(enableStroke, FAST, { Transparency = line }):Play()
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
		if enableState == "busy" or enableState == "done" then
			return
		end
		if type(opts.OnEnable) ~= "function" then
			enableNote.Text = "Not connected"
			enableNote.TextColor3 = T.BAD
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
					enableNote.TextColor3 = T.GOOD
				end
				paintEnable()
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
					enableNote.TextColor3 = T.BAD
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
			Enum.Font.GothamMedium, 10, T.DIM_TEXT)
		c.ZIndex = 3
		local v = label(stats, value, UDim2.fromOffset(x, 18), UDim2.fromOffset(w, 18),
			Enum.Font.GothamBold, 12, T.TEXT_COLOR)
		v.ZIndex = 3
	end
	stat(0, "Access", accessText, 130)
	stat(150, "Build", buildText, 100)
	stat(270, "Component", componentText, 200)

	-- RIGHT: the game image card (WELL fill, thin border, 8px radius like the window cards)
	local card = new("Frame", {
		Name = "GameCard",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -28, 0.5, -30),
		Size = UDim2.fromOffset(CARD_S, CARD_S),
		BackgroundColor3 = T.WELL,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)
	corner(card, R_CARD)
	stroke(card, T.BORDER, 1, 0)

	local cardImage = new("ImageLabel", {
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundColor3 = T.WELL,
		BorderSizePixel = 0,
		Image = gameIconUrl,
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 4,
	}, card)
	corner(cardImage, R_CARD - 1)

	-- NEXT button under the game card: red accent, same width as the card
	local nextBtn = new("TextButton", {
		Name = "NextButton",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0.5, 92),
		Size = UDim2.fromOffset(CARD_S, 38),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = "Next",
		TextSize = 14,
		TextColor3 = WHITE,
		ZIndex = 3,
	}, root)
	corner(nextBtn, R_SMALL)
	local nextScale = new("UIScale", { Scale = 1 }, nextBtn)
	nextBtn.MouseEnter:Connect(function()
		TweenService:Create(nextBtn, FAST, { BackgroundColor3 = ACCENT_HOVER }):Play()
	end)
	nextBtn.MouseLeave:Connect(function()
		TweenService:Create(nextBtn, FAST, { BackgroundColor3 = ACCENT }):Play()
		TweenService:Create(nextScale, FAST, { Scale = 1 }):Play()
	end)
	nextBtn.Activated:Connect(function()
		if type(opts.OnNext) == "function" then
			opts.OnNext()
		elseif opts.Win and type(opts.Win.ShowTab) == "function" then
			opts.Win:ShowTab("Info")
		end
	end)
	nextBtn.MouseButton1Down:Connect(function()
		TweenService:Create(nextScale, FAST, { Scale = 0.97 }):Play()
	end)
	nextBtn.MouseButton1Up:Connect(function()
		TweenService:Create(nextScale, FAST, { Scale = 1 }):Play()
	end)

	return {
		Root = root,
		NextButton = nextBtn,
		EnableButton = enableBtn,
		Notice = notice,
		Unload = function()
			alive = false
			noticeGone = true
			pcall(function()
				root:Destroy()
			end)
		end,
	}
end

return HomePage
