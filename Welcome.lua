-- Welcome.lua  (welcome screen + module loader)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Same look as ui.lua: small black window with tiny rounded corners and a close button.
-- It shows the "yur1" title (gradient text) and a spinning wheel with "Loading everything safely".
-- Under that it shows which module is being checked right now.
--
-- LOADING (done here, not in main.lua):
--   Pass 1: every module in opts.Modules is checked ONE AT A TIME. Each one is downloaded
--           opts.Checks times (default 10) and all copies must be identical, so we know
--           we hold the newest version and not a stale cached one. Then it is compiled.
--   Pass 2: after all modules passed, every module is downloaded once more, very quickly,
--           and compared with what we hold. If one changed it is recompiled.
--   Then the state becomes "ready" and the Continue button can show.
--
-- The Continue button only appears after WaitSeconds (default 10) AND once loading finished.
-- Enter cannot skip the wait either.
--
-- The window is NOT draggable. It always opens in the middle of the screen.
-- OnContinue receives (position, modules). modules is a table keyed by each entry's Id.
--
--   local welcome = Welcome.new({
--       Name = "Y1Welcome",
--       Title = "yur1",
--       ButtonText = "Continue",
--       WaitSeconds = 10,
--       Base = "https://.../main/",      -- must end with a slash
--       NoCache = true,
--       LocalDir = nil,                  -- for testing: workspace folder to use readfile
--       Checks = 10,
--       Modules = {
--           { Id = "UI", Name = "ui.lua", Key = "new", Required = true },
--           ...
--       },
--       OnContinue = function(position, modules) end,
--       OnClose = function() end,
--   })
--   welcome:SetState("loading", "text")  -- still available
--   welcome:GetModules()
--   welcome:GetPosition()
--   welcome:Close(instant)

local Welcome = {}

function Welcome.new(opts)
	opts = opts or {}
	local guiName = opts.Name or "Y1Welcome"
	local title = opts.Title or "yur1"
	local buttonText = opts.ButtonText or "Continue"
	local WAIT_SECONDS = opts.WaitSeconds or 10

	local BASE = opts.Base or ""
	local NO_CACHE = (opts.NoCache ~= false)
	local LOCAL_DIR = opts.LocalDir
	local CHECKS = opts.Checks or 10
	local moduleList = opts.Modules or {}

	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
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
	local loaded = {}           -- Id -> module table
	local sources = {}          -- file name -> source text we are holding

	---------------------------------------------------------------------
	-- THEME (same colours as ui.lua)
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

	local RADIUS = 4

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
	-- WINDOW
	---------------------------------------------------------------------
	local WIN_W = 340
	local WIN_H = 220
	local BAR_H = 34
	local CONTENT_W = WIN_W - 12
	local CONTENT_H = WIN_H - (BAR_H + 6)
	local BTN_W = 240
	local BTN_H = 38
	if touch then
		BTN_H = 46
	end
	local BOT_W = BTN_W + 16            -- a little wider than the button so its grow animation is not clipped
	local STATUS_Y = BTN_H + 16
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

	-- content area
	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(6, BAR_H),
		Size = UDim2.new(1, -12, 1, -(BAR_H + 6)),
		BackgroundTransparency = 1,
	}, window)

	---------------------------------------------------------------------
	-- TITLE: "yur1" with the soft white-to-grey gradient
	---------------------------------------------------------------------
	local titleBase = UDim2.fromOffset(0, -6)
	local titleGroup = new("CanvasGroup", {
		Name = "Title",
		Position = titleBase + UDim2.fromOffset(0, 12),
		Size = UDim2.fromOffset(CONTENT_W, 56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	}, content)

	local titleLabel = new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBlack,
		Text = title,
		TextSize = 44,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, titleGroup)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 138)),
		}),
	}, titleLabel)

	---------------------------------------------------------------------
	-- BOTTOM (the other content): loading wheel first, Continue button after the wait
	---------------------------------------------------------------------
	local bottomBase = UDim2.fromOffset(math.floor((CONTENT_W - BOT_W) / 2), math.floor((CONTENT_H - BOT_H) / 2) + 14)
	local bottom = new("CanvasGroup", {
		Name = "Bottom",
		Position = bottomBase + UDim2.fromOffset(0, 12),
		Size = UDim2.fromOffset(BOT_W, BOT_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	}, content)

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
			Position = UDim2.new(0.5, 0, 0, 18),
			Size = UDim2.fromOffset(30, 30),
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

	local loaderText = label(loaderGroup, "Loading everything safely", UDim2.fromOffset(0, 42), UDim2.new(1, 0, 0, 16),
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

	-- status line: shows which module is being checked right now (also text from SetState)
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

	-- decides what the window shows
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
			local ok, err = pcall(cb, leavePos, loaded)
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

	function W:GetModules()
		return loaded
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
	-- MODULE LOADER (runs behind the welcome window)
	---------------------------------------------------------------------
	local bust = 0

	-- shows what is being checked (only while still loading)
	local function setInfo(text)
		if alive and state == "loading" then
			status.Text = text
		end
	end

	-- one download, no retries
	local function fetchOnce(name)
		if LOCAL_DIR then
			return readfile(LOCAL_DIR .. name)
		end
		bust = bust + 1
		local url = BASE .. name
		if NO_CACHE then
			url = url .. "?v=" .. tostring(os.time()) .. "_" .. tostring(bust)
		end
		local ok, body = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(body) == "string" and body ~= "" then
			return body
		end
		-- fallback to the executor's request function
		local req = (syn and syn.request) or (http and http.request) or http_request or request
		if req then
			local ok2, res = pcall(function()
				return req({ Url = url, Method = "GET" })
			end)
			if ok2 and res and res.StatusCode == 200 and res.Body then
				return res.Body
			end
		end
		error("could not download " .. name, 0)
	end

	-- one download, up to 3 tries
	local function fetch(name)
		local lastErr = "unknown"
		for attempt = 1, 3 do
			local ok, res = pcall(fetchOnce, name)
			if ok then
				return res
			end
			lastErr = tostring(res)
			if not alive then
				break
			end
			task.wait(0.3)
		end
		error(lastErr, 0)
	end

	-- turns source text into the module table and makes sure it has the needed function
	local function compile(entry, src)
		local fn, err = loadstring(src, "=" .. entry.Name)
		if not fn then
			error("could not compile " .. entry.Name .. ": " .. tostring(err), 0)
		end
		local result = fn()
		local key = entry.Key or "new"
		if type(result) ~= "table" or type(result[key]) ~= "function" then
			error(entry.Name .. " did not return a module with ." .. key .. " (got " .. typeof(result) .. ")", 0)
		end
		return result
	end

	-- pass 1 for one module: download it CHECKS times in a row, all copies must match.
	-- if a copy differs (stale cache), the newest one becomes the reference and counting restarts.
	local function checkModule(entry, index, total)
		local ref = nil
		local count = 0
		local restarts = 0
		while count < CHECKS do
			if not alive then
				return nil
			end
			setInfo("[" .. index .. "/" .. total .. "] Checking " .. entry.Name .. " (" .. (count + 1) .. "/" .. CHECKS .. ")")
			local src = fetch(entry.Name)
			if ref == nil or src == ref then
				ref = src
				count = count + 1
			else
				restarts = restarts + 1
				ref = src
				count = 1
				if restarts > 3 then
					count = CHECKS    -- keeps changing: accept the newest copy and move on
				end
			end
			task.wait(0.05)
		end
		return ref
	end

	-- returns true when the failure must stop everything
	local function handleFail(entry, err)
		warn("[Y1] " .. entry.Name .. " failed: " .. tostring(err))
		if entry.Required then
			W:SetState("error", "Could not load " .. entry.Name .. " - see console (F9)")
			return true
		end
		return false
	end

	local function runLoader()
		local total = #moduleList

		-- pass 1: one module at a time, checked CHECKS times each
		for i = 1, total do
			local entry = moduleList[i]
			local ok, src = pcall(checkModule, entry, i, total)
			if not alive then
				return
			end
			if ok and src then
				local ok2, mod = pcall(compile, entry, src)
				if ok2 then
					loaded[entry.Id] = mod
					sources[entry.Name] = src
					print("[Y1] loaded " .. entry.Name)
				elseif handleFail(entry, mod) then
					return
				end
			else
				if handleFail(entry, src) then
					return
				end
			end
		end

		-- pass 2: one very quick scan of everything again
		for i = 1, total do
			local entry = moduleList[i]
			if not alive then
				return
			end
			if sources[entry.Name] then
				setInfo("Final scan: " .. entry.Name .. " (" .. i .. "/" .. total .. ")")
				local ok, src = pcall(fetch, entry.Name)
				if ok and src ~= sources[entry.Name] then
					local ok2, mod = pcall(compile, entry, src)
					if ok2 then
						loaded[entry.Id] = mod
						sources[entry.Name] = src
						print("[Y1] updated " .. entry.Name)
					else
						warn("[Y1] " .. entry.Name .. " changed but failed to compile, keeping the old copy: " .. tostring(mod))
					end
				end
				task.wait()
			end
		end

		if not alive then
			return
		end
		W:SetState("ready", "")
		if opts.OnLoaded then
			pcall(opts.OnLoaded, loaded)
		end
	end

	---------------------------------------------------------------------
	-- INTRO: window pops in, then the title and the wheel fade up
	---------------------------------------------------------------------
	paintButton()
	refreshBottom()

	TweenService:Create(window, SMOOTH, { GroupTransparency = 0 }):Play()
	TweenService:Create(windowScale, POP, { Scale = fitScale }):Play()
	TweenService:Create(titleGroup, SMOOTH, { Position = titleBase, GroupTransparency = 0 }):Play()
	task.delay(0.1, function()
		if alive then
			TweenService:Create(bottom, SMOOTH, { Position = bottomBase, GroupTransparency = 0 }):Play()
		end
	end)

	-- the wait: Continue can only show after WAIT_SECONDS, even if everything is loaded sooner
	task.delay(WAIT_SECONDS, function()
		if alive then
			waitDone = true
			refreshBottom()
		end
	end)

	-- start loading the modules behind the window
	task.spawn(function()
		local ok, err = pcall(runLoader)
		if not ok and alive then
			warn("[Y1] loader crashed: " .. tostring(err))
			W:SetState("error", "Could not load - see console (F9)")
		end
	end)

	return W
end

return Welcome
