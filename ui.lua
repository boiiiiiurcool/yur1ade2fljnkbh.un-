-- ui.lua  (Y1 window module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Black window with tiny rounded corners, slim sidebar, title card, window controls,
-- Home tab (separate module), Settings page (UI toggle keybind + Touch Mode), unload dialog and toasts.
--
--   local UI = <this file>
--   local HomePage = <homepage.lua>
--   local win = UI.new({
--       Name = "Y1PlayerFinder", Logo = "Y1", MainTitle = "Server Locater", MainTip = "Server Locater",
--       Position = positionFromWelcome,
--       StartPage = "Home",            -- "Home" (default), "Main" or "Settings"
--       HomeModule = HomePage,         -- the homepage.lua module
--       Home = { Product = "yur1", Subtitle = "...", Access = "Lifetime access",
--                Build = "Beta 0.6", Component = "Rock and Roll by reruinz" },
--   })
--
-- What you get back:
--   win.HomePage / win.MainPage / win.SettingsPage   frames you put your controls in
--   win.T                             theme colours, radii and tween infos
--   win.H                             helpers: new, corner, stroke, pad, label, hoverable
--   win.Touch                         true while Touch Mode is on
--   win:ShowPage("Home" | "Main" | "Settings")
--   win:Toast(text)                   small pop-up at the bottom
--   win:SetStats(text)                small text in the top bar (left of the window controls)
--   win:OnTouchChange(fn)             fn(isTouch) runs whenever Touch Mode changes
--   win:OnUnload(fn)                  fn() runs when the window is unloaded
--   win:Track(connection)             connection is disconnected on unload
--   win:IsHidden() / win:IsMinimized()
--   win:SetTouch(bool)
--   win:Unload()
--
-- Minimize: the window shrinks away and a small draggable Y1 square appears at the
-- left middle of the screen. Click the square (without dragging) to open the window again.

local UI = {}

function UI.new(opts)
	opts = opts or {}
	local guiName = opts.Name or "Y1UI"
	local logoName = opts.Logo or "Y1"
	local mainTitle = opts.MainTitle or "Main"
	local mainTip = opts.MainTip or mainTitle

	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- only one copy of this window at a time
	do
		local old = playerGui:FindFirstChild(guiName)
		if old then
			old:Destroy()
		end
	end

	local W = {}
	local conns = {}
	local unloadFns = {}
	local touchFns = {}
	local unloaded = false
	local minimized = false
	local maximized = false
	local uiHidden = false
	local currentPage = "Home"
	if opts.StartPage == "Main" or opts.StartPage == "Settings" then
		currentPage = opts.StartPage
	end
	local returnPage = "Home"  -- where the back arrow on Settings goes
	local bodyParts = {}      -- everything that hides while the window is minimized
	local ui = {}             -- layout functions and buttons shared between sections
	local showPage = function(_name) end
	local closePopup = function() end
	local toast = function(_msg, _seconds) end
	local applyTouch = function(_on) end

	---------------------------------------------------------------------
	-- THEME
	---------------------------------------------------------------------
	local BLACK        = Color3.fromRGB(10, 10, 11)    -- window
	local BORDER       = Color3.fromRGB(36, 36, 39)    -- thin outline
	local SIDEBAR_BG   = Color3.fromRGB(17, 17, 19)    -- sidebar, cards, input boxes
	local CARD_BG      = Color3.fromRGB(28, 28, 31)    -- profile card, player rows
	local CARD_HOVER   = Color3.fromRGB(36, 36, 40)
	local POPUP_BG     = Color3.fromRGB(20, 20, 22)
	local CLUSTER_BG   = Color3.fromRGB(30, 30, 33)    -- dark grey behind the control buttons
	local ICON         = Color3.fromRGB(176, 176, 182) -- light grey icons
	local ICON_HOVER   = Color3.fromRGB(240, 240, 244)
	local HOVER_GREY   = Color3.fromRGB(66, 66, 72)    -- highlighted square
	local HOVER_RED    = Color3.fromRGB(214, 62, 62)
	local TEXT_COLOR   = Color3.fromRGB(230, 230, 234)
	local DIM_TEXT     = Color3.fromRGB(116, 116, 124)
	local GREEN        = Color3.fromRGB(52, 199, 120)
	local JOIN_BG      = Color3.fromRGB(232, 232, 236)
	local MATCH_BG     = Color3.fromRGB(50, 50, 57)

	local RADIUS = 4
	local SQUARE_RADIUS = 10

	local WINDOW_SIZE = UDim2.fromOffset(760, 480)
	local BAR_H = 40
	local SIDEBAR_W_MIN = 56
	local TILE = 40
	local CHIP_X = SIDEBAR_W_MIN + 14
	local CHIP_W = 128

	local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local SMOOTH = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local EXPAND = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local COLLAPSE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

	-- sizes of the window chrome that switch in Touch Mode
	local METRICS_NORMAL = {
		ctrlW = 30, ctrlH = 24, backSize = 24,
		keyW = 104, keyH = 28, setRowH = 54, setOff = 0,
		switchW = 42, switchH = 22,
		dlgBtn = 24,
	}
	local METRICS_TOUCH = {
		ctrlW = 40, ctrlH = 30, backSize = 34,
		keyW = 120, keyH = 38, setRowH = 62, setOff = 8,
		switchW = 52, switchH = 28,
		dlgBtn = 34,
	}
	local M = {}
	local function setMetrics(on)
		local src = METRICS_NORMAL
		if on then
			src = METRICS_TOUCH
		end
		for k, v in pairs(src) do
			M[k] = v
		end
	end
	W.Touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	setMetrics(W.Touch)

	W.T = {
		BLACK = BLACK, BORDER = BORDER, SIDEBAR_BG = SIDEBAR_BG, CARD_BG = CARD_BG, CARD_HOVER = CARD_HOVER,
		POPUP_BG = POPUP_BG, CLUSTER_BG = CLUSTER_BG, ICON = ICON, ICON_HOVER = ICON_HOVER,
		HOVER_GREY = HOVER_GREY, HOVER_RED = HOVER_RED, TEXT_COLOR = TEXT_COLOR, DIM_TEXT = DIM_TEXT,
		GREEN = GREEN, JOIN_BG = JOIN_BG, MATCH_BG = MATCH_BG,
		RADIUS = RADIUS, SQUARE_RADIUS = SQUARE_RADIUS,
		FAST = FAST, SMOOTH = SMOOTH, EXPAND = EXPAND, COLLAPSE = COLLAPSE,
	}

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

	-- background + text colour change on hover
	local function hoverable(btn, base, over, textBase, textOver)
		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, FAST, { BackgroundColor3 = over, TextColor3 = textOver }):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, FAST, { BackgroundColor3 = base, TextColor3 = textBase }):Play()
		end)
	end

	W.H = { new = new, corner = corner, stroke = stroke, pad = pad, label = label, hoverable = hoverable }

	local hover = { card = false, popup = false }

	---------------------------------------------------------------------
	-- WINDOW
	---------------------------------------------------------------------
	local gui = new("ScreenGui", {
		Name = guiName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	-- small screens: shrink the whole window to fit
	local fitScale = 1
	do
		local cam = workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			fitScale = math.min(1, (vp.X - 24) / WINDOW_SIZE.X.Offset, (vp.Y - 24) / WINDOW_SIZE.Y.Offset)
			fitScale = math.max(0.5, fitScale)
		end
	end

	local window = new("CanvasGroup", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = opts.Position or UDim2.fromScale(0.5, 0.5),
		Size = WINDOW_SIZE,
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
	}, gui)
	corner(window)

	local windowScale = new("UIScale", { Scale = fitScale }, window)

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

	local bar = new("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundTransparency = 1,
	}, window)

	local sidebar = new("Frame", {
		Name = "Sidebar",
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(0, SIDEBAR_W_MIN, 1, -12),
		BackgroundColor3 = SIDEBAR_BG,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, window)
	corner(sidebar)

	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(SIDEBAR_W_MIN + 12, BAR_H),
		Size = UDim2.new(1, -(SIDEBAR_W_MIN + 18), 1, -(BAR_H + 6)),
		BackgroundTransparency = 1,
	}, window)

	-- pages are canvas groups so they can fade. A canvas group clips everything at its edge,
	-- so the page has a small padding inside: outlines of controls that touch the edge
	-- (search box, tiles, load button...) now have room to draw and are no longer cut off.
	local PAGE_POS = UDim2.fromOffset(0, 0)
	local PAGE_SIZE_UD = UDim2.fromScale(1, 1)

	local function makePage(name)
		local shown = (name == currentPage)
		local gt = 1
		if shown then
			gt = 0
		end
		local p = new("CanvasGroup", {
			Name = name .. "Page",
			Position = PAGE_POS,
			Size = PAGE_SIZE_UD,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			GroupTransparency = gt,
			Visible = shown,
		}, content)
		pad(p, 2, 2, 2, 2)
		return p
	end

	local homePage = makePage("Home")
	local mainPage = makePage("Main")
	local settingsPage = makePage("Settings")

	table.insert(bodyParts, sidebar)
	table.insert(bodyParts, content)

	W.Gui = gui
	W.Window = window
	W.Bar = bar
	W.HomePage = homePage
	W.MainPage = mainPage
	W.SettingsPage = settingsPage

	---------------------------------------------------------------------
	-- HOME TAB CONTENT (comes from the separate homepage module)
	---------------------------------------------------------------------
	do
		local mod = opts.HomeModule
		local okBuild = false
		if type(mod) == "table" and type(mod.build) == "function" then
			local ok, err = pcall(mod.build, homePage, W.T, W.H, opts.Home or {})
			if ok then
				okBuild = true
			else
				warn("[ui] home page error: " .. tostring(err))
			end
		end
		if not okBuild then
			label(homePage, "Home", UDim2.fromOffset(24, 16), UDim2.new(1, -48, 0, 24),
				Enum.Font.GothamBold, 18, TEXT_COLOR)
		end
	end

	---------------------------------------------------------------------
	-- LOGO TEXT
	---------------------------------------------------------------------
	do
		local logo = new("Frame", {
			Name = "Logo",
			Position = UDim2.fromOffset(14, 14),
			Size = UDim2.fromOffset(TILE, 32),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, window)

		local logoLabel = new("TextLabel", {
			Name = "LogoText",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 0),
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

		table.insert(bodyParts, logo)
	end

	---------------------------------------------------------------------
	-- SIDEBAR ICONS (house, server, gear; one marker slides between them)
	---------------------------------------------------------------------
	do
		local TIP_X = 14 + TILE + 10
		local GROW = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local navIcons = {}   -- page name -> function(isActive)
		local navPos = {}     -- page name -> marker position

		local marker = new("Frame", {
			Name = "NavMarker",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0, 80),
			Size = UDim2.fromOffset(3, 18),
			BackgroundColor3 = ICON_HOVER,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, window)
		corner(marker, 2)
		table.insert(bodyParts, marker)

		-- o.page / o.tip / o.tipW / o.anchorY / o.yScale / o.yOffset
		-- o.build(glyph) draws the icon and returns the frames that take the icon colour
		local function makeNavIcon(o)
			local slot = new("Frame", {
				Name = o.page .. "Icon",
				AnchorPoint = Vector2.new(0, o.anchorY),
				Position = UDim2.new(0, 14, o.yScale, o.yOffset),
				Size = UDim2.fromOffset(TILE, TILE),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, window)
			table.insert(bodyParts, slot)

			local centerY = o.yOffset + TILE / 2
			if o.anchorY == 1 then
				centerY = o.yOffset - TILE / 2
			end
			navPos[o.page] = UDim2.new(0, 8, o.yScale, centerY)

			-- everything drawn lives in "glyph" so one UIScale can grow it from the middle
			local glyph = new("Frame", {
				Name = "Glyph",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, slot)
			local glyphScale = new("UIScale", { Scale = 1 }, glyph)
			local inks = o.build(glyph)

			local active = false
			local hovering = false
			local function paint()
				local color = ICON
				if active or hovering then
					color = ICON_HOVER
				end
				for i = 1, #inks do
					TweenService:Create(inks[i], FAST, { BackgroundColor3 = color }):Play()
				end
			end

			local hit = new("TextButton", {
				Name = "Hit",
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 6,
			}, slot)
			hit.Activated:Connect(function()
				showPage(o.page)
			end)

			-- tiny tooltip that fades in beside the icon
			local tip = new("Frame", {
				Name = o.page .. "Tip",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, TIP_X - 4, o.yScale, centerY),
				Size = UDim2.fromOffset(o.tipW, 24),
				BackgroundColor3 = CLUSTER_BG,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 8,
			}, window)
			corner(tip, RADIUS + 3)
			local tipStroke = stroke(tip, BORDER, 1, 1)
			local tipText = new("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.GothamMedium,
				Text = o.tip,
				TextSize = 12,
				TextColor3 = TEXT_COLOR,
				TextTransparency = 1,
				ZIndex = 9,
			}, tip)

			local function showTip(visible)
				local x = TIP_X - 4
				local bg = 1
				local tt = 1
				if visible then
					x = TIP_X
					bg = 0
					tt = 0
				end
				TweenService:Create(tip, SMOOTH, {
					Position = UDim2.new(0, x, o.yScale, centerY),
					BackgroundTransparency = bg,
				}):Play()
				TweenService:Create(tipStroke, FAST, { Transparency = tt }):Play()
				TweenService:Create(tipText, FAST, { TextTransparency = tt }):Play()
			end

			hit.MouseEnter:Connect(function()
				hovering = true
				showTip(true)
				TweenService:Create(glyphScale, GROW, { Scale = 1.2 }):Play()
				paint()
			end)
			hit.MouseLeave:Connect(function()
				hovering = false
				showTip(false)
				TweenService:Create(glyphScale, GROW, { Scale = 1 }):Play()
				paint()
			end)
			hit.MouseButton1Down:Connect(function()
				TweenService:Create(glyphScale, FAST, { Scale = 0.9 }):Play()
			end)
			hit.MouseButton1Up:Connect(function()
				local s = 1
				if hovering then
					s = 1.2
				end
				TweenService:Create(glyphScale, GROW, { Scale = s }):Play()
			end)

			navIcons[o.page] = function(isActive)
				active = isActive
				paint()
			end
		end

		-- house icon: the roof is two square frames, each cut diagonally with a UIGradient whose
		-- transparency has a tiny soft step. That gives a clean smooth slope with no rotated frames.
		local function buildHome(glyph)
			local inks = {}
			local function half(anchorX, rot, seq)
				local f = new("Frame", {
					AnchorPoint = Vector2.new(anchorX, 0),
					Position = UDim2.new(0.5, 0, 0.5, -10),
					Size = UDim2.fromOffset(10, 10),
					BackgroundColor3 = ICON,
					BorderSizePixel = 0,
					ZIndex = 3,
				}, glyph)
				new("UIGradient", { Rotation = rot, Transparency = seq }, f)
				table.insert(inks, f)
			end
			-- left half keeps its lower-right triangle, right half keeps its lower-left triangle
			half(1, 45, NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.46, 1),
				NumberSequenceKeypoint.new(0.54, 0),
				NumberSequenceKeypoint.new(1, 0),
			}))
			half(0, -45, NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.46, 0),
				NumberSequenceKeypoint.new(0.54, 1),
				NumberSequenceKeypoint.new(1, 1),
			}))
			-- small rounded tip so the two halves join without a seam
			local tip = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0.5, -10),
				Size = UDim2.fromOffset(2, 8),
				BackgroundColor3 = ICON,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, glyph)
			corner(tip, 1)
			table.insert(inks, tip)
			local body = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.fromOffset(16, 10),
				BackgroundColor3 = ICON,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, glyph)
			corner(body, 3)
			table.insert(inks, body)
			local door = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 0.5, 10),
				Size = UDim2.fromOffset(4, 6),
				BackgroundColor3 = SIDEBAR_BG,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, glyph)
			corner(door, 2)
			return inks
		end

		-- server icon: two stacked rounded units, each with a status dot and a dash
		local function buildServer(glyph)
			local inks = {}
			local function unit(y)
				local f = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, 0, 0.5, y),
					Size = UDim2.fromOffset(22, 9),
					BackgroundColor3 = ICON,
					BorderSizePixel = 0,
					ZIndex = 3,
				}, glyph)
				corner(f, 4)
				table.insert(inks, f)
				local dot = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0, 6, 0.5, 0),
					Size = UDim2.fromOffset(3, 3),
					BackgroundColor3 = SIDEBAR_BG,
					BorderSizePixel = 0,
					ZIndex = 4,
				}, f)
				corner(dot, 2)
				local dash = new("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 11, 0.5, 0),
					Size = UDim2.fromOffset(7, 2),
					BackgroundColor3 = SIDEBAR_BG,
					BorderSizePixel = 0,
					ZIndex = 4,
				}, f)
				corner(dash, 1)
			end
			unit(-6)
			unit(6)
			return inks
		end

		-- rounded gear: two rounded squares (straight + rotated 45 degrees) + a hollow centre
		local function buildGear(glyph)
			local function shape(w, rot, r, color)
				local f = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(w, w),
					Rotation = rot,
					BackgroundColor3 = color,
					BorderSizePixel = 0,
					ZIndex = 3,
				}, glyph)
				corner(f, r)
				return f
			end
			local sq1 = shape(22, 0, 5, ICON)
			local sq2 = shape(22, 45, 5, ICON)
			shape(10, 0, 5, SIDEBAR_BG)
			return { sq1, sq2 }
		end

		local tipW = math.max(66, #mainTip * 7 + 20)
		local GEAR_Y = -(14 + TILE + 8)       -- bottom edge of the gear tile
		local SERVER_Y = GEAR_Y - TILE - 6    -- server tile sits a tiny bit above the gear
		local HOME_Y = SERVER_Y - TILE - 6    -- house tile sits a tiny bit above the server
		makeNavIcon({ page = "Home", tip = "Home", tipW = 66, anchorY = 1, yScale = 1, yOffset = HOME_Y, build = buildHome })
		makeNavIcon({ page = "Main", tip = mainTip, tipW = tipW, anchorY = 1, yScale = 1, yOffset = SERVER_Y, build = buildServer })
		makeNavIcon({ page = "Settings", tip = "Settings", tipW = 66, anchorY = 1, yScale = 1, yOffset = GEAR_Y, build = buildGear })

		local placed = false
		ui.navUpdate = function()
			for page, setActive in pairs(navIcons) do
				setActive(page == currentPage)
			end
			local p = navPos[currentPage]
			if p then
				if placed then
					TweenService:Create(marker, SMOOTH, { Position = p }):Play()
				else
					marker.Position = p
					placed = true
				end
			end
		end
		ui.navUpdate()
	end

	---------------------------------------------------------------------
	-- PROFILE CARD + ACCOUNT POPUP
	---------------------------------------------------------------------
	do
		local CARD_POS = UDim2.new(0, 14, 1, -14)
		local CARD_SIZE = UDim2.fromOffset(TILE, TILE)
		local POP_POS = UDim2.new(0, SIDEBAR_W_MIN + 12, 1, -14)
		local POP_SIZE = UDim2.fromOffset(264, 148)

		local card = new("TextButton", {
			Name = "ProfileCard",
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(0, 1),
			Position = CARD_POS,
			Size = CARD_SIZE,
			BackgroundColor3 = CARD_BG,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, window)
		corner(card, SQUARE_RADIUS)
		table.insert(bodyParts, card)

		local cardAvatar = new("ImageLabel", {
			Name = "Avatar",
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(TILE, TILE),
			BackgroundColor3 = CARD_BG,
			BorderSizePixel = 0,
			Image = "",
			ZIndex = 4,
		}, card)
		corner(cardAvatar, SQUARE_RADIUS)

		card.MouseEnter:Connect(function()
			hover.card = true
			TweenService:Create(card, FAST, { BackgroundColor3 = CARD_HOVER }):Play()
		end)
		card.MouseLeave:Connect(function()
			hover.card = false
			TweenService:Create(card, FAST, { BackgroundColor3 = CARD_BG }):Play()
		end)

		local popup = new("CanvasGroup", {
			Name = "AccountPopup",
			AnchorPoint = Vector2.new(0, 1),
			Position = CARD_POS,
			Size = CARD_SIZE,
			BackgroundColor3 = POPUP_BG,
			BorderSizePixel = 0,
			GroupTransparency = 1,
			Visible = false,
			ZIndex = 5,
		}, window)
		corner(popup)
		stroke(popup, BORDER, 1, 0)

		local avatar = new("ImageLabel", {
			Position = UDim2.fromOffset(16, 16),
			Size = UDim2.fromOffset(56, 56),
			BackgroundColor3 = CARD_BG,
			BorderSizePixel = 0,
			Image = "",
		}, popup)
		corner(avatar, 14)

		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and url then
				if avatar.Parent then
					avatar.Image = url
				end
				if cardAvatar.Parent then
					cardAvatar.Image = url
				end
			end
		end)

		label(popup, player.DisplayName, UDim2.fromOffset(84, 22), UDim2.fromOffset(164, 20),
			Enum.Font.GothamMedium, 14, TEXT_COLOR)
		label(popup, "@" .. player.Name, UDim2.fromOffset(84, 44), UDim2.fromOffset(164, 16),
			Enum.Font.Gotham, 12, DIM_TEXT)

		local idCard = new("Frame", {
			Position = UDim2.fromOffset(16, 88),
			Size = UDim2.fromOffset(232, 44),
			BackgroundColor3 = CARD_BG,
			BorderSizePixel = 0,
		}, popup)
		corner(idCard)
		label(idCard, "User ID", UDim2.fromOffset(12, 6), UDim2.fromOffset(120, 12),
			Enum.Font.Gotham, 11, DIM_TEXT)
		label(idCard, tostring(player.UserId), UDim2.fromOffset(12, 21), UDim2.fromOffset(208, 18),
			Enum.Font.GothamMedium, 13, TEXT_COLOR)

		local popupOpen = false
		local popupToken = 0

		local function openPopup()
			popupOpen = true
			popupToken = popupToken + 1
			popup.Position = CARD_POS
			popup.Size = CARD_SIZE
			popup.GroupTransparency = 1
			popup.Visible = true
			TweenService:Create(popup, EXPAND, {
				Position = POP_POS,
				Size = POP_SIZE,
				GroupTransparency = 0,
			}):Play()
		end

		closePopup = function()
			if not popupOpen then
				return
			end
			popupOpen = false
			popupToken = popupToken + 1
			local token = popupToken
			TweenService:Create(popup, COLLAPSE, {
				Position = CARD_POS,
				Size = CARD_SIZE,
				GroupTransparency = 1,
			}):Play()
			task.delay(0.24, function()
				if token == popupToken then
					popup.Visible = false
				end
			end)
		end

		card.Activated:Connect(function()
			if popupOpen then
				closePopup()
			else
				openPopup()
			end
		end)

		popup.MouseEnter:Connect(function()
			hover.popup = true
		end)
		popup.MouseLeave:Connect(function()
			hover.popup = false
		end)

		table.insert(conns, UserInputService.InputBegan:Connect(function(input)
			if not popupOpen then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			if hover.popup or hover.card then
				return
			end
			closePopup()
		end))
	end

	---------------------------------------------------------------------
	-- CONTROL CLUSTER (top right)
	---------------------------------------------------------------------
	do
		local GAP = 2
		local PAD = 3
		local btns = {}

		local cluster = new("Frame", {
			Name = "Controls",
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
		}, bar)
		corner(cluster, RADIUS + 2)

		local function makeControl(kind, hoverColor)
			local btn = new("TextButton", {
				Name = kind,
				AutoButtonColor = false,
				Text = "",
				BackgroundColor3 = hoverColor,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, cluster)
			corner(btn, 4)

			local parts = {}
			local function line(w, h, rot)
				local f = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(w, h),
					Rotation = rot or 0,
					BackgroundColor3 = ICON,
					BorderSizePixel = 0,
				}, btn)
				corner(f, 1)
				table.insert(parts, { f, "BackgroundColor3" })
			end

			if kind == "minimize" then
				line(10, 2)
			elseif kind == "maximize" then
				local sq = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(10, 10),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
				}, btn)
				corner(sq, 3)
				local s = stroke(sq, ICON, 1.5, 0)
				table.insert(parts, { s, "Color" })
			else
				line(14, 2, 45)
				line(14, 2, -45)
			end

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
				TweenService:Create(btn, FAST, { BackgroundTransparency = bgT }):Play()
				local color = ICON
				if isOver then
					color = ICON_HOVER
				end
				for _, p in ipairs(parts) do
					TweenService:Create(p[1], FAST, { [p[2]] = color }):Play()
				end
			end

			btn.MouseEnter:Connect(function()
				hovering = true
				paint(true, false)
			end)
			btn.MouseLeave:Connect(function()
				hovering = false
				paint(false, false)
			end)
			btn.MouseButton1Down:Connect(function()
				paint(true, true)
			end)
			btn.MouseButton1Up:Connect(function()
				paint(hovering, false)
			end)
			table.insert(btns, btn)
			return btn
		end

		ui.minimize = makeControl("minimize", HOVER_GREY)
		ui.maximize = makeControl("maximize", HOVER_GREY)
		ui.close = makeControl("close", HOVER_RED)

		ui.layoutControls = function()
			local w = M.ctrlW
			local h = M.ctrlH
			local cw = w * 3 + GAP * 2 + PAD * 2
			local ch = h + PAD * 2
			cluster.Position = UDim2.new(1, -8, 0, (BAR_H - ch) / 2)
			cluster.Size = UDim2.fromOffset(cw, ch)
			for i = 1, #btns do
				btns[i].Position = UDim2.fromOffset(PAD + (i - 1) * (w + GAP), PAD)
				btns[i].Size = UDim2.fromOffset(w, h)
			end
		end
		ui.layoutControls()
	end

	---------------------------------------------------------------------
	-- PAGE TITLE CARD + BACK ARROW + PAGE SWITCHING
	---------------------------------------------------------------------
	do
		local PAGE_TITLES = { Home = "Home", Main = mainTitle, Settings = "Settings" }

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
		local titleLabel = label(titleChip, PAGE_TITLES[currentPage] or currentPage, UDim2.fromOffset(12, 18), UDim2.new(1, -24, 0, 16),
			Enum.Font.GothamMedium, 13, TEXT_COLOR)

		local backBtn = new("TextButton", {
			Name = "Back",
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, BAR_H + 2),
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
			Visible = (currentPage == "Settings"),
			ZIndex = 3,
		}, window)
		corner(backBtn, RADIUS + 2)
		ui.back = backBtn

		-- the arrow lives in a 24x24 holder so it can be scaled up in Touch Mode
		local holder = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 1,
			ZIndex = 4,
		}, backBtn)
		local holderScale = new("UIScale", { Scale = 1 }, holder)

		local arrowParts = {}
		local function arrowStroke(w, x, y, rot)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, x, 0.5, y),
				Size = UDim2.fromOffset(w, 2),
				Rotation = rot,
				BackgroundColor3 = ICON,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, holder)
			corner(f, 1)
			table.insert(arrowParts, f)
		end
		arrowStroke(10, -1, 0, 0)
		arrowStroke(5, 2.3, -2, 45)
		arrowStroke(5, 2.3, 2, -45)

		backBtn.MouseEnter:Connect(function()
			TweenService:Create(backBtn, FAST, { BackgroundColor3 = HOVER_GREY }):Play()
			for _, f in ipairs(arrowParts) do
				TweenService:Create(f, FAST, { BackgroundColor3 = ICON_HOVER }):Play()
			end
		end)
		backBtn.MouseLeave:Connect(function()
			TweenService:Create(backBtn, FAST, { BackgroundColor3 = CLUSTER_BG }):Play()
			for _, f in ipairs(arrowParts) do
				TweenService:Create(f, FAST, { BackgroundColor3 = ICON }):Play()
			end
		end)

		ui.layoutBack = function()
			backBtn.Size = UDim2.fromOffset(M.backSize, M.backSize)
			holderScale.Scale = M.backSize / 24
		end
		ui.layoutBack()

		local titleToken = 0
		local pageToken = 0
		local pages = { Home = homePage, Main = mainPage, Settings = settingsPage }

		showPage = function(name)
			if name == currentPage or not pages[name] then
				return
			end
			-- Settings remembers the page you came from so the back arrow returns there
			if name == "Settings" then
				returnPage = currentPage
			end
			currentPage = name
			backBtn.Visible = (name == "Settings") and not minimized
			if ui.navUpdate then
				ui.navUpdate()
			end

			-- old page fades out, new page fades in while sliding up a little
			pageToken = pageToken + 1
			local pt = pageToken
			local nxt = pages[name]
			for _, p in pairs(pages) do
				if p ~= nxt then
					TweenService:Create(p, FAST, { GroupTransparency = 1 }):Play()
					task.delay(0.14, function()
						if pt == pageToken then
							p.Visible = false
						end
					end)
				end
			end
			nxt.Position = PAGE_POS + UDim2.fromOffset(0, 10)
			nxt.GroupTransparency = 1
			nxt.Visible = true
			TweenService:Create(nxt, SMOOTH, { Position = PAGE_POS, GroupTransparency = 0 }):Play()

			titleToken = titleToken + 1
			local token = titleToken
			TweenService:Create(titleLabel, FAST, { TextTransparency = 1 }):Play()
			task.delay(0.12, function()
				if token ~= titleToken then
					return
				end
				titleLabel.Text = PAGE_TITLES[name] or name
				TweenService:Create(titleLabel, FAST, { TextTransparency = 0 }):Play()
			end)
		end

		backBtn.Activated:Connect(function()
			showPage(returnPage or "Home")
		end)
	end

	---------------------------------------------------------------------
	-- TOAST + TOP BAR STATS
	---------------------------------------------------------------------
	local statsLabel = label(bar, "", UDim2.fromOffset(CHIP_X + CHIP_W + 10, 0),
		UDim2.new(1, -(CHIP_X + CHIP_W + 10 + 116), 1, 0),
		Enum.Font.GothamMedium, 11, DIM_TEXT, Enum.TextXAlignment.Right)

	ui.layoutStats = function()
		local clusterW = M.ctrlW * 3 + 10
		statsLabel.Size = UDim2.new(1, -(CHIP_X + CHIP_W + 10 + clusterW + 16), 1, 0)
	end

	do
		local MAX_TOASTS = 4
		local active = {}
		local order = 0

		-- toasts stack upward from the bottom; newest sits at the bottom
		local holder = new("Frame", {
			Name = "ToastStack",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, (SIDEBAR_W_MIN + 12) / 2, 1, -14),
			Size = UDim2.fromOffset(360, 170),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 22,
		}, window)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, holder)

		local function dismiss(item)
			if item.gone then
				return
			end
			item.gone = true
			for i = 1, #active do
				if active[i] == item then
					table.remove(active, i)
					break
				end
			end
			TweenService:Create(item.lbl, FAST, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			TweenService:Create(item.stroke, FAST, { Transparency = 1 }):Play()
			task.delay(FAST.Time + 0.02, function()
				item.lbl:Destroy()
			end)
		end

		local function arm(item, dur)
			item.token = item.token + 1
			local tk = item.token
			task.delay(dur, function()
				if tk == item.token then
					dismiss(item)
				end
			end)
		end

		toast = function(msg, dur)
			if minimized then
				return
			end
			dur = dur or 2.5
			msg = tostring(msg)

			-- same text again: keep the one that is already there and restart its timer
			for i = 1, #active do
				if active[i].text == msg then
					arm(active[i], dur)
					return
				end
			end

			order = order + 1
			local lbl = new("TextLabel", {
				LayoutOrder = order,
				Size = UDim2.new(0, 0, 0, 28),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = CLUSTER_BG,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = msg,
				TextColor3 = TEXT_COLOR,
				TextTransparency = 1,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				ZIndex = 22,
			}, holder)
			corner(lbl, RADIUS + 4)
			local st = stroke(lbl, BORDER, 1, 1)
			pad(lbl, 14, 0, 14, 0)

			local item = { lbl = lbl, stroke = st, text = msg, token = 0, gone = false }
			active[#active + 1] = item
			TweenService:Create(lbl, FAST, { BackgroundTransparency = 0, TextTransparency = 0 }):Play()
			TweenService:Create(st, FAST, { Transparency = 0 }):Play()

			-- too many: the oldest one leaves
			while #active > MAX_TOASTS do
				dismiss(active[1])
			end
			arm(item, dur)
		end
	end

	---------------------------------------------------------------------
	-- SETTINGS: UI TOGGLE KEYBIND + TOUCH MODE
	---------------------------------------------------------------------
	do
		local keybind = Enum.KeyCode.RightShift
		local listening = false
		local animToken = 0

		local keysHeader = label(settingsPage, "KEYBINDS", UDim2.fromOffset(2, 6), UDim2.fromOffset(200, 14),
			Enum.Font.GothamMedium, 11, DIM_TEXT)

		local keyRow = new("Frame", {
			Name = "ToggleKeybindRow",
			BackgroundColor3 = SIDEBAR_BG,
			BorderSizePixel = 0,
		}, settingsPage)
		corner(keyRow, RADIUS + 4)

		local keyTitle = label(keyRow, "UI Toggle Keybind", UDim2.fromOffset(14, 10), UDim2.new(1, -150, 0, 16),
			Enum.Font.GothamMedium, 13, TEXT_COLOR)
		local keySub = label(keyRow, "Hide or show the whole window", UDim2.fromOffset(14, 29), UDim2.new(1, -150, 0, 14),
			Enum.Font.Gotham, 11, DIM_TEXT)

		local keyBtn = new("TextButton", {
			Name = "KeybindButton",
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(104, 28),
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = ICON_HOVER,
			Text = keybind.Name,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, keyRow)
		corner(keyBtn, RADIUS + 2)

		local function paintKeyBtn(isOver)
			local bg = CLUSTER_BG
			if listening or isOver then
				bg = HOVER_GREY
			end
			TweenService:Create(keyBtn, FAST, { BackgroundColor3 = bg }):Play()
		end
		keyBtn.MouseEnter:Connect(function()
			paintKeyBtn(true)
		end)
		keyBtn.MouseLeave:Connect(function()
			paintKeyBtn(false)
		end)
		keyBtn.Activated:Connect(function()
			listening = not listening
			if listening then
				keyBtn.Text = "Press a key..."
			else
				keyBtn.Text = keybind.Name
			end
			paintKeyBtn(true)
		end)

		-- ===== Touch Mode =====
		local uiHeader = label(settingsPage, "INTERFACE", UDim2.fromOffset(2, 100), UDim2.fromOffset(200, 14),
			Enum.Font.GothamMedium, 11, DIM_TEXT)

		local touchRow = new("Frame", {
			Name = "TouchModeRow",
			BackgroundColor3 = SIDEBAR_BG,
			BorderSizePixel = 0,
		}, settingsPage)
		corner(touchRow, RADIUS + 4)

		local touchTitle = label(touchRow, "Touch Mode", UDim2.fromOffset(14, 10), UDim2.new(1, -150, 0, 16),
			Enum.Font.GothamMedium, 13, TEXT_COLOR)
		local touchSub = label(touchRow, "Bigger buttons, tabs and rows for touchscreens", UDim2.fromOffset(14, 29), UDim2.new(1, -150, 0, 14),
			Enum.Font.Gotham, 11, DIM_TEXT)

		local switch = new("TextButton", {
			Name = "TouchSwitch",
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(42, 22),
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
		}, touchRow)
		corner(switch, 100)
		stroke(switch, BORDER, 1, 0)

		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			BackgroundColor3 = DIM_TEXT,
			BorderSizePixel = 0,
		}, switch)
		corner(knob, 100)

		local function paintSwitch()
			local kd = M.switchH - 6
			local pos = UDim2.new(0, 3, 0.5, 0)
			local trackColor = CLUSTER_BG
			local knobColor = DIM_TEXT
			if W.Touch then
				pos = UDim2.new(1, -(kd + 3), 0.5, 0)
				trackColor = JOIN_BG
				knobColor = BLACK
			end
			TweenService:Create(knob, SMOOTH, { Position = pos, Size = UDim2.fromOffset(kd, kd) }):Play()
			TweenService:Create(knob, FAST, { BackgroundColor3 = knobColor }):Play()
			TweenService:Create(switch, FAST, { BackgroundColor3 = trackColor }):Play()
		end

		switch.Activated:Connect(function()
			applyTouch(not W.Touch)
		end)

		ui.layoutSettings = function()
			local off = M.setOff
			local h = M.setRowH
			local ty = math.floor((h - 34) / 2)
			local textW = M.keyW + 40

			keysHeader.Position = UDim2.fromOffset(2, 6 + off)
			keyRow.Position = UDim2.fromOffset(0, 28 + off)
			keyRow.Size = UDim2.new(1, -8, 0, h)
			keyBtn.Size = UDim2.fromOffset(M.keyW, M.keyH)
			keyTitle.Position = UDim2.fromOffset(14, ty)
			keyTitle.Size = UDim2.new(1, -textW, 0, 16)
			keySub.Position = UDim2.fromOffset(14, ty + 19)
			keySub.Size = UDim2.new(1, -textW, 0, 14)

			local y2 = 28 + off + h + 18
			uiHeader.Position = UDim2.fromOffset(2, y2)
			touchRow.Position = UDim2.fromOffset(0, y2 + 22)
			touchRow.Size = UDim2.new(1, -8, 0, h)
			touchTitle.Position = UDim2.fromOffset(14, ty)
			touchTitle.Size = UDim2.new(1, -(M.switchW + 40), 0, 16)
			touchSub.Position = UDim2.fromOffset(14, ty + 19)
			touchSub.Size = UDim2.new(1, -(M.switchW + 40), 0, 14)
			switch.Size = UDim2.fromOffset(M.switchW, M.switchH)
			paintSwitch()
		end

		-- hide / show animation: the window shrinks a little and fades out, and pops back in
		local HIDE_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		local SHOW_INFO = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local FADE_IN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		local function setUIVisible(show)
			if uiHidden == (not show) then
				return
			end
			uiHidden = not show

			-- while minimized only the little Y1 square is affected
			if minimized then
				if ui.miniShow then
					ui.miniShow(show)
				end
				return
			end

			animToken = animToken + 1
			local token = animToken

			local baseScale = fitScale
			if maximized then
				baseScale = 1
			end

			if show then
				window.Visible = true
				TweenService:Create(windowScale, SHOW_INFO, { Scale = baseScale }):Play()
				TweenService:Create(window, FADE_IN, { GroupTransparency = 0 }):Play()
			else
				closePopup()
				TweenService:Create(windowScale, HIDE_INFO, { Scale = baseScale * 0.9 }):Play()
				TweenService:Create(window, HIDE_INFO, { GroupTransparency = 1 }):Play()
				task.delay(HIDE_INFO.Time + 0.02, function()
					if token == animToken then
						window.Visible = false
					end
				end)
			end
		end

		table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
			if listening then
				if input.UserInputType ~= Enum.UserInputType.Keyboard then
					return
				end
				listening = false
				if input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode ~= Enum.KeyCode.Unknown then
					keybind = input.KeyCode
				end
				keyBtn.Text = keybind.Name
				paintKeyBtn(false)
				return
			end
			if processed then
				return
			end
			if input.KeyCode == keybind then
				setUIVisible(uiHidden)
			end
		end))
	end

	---------------------------------------------------------------------
	-- WINDOW BEHAVIOUR: minimize (Y1 square) / maximize / unload dialog / drag
	---------------------------------------------------------------------
	do
		local normalSize = WINDOW_SIZE
		local normalPos = window.Position
		local winToken = 0
		local miniToken = 0
		local miniSaved = nil   -- where you last left the square (nil = left middle)
		local GuiService = game:GetService("GuiService")

		-- tiny draggable square that stands in for the window while it is minimized
		local MINI_SIZE = 44
		local MINI_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local MINI_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local WIN_HIDE = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		local WIN_SHOW = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		local mini = new("TextButton", {
			Name = "MiniButton",
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.new(0, 12, 0.5, -MINI_SIZE / 2),
			Size = UDim2.fromOffset(MINI_SIZE, MINI_SIZE),
			BackgroundColor3 = BLACK,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 5,
		}, gui)
		corner(mini, SQUARE_RADIUS)
		local miniStroke = stroke(mini, BORDER, 1, 0)
		local miniScale = new("UIScale", { Scale = 0.6 }, mini)
		local miniLogo = new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.GothamBlack,
			Text = logoName,
			TextSize = 20,
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = 6,
		}, mini)
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 138)),
			}),
		}, miniLogo)

		mini.MouseEnter:Connect(function()
			TweenService:Create(miniStroke, FAST, { Color = HOVER_GREY }):Play()
			TweenService:Create(mini, FAST, { BackgroundColor3 = SIDEBAR_BG }):Play()
		end)
		mini.MouseLeave:Connect(function()
			TweenService:Create(miniStroke, FAST, { Color = BORDER }):Play()
			TweenService:Create(mini, FAST, { BackgroundColor3 = BLACK }):Play()
		end)

		ui.miniShow = function(show)
			miniToken = miniToken + 1
			local tk = miniToken
			if show then
				miniScale.Scale = 0.6
				mini.Visible = true
				TweenService:Create(miniScale, MINI_IN, { Scale = 1 }):Play()
			else
				TweenService:Create(miniScale, MINI_OUT, { Scale = 0.6 }):Play()
				task.delay(MINI_OUT.Time + 0.02, function()
					if tk == miniToken then
						mini.Visible = false
					end
				end)
			end
		end

		local function minimizeWindow()
			if minimized then
				return
			end
			closePopup()
			minimized = true
			winToken = winToken + 1
			local tk = winToken
			TweenService:Create(windowScale, WIN_HIDE, { Scale = windowScale.Scale * 0.85 }):Play()
			TweenService:Create(window, WIN_HIDE, { GroupTransparency = 1 }):Play()
			task.delay(WIN_HIDE.Time + 0.02, function()
				if tk == winToken then
					window.Visible = false
				end
			end)
			-- the square appears where you last left it (first time: left middle of the screen)
			if miniSaved then
				mini.Position = miniSaved
			else
				mini.Position = UDim2.new(0, 12, 0.5, -MINI_SIZE / 2)
			end
			uiHidden = false
			ui.miniShow(true)
		end

		local function restore()
			if not minimized then
				return
			end
			minimized = false
			uiHidden = false
			winToken = winToken + 1
			ui.miniShow(false)
			local base = fitScale
			if maximized then
				base = 1
			end
			windowScale.Scale = base * 0.85
			window.GroupTransparency = 1
			window.Visible = true
			TweenService:Create(windowScale, WIN_SHOW, { Scale = base }):Play()
			TweenService:Create(window, FAST, { GroupTransparency = 0 }):Play()
		end

		ui.minimize.Activated:Connect(minimizeWindow)

		ui.maximize.Activated:Connect(function()
			if minimized then
				return
			end
			if maximized then
				maximized = false
				if ui.gripVis then
					ui.gripVis()
				end
				TweenService:Create(window, SMOOTH, { Size = normalSize, Position = normalPos }):Play()
				TweenService:Create(windowScale, SMOOTH, { Scale = fitScale }):Play()
				return
			end
			normalSize = window.Size
			normalPos = window.Position
			maximized = true
			if ui.gripVis then
				ui.gripVis()
			end
			TweenService:Create(window, SMOOTH, {
				Size = UDim2.new(1, -48, 1, -48),
				Position = UDim2.fromScale(0.5, 0.5),
			}):Play()
			TweenService:Create(windowScale, SMOOTH, { Scale = 1 }):Play()
		end)

		-- drag the square anywhere; a tap without moving opens the window again
		-- input positions leave out the top inset, the gui does not, so add it back
		local mDragging = false
		local mMoved = false
		local mGrab = nil
		local mStartPtr = nil

		local function pointer(input)
			local inset = GuiService:GetGuiInset()
			return Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y)
		end

		mini.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				mDragging = true
				mMoved = false
				mStartPtr = pointer(input)
				mGrab = mStartPtr - mini.AbsolutePosition
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						local was = mDragging
						mDragging = false
						if was and not mMoved then
							restore()
						elseif was and mMoved then
							miniSaved = mini.Position
						end
					end
				end)
			end
		end)

		table.insert(conns, UserInputService.InputChanged:Connect(function(input)
			if not mDragging then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				local p = pointer(input)
				if not mMoved and (p - mStartPtr).Magnitude > 4 then
					mMoved = true
				end
				if mMoved then
					local vp = gui.AbsoluteSize
					local nx = math.clamp(p.X - mGrab.X, 0, math.max(0, vp.X - MINI_SIZE))
					local ny = math.clamp(p.Y - mGrab.Y, 0, math.max(0, vp.Y - MINI_SIZE))
					mini.Position = UDim2.fromOffset(nx, ny)
				end
			end
		end))

		-- ===== unload confirmation (pops up when you press X) =====
		local PAD = 3
		local confirmOpen = false
		local confirmToken = 0

		local overlay = new("CanvasGroup", {
			Name = "ConfirmOverlay",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Active = true,
			GroupTransparency = 1,
			Visible = false,
			ZIndex = 30,
		}, window)
		corner(overlay, RADIUS)

		local dialog = new("Frame", {
			Name = "Dialog",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(300, 128),
			BackgroundColor3 = SIDEBAR_BG,
			BorderSizePixel = 0,
			ZIndex = 31,
		}, overlay)
		corner(dialog, RADIUS + 3)
		stroke(dialog, BORDER, 1, 0)

		local dialogScale = new("UIScale", { Scale = 0.9 }, dialog)

		local dialogCaption = label(dialog, "Confirm", UDim2.fromOffset(18, 14), UDim2.fromOffset(264, 12),
			Enum.Font.Gotham, 11, DIM_TEXT)
		dialogCaption.ZIndex = 32

		local dialogText = label(dialog, "Are you sure you want to unload the script?",
			UDim2.fromOffset(18, 30), UDim2.fromOffset(264, 36), Enum.Font.GothamMedium, 13, TEXT_COLOR)
		dialogText.TextWrapped = true
		dialogText.TextTruncate = Enum.TextTruncate.None
		dialogText.TextYAlignment = Enum.TextYAlignment.Top
		dialogText.ZIndex = 32

		local trayFrame = new("Frame", {
			Name = "ButtonTray",
			Position = UDim2.fromOffset(18, 78),
			Size = UDim2.fromOffset(264, 24 + PAD * 2),
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
			ZIndex = 32,
		}, dialog)
		corner(trayFrame, RADIUS + 2)

		local function dialogButton(text, x, hoverColor)
			local b = new("TextButton", {
				AutoButtonColor = false,
				Text = text,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = ICON,
				Position = UDim2.fromOffset(x, PAD),
				Size = UDim2.fromOffset(127, 24),
				BackgroundColor3 = hoverColor,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 33,
			}, trayFrame)
			corner(b, 4)
			b.MouseEnter:Connect(function()
				TweenService:Create(b, FAST, { BackgroundTransparency = 0, TextColor3 = ICON_HOVER }):Play()
			end)
			b.MouseLeave:Connect(function()
				TweenService:Create(b, FAST, { BackgroundTransparency = 1, TextColor3 = ICON }):Play()
			end)
			return b
		end

		local yesBtn = dialogButton("Yes", PAD, HOVER_RED)
		local noBtn = dialogButton("No", PAD + 127 + 4, HOVER_GREY)

		ui.layoutDialog = function()
			local th = M.dlgBtn + PAD * 2
			dialog.Size = UDim2.fromOffset(300, 78 + th + 20)
			trayFrame.Size = UDim2.fromOffset(264, th)
			yesBtn.Size = UDim2.fromOffset(127, M.dlgBtn)
			noBtn.Size = UDim2.fromOffset(127, M.dlgBtn)
		end
		ui.layoutDialog()

		local CONFIRM_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local CONFIRM_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		local function showConfirm()
			if confirmOpen then
				return
			end
			confirmOpen = true
			confirmToken = confirmToken + 1
			closePopup()
			overlay.GroupTransparency = 1
			dialogScale.Scale = 0.9
			overlay.Visible = true
			TweenService:Create(overlay, FAST, { GroupTransparency = 0 }):Play()
			TweenService:Create(dialogScale, CONFIRM_IN, { Scale = 1 }):Play()
		end

		local function hideConfirm()
			if not confirmOpen then
				return
			end
			confirmOpen = false
			confirmToken = confirmToken + 1
			local token = confirmToken
			TweenService:Create(overlay, CONFIRM_OUT, { GroupTransparency = 1 }):Play()
			TweenService:Create(dialogScale, CONFIRM_OUT, { Scale = 0.92 }):Play()
			task.delay(CONFIRM_OUT.Time + 0.02, function()
				if token == confirmToken then
					overlay.Visible = false
				end
			end)
		end

		ui.close.Activated:Connect(function()
			if minimized then
				restore()
			end
			showConfirm()
		end)

		yesBtn.Activated:Connect(function()
			confirmToken = confirmToken + 1
			TweenService:Create(window, CONFIRM_OUT, { GroupTransparency = 1 }):Play()
			TweenService:Create(windowScale, CONFIRM_OUT, { Scale = windowScale.Scale * 0.92 }):Play()
			task.delay(CONFIRM_OUT.Time + 0.02, function()
				W:Unload()
			end)
		end)

		noBtn.Activated:Connect(hideConfirm)

		-- ===== drag the top bar (or the empty sidebar) to move; disabled while maximized =====
		local dragging = false
		local dragStart = nil
		local startPos = nil

		local function bindDrag(handle)
			handle.InputBegan:Connect(function(input)
				if maximized or minimized then
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
							normalPos = window.Position
						end
					end)
				end
			end)
		end
		bindDrag(bar)
		bindDrag(sidebar)

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
				normalPos = window.Position
			end
		end))

		-- ===== resize: drag the grip in the bottom-right corner =====
		local MIN_W = 520
		local MIN_H = 340
		local resizing = false
		local rStart = nil
		local rSize = nil
		local rPos = nil

		local grip = new("TextButton", {
			Name = "ResizeGrip",
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -4),
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 25,
		}, window)

		local gripInks = {}
		local function gripLine(len, c)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(c, c),
				Size = UDim2.fromOffset(len, 2),
				Rotation = -45,
				BackgroundColor3 = DIM_TEXT,
				BorderSizePixel = 0,
				ZIndex = 26,
			}, grip)
			corner(f, 1)
			gripInks[#gripInks + 1] = f
		end
		gripLine(5, 14)
		gripLine(10, 9)

		local function paintGrip(on)
			local col = DIM_TEXT
			if on then
				col = ICON_HOVER
			end
			for i = 1, #gripInks do
				TweenService:Create(gripInks[i], FAST, { BackgroundColor3 = col }):Play()
			end
		end
		grip.MouseEnter:Connect(function()
			paintGrip(true)
		end)
		grip.MouseLeave:Connect(function()
			if not resizing then
				paintGrip(false)
			end
		end)

		ui.gripVis = function()
			grip.Visible = not maximized
		end

		grip.InputBegan:Connect(function(input)
			if maximized or minimized then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				resizing = true
				rStart = input.Position
				rSize = window.Size
				rPos = window.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						resizing = false
						paintGrip(false)
						normalSize = window.Size
						normalPos = window.Position
					end
				end)
			end
		end)

		table.insert(conns, UserInputService.InputChanged:Connect(function(input)
			if not resizing then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				local sc = windowScale.Scale
				local d = input.Position - rStart
				local vp = gui.AbsoluteSize
				local maxW = math.max(MIN_W, math.floor((vp.X - 12) / sc))
				local maxH = math.max(MIN_H, math.floor((vp.Y - 12) / sc))
				local nw = math.clamp(rSize.X.Offset + d.X / sc, MIN_W, maxW)
				local nh = math.clamp(rSize.Y.Offset + d.Y / sc, MIN_H, maxH)
				window.Size = UDim2.fromOffset(nw, nh)
				-- the window is centre-anchored, so shift it to keep the top-left corner still
				window.Position = UDim2.new(
					rPos.X.Scale, rPos.X.Offset + (nw - rSize.X.Offset) * sc / 2,
					rPos.Y.Scale, rPos.Y.Offset + (nh - rSize.Y.Offset) * sc / 2
				)
			end
		end))
	end

	---------------------------------------------------------------------
	-- TOUCH MODE + PUBLIC API
	---------------------------------------------------------------------
	applyTouch = function(on)
		W.Touch = on
		setMetrics(on)
		ui.layoutControls()
		ui.layoutBack()
		ui.layoutSettings()
		ui.layoutDialog()
		ui.layoutStats()
		for i = 1, #touchFns do
			local ok, err = pcall(touchFns[i], on)
			if not ok then
				warn("[ui] touch callback error: " .. tostring(err))
			end
		end
	end

	function W:ShowPage(name)
		showPage(name)
	end

	function W:SetTouch(on)
		applyTouch(on)
	end

	function W:OnTouchChange(fn)
		table.insert(touchFns, fn)
	end

	function W:OnUnload(fn)
		table.insert(unloadFns, fn)
	end

	function W:Track(conn)
		table.insert(conns, conn)
		return conn
	end

	function W:Toast(msg, seconds)
		toast(msg, seconds)
	end

	function W:SetStats(text)
		statsLabel.Text = text
	end

	function W:IsHidden()
		return uiHidden
	end

	function W:IsMinimized()
		return minimized
	end

	function W:Unload()
		if unloaded then
			return
		end
		unloaded = true
		for i = 1, #unloadFns do
			local ok, err = pcall(unloadFns[i])
			if not ok then
				warn("[ui] unload callback error: " .. tostring(err))
			end
		end
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		gui:Destroy()
	end

	-- first layout pass with the starting mode (touch-only devices start in Touch Mode)
	ui.layoutSettings()
	ui.layoutStats()

	return W
end

return UI
