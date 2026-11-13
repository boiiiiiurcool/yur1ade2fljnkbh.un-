-- Auth.lua  (key + account creation page, then login page; runs BEFORE Welcome.lua)
-- ASCII only, conservative syntax (no += and no continue).
--
-- One centered card: the logo on top, a two-tab switch (Create account | Log in) and the form.
-- Three pages in one window:
--   KEY page      Key (full width), then Username + Password side by side -> "Create account"
--                 The server checks the key (it must exist, be unused and not revoked), makes the account
--                 and marks the key as used. Then the window goes to the LOGIN page.
--   LOGIN page    Username + Password side by side -> "Log in"
--                 The server checks the password and the HWID. The first time an account logs in, the
--                 HWID of that device is saved on the account; from then on only that device can log in.
--   WELCOME page  Shown on load when this device already has a saved session (small, compact window).
--                 "Welcome back, We remembered who you are" + the account info + Continue / Log out.
--                 Continue -> OnSuccess. Log out -> the saved session is deleted and the KEY page shows.
--
-- ANTI TAMPERING
--   1. The saved session file is signed. The signature covers token, username, expiry and HWID, so
--      changing the name (or anything else) in the file makes the signature wrong. A session with a
--      wrong signature is deleted and the KEY page shows. A copy of the file from another device
--      fails too, because the HWID is part of the signature.
--   2. Verify = true makes "Continue" ask the server first (POST <ApiUrl>verify). The username and the
--      expiry shown and passed on come from the server's answer, never from the file. Revoked accounts
--      and revoked tokens stop working at once. This is the strong protection; the local signature
--      alone can be beaten by someone who edits this script, because the Secret is inside it.
--
-- Nothing is decided on this device: every decision is made by the website (the Lovable server).
-- This file only shows the UI and sends these requests:
--   POST <ApiUrl>register   { key, username, password, hwid }
--   POST <ApiUrl>login      { username, password, hwid }
--   POST <ApiUrl>verify     { token, username, hwid }      (only when Verify = true)
-- Every answer is JSON: { ok = true/false, message = "...", token = "...", username = "...", expires_at = "..." }
--
--   local auth = Auth.new({
--       Name = "Y1Auth",
--       Title = "yur1",                                      -- last character is drawn in white, the rest in red
--       ApiUrl = "https://xxxx.supabase.co/functions/v1/",   -- must end with a slash
--       SessionFile = "Y1Auth_session.json",                 -- optional, where the session is remembered
--       Secret = "change-this-to-your-own-random-text",      -- optional, used to sign the session file
--       Verify = true,                                       -- optional, on by default (false = skip the server check)
--       Endpoints = { verify = "https://..." },              -- optional, verify already defaults to yur1.lovable.app
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
	local SESSION_FILE = opts.SessionFile or "Y1Auth_session.json"
	local SECRET = opts.Secret or "y1-session-secret-change-me"
	local VERIFY = (opts.Verify ~= false) -- on by default, pass Verify = false to turn it off
	-- optional: full URLs per endpoint, for when register / login do not share one base url
	local EP = {
		verify = "https://yur1.lovable.app/api/public/verify",
	}
	if type(opts.Endpoints) == "table" then
		for k, v in pairs(opts.Endpoints) do
			EP[k] = v
		end
	end

	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
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
	local current = nil -- the remembered session shown on the welcome page

	---------------------------------------------------------------------
	-- THEME
	---------------------------------------------------------------------
	local BG         = Color3.fromRGB(35, 35, 35)     -- window background (flat, no gradient)
	local BLACK      = Color3.fromRGB(10, 10, 11)     -- dark text on the light button
	local WELL       = Color3.fromRGB(28, 28, 28)     -- recessed surfaces: fields + tab bar + info card
	local PILL       = Color3.fromRGB(54, 54, 56)     -- the sliding tab pill
	local BORDER     = Color3.fromRGB(54, 54, 54)
	local BORDER_HI  = Color3.fromRGB(78, 78, 80)     -- field border on hover
	local ICON       = Color3.fromRGB(176, 176, 182)
	local TEXT_COLOR = Color3.fromRGB(232, 232, 236)
	local DIM_TEXT   = Color3.fromRGB(122, 122, 128)
	local JOIN_BG    = Color3.fromRGB(232, 232, 236)
	local GOOD       = Color3.fromRGB(110, 200, 140)
	local BAD        = Color3.fromRGB(214, 90, 90)
	local CALM_RED   = Color3.fromRGB(196, 92, 92)    -- "yur" in the logo, focus ring

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
	-- REMEMBERED SESSION (saved in a signed file, never throws)
	---------------------------------------------------------------------
	-- a 64 bit keyed checksum (two 32 bit parts) over everything that matters in the session.
	-- Change any character of token, username, expiry or HWID and the signature no longer matches.
	local function sign(s)
		local str = tostring(s.token) .. "|" .. tostring(s.username) .. "|" .. tostring(s.expires_at)
			.. "|" .. tostring(s.hwid) .. "|" .. SECRET
		local h1 = 5381
		local h2 = 52711
		for i = 1, #str do
			local b = string.byte(str, i)
			h1 = (h1 * 131 + b + i) % 4294967291
			h2 = (h2 * 257 + b * (i % 7 + 1)) % 4294967279
		end
		return string.format("%08x%08x", h1, h2)
	end

	local function saveSession(session)
		pcall(function()
			if type(writefile) == "function" then
				local out = {
					token = session.token,
					username = session.username,
					expires_at = session.expires_at,
					hwid = session.hwid,
				}
				out.sig = sign(out)
				writefile(SESSION_FILE, HttpService:JSONEncode(out))
			end
		end)
	end

	local function clearSession()
		pcall(function()
			if type(isfile) == "function" and type(delfile) == "function" and isfile(SESSION_FILE) then
				delfile(SESSION_FILE)
			end
		end)
	end

	-- true when an ISO date like 2026-12-01T10:00:00Z is in the past (unreadable dates count as not expired)
	local function isExpired(stamp)
		if type(stamp) ~= "string" then
			return false
		end
		local y, mo, d, h, mi, s = string.match(stamp, "(%d+)-(%d+)-(%d+)[T ](%d+):(%d+):(%d+)")
		if y == nil then
			return false
		end
		local ok, res = pcall(function()
			local t = os.time({
				year = tonumber(y), month = tonumber(mo), day = tonumber(d),
				hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
			})
			local off = os.time(os.date("*t")) - os.time(os.date("!*t"))
			return (t + off) < os.time()
		end)
		if ok then
			return res
		end
		return false
	end

	-- returns the saved session when it is genuine and still good, else nil (and removes a bad file)
	-- second value: a short reason when a file was thrown away
	local function loadSession()
		local raw = nil
		local ok, res = pcall(function()
			if type(isfile) == "function" and type(readfile) == "function" and isfile(SESSION_FILE) then
				return readfile(SESSION_FILE)
			end
			return nil
		end)
		if ok and type(res) == "string" and res ~= "" then
			raw = res
		end
		if raw == nil then
			return nil, nil
		end
		local okDec, s = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if not okDec or type(s) ~= "table" or type(s.token) ~= "string" or s.token == ""
			or type(s.username) ~= "string" or s.username == "" or type(s.sig) ~= "string" then
			clearSession()
			return nil, "Saved login was damaged. Please log in again."
		end
		-- tamper check: the signature must match what is in the file
		if s.sig ~= sign(s) then
			clearSession()
			return nil, "Saved login was changed. Please log in again."
		end
		-- the file must belong to this device
		if s.hwid ~= getHwid() then
			clearSession()
			return nil, "Saved login is from another device. Please log in again."
		end
		if isExpired(s.expires_at) then
			clearSession()
			return nil, "Saved login expired. Please log in again."
		end
		return s, nil
	end

	---------------------------------------------------------------------
	-- WINDOW
	---------------------------------------------------------------------
	local WIN_W = 520
	local WIN_H = 430
	local SMALL_W = 400 -- the welcome page uses a smaller window
	local SMALL_H = 290
	local SIDE = 44
	local HEAD_H = 118 -- logo + subtitle area on top

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
	corner(window, 8)
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
		corner(outline, 7)
		stroke(outline, BORDER, 1, 0)
	end

	local function setWinSize(w, h, animate)
		local size = UDim2.fromOffset(w, h)
		if animate then
			TweenService:Create(window, SMOOTH, { Size = size }):Play()
		else
			window.Size = size
		end
	end

	-- LOGO: "yur" in a calm red, the last character (the 1) keeps the white gradient
	local titleHead = string.sub(title, 1, -2)
	local titleTail = string.sub(title, -1)

	local titleRow = new("Frame", {
		Name = "Logo",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 28),
		Size = UDim2.fromOffset(0, 52),
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
			Size = UDim2.fromOffset(0, 52),
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Enum.Font.GothamBlack,
			Text = text,
			TextSize = 46,
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

	local subtitle = label(window, "", UDim2.fromOffset(SIDE, 86), UDim2.new(1, -SIDE * 2, 0, 16),
		Enum.Font.GothamMedium, 12, DIM_TEXT, Enum.TextXAlignment.Center)
	subtitle.ZIndex = 3

	-- the form column
	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(SIDE, HEAD_H),
		Size = UDim2.new(1, -SIDE * 2, 1, -(HEAD_H + 20)),
		BackgroundTransparency = 1,
	}, window)

	-- two-tab switch: a pill slides between "Create account" and "Log in"
	local tabs = new("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = WELL,
		BorderSizePixel = 0,
	}, content)
	corner(tabs, 10)
	stroke(tabs, BORDER, 1, 0)

	local indicator = new("Frame", {
		Position = UDim2.new(0, 3, 0, 3),
		Size = UDim2.new(0.5, -5, 1, -6),
		BackgroundColor3 = PILL,
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
			TextColor3 = DIM_TEXT,
			ZIndex = 3,
		}, tabs)
		return b
	end
	local tabKey = makeTab(0, "Create account")
	local tabLogin = makeTab(0.5, "Log in")

	-- the message line (errors in red, good news in green); it sits under the button of each page
	local statusLine = new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 32),
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = BAD,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, content)

	-- a quick side-to-side shake of the window when something went wrong
	local function shake()
		task.spawn(function()
			local base = window.Position
			local offs = { 7, -7, 4, -4, 0 }
			for i = 1, #offs do
				if not alive or finished then
					return
				end
				local tw = TweenService:Create(window, TweenInfo.new(0.045, Enum.EasingStyle.Quad), {
					Position = UDim2.new(base.X.Scale, base.X.Offset + offs[i], base.Y.Scale, base.Y.Offset),
				})
				tw:Play()
				tw.Completed:Wait()
			end
		end)
	end

	local function setStatus(text, good)
		statusLine.Text = text or ""
		if good then
			statusLine.TextColor3 = GOOD
		else
			statusLine.TextColor3 = BAD
		end
		if text ~= nil and text ~= "" then
			statusLine.TextTransparency = 1
			TweenService:Create(statusLine, FAST, { TextTransparency = 0 }):Play()
			if not good then
				shake()
			end
		end
	end

	---------------------------------------------------------------------
	-- CONTROLS
	---------------------------------------------------------------------
	-- a labelled text field. masked = shows * instead of the text (the real text is kept in f.real)
	-- and gets a Show / Hide switch on the right
	-- col: nil = full width, "L" = left half, "R" = right half
	local function makeField(parent, y, caption, placeholder, masked, col)
		local f = { real = "", revealed = false }
		local xs = 0
		local xo = 0
		local ws = 1
		local wo = 0
		if col == "L" then
			xs = 0
			xo = 0
			ws = 0.5
			wo = -6
		elseif col == "R" then
			xs = 0.5
			xo = 6
			ws = 0.5
			wo = -6
		end
		local cap = label(parent, string.upper(caption), UDim2.new(xs, xo + 2, 0, y), UDim2.new(ws, wo - 4, 0, 14),
			Enum.Font.GothamMedium, 10, DIM_TEXT)
		cap.ZIndex = 3
		local box = new("TextBox", {
			Position = UDim2.new(xs, xo, 0, y + 16),
			Size = UDim2.new(ws, wo, 0, 38),
			BackgroundColor3 = WELL,
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
		local padRight = 14
		if masked then
			padRight = 58
		end
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, padRight) }, box)
		corner(box, 8)
		local st = stroke(box, BORDER, 1, 0)
		f.box = box

		local focused = false
		box.MouseEnter:Connect(function()
			if not focused then
				TweenService:Create(st, FAST, { Color = BORDER_HI }):Play()
			end
		end)
		box.MouseLeave:Connect(function()
			if not focused then
				TweenService:Create(st, FAST, { Color = BORDER }):Play()
			end
		end)
		box.Focused:Connect(function()
			focused = true
			TweenService:Create(st, FAST, { Color = CALM_RED }):Play()
			TweenService:Create(cap, FAST, { TextColor3 = ICON }):Play()
		end)
		box.FocusLost:Connect(function(enterPressed)
			focused = false
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
				if f.revealed then
					f.real = box.Text
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

			local eye = new("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 50, 0.5, 0),
				Size = UDim2.fromOffset(44, 24),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Font = Enum.Font.GothamMedium,
				Text = "Show",
				TextSize = 11,
				TextColor3 = DIM_TEXT,
			}, box)
			eye.MouseEnter:Connect(function()
				TweenService:Create(eye, FAST, { TextColor3 = TEXT_COLOR }):Play()
			end)
			eye.MouseLeave:Connect(function()
				TweenService:Create(eye, FAST, { TextColor3 = DIM_TEXT }):Play()
			end)
			eye.Activated:Connect(function()
				f.revealed = not f.revealed
				guard = true
				if f.revealed then
					box.Text = f.real
					eye.Text = "Hide"
				else
					box.Text = string.rep("*", #f.real)
					eye.Text = "Show"
				end
				guard = false
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

	-- col: nil = full width, "L" = left half, "R" = right half
	-- secondary = dark button with a border (used for "Log out")
	-- height: optional, default 42
	local function makeButton(parent, y, text, col, secondary, height)
		local xs = 0
		local xo = 0
		local ws = 1
		local wo = 0
		if col == "L" then
			ws = 0.5
			wo = -6
		elseif col == "R" then
			xs = 0.5
			xo = 6
			ws = 0.5
			wo = -6
		end
		local baseBg = JOIN_BG
		local hoverBg = Color3.fromRGB(255, 255, 255)
		local textC = BLACK
		if secondary then
			baseBg = WELL
			hoverBg = PILL
			textC = TEXT_COLOR
		end
		local b = new("TextButton", {
			AutoButtonColor = false,
			Position = UDim2.new(xs, xo, 0, y),
			Size = UDim2.new(ws, wo, 0, height or 42),
			BackgroundColor3 = baseBg,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextSize = 14,
			TextColor3 = textC,
		}, parent)
		corner(b, 8)
		if secondary then
			stroke(b, BORDER, 1, 0)
		end
		local sc = new("UIScale", { Scale = 1 }, b)
		b.MouseEnter:Connect(function()
			TweenService:Create(b, FAST, { BackgroundColor3 = hoverBg }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b, FAST, { BackgroundColor3 = baseBg }):Play()
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
	-- THE PAGES
	---------------------------------------------------------------------
	local FORM_Y = 58
	local KEY_BTN_Y = 134
	local LOGIN_BTN_Y = 80
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

	-- KEY page: key on top, username + password side by side, create account
	local kKey = makeField(keyPage, 0, "Key", "Y1-XXXX-XXXX-XXXX", false)
	local kUser = makeField(keyPage, 62, "Username", "Create a username", false, "L")
	local kPass = makeField(keyPage, 62, "Password", "Create a password", true, "R")
	local kBtn = makeButton(keyPage, KEY_BTN_Y, "Create account")

	-- LOGIN page: username + password side by side, log in
	local lUser = makeField(loginPage, 0, "Username", "Your username", false, "L")
	local lPass = makeField(loginPage, 0, "Password", "Your password", true, "R")
	local lBtn = makeButton(loginPage, LOGIN_BTN_Y, "Log in")

	-- WELCOME page: the remembered account (read only info card) + Continue / Log out
	-- these are labels, not text boxes: nothing on this page can be typed into or edited
	local welcomePage = new("Frame", {
		Name = "WelcomePage",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, content)

	local infoCard = new("Frame", {
		Name = "Info",
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = WELL,
		BorderSizePixel = 0,
	}, welcomePage)
	corner(infoCard, 8)
	stroke(infoCard, BORDER, 1, 0)

	local function infoRow(y, caption)
		local cap = label(infoCard, string.upper(caption), UDim2.fromOffset(14, y), UDim2.new(0.4, -14, 0, 22),
			Enum.Font.GothamMedium, 10, DIM_TEXT)
		cap.ZIndex = 3
		local val = label(infoCard, "", UDim2.new(0.4, 0, 0, y), UDim2.new(0.6, -14, 0, 22),
			Enum.Font.GothamMedium, 13, TEXT_COLOR, Enum.TextXAlignment.Right)
		val.ZIndex = 3
		return val
	end
	local infoUser = infoRow(8, "Username")
	local infoExpires = infoRow(31, "Session ends")
	local infoDevice = infoRow(54, "Device")

	local wContinue = makeButton(welcomePage, 98, "Continue", "L", false, 38)
	local wLogout = makeButton(welcomePage, 98, "Log out", "R", true, 38)

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
			pos = UDim2.new(0.5, 2, 0, 3)
		end
		if animate then
			TweenService:Create(indicator, SMOOTH, { Position = pos }):Play()
		else
			indicator.Position = pos
		end
		local onC = Color3.new(1, 1, 1)
		local offC = DIM_TEXT
		TweenService:Create(tabKey, FAST, { TextColor3 = isKey and onC or offC }):Play()
		TweenService:Create(tabLogin, FAST, { TextColor3 = isKey and offC or onC }):Play()
	end

	local function showPage(name, animate)
		page = name
		setWinSize(WIN_W, WIN_H, animate)
		tabs.Visible = true
		formArea.Visible = true
		welcomePage.Visible = false
		keyPage.Visible = (name == "key")
		loginPage.Visible = (name == "login")
		if name == "key" then
			subtitle.Text = "Enter your key to create your account"
			statusLine.Position = UDim2.fromOffset(0, FORM_Y + KEY_BTN_Y + 42 + 12)
		else
			subtitle.Text = "Welcome back, log in to continue"
			statusLine.Position = UDim2.fromOffset(0, FORM_Y + LOGIN_BTN_Y + 42 + 12)
		end
		paintTabs(animate)
	end

	local function showWelcome(session, animate)
		current = session
		page = "welcome"
		setWinSize(SMALL_W, SMALL_H, animate)
		tabs.Visible = false
		formArea.Visible = false
		keyPage.Visible = false
		loginPage.Visible = false
		welcomePage.Visible = true
		subtitle.Text = "Welcome back, We remembered who you are"
		statusLine.Text = ""
		statusLine.Position = UDim2.fromOffset(0, 142)

		infoUser.Text = tostring(session.username)
		local ends = "No expiry"
		if type(session.expires_at) == "string" and session.expires_at ~= "" then
			ends = string.match(session.expires_at, "^(%d+-%d+-%d+)") or session.expires_at
		end
		infoExpires.Text = ends
		infoDevice.Text = "This device"
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

	-- fades the window out, closes it and hands the session to OnSuccess
	local function finish(session, wait)
		finished = true
		local leavePos = window.Position
		task.delay(wait, function()
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
				local session = {
					token = res.token,
					username = res.username or user,
					expires_at = res.expires_at,
					hwid = hwid,
				}
				saveSession(session)
				setStatus("Welcome, " .. tostring(session.username) .. "!", true)
				finish(session, 0.6)
			else
				lPass.clear()
				setStatus(tostring(res.message or "Login failed."))
			end
		end)
	end

	-- throws the remembered session away and goes back to the starting page
	local function dropToStart(message, good)
		clearSession()
		current = nil
		lPass.clear()
		lUser.clear()
		showPage("key", true)
		if message ~= nil then
			setStatus(message, good)
		end
	end

	local function doContinue()
		if busy or not alive or finished or current == nil then
			return
		end
		if not VERIFY then
			finish(current, 0)
			return
		end
		-- ask the server: the name and expiry that are passed on come from its answer, not from the file
		local sess = current
		setBusy(true, wContinue, "Continue", "Checking...")
		task.spawn(function()
			local res = post("verify", { token = sess.token, username = sess.username, hwid = sess.hwid })
			if not alive then
				return
			end
			setBusy(false, wContinue, "Continue", "Checking...")
			if res.ok then
				local checked = {
					token = sess.token,
					username = res.username or sess.username,
					expires_at = res.expires_at or sess.expires_at,
					hwid = sess.hwid,
				}
				saveSession(checked)
				finish(checked, 0)
			else
				dropToStart(tostring(res.message or "Session is no longer valid. Please log in again."), false)
			end
		end)
	end

	local function doLogout()
		if busy or not alive or finished then
			return
		end
		dropToStart("You have been logged out.", true)
	end

	kBtn.Activated:Connect(doRegister)
	lBtn.Activated:Connect(doLogin)
	wContinue.Activated:Connect(doContinue)
	wLogout.Activated:Connect(doLogout)
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

	-- a genuine saved session on this device: open on the small welcome page instead of the key page
	local saved, why = loadSession()
	if saved ~= nil then
		showWelcome(saved, false)
	elseif why ~= nil then
		setStatus(why, false)
	end

	-- intro
	TweenService:Create(window, SMOOTH, { GroupTransparency = 0 }):Play()
	TweenService:Create(windowScale, POP, { Scale = fitScale }):Play()

	return W
end

return Auth
