-- ui.lua  (Y1 window module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Black window with tiny rounded corners, slim sidebar, title card, window controls,
-- Settings page (UI toggle keybind + Touch Mode), unload dialog and toasts.
--
--   local UI = <this file>
--   local win = UI.new({ Name = "Y1PlayerFinder", Logo = "Y1", MainTitle = "Player Finder", MainTip = "Player Finder" })
--
-- What you get back:
--   win.MainPage / win.SettingsPage   frames you put your controls in
--   win.T                             theme colours, radii and tween infos
--   win.H                             helpers: new, corner, stroke, pad, label, hoverable
--   win.Touch                         true while Touch Mode is on
--   win:Toast(text)                   small pop-up at the bottom
--   win:SetStats(text)                small text in the top bar (left of the window controls)
--   win:OnTouchChange(fn)             fn(isTouch) runs whenever Touch Mode changes
--   win:OnUnload(fn)                  fn() runs when the window is unloaded
--   win:Track(connection)             connection is disconnected on unload
--   win:IsHidden() / win:IsMinimized()
--   win:SetTouch(bool)
--   win:Unload()

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
	local currentPage = "Main"
	local bodyParts = {}      -- everything that hides while the window is minimized
	local ui = {}             -- layout functions and buttons shared between sections
	local showPage = function(_name) end
	local closePopup = function() end
	local toast = function(_msg) end
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
		Position = UDim2.fromScale(0.5, 0.5),
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

	local mainPage = new("Frame", {
		Name = "MainPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = true,
	}, content)

	local settingsPage = new("Frame", {
		Name = "SettingsPage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, content)

	table.insert(bodyParts, sidebar)
	table.insert(bodyParts, content)

	W.Gui = gui
	W.Window = window
	W.Bar = bar
	W.MainPage = mainPage
	W.SettingsPage = settingsPage

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
	-- SIDEBAR ICONS (server icon = main page, gear icon = Settings)
	---------------------------------------------------------------------
	do
		local TIP_X = 14 + TILE + 10
		local GROW = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local navIcons = {}   -- page name -> function(isActive)

		-- o.page / o.tip / o.tipW / o.anchorY (0 = from the top, 1 = from the bottom) / o.yScale / o.yOffset
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

			-- small marker on the sidebar edge for the page you are on
			local marker = new("Frame", {
				Name = o.page .. "Marker",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 8, o.yScale, centerY),
				Size = UDim2.fromOffset(3, 18),
				BackgroundColor3 = ICON_HOVER,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, window)
			corner(marker, 2)
			table.insert(bodyParts, marker)

			-- everything drawn lives in "glyph" so one UIScale can grow it from the middle on hover
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
			corner(tip, RADIUS + 1)
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

			navIcons[o.page] = function(isActive)
				active = isActive
				local t = 1
				if isActive then
					t = 0
				end
				TweenService:Create(marker, FAST, { BackgroundTransparency = t }):Play()
				paint()
			end
		end

		-- server icon: two stacked units, each with a status dot and a dash
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
				corner(f, 3)
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

		-- scalloped gear: two rounded squares (straight + rotated 45 degrees) + a hollow centre
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
			local sq1 = shape(22, 0, 3, ICON)
			local sq2 = shape(22, 45, 3, ICON)
			shape(10, 0, 5, SIDEBAR_BG)
			return { sq1, sq2 }
		end

		local tipW = math.max(66, #mainTip * 7 + 20)
		makeNavIcon({ page = "Main", tip = mainTip, tipW = tipW, anchorY = 0, yScale = 0, yOffset = 60, build = buildServer })
		makeNavIcon({ page = "Settings", tip = "Settings", tipW = 66, anchorY = 1, yScale = 1, yOffset = -(14 + TILE + 8), build = buildGear })

		ui.navUpdate = function()
			for page, setActive in pairs(navIcons) do
				setActive(page == currentPage)
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
		corner(cluster, RADIUS + 1)

		local function makeControl(kind, hoverColor)
			local btn = new("TextButton", {
				Name = kind,
				AutoButtonColor = false,
				Text = "",
				BackgroundColor3 = hoverColor,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, cluster)
			corner(btn, 3)

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
				corner(sq, 2)
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
	-- PAGE TITLE CARD + BACK ARROW
	---------------------------------------------------------------------
	do
		local PAGE_TITLES = { Main = mainTitle, Settings = "Settings" }

		local titleChip = new("Frame", {
			Name = "TitleCard",
			Position = UDim2.fromOffset(CHIP_X, 6),
			Size = UDim2.fromOffset(CHIP_W, 36),
			BackgroundColor3 = SIDEBAR_BG,
			BorderSizePixel = 0,
		}, window)
		corner(titleChip, RADIUS + 1)

		label(titleChip, "Tab", UDim2.fromOffset(12, 5), UDim2.new(1, -24, 0, 12),
			Enum.Font.Gotham, 11, DIM_TEXT)
		local titleLabel = label(titleChip, PAGE_TITLES.Main, UDim2.fromOffset(12, 18), UDim2.new(1, -24, 0, 16),
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
			Visible = false,
			ZIndex = 3,
		}, window)
		corner(backBtn, RADIUS + 1)
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

		showPage = function(name)
			if name == currentPage then
				return
			end
			currentPage = name
			mainPage.Visible = (name == "Main")
			settingsPage.Visible = (name == "Settings")
			backBtn.Visible = (name ~= "Main") and not minimized
			if ui.navUpdate then
				ui.navUpdate()
			end

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
			showPage("Main")
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
		local toastLbl = new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, (SIDEBAR_W_MIN + 12) / 2, 1, -14),
			Size = UDim2.new(0, 0, 0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
			Text = "",
			TextColor3 = TEXT_COLOR,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			Visible = false,
			ZIndex = 22,
		}, window)
		corner(toastLbl, RADIUS + 2)
		stroke(toastLbl, BORDER, 1, 0)
		pad(toastLbl, 14, 0, 14, 0)

		local toastToken = 0
		toast = function(msg)
			if minimized then
				return
			end
			toastToken = toastToken + 1
			local t = toastToken
			toastLbl.Text = msg
			toastLbl.Visible = true
			task.delay(2.5, function()
				if t == toastToken then
					toastLbl.Visible = false
				end
			end)
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
		corner(keyRow, RADIUS + 2)

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
		corner(keyBtn, RADIUS + 1)

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
		corner(touchRow, RADIUS + 2)

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
	-- WINDOW BEHAVIOUR: minimize / maximize / unload dialog / drag
	---------------------------------------------------------------------
	do
		local normalSize = WINDOW_SIZE
		local normalPos = window.Position

		local function setBodyVisible(visible)
			for i = 1, #bodyParts do
				bodyParts[i].Visible = visible
			end
			ui.back.Visible = visible and currentPage ~= "Main"
		end

		local function restore()
			minimized = false
			maximized = false
			setBodyVisible(true)
			TweenService:Create(window, SMOOTH, { Size = normalSize, Position = normalPos }):Play()
			TweenService:Create(windowScale, SMOOTH, { Scale = fitScale }):Play()
		end

		ui.minimize.Activated:Connect(function()
			if minimized then
				restore()
				return
			end
			closePopup()
			if not maximized then
				normalSize = window.Size
				normalPos = window.Position
			end
			minimized = true
			maximized = false
			setBodyVisible(false)
			TweenService:Create(window, SMOOTH, {
				Size = UDim2.fromOffset(normalSize.X.Offset, BAR_H),
				Position = normalPos,
			}):Play()
			TweenService:Create(windowScale, SMOOTH, { Scale = fitScale }):Play()
		end)

		ui.maximize.Activated:Connect(function()
			if maximized or minimized then
				restore()
				return
			end
			normalSize = window.Size
			normalPos = window.Position
			maximized = true
			TweenService:Create(window, SMOOTH, {
				Size = UDim2.new(1, -48, 1, -48),
				Position = UDim2.fromScale(0.5, 0.5),
			}):Play()
			TweenService:Create(windowScale, SMOOTH, { Scale = 1 }):Play()
		end)

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
		corner(dialog, RADIUS + 1)
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
		corner(trayFrame, RADIUS + 1)

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
			corner(b, 3)
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
				if maximized then
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
							if not minimized then
								normalPos = window.Position
							end
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

	function W:Toast(msg)
		toast(msg)
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
