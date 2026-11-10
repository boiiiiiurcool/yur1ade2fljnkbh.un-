-- Auth.lua  (key + account creation page, then login page; runs BEFORE Welcome.lua)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Same look as Welcome.lua / ui.lua. Layout: a side panel on the left (logo + short facts) and the form
-- on the right with a two-tab switch (Create account | Log in) on top. Two pages in one window:
--   KEY page    Key + Username + Password -> "Create account"
--               The server checks the key (it must exist, be unused and not revoked), makes the account
--               and marks the key as used. Then the window goes to the LOGIN page.
--   LOGIN page  Username + Password -> "Log in"
--               The server checks the password and the HWID. The first time an account logs in, the
--               HWID of that device is saved on the account; from then on only that device can log in.
--
-- Nothing is checked on this device: every decision is made by the website (the Lovable server).
-- This file only shows the UI and sends two requests:
--   POST <ApiUrl>register   { key, username, password, hwid }
--   POST <ApiUrl>login      { username, password, hwid }
-- Every answer is JSON: { ok = true/false, message = "...", token = "...", username = "...", expires_at = "..." }
--
--   local auth = Auth.new({
--       Name = "Y1Auth",
--       Title = "yur1",
--       ApiUrl = "https://xxxx.supabase.co/functions/v1/",   -- must end with a slash
--       OnSuccess = function(session, position) end,         -- session = { token, username, expires_at, hwid }
--       OnClose = function() end,                            -- the X was pressed
--   })
--   auth:Close(instant)

local Auth = {}

function Auth.new(opts)
	opts = opts or {}
	local guiName = opts.Name or "Y1Auth"
	local title = opts.Title or "yur1"
	local API = opts.ApiUrl or ""
	-- optional: full URLs per endpoint, for when register / login do not share one base url
	local EP = opts.Endpoints or {}

	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local HttpService = game:GetService("HttpService")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- only one auth window at a time
	do
		local old = playerGui:FindFirstChild(guiName)
		if old then
			old:Destroy()
		end
	end

	local W = {}
	local alive = true
	local busy = false
	local finished = false
	local page = "key"

	---------------------------------------------------------------------
	-- THEME (same colours as Welcome.lua)
	---------------------------------------------------------------------
	local BLACK      = Color3.fromRGB(10, 10, 11)
	local BORDER     = Color3.fromRGB(36, 36, 39)
	local CLUSTER_BG = Color3.fromRGB(30, 30, 33)
	local ICON       = Color3.fromRGB(176, 176, 182)
	local ICON_HOVER = Color3.fromRGB(240, 240, 244)
	local HOVER_RED  = Color3.fromRGB(214, 62, 62)
	local TEXT_COLOR = Color3.fromRGB(230, 230, 234)
	local DIM_TEXT   = Color3.fromRGB(116, 116, 124)
	local JOIN_BG    = Color3.fromRGB(232, 232, 236)
	local GOOD       = Color3.fromRGB(110, 200, 140)

	local RADIUS = 4
	local PANEL_BG = Color3.fromRGB(17, 17, 19)

	local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local SMOOTH = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local POP = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local LEAVE = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

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
	-- HWID + HTTP
	---------------------------------------------------------------------
	-- the id of this device: the executor's own id when it has one, else Roblox's client id
	local function getHwid()
		local id = nil
		local ok, res = pcall(function()
			if type(gethwid) == "function" then
				return gethwid()
			end
			return nil
		end)
		if ok and type(res) == "string" and res ~= "" then
			id = res
		end
		if id == nil then
			local ok2, res2 = pcall(function()
				return game:GetService("RbxAnalyticsService"):GetClientId()
			end)
			if ok2 and type(res2) == "string" and res2 ~= "" then
				id = res2
			end
		end
		return id
	end

	local function httpRequest()
		return (syn and syn.request) or (http and http.request) or http_request or request
	end

	-- sends a POST to the server and returns the decoded answer table (never throws)
	local function post(path, data)
		local req = httpRequest()
		if req == nil then
			return { ok = false, message = "This executor cannot send web requests." }
		end
		local okSend, res = pcall(function()
			return req({
				Url = EP[path] or (API .. path),
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode(data),
			})
		end)
		if not okSend or type(res) ~= "table" then
			return { ok = false, message = "Could not reach the server. Try again." }
		end
		local body = res.Body
		if type(body) ~= "string" or body == "" then
			return { ok = false, message = "The server sent an empty answer (" .. tostring(res.StatusCode) .. ")." }
		end
		local okDec, decoded = pcall(function()
			return HttpService:JSONDecode(body)
		end)
		if not okDec or type(decoded) ~= "table" then
			return { ok = false, message = "The server sent an answer that could not be read." }
		end
		return decoded
	end

	---------------------------------------------------------------------
	-- WINDOW
	---------------------------------------------------------------------
	local WIN_W = 560
	local WIN_H = 360
	local BAR_H = 34

	local gui = new("ScreenGui", {
		Name = guiName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 1001,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

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

	local bar = new("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundTransparency = 1,
	}, window)

	-- close button (top right)
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

		local function paint(isOver)
			local bgT = 1
			if isOver then
				bgT = 0
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
			paint(true)
		end)
		closeBtn.MouseLeave:Connect(function()
			paint(false)
		end)
	end

	-- LEFT: side panel with the logo, what the page is for, and three short facts
	local PANEL_W = 190
	local panel = new("Frame", {
		Name = "Panel",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(0, PANEL_W, 1, -12),
		BackgroundColor3 = PANEL_BG,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, window)
	corner(panel, RADIUS + 2)
	stroke(panel, BORDER, 1, 0)

	local titleLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 48),
		Font = Enum.Font.GothamBlack,
		Text = title,
		TextSize = 38,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
	}, panel)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 138)),
		}),
	}, titleLabel)

	local subtitle = label(panel, "", UDim2.fromOffset(18, 90), UDim2.new(1, -36, 0, 36),
		Enum.Font.Gotham, 12, ICON, Enum.TextXAlignment.Center)
	subtitle.TextWrapped = true
	subtitle.TextTruncate = Enum.TextTruncate.None
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.ZIndex = 3

	new("Frame", {
		Position = UDim2.fromOffset(28, 150),
		Size = UDim2.new(1, -56, 0, 1),
		BackgroundColor3 = BORDER,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, panel)

	local facts = {
		"You deserve the best from us",
		"Dont crack this",
		"Powered by reruinz server auth",
	}
	for i = 1, #facts do
		local ft = label(panel, facts[i], UDim2.fromOffset(18, 168 + (i - 1) * 28), UDim2.new(1, -36, 0, 20),
			Enum.Font.GothamMedium, 12, DIM_TEXT, Enum.TextXAlignment.Center)
		ft.ZIndex = 3
	end

	-- RIGHT: the form
	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(PANEL_W + 6 + 18, BAR_H),
		Size = UDim2.new(1, -(PANEL_W + 6 + 18 + 18), 1, -(BAR_H + 18)),
		BackgroundTransparency = 1,
	}, window)

	-- two-tab switch: a light pill slides between "Create account" and "Log in"
	local tabs = new("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = CLUSTER_BG,
		BorderSizePixel = 0,
	}, content)
	corner(tabs, 10)

	local indicator = new("Frame", {
		Position = UDim2.new(0, 3, 0, 3),
		Size = UDim2.new(0.5, -4, 1, -6),
		BackgroundColor3 = JOIN_BG,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, tabs)
	corner(indicator, 8)

	local function makeTab(xScale, text)
		local b = new("TextButton", {
			AutoButtonColor = false,
			Position = UDim2.fromScale(xScale, 0),
			Size = UDim2.fromScale(0.5, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			Text = text,
			TextSize = 13,
			TextColor3 = ICON,
			ZIndex = 3,
		}, tabs)
		return b
	end
	local tabKey = makeTab(0, "Create account")
	local tabLogin = makeTab(0.5, "Log in")

	-- the message line (errors in red, good news in green); it sits under the button of each page
	local statusLine = new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = HOVER_RED,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, content)

	local function setStatus(text, good)
		statusLine.Text = text or ""
		if good then
			statusLine.TextColor3 = GOOD
		else
			statusLine.TextColor3 = HOVER_RED
		end
	end

	---------------------------------------------------------------------
	-- CONTROLS
	---------------------------------------------------------------------
	-- a labelled text field. masked = shows * instead of the text (the real text is kept in f.real)
	local function makeField(parent, y, caption, placeholder, masked)
		local f = { real = "" }
		local cap = label(parent, string.upper(caption), UDim2.fromOffset(2, y), UDim2.new(1, -4, 0, 14),
			Enum.Font.GothamMedium, 10, DIM_TEXT)
		cap.ZIndex = 3
		local box = new("TextBox", {
			Position = UDim2.fromOffset(0, y + 16),
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = TEXT_COLOR,
			PlaceholderText = placeholder,
			PlaceholderColor3 = DIM_TEXT,
			Text = "",
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, parent)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, box)
		corner(box, RADIUS + 2)
		local st = stroke(box, BORDER, 1, 0)
		f.box = box

		box.Focused:Connect(function()
			TweenService:Create(st, FAST, { Color = ICON }):Play()
			TweenService:Create(cap, FAST, { TextColor3 = ICON }):Play()
		end)
		box.FocusLost:Connect(function(enterPressed)
			TweenService:Create(st, FAST, { Color = BORDER }):Play()
			TweenService:Create(cap, FAST, { TextColor3 = DIM_TEXT }):Play()
			if enterPressed and f.onEnter then
				f.onEnter()
			end
		end)

		if masked then
			-- the box shows only stars. When the text changes we work out what was typed / deleted by
			-- comparing the stars at the start and the end, and keep the real password in f.real
			local guard = false
			box:GetPropertyChangedSignal("Text"):Connect(function()
				if guard then
					return
				end
				local t = box.Text
				local m = #f.real
				local n = #t
				local ms = math.min(m, n)
				local i = 0
				while i < ms and string.sub(t, i + 1, i + 1) == "*" do
					i = i + 1
				end
				local j = 0
				while j < ms - i and string.sub(t, n - j, n - j) == "*" do
					j = j + 1
				end
				local inserted = string.sub(t, i + 1, n - j)
				f.real = string.sub(f.real, 1, i) .. inserted .. string.sub(f.real, m - j + 1)
				local shown = string.rep("*", #f.real)
				if t ~= shown then
					guard = true
					box.Text = shown
					guard = false
				end
			end)
		end

		function f.get()
			if masked then
				return f.real
			end
			return box.Text
		end
		function f.clear()
			f.real = ""
			box.Text = ""
		end
		return f
	end

	local function makeButton(parent, y, text)
		local b = new("TextButton", {
			AutoButtonColor = false,
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundColor3 = JOIN_BG,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			Text = text,
			TextSize = 14,
			TextColor3 = BLACK,
		}, parent)
		corner(b, 8)
		local sc = new("UIScale", { Scale = 1 }, b)
		b.MouseEnter:Connect(function()
			TweenService:Create(b, FAST, { BackgroundColor3 = Color3.fromRGB(255, 255, 255) }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b, FAST, { BackgroundColor3 = JOIN_BG }):Play()
			TweenService:Create(sc, FAST, { Scale = 1 }):Play()
		end)
		b.MouseButton1Down:Connect(function()
			TweenService:Create(sc, FAST, { Scale = 0.98 }):Play()
		end)
		b.MouseButton1Up:Connect(function()
			TweenService:Create(sc, FAST, { Scale = 1 }):Play()
		end)
		return b
	end

	---------------------------------------------------------------------
	-- THE TWO PAGES
	---------------------------------------------------------------------
	local formArea = new("Frame", {
		Name = "Form",
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, content)
	local keyPage = new("Frame", {
		Name = "KeyPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, formArea)
	local loginPage = new("Frame", {
		Name = "LoginPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, formArea)

	-- KEY page: key, username, password, create account
	local kKey = makeField(keyPage, 0, "Key", "Y1-XXXX-XXXX-XXXX", false)
	local kUser = makeField(keyPage, 58, "Username", "Create a username", false)
	local kPass = makeField(keyPage, 116, "Password", "Create a password", true)
	local kBtn = makeButton(keyPage, 184, "Create account")

	-- LOGIN page: username, password, log in
	local lUser = makeField(loginPage, 0, "Username", "Your username", false)
	local lPass = makeField(loginPage, 58, "Password", "Your password", true)
	local lBtn = makeButton(loginPage, 126, "Log in")

	-- Enter jumps to the next field (the last one submits, see below)
	kKey.onEnter = function()
		kUser.box:CaptureFocus()
	end
	kUser.onEnter = function()
		kPass.box:CaptureFocus()
	end
	lUser.onEnter = function()
		lPass.box:CaptureFocus()
	end

	local function paintTabs(animate)
		local isKey = (page == "key")
		local pos = UDim2.new(0, 3, 0, 3)
		if not isKey then
			pos = UDim2.new(0.5, 1, 0, 3)
		end
		if animate then
			TweenService:Create(indicator, SMOOTH, { Position = pos }):Play()
		else
			indicator.Position = pos
		end
		local onC = BLACK
		local offC = ICON
		TweenService:Create(tabKey, FAST, { TextColor3 = isKey and onC or offC }):Play()
		TweenService:Create(tabLogin, FAST, { TextColor3 = isKey and offC or onC }):Play()
	end

	local function showPage(name, animate)
		page = name
		keyPage.Visible = (name == "key")
		loginPage.Visible = (name == "login")
		if name == "key" then
			subtitle.Text = "Enter your key and create your account"
			statusLine.Position = UDim2.fromOffset(0, 56 + 184 + 38 + 10)
		else
			subtitle.Text = "Log in to continue"
			statusLine.Position = UDim2.fromOffset(0, 56 + 126 + 38 + 10)
		end
		paintTabs(animate)
	end
	showPage("key", false)

	---------------------------------------------------------------------
	-- ACTIONS
	---------------------------------------------------------------------
	local function setBusy(b, btn, idleText, busyText)
		busy = b
		if b then
			btn.Text = busyText
			btn.TextTransparency = 0.4
		else
			btn.Text = idleText
			btn.TextTransparency = 0
		end
	end

	local function trim(s)
		return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
	end

	local function doRegister()
		if busy or not alive or finished then
			return
		end
		local key = string.upper((string.gsub(kKey.get(), "%s", "")))
		local user = trim(kUser.get())
		local pass = kPass.get()
		if key == "" then
			setStatus("Enter your key.")
			return
		end
		if #user < 3 or #user > 20 or string.find(user, "[^%w_]") then
			setStatus("Username: 3-20 letters, numbers or _")
			return
		end
		if #pass < 6 then
			setStatus("Password must be at least 6 characters.")
			return
		end
		local hwid = getHwid()
		if hwid == nil then
			setStatus("Could not read this device's HWID.")
			return
		end
		setStatus("")
		setBusy(true, kBtn, "Create account", "Please wait...")
		task.spawn(function()
			local res = post("register", { key = key, username = user, password = pass, hwid = hwid })
			if not alive then
				return
			end
			setBusy(false, kBtn, "Create account", "Please wait...")
			if res.ok then
				-- account made: go to the login page with the username filled in
				lUser.box.Text = user
				lPass.clear()
				kKey.clear()
				kUser.clear()
				kPass.clear()
				showPage("login", true)
				setStatus("Account created! Now log in.", true)
			else
				setStatus(tostring(res.message or "Could not create the account."))
			end
		end)
	end

	local function doLogin()
		if busy or not alive or finished then
			return
		end
		local user = trim(lUser.get())
		local pass = lPass.get()
		if user == "" or pass == "" then
			setStatus("Enter your username and password.")
			return
		end
		local hwid = getHwid()
		if hwid == nil then
			setStatus("Could not read this device's HWID.")
			return
		end
		setStatus("")
		setBusy(true, lBtn, "Log in", "Logging in...")
		task.spawn(function()
			local res = post("login", { username = user, password = pass, hwid = hwid })
			if not alive then
				return
			end
			setBusy(false, lBtn, "Log in", "Logging in...")
			if res.ok and type(res.token) == "string" and res.token ~= "" then
				finished = true
				setStatus("Welcome, " .. tostring(res.username or user) .. "!", true)
				local session = {
					token = res.token,
					username = res.username or user,
					expires_at = res.expires_at,
					hwid = hwid,
				}
				local leavePos = window.Position
				task.delay(0.6, function()
					if not alive then
						return
					end
					TweenService:Create(window, LEAVE, { GroupTransparency = 1 }):Play()
					TweenService:Create(windowScale, LEAVE, { Scale = fitScale * 0.94 }):Play()
					task.delay(LEAVE.Time + 0.03, function()
						if not alive then
							return
						end
						local cb = opts.OnSuccess
						W:Close(true)
						if cb then
							local okCb, err = pcall(cb, session, leavePos)
							if not okCb then
								warn("[auth] OnSuccess error: " .. tostring(err))
							end
						end
					end)
				end)
			else
				lPass.clear()
				setStatus(tostring(res.message or "Login failed."))
			end
		end)
	end

	kBtn.Activated:Connect(doRegister)
	lBtn.Activated:Connect(doLogin)
	kPass.onEnter = doRegister
	lPass.onEnter = doLogin

	tabKey.Activated:Connect(function()
		if busy or page == "key" then
			return
		end
		setStatus("")
		showPage("key", true)
	end)
	tabLogin.Activated:Connect(function()
		if busy or page == "login" then
			return
		end
		setStatus("")
		showPage("login", true)
	end)

	closeBtn.Activated:Connect(function()
		if not alive or finished then
			return
		end
		local cb = opts.OnClose
		W:Close(false)
		if cb then
			local okCb, err = pcall(cb)
			if not okCb then
				warn("[auth] OnClose error: " .. tostring(err))
			end
		end
	end)

	---------------------------------------------------------------------
	-- PUBLIC API
	---------------------------------------------------------------------
	function W:Close(instant)
		if not alive then
			return
		end
		alive = false
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

	-- intro
	TweenService:Create(window, SMOOTH, { GroupTransparency = 0 }):Play()
	TweenService:Create(windowScale, POP, { Scale = fitScale }):Play()

	return W
end

return Auth
