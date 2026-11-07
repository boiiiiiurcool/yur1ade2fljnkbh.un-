-- Welcome.lua  (welcome screen module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Same base layout as ui.lua: black window with tiny rounded corners, slim sidebar with the Y1 logo
-- and your picture, title card top left, close button top right, content area on the right.
-- In the content area: "yur1" on top, "Welcome to yur1", your profile card next to a game card
-- (current game name + icon), tiles for user ID, account age, creation date and role, and a
-- Continue button.
--
-- The window is draggable. When Continue is pressed, OnContinue receives the window's current
-- position (a UDim2) so the main window can open in the exact same spot.
--
--   local Welcome = <this file>
--   local welcome = Welcome.new({
--       Name = "Y1Welcome",
--       Title = "yur1",
--       Logo = "Y1",
--       ButtonText = "Continue",
--       DefaultRole = "Tester",
--       Roles = { [12345678] = "Owner" },
--       OnContinue = function(position) end,  -- position = UDim2 where the welcome window was
--       OnClose = function() end,
--   })
--   welcome:SetState("loading", "Loading modules...")
--   welcome:SetState("ready")
--   welcome:SetState("error", "Could not load")
--   welcome:GetPosition()                              -- current window position (UDim2)
--   welcome:Close(instant)                             -- closes it without running OnContinue

local Welcome = {}

function Welcome.new(opts)
	opts = opts or {}
	local guiName = opts.Name or "Y1Welcome"
	local title = opts.Title or "yur1"
	local logoName = opts.Logo or "Y1"
	local buttonText = opts.ButtonText or "Continue"
	local defaultRole = opts.DefaultRole or "Tester"

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
	local HOVER_GREY = Color3.fromRGB(66, 66, 72)
	local HOVER_RED  = Color3.fromRGB(214, 62, 62)
	local TEXT_COLOR = Color3.fromRGB(230, 230, 234)
	local DIM_TEXT   = Color3.fromRGB(116, 116, 124)
	local JOIN_BG    = Color3.fromRGB(232, 232, 236)
	local PILL_BG    = Color3.fromRGB(46, 46, 52)

	local RADIUS = 4
	local SQUARE_RADIUS = 10

	local ROLE_COLORS = {
		Tester = Color3.fromRGB(255, 190, 90),
		Owner = Color3.fromRGB(255, 110, 110),
		Admin = Color3.fromRGB(120, 170, 255),
		Developer = Color3.fromRGB(52, 199, 120),
	}

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
	-- WINDOW (same base as ui.lua)
	---------------------------------------------------------------------
	local WIN_W = 760
	local WIN_H = 480
	local BAR_H = 40
	local SIDEBAR_W = 56
	local TILE = 40
	local CHIP_X = SIDEBAR_W + 14
	local CHIP_W = 128
	local CONTENT_W = WIN_W - (SIDEBAR_W + 18)
	local BTN_W = 320
	local BTN_H = 46
	if touch then
		BTN_H = 54
	end
	local STATUS_H = 14

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

	-- top bar (drag handle + close button)
	local bar = new("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundTransparency = 1,
	}, window)

	-- sidebar: Y1 logo on top, your picture at the bottom
	local sidebar = new("Frame", {
		Name = "Sidebar",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(0, SIDEBAR_W, 1, -12),
		BackgroundColor3 = SIDEBAR_BG,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, window)
	corner(sidebar)

	do
		local logo = new("Frame", {
			Name = "Logo",
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.fromOffset(TILE, 32),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, window)
		local logoLabel = new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 30),
			Font = Enum.Font.GothamBlack,
			Text = logoName,
			TextSize = 24,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 4,
		}, logo)
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 138)),
			}),
		}, logoLabel)

		local tile = new("Frame", {
			Name = "ProfileTile",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 14, 1, -14),
			Size = UDim2.fromOffset(TILE, TILE),
			BackgroundColor3 = CARD_BG,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, window)
		corner(tile, SQUARE_RADIUS)
		local tileImg = new("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = CARD_BG,
			BorderSizePixel = 0,
			Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150",
			ZIndex = 4,
		}, tile)
		corner(tileImg, SQUARE_RADIUS)
	end

	-- title card (top left), same as the "Tab / <page>" card in ui.lua
	do
		local titleChip = new("Frame", {
			Name = "TitleCard",
			Position = UDim2.fromOffset(CHIP_X, 6),
			Size = UDim2.fromOffset(CHIP_W, 36),
			BackgroundColor3 = SIDEBAR_BG,
			BorderSizePixel = 0,
		}, window)
		corner(titleChip, RADIUS + 2)
		label(titleChip, "Tab", UDim2.fromOffset(12, 5), UDim2.new(1, -24, 0, 12),
			Enum.Font.Gotham, 11, DIM_TEXT)
		label(titleChip, "Welcome", UDim2.fromOffset(12, 18), UDim2.new(1, -24, 0, 16),
			Enum.Font.GothamMedium, 13, TEXT_COLOR)
	end

	-- close button (top right), same look as the control cluster in ui.lua
	local closeBtn = nil
	do
		local PAD = 3
		local bw = 30
		local bh = 24
		if touch then
			bw = 40
			bh = 30
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
				Size = UDim2.fromOffset(14, 2),
				Rotation = rot,
				BackgroundColor3 = ICON,
				BorderSizePixel = 0,
			}, closeBtn)
			corner(f, 1)
			table.insert(parts, f)
		end
		line(45)
		line(-45)

		local hovering = false
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
			hovering = true
			paint(true, false)
		end)
		closeBtn.MouseLeave:Connect(function()
			hovering = false
			paint(false, false)
		end)
		closeBtn.MouseButton1Down:Connect(function()
			paint(true, true)
		end)
		closeBtn.MouseButton1Up:Connect(function()
			paint(hovering, false)
		end)
	end

	-- content area, same position and size as in ui.lua
	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(SIDEBAR_W + 12, BAR_H),
		Size = UDim2.new(1, -(SIDEBAR_W + 18), 1, -(BAR_H + 6)),
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
	local header = makeSection(0, 14, CONTENT_W, 108, false)

	local titleLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 52),
		Font = Enum.Font.GothamBlack,
		Text = title,
		TextSize = 46,
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

	label(header, "Welcome to " .. title, UDim2.fromOffset(0, 56), UDim2.new(1, 0, 0, 22),
		Enum.Font.GothamMedium, 17, TEXT_COLOR, Enum.TextXAlignment.Center)
	label(header, "Drag this window anywhere - the menu opens where you leave it", UDim2.fromOffset(0, 82), UDim2.new(1, 0, 0, 16),
		Enum.Font.Gotham, 12, DIM_TEXT, Enum.TextXAlignment.Center)

	-- ===== profile card (left) + game card (right) =====
	local profile = makeSection(2, 132, CONTENT_W - 4, 88, true)

	local profCard = new("Frame", {
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = SIDEBAR_BG,
		BorderSizePixel = 0,
	}, profile)
	corner(profCard, SQUARE_RADIUS)
	stroke(profCard, BORDER, 1, 0)

	local avatar = new("ImageLabel", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = CARD_BG,
		BorderSizePixel = 0,
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150",
	}, profCard)
	corner(avatar, 14)

	label(profCard, player.DisplayName, UDim2.fromOffset(92, 18), UDim2.new(1, -104, 0, 24),
		Enum.Font.GothamBold, 18, TEXT_COLOR)
	label(profCard, "@" .. player.Name, UDim2.fromOffset(92, 46), UDim2.new(1, -104, 0, 18),
		Enum.Font.Gotham, 13, DIM_TEXT)

	local gameCard = new("Frame", {
		Position = UDim2.new(0.5, 4, 0, 0),
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = SIDEBAR_BG,
		BorderSizePixel = 0,
	}, profile)
	corner(gameCard, SQUARE_RADIUS)
	stroke(gameCard, BORDER, 1, 0)

	local gameIcon = new("ImageLabel", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = CARD_BG,
		BorderSizePixel = 0,
		Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=256&h=256",
	}, gameCard)
	corner(gameIcon, 14)

	label(gameCard, "Current game", UDim2.fromOffset(92, 14), UDim2.new(1, -104, 0, 14),
		Enum.Font.Gotham, 11, DIM_TEXT)
	local gameNameLabel = label(gameCard, game.Name, UDim2.fromOffset(92, 30), UDim2.new(1, -104, 0, 22),
		Enum.Font.GothamBold, 16, TEXT_COLOR)
	label(gameCard, "Place ID: " .. tostring(game.PlaceId), UDim2.fromOffset(92, 56), UDim2.new(1, -104, 0, 16),
		Enum.Font.Gotham, 12, DIM_TEXT)

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

	-- ===== info tiles in one row: user ID, account age, creation date, role =====
	local tilesGroup = makeSection(2, 234, CONTENT_W - 4, 60, true)
	local TILE_W = (CONTENT_W - 4 - 24) / 4

	local function makeTile(index, caption)
		local f = new("Frame", {
			Position = UDim2.fromOffset((index - 1) * (TILE_W + 8), 0),
			Size = UDim2.fromOffset(TILE_W, 60),
			BackgroundColor3 = SIDEBAR_BG,
			BorderSizePixel = 0,
		}, tilesGroup)
		corner(f, RADIUS + 4)
		stroke(f, BORDER, 1, 0)
		local cap = label(f, caption, UDim2.fromOffset(12, 10), UDim2.new(1, -24, 0, 12),
			Enum.Font.Gotham, 11, DIM_TEXT)
		return f, cap
	end

	local function tileValue(tile, text)
		return label(tile, text, UDim2.fromOffset(12, 29), UDim2.new(1, -24, 0, 18),
			Enum.Font.GothamMedium, 13, TEXT_COLOR)
	end

	local idTile = makeTile(1, "User ID")
	tileValue(idTile, tostring(player.UserId))

	local ageTile, ageCaption = makeTile(2, "Account Age (" .. days .. " days)")
	local ageValue = tileValue(ageTile, formatAge(days))

	local createdTile = makeTile(3, "Created")
	local createdValue = tileValue(createdTile, createdText)

	local roleTile = makeTile(4, "Role")
	do
		local roleColor = ROLE_COLORS[role] or ICON_HOVER
		local okSz, sz = pcall(function()
			return game:GetService("TextService"):GetTextSize(role, 12, Enum.Font.GothamMedium, Vector2.new(1000, 20))
		end)
		local textW = #role * 7
		if okSz and sz then
			textW = math.ceil(sz.X)
		end
		local pill = new("Frame", {
			Position = UDim2.fromOffset(12, 28),
			Size = UDim2.fromOffset(textW + 32, 20),
			BackgroundColor3 = PILL_BG,
			BorderSizePixel = 0,
		}, roleTile)
		corner(pill, 100)
		local dot = new("Frame", {
			Position = UDim2.fromOffset(9, 6),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = roleColor,
			BorderSizePixel = 0,
		}, pill)
		corner(dot, 100)
		new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -26, 1, 0),
			Font = Enum.Font.GothamMedium,
			Text = role,
			TextSize = 12,
			TextColor3 = TEXT_COLOR,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, pill)
	end

	-- ===== continue button + status line =====
	local btnSection = makeSection((CONTENT_W - BTN_W) / 2, 322, BTN_W, BTN_H + 8 + STATUS_H, false)

	local btn = new("TextButton", {
		Name = "Continue",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, BTN_H),
		BackgroundColor3 = CLUSTER_BG,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = "Loading...",
		TextSize = 15,
		TextColor3 = DIM_TEXT,
	}, btnSection)
	corner(btn, 8)
	local btnScale = new("UIScale", { Scale = 1 }, btn)

	-- rounded chevron drawn with two bars (same style as the arrows in the main window)
	local chev = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -28, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		Visible = false,
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

	local status = label(btnSection, "", UDim2.fromOffset(0, BTN_H + 8), UDim2.new(1, 0, 0, STATUS_H),
		Enum.Font.Gotham, 11, DIM_TEXT, Enum.TextXAlignment.Center)

	---------------------------------------------------------------------
	-- BUTTON STATES
	---------------------------------------------------------------------
	local hovering = false
	local pulse = nil

	local function paintButton()
		local bg = CLUSTER_BG
		local tc = DIM_TEXT
		local txt = "Loading..."
		if state == "ready" then
			txt = buttonText
			tc = BLACK
			bg = JOIN_BG
			if hovering then
				bg = Color3.fromRGB(255, 255, 255)
			end
		elseif state == "error" then
			txt = "Could not load"
			tc = HOVER_RED
		end
		btn.Text = txt
		TweenService:Create(btn, FAST, { BackgroundColor3 = bg, TextColor3 = tc }):Play()

		chev.Visible = (state == "ready")
		local cx = -28
		if state == "ready" and hovering then
			cx = -24
		end
		TweenService:Create(chev, SPRING, { Position = UDim2.new(1, cx, 0.5, 0) }):Play()

		-- the text pulses while loading
		if pulse then
			pulse:Cancel()
			pulse = nil
			btn.TextTransparency = 0
		end
		if state == "loading" then
			pulse = TweenService:Create(btn, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.55 })
			pulse:Play()
		end
	end

	-- leavePos = where the window was when Continue was pressed
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
		if not alive or continued or state ~= "ready" then
			return
		end
		continued = true
		-- remember the spot before anything else happens
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
		if state == "ready" then
			paintButton()
			TweenService:Create(btnScale, SPRING, { Scale = 1.02 }):Play()
		end
	end)
	btn.MouseLeave:Connect(function()
		hovering = false
		if state == "ready" then
			paintButton()
		end
		TweenService:Create(btnScale, SPRING, { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		if state == "ready" then
			TweenService:Create(btnScale, FAST, { Scale = 0.96 }):Play()
		end
	end)
	btn.MouseButton1Up:Connect(function()
		local s = 1
		if hovering and state == "ready" then
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

	-- Enter also continues
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			doContinue()
		end
	end))

	---------------------------------------------------------------------
	-- DRAG (top bar or the empty sidebar, like ui.lua)
	---------------------------------------------------------------------
	local dragging = false
	local dragStart = nil
	local startPos = nil

	local function bindDrag(handle)
		handle.InputBegan:Connect(function(input)
			if continued then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPos = window.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
					end
				end)
			end
		end)
	end
	bindDrag(bar)
	bindDrag(sidebar)

	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		if not dragging or continued then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Position - dragStart
			window.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
		end
	end))

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
		else
			status.TextColor3 = DIM_TEXT
		end
		paintButton()
	end

	function W:GetPosition()
		return window.Position
	end

	function W:Close(instant)
		if not alive then
			return
		end
		alive = false
		if pulse then
			pulse:Cancel()
			pulse = nil
		end
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
