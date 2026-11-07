-- Welcome.lua  (welcome screen module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Shows before the main window, in the same Y1 look: "yur1" on top, "Welcome to yur1",
-- then your profile picture, display name, username, user ID, account age, creation date,
-- role (everybody is a Tester right now) and a Continue button.
--
--   local Welcome = <this file>
--   local welcome = Welcome.new({
--       Name = "Y1Welcome",
--       Title = "yur1",
--       ButtonText = "Continue",
--       DefaultRole = "Tester",             -- everybody is a Tester for now
--       Roles = { [12345678] = "Owner" },   -- optional: a different role for a specific user ID later
--       OnContinue = function() end,        -- runs after the welcome has faded out
--   })
--   welcome:SetState("loading", "Loading modules...")   -- Continue is disabled and pulses
--   welcome:SetState("ready")                           -- Continue works (Enter works too)
--   welcome:SetState("error", "Could not load")         -- Continue stays disabled
--   welcome:Close(instant)                              -- closes it without running OnContinue

local Welcome = {}

function Welcome.new(opts)
	opts = opts or {}
	local guiName = opts.Name or "Y1Welcome"
	local title = opts.Title or "yur1"
	local buttonText = opts.ButtonText or "Continue"
	local defaultRole = opts.DefaultRole or "Tester"

	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local HttpService = game:GetService("HttpService")
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
		c.CornerRadius = UDim.new(0, r or 4)
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
	-- WINDOW
	---------------------------------------------------------------------
	local WIN_W = 420
	local HEADER_H = 126
	local PROF_Y = 132
	local PROF_H = 84
	local TILES_Y = 226
	local TILES_H = 112
	local BTN_Y = 354
	local BTN_H = 44
	if touch then
		BTN_H = 52
	end
	local STATUS_H = 14
	local WIN_H = BTN_Y + BTN_H + 8 + STATUS_H + 18

	local gui = new("ScreenGui", {
		Name = guiName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 1000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	-- dim backdrop (also keeps clicks from reaching the game)
	local dim = new("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 1,
	}, gui)

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
		ZIndex = 2,
	}, gui)
	corner(window, 4)
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
		corner(outline, 4)
		stroke(outline, BORDER, 1, 0)
	end

	-- each part of the window is its own canvas group so it can fade in on its own.
	-- groups with outlined children are 2px bigger with 2px padding so outlines are not cut off.
	local sections = {}
	local function makeSection(x, y, w, h, outlined)
		local g = new("CanvasGroup", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			GroupTransparency = 1,
		}, window)
		if outlined then
			g.Position = UDim2.fromOffset(x - 2, y - 2)
			g.Size = UDim2.fromOffset(w + 4, h + 4)
			pad(g, 2, 2, 2, 2)
		end
		table.insert(sections, { group = g, pos = g.Position })
		return g
	end

	-- ===== header: "yur1" on top, "Welcome to yur1" under it (also the drag handle) =====
	local header = makeSection(0, 0, WIN_W, HEADER_H, false)

	local logoLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 20),
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
	}, logoLabel)

	label(header, "Welcome to " .. title, UDim2.fromOffset(0, 78), UDim2.new(1, 0, 0, 22),
		Enum.Font.GothamMedium, 17, TEXT_COLOR, Enum.TextXAlignment.Center)
	label(header, "This is the account you are using", UDim2.fromOffset(0, 102), UDim2.new(1, 0, 0, 16),
		Enum.Font.Gotham, 12, DIM_TEXT, Enum.TextXAlignment.Center)

	-- ===== profile card: picture, display name, username =====
	local profile = makeSection(20, PROF_Y, WIN_W - 40, PROF_H, true)

	local profCard = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = SIDEBAR_BG,
		BorderSizePixel = 0,
	}, profile)
	corner(profCard, 12)
	stroke(profCard, BORDER, 1, 0)

	local avatar = new("ImageLabel", {
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = CARD_BG,
		BorderSizePixel = 0,
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150",
	}, profCard)
	corner(avatar, 14)

	label(profCard, player.DisplayName, UDim2.fromOffset(84, 16), UDim2.new(1, -96, 0, 22),
		Enum.Font.GothamBold, 17, TEXT_COLOR)
	label(profCard, "@" .. player.Name, UDim2.fromOffset(84, 40), UDim2.new(1, -96, 0, 18),
		Enum.Font.Gotham, 13, DIM_TEXT)

	-- ===== info tiles: user ID, account age, creation date, role =====
	local tilesGroup = makeSection(20, TILES_Y, WIN_W - 40, TILES_H, true)
	local TILE_W = (WIN_W - 40 - 8) / 2

	local function makeTile(x, y, caption)
		local f = new("Frame", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(TILE_W, 52),
			BackgroundColor3 = SIDEBAR_BG,
			BorderSizePixel = 0,
		}, tilesGroup)
		corner(f, 10)
		stroke(f, BORDER, 1, 0)
		local cap = label(f, caption, UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 12),
			Enum.Font.Gotham, 11, DIM_TEXT)
		return f, cap
	end

	local function tileValue(tile, text)
		return label(tile, text, UDim2.fromOffset(12, 25), UDim2.new(1, -24, 0, 18),
			Enum.Font.GothamMedium, 13, TEXT_COLOR)
	end

	local idTile = makeTile(0, 0, "User ID")
	tileValue(idTile, tostring(player.UserId))

	local ageTile, ageCaption = makeTile(TILE_W + 8, 0, "Account Age (" .. days .. " days)")
	local ageValue = tileValue(ageTile, formatAge(days))

	local createdTile = makeTile(0, 60, "Created")
	local createdValue = tileValue(createdTile, createdText)

	local roleTile = makeTile(TILE_W + 8, 60, "Role")
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
			Position = UDim2.fromOffset(12, 24),
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
	local btnSection = makeSection(20, BTN_Y, WIN_W - 40, BTN_H + 8 + STATUS_H, false)

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
	corner(btn, 100)
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

	local function leaveAndCallback()
		local cb = opts.OnContinue
		W:Close(true)
		if cb then
			local ok, err = pcall(cb)
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
		TweenService:Create(window, LEAVE, { GroupTransparency = 1 }):Play()
		TweenService:Create(windowScale, LEAVE, { Scale = fitScale * 0.94 }):Play()
		TweenService:Create(dim, LEAVE, { BackgroundTransparency = 1 }):Play()
		task.delay(LEAVE.Time + 0.03, function()
			if alive then
				leaveAndCallback()
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
	-- DRAG (by the header)
	---------------------------------------------------------------------
	local dragging = false
	local dragStart = nil
	local startPos = nil

	header.InputBegan:Connect(function(input)
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

	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		if not dragging then
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
			TweenService:Create(dim, LEAVE, { BackgroundTransparency = 1 }):Play()
			task.delay(LEAVE.Time + 0.03, function()
				gui:Destroy()
			end)
		end
	end

	---------------------------------------------------------------------
	-- INTRO: window pops in, then each part fades up one after the other
	---------------------------------------------------------------------
	paintButton()

	TweenService:Create(dim, SMOOTH, { BackgroundTransparency = 0.45 }):Play()
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
