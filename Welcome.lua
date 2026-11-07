-- Welcome.lua  (welcome screen module, minimal)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Same look as ui.lua: small black window with tiny rounded corners and a close button.
-- It shows the "yur1" title (gradient text) and a spinning wheel with "Loading everything safely".
-- No profile, no user ID, no game card, no tiles.
--
-- The Continue button only appears after WaitSeconds (default 10) AND once SetState("ready")
-- was called. Enter cannot skip the wait either.
--
-- The window is NOT draggable. It always opens in the middle of the screen.
-- OnContinue still receives the window position (always centered) so main.lua keeps working.
--
--   local Welcome = <this file>
--   local welcome = Welcome.new({
--       Name = "Y1Welcome",
--       Title = "yur1",
--       ButtonText = "Continue",
--       WaitSeconds = 10,
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
	local buttonText = opts.ButtonText or "Continue"
	local WAIT_SECONDS = opts.WaitSeconds or 10

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
	local titleBase = UDim2.fromOffset(0, 8)
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

	return W
end

return Welcome
