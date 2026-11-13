-- Auth.lua  (key + account creation page, then login page; runs BEFORE Welcome.lua)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Layout: one centered column. The logo sits on top, then the two-tab switch (Create account | Log in)
-- and the form. A small notification card pops up at the bottom right of the screen. Two pages in one window:
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
--       Title = "yur1",                                      -- last character is drawn in white, the rest in red
--       ApiUrl = "https://xxxx.supabase.co/functions/v1/",   -- must end with a slash
--       OnSuccess = function(session, position) end,         -- session = { token, username, expires_at, hwid }
--       OnClose = function() end,                            -- only fires if you call auth:Close(false) yourself
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
	-- THEME
	---------------------------------------------------------------------
	local BG         = Color3.fromRGB(35, 35, 35)     -- window background (from the screenshot)
	local BLACK      = Color3.fromRGB(10, 10, 11)     -- dark text on light buttons
	local BORDER     = Color3.fromRGB(58, 58, 58)
	local CLUSTER_BG = Color3.fromRGB(45, 45, 45)     -- fields + tab bar
	local TOAST_BG   = Color3.fromRGB(26, 26, 26)
	local ICON       = Color3.fromRGB(176, 176, 182)
	local HOVER_RED  = Color3.fromRGB(214, 62, 62)    -- error text
	local TEXT_COLOR = Color3.fromRGB(230, 230, 234)
	local DIM_TEXT   = Color3.fromRGB(128, 128, 134)
	local JOIN_BG    = Color3.fromRGB(232, 232, 236)
	local GOOD       = Color3.fromRGB(110, 200, 140)
	local CALM_RED   = Color3.fromRGB(196, 92, 92)    -- "yur" in the logo

	local RADIUS = 4

	local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local SMOOTH = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local POP = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local LEAVE = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

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
	local WIN_W = 380
	local WIN_H = 440
	local HEAD_H = 104 -- the logo + subtitle area on top

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
		BackgroundColor3 = BG,
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

	-- TOP: the logo, centered. "yur" in a calm red, the last character (the 1) keeps the white gradient
	local titleHead = string.sub(title, 1, -2)
	local titleTail = string.sub(title, -1)

	local titleRow = new("Frame", {
		Name = "Logo",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.fromOffset(0, 48),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, window)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, titleRow)

	local function logoPart(text, order, color)
		return new("TextLabel", {
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 48),
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Enum.Font.GothamBlack,
			Text = text,
			TextSize = 42,
			TextColor3 = color,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 3,
		}, titleRow)
	end

	logoPart(titleHead, 1, CALM_RED)
	local oneLabel = logoPart(titleTail, 2, Color3.new(1, 1, 1))
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 138)),
		}),
	}, oneLabel)

	local subtitle = label(window, "", UDim2.fromOffset(28, 72), UDim2.new(1, -56, 0, 16),
		Enum.Font.Gotham, 12, DIM_TEXT, Enum.TextXAlignment.Center)
	subtitle.ZIndex = 3

	-- the form column
	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(28, HEAD_H),
		Size = UDim2.new(1, -56, 1, -(HEAD_H + 20)),
		BackgroundTransparency = 1,
	}, window)

	-- two-tab switch: a light pill slides between "Create account" and "Log in"
	local tabs = new("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(0, 0),
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
	local FORM_Y = 50
	local formArea = new("Frame", {
		Name = "Form",
		Position = UDim2.fromOffset(0, FORM_Y),
		Size = UDim2.new(1, 0, 1, -FORM_Y),
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
			statusLine.Position = UDim2.fromOffset(0, FORM_Y + 184 + 38 + 10)
		else
			subtitle.Text = "Log in to continue"
			statusLine.Position = UDim2.fromOffset(0, FORM_Y + 126 + 38 + 10)
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
					hideToast()
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

	---------------------------------------------------------------------
	-- NOTIFICATION (bottom right of the screen)
	---------------------------------------------------------------------
	local TOAST_W = 330
	local TOAST_H = 92
	local toast = new("Frame", {
		Name = "Notice",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, TOAST_W + 40, 1, -18),
		Size = UDim2.fromOffset(TOAST_W, TOAST_H),
		BackgroundColor3 = TOAST_BG,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, gui)
	corner(toast, 10)
	stroke(toast, BORDER, 1, 0)

	-- icon: a small fingerprint made of rings, with a gap cut through them
	local iconBox = new("Frame", {
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		ZIndex = 51,
	}, toast)
	local ringSizes = { 32, 25, 18, 11 }
	for i = 1, #ringSizes do
		local r = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(ringSizes[i], ringSizes[i]),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 51,
		}, iconBox)
		corner(r, 100)
		stroke(r, ICON, 1.5, 0)
	end
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 4, 0.5, 2),
		Size = UDim2.fromOffset(3, 18),
		BackgroundColor3 = TOAST_BG,
		BorderSizePixel = 0,
		ZIndex = 52,
	}, iconBox)

	local tTitle = label(toast, "Reruinz Server Auth", UDim2.fromOffset(64, 12), UDim2.new(1, -78, 0, 16),
		Enum.Font.GothamBold, 12, DIM_TEXT)
	tTitle.ZIndex = 51
	local tBody = label(toast, "Dont attempt to do anything silly because its not worth the pain",
		UDim2.fromOffset(64, 30), UDim2.new(1, -78, 0, 34), Enum.Font.GothamMedium, 13, TEXT_COLOR)
	tBody.TextWrapped = true
	tBody.TextTruncate = Enum.TextTruncate.None
	tBody.TextYAlignment = Enum.TextYAlignment.Top
	tBody.ZIndex = 51
	local tFoot = label(toast, "rock and roll", UDim2.fromOffset(64, 68), UDim2.new(1, -78, 0, 16),
		Enum.Font.Gotham, 12, DIM_TEXT)
	tFoot.ZIndex = 51

	local function hideToast()
		TweenService:Create(toast, LEAVE, { Position = UDim2.new(1, TOAST_W + 40, 1, -18) }):Play()
	end

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
			hideToast()
			task.delay(LEAVE.Time + 0.03, function()
				gui:Destroy()
			end)
		end
	end

	-- intro
	TweenService:Create(window, SMOOTH, { GroupTransparency = 0 }):Play()
	TweenService:Create(windowScale, POP, { Scale = fitScale }):Play()
	task.delay(0.35, function()
		if alive then
			TweenService:Create(toast, SMOOTH, { Position = UDim2.new(1, -18, 1, -18) }):Play()
		end
	end)

	return W
end

return Auth
