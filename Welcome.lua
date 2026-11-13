-- Welcome.lua  (welcome screen + module loader)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Same look as Auth.lua: one centered flat card with the logo on top ("yur" in red, the 1 in white),
-- a subtitle, a list with ONE LOADING BAR PER MODULE (waiting -> checking 3/10 -> ready), a counter,
-- an overall bar, and the Continue button once everything is loaded.
--
-- Module file names are HIDDEN on screen: rows say "Module 1", "Module 2", ...
-- Ready is GREEN. There are no status dots.
--
-- SILENT: nothing is printed or warned in the console. A failure shows in the window instead
-- (the row turns amber); the last error text (with the real file name) is available
-- with welcome:GetError().
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
--       Title = "yur1",                  -- last character is drawn in white, the rest in red
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
--   welcome:GetError()               -- last error text (nil when there was none)
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
	local lastError = nil       -- last error text (never printed)

	---------------------------------------------------------------------
	-- THEME (same colours as Auth.lua)
	---------------------------------------------------------------------
	local BG         = Color3.fromRGB(35, 35, 35)     -- window background (flat, no gradient)
	local BLACK      = Color3.fromRGB(10, 10, 11)     -- dark text on the light button
	local WELL       = Color3.fromRGB(28, 28, 28)     -- recessed surfaces: list + bars
	local BORDER     = Color3.fromRGB(54, 54, 54)
	local ICON       = Color3.fromRGB(176, 176, 182)
	local ICON_HOVER = Color3.fromRGB(240, 240, 244)
	local TEXT_COLOR = Color3.fromRGB(232, 232, 236)
	local DIM_TEXT   = Color3.fromRGB(122, 122, 128)
	local JOIN_BG    = Color3.fromRGB(232, 232, 236)
	local GOOD       = Color3.fromRGB(110, 200, 140)  -- ready
	local BAD        = Color3.fromRGB(214, 90, 90)    -- fatal error
	local WARN       = Color3.fromRGB(226, 168, 72)   -- failed modules
	local CALM_RED   = Color3.fromRGB(196, 92, 92)    -- "yur" in the logo, close button hover

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
	local WIN_W = 520
	local WIN_H = 430
	local SIDE = 44
	local HEAD_H = 118 -- logo + subtitle area on top
	local BTN_H = 42
	if touch then
		BTN_H = 48
	end

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

	local subtitle = label(window, "Loading everything safely", UDim2.fromOffset(SIDE, 86),
		UDim2.new(1, -SIDE * 2, 0, 16), Enum.Font.GothamMedium, 12, DIM_TEXT, Enum.TextXAlignment.Center)
	subtitle.ZIndex = 3

	-- close button (top right): two rounded bars, turns red on hover
	local closeBtn = nil
	do
		local size = 26
		if touch then
			size = 38
		end
		closeBtn = new("TextButton", {
			Name = "close",
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = CALM_RED,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 25,
		}, window)
		corner(closeBtn, 6)

		local parts = {}
		local function line(rot)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(12, 2),
				Rotation = rot,
				BackgroundColor3 = ICON,
				BorderSizePixel = 0,
				ZIndex = 26,
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

	---------------------------------------------------------------------
	-- CONTENT COLUMN: header, one loading bar per module, overall bar / Continue button
	---------------------------------------------------------------------
	local CONTENT_W = WIN_W - SIDE * 2
	local CONTENT_H = WIN_H - (HEAD_H + 20)
	local ROW_H = 34
	local LIST_Y = 18
	local LIST_H = 170
	local BOT_Y = LIST_Y + LIST_H + 12
	local BOT_H = CONTENT_H - BOT_Y
	local total = #moduleList

	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(SIDE, HEAD_H),
		Size = UDim2.fromOffset(CONTENT_W, CONTENT_H),
		BackgroundTransparency = 1,
	}, window)

	local headCap = label(content, "MODULES", UDim2.fromOffset(2, 0), UDim2.new(0.5, 0, 0, 14),
		Enum.Font.GothamMedium, 10, DIM_TEXT)
	headCap.ZIndex = 3
	local counter = label(content, "0 / " .. tostring(total), UDim2.new(0.5, 0, 0, 0), UDim2.new(0.5, -2, 0, 14),
		Enum.Font.GothamMedium, 10, DIM_TEXT, Enum.TextXAlignment.Right)
	counter.ZIndex = 3

	local list = new("ScrollingFrame", {
		Name = "ModuleList",
		Position = UDim2.fromOffset(0, LIST_Y),
		Size = UDim2.new(1, 0, 0, LIST_H),
		BackgroundColor3 = WELL,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = BORDER,
		CanvasSize = UDim2.fromOffset(0, total * ROW_H + 8),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, content)
	corner(list, 8)
	stroke(list, BORDER, 1, 0)

	local rowsUI = {}
	local rowKind = {}
	local rowProg = {}
	for i = 1, total do
		local row = new("Frame", {
			Position = UDim2.fromOffset(0, 4 + (i - 1) * ROW_H),
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, list)
		-- the real file name is hidden: rows are just numbered
		local nm = label(row, "Module " .. tostring(i), UDim2.fromOffset(14, 3), UDim2.new(1, -134, 0, 16),
			Enum.Font.GothamMedium, 12, DIM_TEXT)
		local st = label(row, "Waiting", UDim2.new(1, -118, 0, 3), UDim2.fromOffset(104, 16),
			Enum.Font.Gotham, 11, DIM_TEXT, Enum.TextXAlignment.Right)
		local track = new("Frame", {
			Position = UDim2.fromOffset(14, 23),
			Size = UDim2.new(1, -28, 0, 4),
			BackgroundColor3 = BG,
			BorderSizePixel = 0,
		}, row)
		corner(track, 2)
		local fill = new("Frame", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = ICON_HOVER,
			BorderSizePixel = 0,
		}, track)
		corner(fill, 2)
		-- soft highlight behind the row that is being worked on 
		local hl = new("Frame", {
			Position = UDim2.fromOffset(4, 1),
			Size = UDim2.new(1, -8, 1, -2),
			BackgroundColor3 = BORDER,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 0,
		}, row)
		corner(hl, 6)
		-- a light band that sweeps over the bar while the module is being worked on
		local shine = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Visible = false,
		}, fill)
		corner(shine, 2)
		local shineGrad = new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.55),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, shine)
		rowsUI[i] = { name = nm, st = st, fill = fill, hl = hl, shine = shine, grad = shineGrad }
		rowKind[i] = "wait"
		rowProg[i] = 0
	end

	-- bottom: overall bar first, Continue button once everything is loaded and the wait is over
	local bottom = new("Frame", {
		Name = "Bottom",
		Position = UDim2.fromOffset(0, BOT_Y),
		Size = UDim2.fromOffset(CONTENT_W, BOT_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, content)

	local loaderGroup = new("CanvasGroup", {
		Name = "Loader",
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 0,
	}, bottom)
	local loaderText = label(loaderGroup, "Checking modules", UDim2.fromOffset(2, 6),
		UDim2.new(1, -60, 0, 16), Enum.Font.GothamMedium, 12, TEXT_COLOR)
	local percent = label(loaderGroup, "0%", UDim2.new(1, -52, 0, 6), UDim2.fromOffset(50, 16),
		Enum.Font.GothamMedium, 12, DIM_TEXT, Enum.TextXAlignment.Right)
	local overallTrack = new("Frame", {
		Position = UDim2.fromOffset(2, 30),
		Size = UDim2.new(1, -4, 0, 6),
		BackgroundColor3 = WELL,
		BorderSizePixel = 0,
	}, loaderGroup)
	corner(overallTrack, 3)
	stroke(overallTrack, BORDER, 1, 0)
	local overallFill = new("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = ICON_HOVER,
		BorderSizePixel = 0,
	}, overallTrack)
	corner(overallFill, 3)

	local btnGroup = new("CanvasGroup", {
		Name = "ButtonGroup",
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
	}, bottom)

	local btn = new("TextButton", {
		Name = "Continue",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(0, 3),
		Size = UDim2.new(1, 0, 0, BTN_H),
		BackgroundColor3 = JOIN_BG,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = buttonText,
		TextSize = 14,
		TextColor3 = BLACK,
	}, btnGroup)
	corner(btn, 8)
	local btnScale = new("UIScale", { Scale = 1 }, btn)

	-- rounded chevron drawn with two bars
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

	-- what is being checked right now (also text from SetState), under the bar / button
	local status = label(bottom, "", UDim2.fromOffset(2, 54), UDim2.new(1, -4, 0, 34),
		Enum.Font.Gotham, 11, DIM_TEXT, Enum.TextXAlignment.Center)
	status.TextWrapped = true
	status.TextTruncate = Enum.TextTruncate.None
	status.TextYAlignment = Enum.TextYAlignment.Top
	status.ZIndex = 3

	---------------------------------------------------------------------
	-- PROGRESS (one bar per module + the overall bar)
	---------------------------------------------------------------------
	local function paintOverall()
		local sum = 0
		local done = 0
		for i = 1, total do
			sum = sum + rowProg[i]
			if rowKind[i] == "done" then
				done = done + 1
			end
		end
		local f = 0
		if total > 0 then
			f = sum / total
		end
		counter.Text = tostring(done) .. " / " .. tostring(total)
		percent.Text = tostring(math.floor(f * 100 + 0.5)) .. "%"
		TweenService:Create(overallFill, FAST, { Size = UDim2.new(f, 0, 1, 0) }):Play()
	end

	-- kind: "wait" | "active" | "done" | "fail"
	local function setRow(i, f, text, kind)
		local r = rowsUI[i]
		if not r or not alive then
			return
		end
		f = math.clamp(f, 0, 1)
		rowKind[i] = kind
		rowProg[i] = f
		r.st.Text = text

		local nameC = DIM_TEXT
		local stC = DIM_TEXT
		local fillC = ICON_HOVER
		local hlC = BORDER
		local hlT = 1
		if kind == "active" then
			nameC = TEXT_COLOR
			stC = ICON
			hlT = 0.45
		elseif kind == "done" then
			nameC = TEXT_COLOR
			stC = GOOD
			fillC = GOOD
		elseif kind == "fail" then
			nameC = TEXT_COLOR
			stC = WARN
			fillC = WARN
			hlC = WARN
			hlT = 0.8
		end

		r.hl.BackgroundColor3 = hlC
		TweenService:Create(r.hl, SMOOTH, { BackgroundTransparency = hlT }):Play()
		r.shine.Visible = (kind == "active")
		TweenService:Create(r.name, FAST, { TextColor3 = nameC }):Play()
		TweenService:Create(r.st, FAST, { TextColor3 = stC }):Play()
		TweenService:Create(r.fill, FAST, { Size = UDim2.new(f, 0, 1, 0), BackgroundColor3 = fillC }):Play()
		paintOverall()
		if kind == "active" then
			-- keep the module being checked in view
			local y = math.max(0, (i - 1) * ROW_H - ROW_H)
			local maxY = math.max(0, total * ROW_H + 8 - LIST_H)
			TweenService:Create(list, SMOOTH, { CanvasPosition = Vector2.new(0, math.min(y, maxY)) }):Play()
		end
	end

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

	-- decides what the bottom shows
	local function refreshBottom()
		if not alive then
			return
		end

		if state == "error" then
			loaderText.Text = "Could not load"
			loaderText.TextColor3 = BAD
			overallFill.BackgroundColor3 = BAD
			subtitle.Text = "Something went wrong"
		elseif state == "ready" then
			loaderText.Text = "Everything is ready"
			loaderText.TextColor3 = GOOD
			overallFill.BackgroundColor3 = GOOD
			subtitle.Text = "All modules are ready"
		else
			loaderText.Text = "Checking modules"
			loaderText.TextColor3 = TEXT_COLOR
			overallFill.BackgroundColor3 = ICON_HOVER
			subtitle.Text = "Loading everything safely"
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
				lastError = "OnContinue error: " .. tostring(err)
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
		local sc = 1
		if hovering then
			sc = 1.02
		end
		TweenService:Create(btnScale, SPRING, { Scale = sc }):Play()
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
				lastError = "OnClose error: " .. tostring(err)
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
			status.TextColor3 = BAD
		else
			status.TextColor3 = DIM_TEXT
		end
		refreshBottom()
	end

	function W:GetPosition()
		return window.Position
	end

	function W:GetModules()
		return loaded
	end

	function W:GetError()
		return lastError
	end

	function W:Close(instant)
		if not alive then
			return
		end
		alive = false
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

	-- shows what is being checked (only while still loading). Never shows file names.
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
	-- The module's bar fills while this runs (0 - 85 percent).
	local function checkModule(entry, index, count_total)
		local ref = nil
		local count = 0
		local restarts = 0
		setRow(index, 0, "Starting", "active")
		while count < CHECKS do
			if not alive then
				return nil
			end
			setInfo("[" .. index .. "/" .. count_total .. "] Checking module " .. index)
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
			setRow(index, 0.85 * count / CHECKS, "Checking " .. count .. "/" .. CHECKS, "active")
			task.wait(0.05)
		end
		return ref
	end

	-- returns true when the failure must stop everything (nothing is printed, the row turns amber)
	local function handleFail(entry, err, index)
		lastError = entry.Name .. ": " .. tostring(err)
		setRow(index, rowProg[index] or 0, "Failed", "fail")
		if entry.Required then
			W:SetState("error", "Could not load module " .. index)
			return true
		end
		return false
	end

	local function runLoader()
		local count_total = #moduleList

		-- pass 1: one module at a time, checked CHECKS times each
		for i = 1, count_total do
			local entry = moduleList[i]
			local ok, src = pcall(checkModule, entry, i, count_total)
			if not alive then
				return
			end
			if ok and src then
				local ok2, mod = pcall(compile, entry, src)
				if ok2 then
					loaded[entry.Id] = mod
					sources[entry.Name] = src
					setRow(i, 0.92, "Compiled", "active")
				elseif handleFail(entry, mod, i) then
					return
				end
			else
				if handleFail(entry, src, i) then
					return
				end
			end
		end

		-- pass 2: one very quick scan of everything again
		for i = 1, count_total do
			local entry = moduleList[i]
			if not alive then
				return
			end
			if sources[entry.Name] then
				setInfo("Final scan: module " .. i .. " of " .. count_total)
				local ok, src = pcall(fetch, entry.Name)
				if ok and src ~= sources[entry.Name] then
					local ok2, mod = pcall(compile, entry, src)
					if ok2 then
						loaded[entry.Id] = mod
						sources[entry.Name] = src
					else
						lastError = entry.Name .. " changed but failed to compile, kept the old copy: " .. tostring(mod)
					end
				end
				setRow(i, 1, "Ready", "done")
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
	-- INTRO: the window pops in
	---------------------------------------------------------------------
	paintButton()
	refreshBottom()

	TweenService:Create(window, SMOOTH, { GroupTransparency = 0 }):Play()
	TweenService:Create(windowScale, POP, { Scale = fitScale }):Play()

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
			lastError = "loader crashed: " .. tostring(err)
			W:SetState("error", "Could not load")
		end
	end)

	return W
end

return Welcome
