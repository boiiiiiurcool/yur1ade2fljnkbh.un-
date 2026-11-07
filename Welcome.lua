-- Welcome.lua  (welcome screen module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Same look as ui.lua: black window with tiny rounded corners (no sidebar),
-- close button top right, content area on a soft gradient. This version is a smaller window.
-- In the content area: "yur1" on top, "Welcome to yur1", your profile card next to a game card
-- (current game name + icon), tiles for user ID, account age, creation date and role.
--
-- At the bottom it shows a loading wheel with "Loading everything safely". The Continue button
-- only appears after WaitSeconds (default 10) AND once SetState("ready") was called.
-- Enter cannot skip the wait either.
--
-- The window is NOT draggable. It always opens in the middle of the screen.
-- OnContinue still receives the window position (always centered) so main.lua keeps working.
--
--   local Welcome = <this file>
--   local welcome = Welcome.new({
--       Name = "Y1Welcome",
--       Title = "yur1",
--       Logo = "Y1",
--       ButtonText = "Continue",
--       DefaultRole = "Tester",
--       WaitSeconds = 10,
--       Roles = { [12345678] = "Owner" },
--       OnContinue = function(position) end,
--       OnClose = function() end,
--   })
--   welcome:SetState("loading", "Loading modules...")
--   welcome:SetState("ready")
--   welcome:SetState("error", "Could not load")
--   welcome:GetPosition()
--   welcome:Close(instant)

local Welcome = {}

function Welcome.new(opts)
	opts = opts or {}
	local guiName = opts.Name or "Y1Welcome"
	local title = opts.Title or "yur1"
	local logoName = opts.Logo or "Y1"
	local buttonText = opts.ButtonText or "Continue"
	local defaultRole = opts.DefaultRole or "Tester"
	local WAIT_SECONDS = opts.WaitSeconds or 10

	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local HttpService = game:GetService("HttpService")
	local MarketplaceService = game:GetService("MarketplaceService")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- only one welcome screen at a time
	do
		local old = playerGui:FindFirstChild(guiName)
		if old then
			old:Destroy()
		end
	end

	local W = {}
	local conns = {}
	local alive = true
	local continued = false
	local state = "loading"
	local waitDone = false      -- true once WAIT_SECONDS have passed
	local btnShown = false      -- true while the Continue button is the thing on screen

	---------------------------------------------------------------------
	-- THEME (same colours as ui.lua)
	---------------------------------------------------------------------
	local BLACK      = Color3.fromRGB(10, 10, 11)
	local BORDER     = Color3.fromRGB(36, 36, 39)
	local SIDEBAR_BG = Color3.fromRGB(17, 17, 19)
	local CARD_BG    = Color3.fromRGB(28, 28, 31)
	local CLUSTER_BG = Color3.fromRGB(30, 30, 33)
	local ICON       = Color3.fromRGB(176, 176, 182)
	local ICON_HOVER = Color3.fromRGB(240, 240, 244)
	local HOVER_RED  = Color3.fromRGB(214, 62, 62)
	local TEXT_COLOR = Color3.fromRGB(230, 230, 234)
	local DIM_TEXT   = Color3.fromRGB(116, 116, 124)
	local JOIN_BG    = Color3.fromRGB(232, 232, 236)

	local RADIUS = 4
	local SQUARE_RADIUS = 10

	local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local SMOOTH = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local POP = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local LEAVE = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	local SPRING = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	---------------------------------------------------------------------
	-- HELPERS
	---------------------------------------------------------------------
	local function new(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do
			o[k] = v
		end
		o.Parent = parent
		return o
	end

	local function corner(obj, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r or RADIUS)
		c.Parent = obj
		return c
	end

	local function stroke(obj, color, thickness, transparency)
		local s = Instance.new("UIStroke")
		s.Color = color
		s.Thickness = thickness or 1
		s.Transparency = transparency or 0
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = obj
		return s
	end

	local function pad(o, l, t, r, b)
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, l)
		p.PaddingTop = UDim.new(0, t)
		p.PaddingRight = UDim.new(0, r)
		p.PaddingBottom = UDim.new(0, b)
		p.Parent = o
	end

	local function label(parent, text, pos, size, font, textSize, color, align)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = pos
		l.Size = size
		l.Font = font
		l.Text = text
		l.TextColor3 = color
		l.TextSize = textSize
		l.TextXAlignment = align or Enum.TextXAlignment.Left
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.Parent = parent
		return l
	end

	---------------------------------------------------------------------
	-- ACCOUNT INFO
	---------------------------------------------------------------------
	local MONTHS = {
		"January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December",
	}

	local function plural(n, word)
		if n == 1 then
			return n .. " " .. word
		end
		return n .. " " .. word .. "s"
	end

	local function formatAge(days)
		if days < 1 then
			return "Today"
		end
		local y = math.floor(days / 365)
		local rest = days - y * 365
		local m = math.floor(rest / 30)
		local d = rest - m * 30
		if y > 0 then
			if m > 0 then
				return plural(y, "year") .. ", " .. plural(m, "month")
			end
			return plural(y, "year")
		end
		if m > 0 then
			if d > 0 then
				return plural(m, "month") .. ", " .. plural(d, "day")
			end
			return plural(m, "month")
		end
		return plural(d, "day")
	end

	local function formatDate(m, d, y)
		return (MONTHS[m] or "?") .. " " .. d .. ", " .. y
	end

	local days = player.AccountAge
	local createdText = "Unknown"
	do
		local ok, t = pcall(function()
			return os.date("!*t", os.time() - days * 86400)
		end)
		if ok and type(t) == "table" then
			createdText = formatDate(t.month, t.day, t.year)
		end
	end

	local role = defaultRole
	if opts.Roles and opts.Roles[player.UserId] then
		role = opts.Roles[player.UserId]
	end

	---------------------------------------------------------------------
	-- WINDOW (same base as ui.lua, smaller)
	---------------------------------------------------------------------
	local WIN_W = 460
	local WIN_H = 360
	local BAR_H = 34
	local CONTENT_W = WIN_W - 12
	local BTN_W = 240
	local BTN_H = 38
	if touch then
		BTN_H = 46
	end
	local BOT_W = BTN_W + 16            -- a little wider than the button so its grow animation is not clipped
	local STATUS_Y = BTN_H + 10
	local BOT_H = STATUS_Y + 14

	local gui = new("ScreenGui", {
		Name = guiName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	-- small screens: shrink the whole window to fit
	local fitScale = 1
	do
		local cam = workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			fitScale = math.min(1, (vp.X - 24) / WIN_W, (vp.Y - 24) / WIN_H)
			fitScale = math.max(0.5, fitScale)
		end
	end

	local window = new("CanvasGroup", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WIN_W, WIN_H),
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	}, gui)
	corner(window)
	local windowScale = new("UIScale", { Scale = fitScale * 0.92 }, window)

	-- clean gradient background behind everything
	do
		local backdrop = new("Frame", {
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 0,
		}, window)
		corner(backdrop, RADIUS)
		new("UIGradient", {
			Rotation = 45,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 31)),
				ColorSequenceKeypoint.new(0.55, Color3.fromRGB(16, 16, 17)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 10, 11)),
			}),
		}, backdrop)
	end

	do
		local outline = new("Frame", {
			Name = "Outline",
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 20,
		}, window)
		corner(outline, RADIUS)
		stroke(outline, BORDER, 1, 0)
	end

	-- top bar (holds the close button)
	local bar = new("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundTransparency = 1,
	}, window)

	-- (no sidebar)

	-- close button (top right), same look as the control cluster in ui.lua
	local closeBtn = nil
	do
		local PAD = 3
		local bw = 26
		local bh = 20
		if touch then
			bw = 40
			bh = 28
		end
		local ch = bh + PAD * 2
		local cluster = new("Frame", {
			Name = "Controls",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, (BAR_H - ch) / 2),
			Size = UDim2.fromOffset(bw + PAD * 2, ch),
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
		}, bar)
		corner(cluster, RADIUS + 2)

		closeBtn = new("TextButton", {
			Name = "close",
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(PAD, PAD),
			Size = UDim2.fromOffset(bw, bh),
			BackgroundColor3 = HOVER_RED,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, cluster)
		corner(closeBtn, 4)

		local parts = {}
		local function line(rot)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(12, 2),
				Rotation = rot,
				BackgroundColor3 = ICON,
				BorderSizePixel = 0,
			}, closeBtn)
			corner(f, 1)
			table.insert(parts, f)
		end
		line(45)
		line(-45)

		local hoveringClose = false
		local function paint(isOver, pressed)
			local bgT = 1
			if isOver then
				if pressed then
					bgT = 0.35
				else
					bgT = 0
				end
			end
			TweenService:Create(closeBtn, FAST, { BackgroundTransparency = bgT }):Play()
			local color = ICON
			if isOver then
				color = ICON_HOVER
			end
			for i = 1, #parts do
				TweenService:Create(parts[i], FAST, { BackgroundColor3 = color }):Play()
			end
		end
		closeBtn.MouseEnter:Connect(function()
			hoveringClose = true
			paint(true, false)
		end)
		closeBtn.MouseLeave:Connect(function()
			hoveringClose = false
			paint(false, false)
		end)
		closeBtn.MouseButton1Down:Connect(function()
			paint(true, true)
		end)
		closeBtn.MouseButton1Up:Connect(function()
			paint(hoveringClose, false)
		end)
	end

	-- content area, same layout idea as ui.lua
	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(6, BAR_H),
		Size = UDim2.new(1, -12, 1, -(BAR_H + 6)),
		BackgroundTransparency = 1,
	}, window)

	-- each part of the content is its own canvas group so it can fade in on its own.
	-- groups with outlined children are 2px bigger with 2px padding so outlines are not cut off.
	local sections = {}
	local function makeSection(x, y, w, h, outlined)
		local g = new("CanvasGroup", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			GroupTransparency = 1,
		}, content)
		if outlined then
			g.Position = UDim2.fromOffset(x - 2, y - 2)
			g.Size = UDim2.fromOffset(w + 4, h + 4)
			pad(g, 2, 2, 2, 2)
		end
		table.insert(sections, { group = g, pos = g.Position })
		return g
	end

	-- ===== header: "yur1" on top middle, "Welcome to yur1" under it =====
	local header = makeSection(0, 6, CONTENT_W, 78, false)

	local titleLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 40),
		Font = Enum.Font.GothamBlack,
		Text = title,
		TextSize = 34,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, header)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 138)),
		}),
	}, titleLabel)

	label(header, "Welcome to " .. title, UDim2.fromOffset(0, 42), UDim2.new(1, 0, 0, 18),
		Enum.Font.GothamMedium, 14, TEXT_COLOR, Enum.TextXAlignment.Center)
	label(header, "Built for amazing people just like you :)", UDim2.fromOffset(0, 62), UDim2.new(1, 0, 0, 14),
		Enum.Font.Gotham, 11, DIM_TEXT, Enum.TextXAlignment.Center)

	-- ===== profile card (left) + game card (right) =====
	local profile = makeSection(2, 90, CONTENT_W - 4, 58, true)

	local profCard = new("Frame", {
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = SIDEBAR_BG,
		BorderSizePixel = 0,
	}, profile)
	corner(profCard, SQUARE_RADIUS)
	stroke(profCard, BORDER, 1, 0)

	local avatar = new("ImageLabel", {
		Position = UDim2.fromOffset(9, 9),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = CARD_BG,
		BorderSizePixel = 0,
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150",
	}, profCard)
	corner(avatar, 10)

	label(profCard, player.DisplayName, UDim2.fromOffset(60, 11), UDim2.new(1, -68, 0, 18),
		Enum.Font.GothamBold, 14, TEXT_COLOR)
	label(profCard, "@" .. player.Name, UDim2.fromOffset(60, 30), UDim2.new(1, -68, 0, 14),
		Enum.Font.Gotham, 11, DIM_TEXT)

	local gameCard = new("Frame", {
		Position = UDim2.new(0.5, 4, 0, 0),
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = SIDEBAR_BG,
		BorderSizePixel = 0,
	}, profile)
	corner(gameCard, SQUARE_RADIUS)
	stroke(gameCard, BORDER, 1, 0)

	local gameIcon = new("ImageLabel", {
		Position = UDim2.fromOffset(9, 9),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = CARD_BG,
		BorderSizePixel = 0,
		Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=256&h=256",
	}, gameCard)
	corner(gameIcon, 10)

	label(gameCard, "Current game", UDim2.fromOffset(60, 8), UDim2.new(1, -68, 0, 12),
		Enum.Font.Gotham, 10, DIM_TEXT)
	local gameNameLabel = label(gameCard, game.Name, UDim2.fromOffset(60, 21), UDim2.new(1, -68, 0, 18),
		Enum.Font.GothamBold, 13, TEXT_COLOR)
	label(gameCard, "Place ID: " .. tostring(game.PlaceId), UDim2.fromOffset(60, 40), UDim2.new(1, -68, 0, 12),
		Enum.Font.Gotham, 10, DIM_TEXT)

	-- the real game name comes from the marketplace (runs in the background)
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(game.PlaceId)
		end)
		if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
			if alive and gameNameLabel.Parent then
				gameNameLabel.Text = info.Name
			end
		end
	end)

	-- ===== info tiles in a 2x2 grid: user ID, account age, creation date, role =====
	local TILE_H = 40
	local tilesGroup = makeSection(2, 156, CONTENT_W - 4, TILE_H * 2 + 8, true)
	local TILE_W = (CONTENT_W - 4 - 8) / 2

	local function makeTile(index, caption)
		local col = (index - 1) % 2
		local row = math.floor((index - 1) / 2)
		local f = new("Frame", {
			Position = UDim2.fromOffset(col * (TILE_W + 8), row * (TILE_H + 8)),
			Size = UDim2.fromOffset(TILE_W, TILE_H),
			BackgroundColor3 = SIDEBAR_BG,
			BorderSizePixel = 0,
		}, tilesGroup)
		corner(f, RADIUS + 4)
		stroke(f, BORDER, 1, 0)
		local cap = label(f, caption, UDim2.fromOffset(10, 6), UDim2.new(1, -20, 0, 12),
			Enum.Font.Gotham, 10, DIM_TEXT)
		return f, cap
	end

	local function tileValue(tile, text)
		return label(tile, text, UDim2.fromOffset(10, 20), UDim2.new(1, -20, 0, 16),
			Enum.Font.GothamMedium, 12, TEXT_COLOR)
	end

	local idTile = makeTile(1, "User ID")
	tileValue(idTile, tostring(player.UserId))

	local ageTile, ageCaption = makeTile(2, "Account Age (" .. days .. " days)")
	local ageValue = tileValue(ageTile, formatAge(days))

	local createdTile = makeTile(3, "Created")
	local createdValue = tileValue(createdTile, createdText)

	-- role is plain text (no dot, no pill)
	local roleTile = makeTile(4, "Role")
	tileValue(roleTile, role)

	-- ===== bottom: loading wheel first, Continue button after the wait =====
	local bottom = makeSection((CONTENT_W - BOT_W) / 2, 254, BOT_W, BOT_H, false)

	-- loading part: wheel + "Loading everything safely"
	local loaderGroup = new("CanvasGroup", {
		Name = "Loader",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 0,
	}, bottom)

	local function ringFrame()
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 14),
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, loaderGroup)
		corner(f, 100)
		return f
	end
	local track = ringFrame()
	stroke(track, CLUSTER_BG, 3, 0)
	local arc = ringFrame()
	local arcStroke = stroke(arc, ICON_HOVER, 3, 0)
	local grad = new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, arcStroke)
	local spin = TweenService:Create(
		grad,
		TweenInfo.new(0.9, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
		{ Rotation = 360 }
	)
	spin:Play()

	local loaderText = label(loaderGroup, "Loading everything safely", UDim2.fromOffset(0, 34), UDim2.new(1, 0, 0, 16),
		Enum.Font.GothamMedium, 13, TEXT_COLOR, Enum.TextXAlignment.Center)

	-- button part (hidden until the wait is over and the state is "ready")
	local btnGroup = new("CanvasGroup", {
		Name = "ButtonGroup",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
	}, bottom)

	local btn = new("TextButton", {
		Name = "Continue",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.fromOffset(BTN_W, BTN_H),
		BackgroundColor3 = JOIN_BG,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = buttonText,
		TextSize = 14,
		TextColor3 = BLACK,
	}, btnGroup)
	corner(btn, 8)
	local btnScale = new("UIScale", { Scale = 1 }, btn)

	-- rounded chevron drawn with two bars (same style as the arrows in the main window)
	local chev = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -24, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
	}, btn)
	local function chevBar(y, rot)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, -0.5, 0.5, y),
			Size = UDim2.fromOffset(7, 2),
			Rotation = rot,
			BackgroundColor3 = BLACK,
			BorderSizePixel = 0,
		}, chev)
		corner(f, 1)
	end
	chevBar(-2.5, 45)
	chevBar(2.5, -45)

	-- status line (text from SetState), sits under both the wheel text and the button
	local status = label(bottom, "", UDim2.fromOffset(0, STATUS_Y), UDim2.new(1, 0, 0, 14),
		Enum.Font.Gotham, 11, DIM_TEXT, Enum.TextXAlignment.Center)

	---------------------------------------------------------------------
	-- LOADER <-> BUTTON SWITCH
	---------------------------------------------------------------------
	local hovering = false
	local swapToken = 0

	local function paintButton()
		local bg = JOIN_BG
		if hovering then
			bg = Color3.fromRGB(255, 255, 255)
		end
		TweenService:Create(btn, FAST, { BackgroundColor3 = bg }):Play()
		local cx = -24
		if hovering then
			cx = -20
		end
		TweenService:Create(chev, SPRING, { Position = UDim2.new(1, cx, 0.5, 0) }):Play()
	end

	-- decides what the bottom of the window shows
	local function refreshBottom()
		if not alive then
			return
		end

		local isErr = (state == "error")
		if isErr then
			loaderText.Text = "Could not load"
			loaderText.TextColor3 = HOVER_RED
			track.Visible = false
			arc.Visible = false
		else
			loaderText.Text = "Loading everything safely"
			loaderText.TextColor3 = TEXT_COLOR
			track.Visible = true
			arc.Visible = true
		end

		local showBtn = (state == "ready" and waitDone)
		if showBtn and not btnShown then
			btnShown = true
			swapToken = swapToken + 1
			local tk = swapToken
			btnGroup.Visible = true
			TweenService:Create(loaderGroup, FAST, { GroupTransparency = 1 }):Play()
			TweenService:Create(btnGroup, SMOOTH, { GroupTransparency = 0 }):Play()
			task.delay(FAST.Time + 0.03, function()
				if alive and tk == swapToken then
					loaderGroup.Visible = false
				end
			end)
		elseif (not showBtn) and btnShown then
			btnShown = false
			swapToken = swapToken + 1
			local tk = swapToken
			loaderGroup.Visible = true
			TweenService:Create(btnGroup, FAST, { GroupTransparency = 1 }):Play()
			TweenService:Create(loaderGroup, SMOOTH, { GroupTransparency = 0 }):Play()
			task.delay(FAST.Time + 0.03, function()
				if alive and tk == swapToken then
					btnGroup.Visible = false
				end
			end)
		end
	end

	local function leaveAndCallback(leavePos)
		local cb = opts.OnContinue
		W:Close(true)
		if cb then
			local ok, err = pcall(cb, leavePos)
			if not ok then
				warn("[welcome] OnContinue error: " .. tostring(err))
			end
		end
	end

	local function doContinue()
		if not alive or continued or state ~= "ready" or not waitDone or not btnShown then
			return
		end
		continued = true
		local leavePos = window.Position
		TweenService:Create(window, LEAVE, { GroupTransparency = 1 }):Play()
		TweenService:Create(windowScale, LEAVE, { Scale = fitScale * 0.94 }):Play()
		task.delay(LEAVE.Time + 0.03, function()
			if alive then
				leaveAndCallback(leavePos)
			end
		end)
	end

	btn.MouseEnter:Connect(function()
		hovering = true
		paintButton()
		TweenService:Create(btnScale, SPRING, { Scale = 1.02 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		hovering = false
		paintButton()
		TweenService:Create(btnScale, SPRING, { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(btnScale, FAST, { Scale = 0.96 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		local s = 1
		if hovering then
			s = 1.02
		end
		TweenService:Create(btnScale, SPRING, { Scale = s }):Play()
	end)
	btn.Activated:Connect(doContinue)

	closeBtn.Activated:Connect(function()
		if not alive or continued then
			return
		end
		local cb = opts.OnClose
		W:Close(false)
		if cb then
			local ok, err = pcall(cb)
			if not ok then
				warn("[welcome] OnClose error: " .. tostring(err))
			end
		end
	end)

	-- Enter also continues (but only once the button is showing)
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			doContinue()
		end
	end))

	-- (no dragging: the welcome window stays in the middle of the screen)

	---------------------------------------------------------------------
	-- PUBLIC API
	---------------------------------------------------------------------
	function W:SetState(newState, text)
		if not alive then
			return
		end
		state = newState
		status.Text = text or ""
		if newState == "error" then
			status.TextColor3 = HOVER_RED
			spin:Pause()
		else
			status.TextColor3 = DIM_TEXT
			spin:Play()
		end
		refreshBottom()
	end

	function W:GetPosition()
		return window.Position
	end

	function W:Close(instant)
		if not alive then
			return
		end
		alive = false
		spin:Cancel()
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		if instant then
			gui:Destroy()
		else
			TweenService:Create(window, LEAVE, { GroupTransparency = 1 }):Play()
			TweenService:Create(windowScale, LEAVE, { Scale = fitScale * 0.94 }):Play()
			task.delay(LEAVE.Time + 0.03, function()
				gui:Destroy()
			end)
		end
	end

	---------------------------------------------------------------------
	-- INTRO: window pops in, then each part fades up one after the other
	---------------------------------------------------------------------
	paintButton()
	refreshBottom()

	TweenService:Create(window, SMOOTH, { GroupTransparency = 0 }):Play()
	TweenService:Create(windowScale, POP, { Scale = fitScale }):Play()

	for i = 1, #sections do
		local s = sections[i]
		local base = s.pos
		s.group.Position = base + UDim2.fromOffset(0, 12)
		task.delay(0.08 + (i - 1) * 0.07, function()
			if alive then
				TweenService:Create(s.group, SMOOTH, { Position = base, GroupTransparency = 0 }):Play()
			end
		end)
	end

	-- the wait: Continue can only show after WAIT_SECONDS, even if everything is loaded sooner
	task.delay(WAIT_SECONDS, function()
		if alive then
			waitDone = true
			refreshBottom()
		end
	end)

	---------------------------------------------------------------------
	-- exact creation date from the Roblox users API (needs an executor request function)
	---------------------------------------------------------------------
	task.spawn(function()
		local req = (syn and syn.request) or (http and http.request) or http_request or request
		if not req then
			return
		end
		local ok, res = pcall(function()
			return req({ Url = "https://users.roblox.com/v1/users/" .. tostring(player.UserId), Method = "GET" })
		end)
		if not ok or not res or res.StatusCode ~= 200 then
			return
		end
		local okJ, data = pcall(function()
			return HttpService:JSONDecode(res.Body)
		end)
		if not okJ or type(data) ~= "table" or type(data.created) ~= "string" then
			return
		end
		local ys, ms, ds = string.match(data.created, "^(%d+)-(%d+)-(%d+)")
		if not ys then
			return
		end
		local y = tonumber(ys)
		local m = tonumber(ms)
		local d = tonumber(ds)
		if not y or not m or not d or not alive then
			return
		end
		createdValue.Text = formatDate(m, d, y)
		local okT, t = pcall(function()
			return os.time({ year = y, month = m, day = d, hour = 12 })
		end)
		if okT and t then
			local exact = math.max(0, math.floor((os.time() - t) / 86400))
			ageValue.Text = formatAge(exact)
			ageCaption.Text = "Account Age (" .. exact .. " days)"
		end
	end)

	return W
end

return Welcome
