-- Y1UI.lua  (the Y1 window as a module: main.lua loads it through Welcome.lua, like the old ui.lua)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Same look as Welcome.lua / Auth.lua: flat dark card, "Y" in calm red, the 1 in white, thin borders, red accent.
-- Top bar: logo, current tab name, search box, keybinds / minimize / maximize / close.
-- Bottom bar: Home, Info, Combat, Visuals, World, Misc, Server, Config, Settings.
--
-- HOW IT PLUGS INTO main.lua
--   local win = modules.UI.new({
--       Name = "Y1PlayerFinder", Logo = "Y1", StartPage = "Home", HideKey = Enum.KeyCode.RightShift, Watermark = true,
--       HomeModule = ..., Home = {...},            -- a tab is filled by  <Id>Module.build(container, T, H, ctx)
--       InfoModule = ..., CombatModule = ..., Combat = {...}, VisualsModule = ..., Visuals = {...},
--       WorldModule = ..., World = {...}, MiscModule = ..., Misc = {...},
--       -- optional: ConfigModule / Config, SettingsModule / Settings, ServerModule / Server,
--       --           Binds   = { {id, title, wired, default}, ... }                (plain key rows)
--       --           Toggles = { {id, title, default, enabled, onToggle}, ... }    (modules you can turn on / off)
--   })
--   * T = the theme table (the old names SIDEBAR_BG / POPUP_BG / CLUSTER_BG / JOIN_BG / BLACK ... still work)
--   * H = { new, corner, stroke, label }
--   * ctx = a copy of the tab's table (opts.<Id>) plus Win (this window), Theme and Helpers
--   * a module may return { Unload = fn }; it is called when the window unloads
--   * finder.lua goes on the Server tab:  win:GetPage("Server")  (also win.MainPage)
--
-- WINDOW OBJECT (win)
--   win:Unload()                 win:OnUnload(fn)             win:IsAlive()
--   win:Toast(text, seconds)     win:ShowTab(id)              win:GetTab()           win:OnTab(fn(id))
--   win:GetPage(id)              win.Pages[id]                win.MainPage           win.Gui / win.Window / win.Content
--   win:OnSearch(fn(query))      win:GetSearch()              win:SetSearch(text)
--   win:AddBind({ id, title, wired, default = { kind = "Key", key = Enum.KeyCode.E } })
--   win:IsBind(id, input)        win:GetBind(id)              win:SetHidden(bool)
--   win:SetPageMessage(id, title, text, isError)
--
-- MODULE TOGGLES (Trigger Bot, Aimbot, ESP ... everything you can turn on / off)
--   Every toggle gets a row in the Keybinds panel: a status dot (grey = off, green = on), its name and its key.
--   Pressing the key flips the module (a small toast says "Trigger Bot on / off"). Click the key box to rebind.
--   win:AddToggle({ id = "TriggerBot", title = "Trigger Bot", default = { kind = "Key", key = Enum.KeyCode.T },
--                   enabled = false, wired = true, onToggle = function(on) end })
--   win:SetToggle(id, bool)      -- set it from your own on-page switch (silent, no toast)
--   win:Toggle(id)               -- flip it (with a toast)
--   win:GetToggle(id)            -- true / false
--   win:OnToggle(id, fn(on))     -- called whenever it changes (key press, SetToggle, Toggle) so your switch can follow
--
-- Left / Right arrow keys do NOT switch tabs on purpose (games use them to move); click the tabs.
-- Run it on its own (no modules) for a preview:   loadstring(game:HttpGet("https://.../Y1UI.lua"))().new({})

local UI = {}

function UI.new(opts)
	opts = opts or {}

	local CONFIG = {
		Name = opts.Name or "Y1UI",
		Logo = opts.Logo or "Y1",                                  -- first letter(s) red, last character white
		HideKey = opts.HideKey or Enum.KeyCode.RightShift,         -- hides / shows the window
		StartTab = opts.StartPage or opts.StartTab or "Home",
		Watermark = (opts.Watermark ~= false),
	}

	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local RunService = game:GetService("RunService")
	local MarketplaceService = game:GetService("MarketplaceService")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- only one copy at a time (also stops an older run of this window)
	local okEnv0, env0 = pcall(getgenv)
	if not okEnv0 or type(env0) ~= "table" then
		env0 = nil
	end
	if env0 and env0.__Y1_UI_STOP then
		pcall(env0.__Y1_UI_STOP)
	end
	do
		local old = playerGui:FindFirstChild(CONFIG.Name)
		if old then
			old:Destroy()
		end
	end

	---------------------------------------------------------------------
	-- THEME (same colours as Welcome.lua / Auth.lua)
	---------------------------------------------------------------------
	local BG         = Color3.fromRGB(35, 35, 35)     -- window
	local WELL       = Color3.fromRGB(28, 28, 28)     -- tab bar + content card
	local BORDER     = Color3.fromRGB(54, 54, 54)
	local ICON       = Color3.fromRGB(176, 176, 182)
	local ICON_HOVER = Color3.fromRGB(240, 240, 244)
	local TEXT_COLOR = Color3.fromRGB(232, 232, 236)
	local DIM_TEXT   = Color3.fromRGB(122, 122, 128)
	local CALM_RED   = Color3.fromRGB(196, 92, 92)    -- accent
	local HOVER_GREY = Color3.fromRGB(62, 62, 66)
	local ON_GREEN   = Color3.fromRGB(110, 200, 140)  -- "module is on" dot

	local RADIUS = 4

	local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local SMOOTH = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local POP = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local LEAVE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	local GROW = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	-- the theme table every module page gets as its second argument (T).
	-- The old names (SIDEBAR_BG, POPUP_BG, CLUSTER_BG, JOIN_BG, BLACK ...) are mapped to the new colours so the
	-- existing module files keep working. An unknown colour name falls back to ICON instead of crashing the page.
	local T = {
		BG = BG,
		WELL = WELL,
		BORDER = BORDER,
		ICON = ICON,
		ICON_HOVER = ICON_HOVER,
		TEXT_COLOR = TEXT_COLOR,
		DIM_TEXT = DIM_TEXT,
		ACCENT = CALM_RED,
		CALM_RED = CALM_RED,
		HOVER_GREY = HOVER_GREY,
		GOOD = ON_GREEN,
		BAD = Color3.fromRGB(214, 90, 90),
		WARN = Color3.fromRGB(226, 168, 72),
		-- names used by the module files
		SIDEBAR_BG = BG,                              -- the connected group backgrounds on a page
		POPUP_BG = Color3.fromRGB(40, 40, 42),        -- the little settings pop-ups
		CLUSTER_BG = WELL,                            -- switch tracks, slider tracks, drop-down buttons
		JOIN_BG = Color3.fromRGB(232, 232, 236),      -- switch "on" colour / light buttons
		BLACK = Color3.fromRGB(10, 10, 11),
		RADIUS = RADIUS,
		FAST = FAST,
		SMOOTH = SMOOTH,
		POP = POP,
		LEAVE = LEAVE,
		GROW = GROW,
	}
	setmetatable(T, {
		__index = function(_, key)
			if type(key) == "string" then
				return ICON
			end
			return nil
		end,
	})

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

	-- the helper table every module page gets as its third argument (H)
	local H = { new = new, corner = corner, stroke = stroke, label = label }

	-- a centred block inside an icon (y = offset from the middle)
	local function block(glyph, w, h, y, color, z, r)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z,
		}, glyph)
		if r then
			corner(f, r)
		end
		return f
	end

	-- one short 2px line between two points (measured from the middle of the glyph)
	local function segment(glyph, inks, x1, y1, x2, y2, z)
		local dx = x2 - x1
		local dy = y2 - y1
		local len = math.sqrt(dx * dx + dy * dy)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, (x1 + x2) / 2, 0.5, (y1 + y2) / 2),
			Size = UDim2.fromOffset(len + 1.5, 2),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = ICON,
			BorderSizePixel = 0,
			ZIndex = z,
		}, glyph)
		corner(f, 1)
		table.insert(inks, f)
	end

	-- a true outline circle (a UIStroke, no cut-out colour): "outer" is the outside diameter, "thick" the line weight.
	local function ring(glyph, inks, outer, thick, x, y, z)
		local inner = outer - thick * 2
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, x, 0.5, y),
			Size = UDim2.fromOffset(inner, inner),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = z,
		}, glyph)
		corner(f, 100)
		local s = stroke(f, ICON, thick, 0)
		table.insert(inks, s)
		return f
	end

	---------------------------------------------------------------------
	-- ICONS (drawn with frames, they take the icon colour; cut-outs use the tab bar colour)
	---------------------------------------------------------------------
	local CUT = WELL
	local ICONS = {}

	ICONS.Home = function(glyph)
		local R = 3
		local SH = -1
		local roof = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, SH),
			Size = UDim2.fromOffset(16, 16),
			Rotation = 45,
			BackgroundColor3 = ICON,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, glyph)
		corner(roof, R)
		local walls = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.5, SH),
			Size = UDim2.fromOffset(20, 12),
			BackgroundColor3 = ICON,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, glyph)
		corner(walls, R)
		local fill = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.5, SH),
			Size = UDim2.fromOffset(20, 4),
			BackgroundColor3 = ICON,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, glyph)
		local door = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.5, 3),
			Size = UDim2.fromOffset(6, 11),
			BackgroundColor3 = CUT,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, glyph)
		corner(door, 3)
		return { roof, walls, fill }
	end

	ICONS.Info = function(glyph)
		local card = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(24, 18),
			BackgroundColor3 = ICON,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, glyph)
		corner(card, 4)
		local function cut(x, y, w, h, r, anchorX)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(anchorX or 0, 0),
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(w, h),
				BackgroundColor3 = CUT,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, card)
			corner(f, r)
		end
		cut(8, 4, 5, 5, 3, 0.5)
		cut(8, 10, 9, 5, 3, 0.5)
		cut(14, 5, 7, 2, 1)
		cut(14, 9, 7, 2, 1)
		cut(14, 13, 4, 2, 1)
		return { card }
	end

	ICONS.Combat = function(glyph)
		local inks = {}
		table.insert(inks, block(glyph, 22, 22, 0, ICON, 3, 100))
		block(glyph, 16, 16, 0, CUT, 4, 100)
		local function tick(x, y, w, h)
			local f = block(glyph, w, h, y, ICON, 5, 1)
			f.Position = UDim2.new(0.5, x, 0.5, y)
			table.insert(inks, f)
		end
		tick(0, -9, 2, 8)
		tick(0, 9, 2, 8)
		tick(-9, 0, 8, 2)
		tick(9, 0, 8, 2)
		table.insert(inks, block(glyph, 4, 4, 0, ICON, 5, 100))
		return inks
	end

	-- VISUALS: an eye. Two arcs (the lids) meeting in points at the sides, and a solid pupil.
	ICONS.Visuals = function(glyph)
		local inks = {}
		local A = 12      -- half width of the eye
		local B = 8.5     -- half height of the eye (at the middle)
		local N = 14      -- segments per lid
		for side = -1, 1, 2 do
			local px = -A
			local py = 0
			for i = 1, N do
				local x = -A + (2 * A) * i / N
				local t = x / A
				local y = side * B * (1 - t * t)
				segment(glyph, inks, px, py, x, y, 3)
				px = x
				py = y
			end
		end
		table.insert(inks, block(glyph, 8, 8, 0, ICON, 4, 100))
		return inks
	end

	-- WORLD: a globe. Outline circle (24 across), one meridian (ellipse) and the equator. All lines are 2px.
	ICONS.World = function(glyph)
		local inks = {}
		ring(glyph, inks, 24, 2, 0, 0, 3)
		local N = 36
		local RX = 5
		local RY = 10
		local px = 0
		local py = -RY
		for i = 1, N do
			local t = -math.pi / 2 + (2 * math.pi) * i / N
			local x = RX * math.cos(t)
			local y = RY * math.sin(t)
			segment(glyph, inks, px, py, x, y, 4)
			px = x
			py = y
		end
		table.insert(inks, block(glyph, 20, 2, 0, ICON, 4, 1))
		return inks
	end

	-- MISC: a person. Solid head (10) and solid shoulders (the top of a 22 circle, clipped), 22 tall in total, centred.
	ICONS.Misc = function(glyph)
		local inks = {}
		table.insert(inks, block(glyph, 10, 10, -6, ICON, 3, 100))
		local clip = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.5, 1),
			Size = UDim2.fromOffset(22, 10),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 3,
		}, glyph)
		local body = new("Frame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = ICON,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, clip)
		corner(body, 100)
		table.insert(inks, body)
		return inks
	end

	ICONS.Server = function(glyph)
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
				BackgroundColor3 = CUT,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, f)
			corner(dot, 2)
			local dash = new("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 11, 0.5, 0),
				Size = UDim2.fromOffset(7, 2),
				BackgroundColor3 = CUT,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, f)
			corner(dash, 1)
		end
		unit(-6)
		unit(6)
		return inks
	end

	-- CONFIG: a rounded square split into four panes by a cross
	ICONS.Config = function(glyph)
		local inks = {}
		local box = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, glyph)
		corner(box, 5)
		table.insert(inks, stroke(box, ICON, 2, 0))
		table.insert(inks, block(glyph, 2, 20, 0, ICON, 3, 1))
		table.insert(inks, block(glyph, 20, 2, 0, ICON, 3, 1))
		return inks
	end

	ICONS.Settings = function(glyph)
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
		shape(10, 0, 5, CUT)
		return { sq1, sq2 }
	end

	---------------------------------------------------------------------
	-- TABS: id, title in the top bar, name under the icon, short text, icon. Left to right.
	-- A tab is filled by the module you pass in the options:  opts.<Id>Module  (+ opts.<Id> as its settings table)
	--   Home -> HomeModule/Home, Info -> InfoModule/Info, Combat -> CombatModule/Combat, Visuals -> VisualsModule/Visuals,
	--   World -> WorldModule/World, Misc -> MiscModule/Misc, Config -> ConfigModule/Config, Settings -> SettingsModule/Settings.
	-- The Server tab is where finder.lua goes (win:GetPage("Server") / win.MainPage).
	---------------------------------------------------------------------
	local TABS = {
		{ id = "Home",     title = "Home",     tip = "Home",     sub = "Nothing here yet",            icon = ICONS.Home },
		{ id = "Info",     title = "Info",     tip = "Info",     sub = "Your info will show here",    icon = ICONS.Info },
		{ id = "Combat",   title = "Combat",   tip = "Combat",   sub = "Combat options will go here", icon = ICONS.Combat },
		{ id = "Visuals",  title = "Visuals",  tip = "Visuals",  sub = "Visual options will go here", icon = ICONS.Visuals },
		{ id = "World",    title = "World",    tip = "World",    sub = "World options will go here",  icon = ICONS.World },
		{ id = "Misc",     title = "Misc",     tip = "Misc",     sub = "Extra options will go here",  icon = ICONS.Misc },
		{ id = "Server",   title = "Server",   tip = "Server",   sub = "Server tools will go here",   icon = ICONS.Server },
		{ id = "Config",   title = "Config",   tip = "Config",   sub = "Config options will go here", icon = ICONS.Config },
		{ id = "Settings", title = "Settings", tip = "Settings", sub = "Settings will go here",       icon = ICONS.Settings },
	}

	local tabById = {}
	for i = 1, #TABS do
		tabById[TABS[i].id] = TABS[i]
	end
	local currentTab = CONFIG.StartTab
	if not tabById[currentTab] then
		currentTab = TABS[1].id
	end

	---------------------------------------------------------------------
	-- WINDOW
	---------------------------------------------------------------------
	local WIN_W = 760
	local WIN_H = 480
	local BAR_H = 56        -- top bar
	local TAB_H = 62        -- bottom tab bar
	local SLOT_W = 78       -- width of one tab
	local GAP = 8

	local conns = {}
	local alive = true
	local minimized = false
	local maximized = false
	local hidden = false
	local handles = {}      -- what the module pages returned (their Unload is called when this window unloads)
	local unloadCbs = {}    -- win:OnUnload callbacks
	local tabCbs = {}       -- win:OnTab callbacks
	local searchCbs = {}    -- win:OnSearch callbacks

	-- the object this file returns (methods are added further down)
	local win = {}

	local gui = new("ScreenGui", {
		Name = CONFIG.Name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	-- where the window starts: a little right of the middle, so the keybinds panel fits on its left
	local START_POS = UDim2.new(0.5, 132, 0.5, 0)
	if typeof(opts.Position) == "UDim2" then
		START_POS = opts.Position   -- main.lua passes the spot where the welcome window was
	end

	local fitScale = 1
	do
		local cam = workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			fitScale = math.min(1, (vp.X - 24) / WIN_W, (vp.Y - 24) / WIN_H)
			fitScale = math.max(0.5, fitScale)
		end
	end

	-- where the window ends up on screen at start (used to place the keybinds panel and the watermark once)
	local START_LEFT = 0
	local START_TOP = 0
	do
		local vp = gui.AbsoluteSize
		if vp.X <= 0 or vp.Y <= 0 then
			local cam = workspace.CurrentCamera
			if cam then
				vp = cam.ViewportSize
			end
		end
		local ww = WIN_W * fitScale
		local wh = WIN_H * fitScale
		START_LEFT = vp.X * START_POS.X.Scale + START_POS.X.Offset - ww / 2
		START_TOP = vp.Y * START_POS.Y.Scale + START_POS.Y.Offset - wh / 2
	end

	local window = new("CanvasGroup", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = START_POS,
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
			ZIndex = 60,
		}, window)
		corner(outline, 7)
		stroke(outline, BORDER, 1, 0)
	end

	-- top bar (drag handle)
	local bar = new("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundTransparency = 1,
	}, window)

	-- logo: "Y" in red, the last character white with the soft gradient
	do
		local head = string.sub(CONFIG.Logo, 1, -2)
		local tail = string.sub(CONFIG.Logo, -1)
		local row = new("Frame", {
			Name = "Logo",
			Position = UDim2.fromOffset(18, 13),
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			ZIndex = 4,
		}, window)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		local function part(text, order, color)
			return new("TextLabel", {
				LayoutOrder = order,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(0, 30),
				AutomaticSize = Enum.AutomaticSize.X,
				Font = Enum.Font.GothamBlack,
				Text = text,
				TextSize = 24,
				TextColor3 = color,
				ZIndex = 4,
			}, row)
		end
		part(head, 1, CALM_RED)
		local one = part(tail, 2, Color3.new(1, 1, 1))
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 138)),
			}),
		}, one)
		-- thin vertical divider between the logo and the tab name
		new("Frame", {
			Position = UDim2.fromOffset(70, 14),
			Size = UDim2.fromOffset(1, 28),
			BackgroundColor3 = BORDER,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, window)
	end

	-- content card (between the top bar and the tab bar)
	local card = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(GAP, BAR_H),
		Size = UDim2.new(1, -(GAP * 2), 1, -(BAR_H + TAB_H + GAP * 2)),
		BackgroundColor3 = WELL,
		BorderSizePixel = 0,
	}, window)
	corner(card, 8)
	stroke(card, BORDER, 1, 0)

	-- bottom tab bar
	local tabBar = new("Frame", {
		Name = "TabBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, GAP, 1, -GAP),
		Size = UDim2.new(1, -(GAP * 2), 0, TAB_H),
		BackgroundColor3 = WELL,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, window)
	corner(tabBar, 8)
	stroke(tabBar, BORDER, 1, 0)

	-- the tabs sit in a block that stays centred in the bar
	local tabRow = new("Frame", {
		Name = "Tabs",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(SLOT_W * #TABS, TAB_H),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, tabBar)

	---------------------------------------------------------------------
	-- PAGES: every tab has a page (faded in / out) with an empty "Body" frame inside.
	-- The module for that tab builds into the Body. Until something is built there, a short message shows.
	---------------------------------------------------------------------
	local PAGE_POS = UDim2.fromOffset(0, 0)
	local pages = {}          -- [id] = the page (CanvasGroup)
	local containers = {}     -- [id] = the Body frame the modules build into
	local placeholders = {}   -- [id] = { frame, title, sub }

	local function makePage(tab)
		local shown = (tab.id == currentTab)
		local gt = 1
		if shown then
			gt = 0
		end
		local p = new("CanvasGroup", {
			Name = tab.id .. "Page",
			Position = PAGE_POS,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			GroupTransparency = gt,
			Visible = shown,
		}, card)

		local mid = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(420, 120),
			BackgroundTransparency = 1,
		}, p)
		local t1 = label(mid, tab.title, UDim2.fromOffset(0, 8), UDim2.new(1, 0, 0, 26),
			Enum.Font.GothamBold, 20, TEXT_COLOR, Enum.TextXAlignment.Center)
		local t2 = label(mid, tab.sub, UDim2.fromOffset(0, 40), UDim2.new(1, 0, 0, 70),
			Enum.Font.GothamMedium, 12, DIM_TEXT, Enum.TextXAlignment.Center)
		t2.TextWrapped = true
		t2.TextTruncate = Enum.TextTruncate.None
		t2.TextYAlignment = Enum.TextYAlignment.Top

		local body = new("Frame", {
			Name = "Body",
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 1, -16),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, p)
		-- the message goes away as soon as something is built into the page
		body.ChildAdded:Connect(function(c)
			if c:IsA("GuiObject") and mid.Visible then
				mid.Visible = false
			end
		end)

		pages[tab.id] = p
		containers[tab.id] = body
		placeholders[tab.id] = { frame = mid, title = t1, sub = t2 }
	end
	for i = 1, #TABS do
		makePage(TABS[i])
	end

	---------------------------------------------------------------------
	-- TOP BAR: current tab caption + title
	---------------------------------------------------------------------
	local titleLabel = nil
	do
		label(window, "CURRENT TAB", UDim2.fromOffset(84, 11), UDim2.fromOffset(200, 12),
			Enum.Font.GothamMedium, 10, DIM_TEXT)
		titleLabel = label(window, tabById[currentTab].title, UDim2.fromOffset(84, 24),
			UDim2.fromOffset(300, 22), Enum.Font.GothamBold, 17, TEXT_COLOR)
		titleLabel.ZIndex = 3
	end

	---------------------------------------------------------------------
	-- SEARCH BOX (top bar, between the tab name and the window buttons)
	-- You can click it and type. Modules can listen with win:OnSearch(function(query) ... end).
	-- Escape clears it, the small x clears it, Enter just leaves the box.
	---------------------------------------------------------------------
	local searchQuery = ""
	local searchBox = nil

	local function onSearch(query)
		for i = 1, #searchCbs do
			pcall(searchCbs[i], query)
		end
	end

	do
		local PILL_W = 260
		local PILL_H = 32

		local pill = new("Frame", {
			Name = "Search",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, BAR_H / 2),
			Size = UDim2.fromOffset(PILL_W, PILL_H),
			BackgroundColor3 = WELL,
			BorderSizePixel = 0,
			Active = true,   -- clicks on the pill must not start dragging the window
			ZIndex = 10,
		}, window)
		corner(pill, 100)
		local pillStroke = stroke(pill, BORDER, 1, 0)

		-- magnifier: a ring and a handle, 2.5px lines
		local LINE = 2.5
		local holder = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(21, PILL_H / 2),
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			ZIndex = 11,
		}, pill)
		local ringF = new("Frame", {
			Position = UDim2.fromOffset(1 + LINE, 1 + LINE),
			Size = UDim2.fromOffset(16 - LINE * 2, 16 - LINE * 2),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 12,
		}, holder)
		corner(ringF, 100)
		local ringStroke = stroke(ringF, ICON, LINE, 0)
		local handle = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(16.8, 16.8),
			Size = UDim2.fromOffset(9, LINE),
			Rotation = 45,
			BackgroundColor3 = ICON,
			BorderSizePixel = 0,
			ZIndex = 12,
		}, holder)
		corner(handle, 1)

		local box = new("TextBox", {
			Name = "SearchBox",
			Position = UDim2.fromOffset(38, 0),
			Size = UDim2.new(1, -(38 + 34), 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Text = "",
			PlaceholderText = "Search features",
			PlaceholderColor3 = DIM_TEXT,
			TextColor3 = TEXT_COLOR,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 12,
		}, pill)
		searchBox = box

		-- clicking the magnifier also puts the cursor in the box
		local iconHit = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(36, PILL_H),
			ZIndex = 13,
		}, pill)
		iconHit.Activated:Connect(function()
			box:CaptureFocus()
		end)

		-- small x on the right, only while there is text
		local clearBtn = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 13,
		}, pill)
		local clearParts = {}
		for i = 1, 2 do
			local rot = 45
			if i == 2 then
				rot = -45
			end
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(11, 2.5),
				Rotation = rot,
				BackgroundColor3 = DIM_TEXT,
				BorderSizePixel = 0,
				ZIndex = 14,
			}, clearBtn)
			corner(f, 1)
			clearParts[i] = f
		end
		clearBtn.MouseEnter:Connect(function()
			for i = 1, #clearParts do
				TweenService:Create(clearParts[i], FAST, { BackgroundColor3 = ICON_HOVER }):Play()
			end
		end)
		clearBtn.MouseLeave:Connect(function()
			for i = 1, #clearParts do
				TweenService:Create(clearParts[i], FAST, { BackgroundColor3 = DIM_TEXT }):Play()
			end
		end)
		clearBtn.Activated:Connect(function()
			box.Text = ""
			box:CaptureFocus()
		end)

		-- the look changes while the box has the cursor: red outline, brighter magnifier
		local function paintFocus(on)
			local line = BORDER
			local ink = ICON
			if on then
				line = CALM_RED
				ink = ICON_HOVER
			end
			TweenService:Create(pillStroke, FAST, { Color = line }):Play()
			TweenService:Create(ringStroke, FAST, { Color = ink }):Play()
			TweenService:Create(handle, FAST, { BackgroundColor3 = ink }):Play()
		end
		box.Focused:Connect(function()
			paintFocus(true)
		end)
		box.FocusLost:Connect(function(enterPressed, input)
			paintFocus(false)
			if input and input.KeyCode == Enum.KeyCode.Escape then
				box.Text = ""
			end
		end)

		box:GetPropertyChangedSignal("Text"):Connect(function()
			searchQuery = box.Text
			clearBtn.Visible = (box.Text ~= "")
			onSearch(searchQuery)
		end)
	end

	---------------------------------------------------------------------
	-- TAB BAR: icon + name for every tab, a hover pill, and the sliding red marker
	---------------------------------------------------------------------
	local navIcons = {}
	local navPos = {}
	local showTab = function(_id) end

	local marker = new("Frame", {
		Name = "NavMarker",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(28, 3),
		BackgroundColor3 = CALM_RED,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, tabRow)
	corner(marker, 2)

	do
		for i = 1, #TABS do
			local tab = TABS[i]
			local x0 = (i - 1) * SLOT_W
			navPos[tab.id] = UDim2.fromOffset(x0 + (SLOT_W - 28) / 2, 0)

			local slot = new("Frame", {
				Name = tab.id .. "Tab",
				Position = UDim2.fromOffset(x0, 0),
				Size = UDim2.fromOffset(SLOT_W, TAB_H),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, tabRow)

			-- soft pill behind the tab (shows on hover, faintly on the active tab)
			local pill = new("Frame", {
				Position = UDim2.fromOffset(5, 7),
				Size = UDim2.new(1, -10, 1, -14),
				BackgroundColor3 = HOVER_GREY,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, slot)
			corner(pill, 8)

			local glyph = new("Frame", {
				Name = "Glyph",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, 22),
				Size = UDim2.fromOffset(34, 34),
				BackgroundTransparency = 1,
				ZIndex = 4,
			}, slot)
			local glyphScale = new("UIScale", { Scale = 0.85 }, glyph)
			local inks = tab.icon(glyph)

			local name = label(slot, tab.tip, UDim2.new(0, 0, 0, 40), UDim2.new(1, 0, 0, 14),
				Enum.Font.GothamMedium, 11, DIM_TEXT, Enum.TextXAlignment.Center)
			name.ZIndex = 4

			local active = false
			local hovering = false
			local function paint()
				local color = ICON
				local nameColor = DIM_TEXT
				local pillT = 1
				if active then
					color = ICON_HOVER
					nameColor = TEXT_COLOR
					pillT = 0.82
				end
				if hovering then
					color = ICON_HOVER
					if not active then
						nameColor = ICON
					end
					pillT = 0.55
				end
				for k = 1, #inks do
					local ink = inks[k]
					local prop = "BackgroundColor3"
					if ink:IsA("UIStroke") then
						prop = "Color"
					end
					TweenService:Create(ink, FAST, { [prop] = color }):Play()
				end
				TweenService:Create(name, FAST, { TextColor3 = nameColor }):Play()
				TweenService:Create(pill, FAST, { BackgroundTransparency = pillT }):Play()
			end

			local hit = new("TextButton", {
				Name = "Hit",
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 8,
			}, slot)
			hit.Activated:Connect(function()
				showTab(tab.id)
			end)

			hit.MouseEnter:Connect(function()
				hovering = true
				TweenService:Create(glyphScale, GROW, { Scale = 0.98 }):Play()
				paint()
			end)
			hit.MouseLeave:Connect(function()
				hovering = false
				TweenService:Create(glyphScale, GROW, { Scale = 0.85 }):Play()
				paint()
			end)
			hit.MouseButton1Down:Connect(function()
				TweenService:Create(glyphScale, FAST, { Scale = 0.78 }):Play()
			end)
			hit.MouseButton1Up:Connect(function()
				local s = 0.85
				if hovering then
					s = 0.98
				end
				TweenService:Create(glyphScale, GROW, { Scale = s }):Play()
			end)

			navIcons[tab.id] = function(isActive)
				active = isActive
				paint()
			end
		end
	end

	local markerPlaced = false
	local function navUpdate()
		for id, setActive in pairs(navIcons) do
			setActive(id == currentTab)
		end
		local p = navPos[currentTab]
		if p then
			if markerPlaced then
				TweenService:Create(marker, SMOOTH, { Position = p }):Play()
			else
				marker.Position = p
				markerPlaced = true
			end
		end
	end
	navUpdate()

	---------------------------------------------------------------------
	-- TAB SWITCHING
	---------------------------------------------------------------------
	do
		local pageToken = 0
		local titleToken = 0
		showTab = function(id)
			if id == currentTab or not pages[id] then
				return
			end
			currentTab = id
			navUpdate()

			pageToken = pageToken + 1
			local pt = pageToken
			local nxt = pages[id]
			for pid, p in pairs(pages) do
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
			local tk = titleToken
			TweenService:Create(titleLabel, FAST, { TextTransparency = 1 }):Play()
			task.delay(0.12, function()
				if tk ~= titleToken then
					return
				end
				titleLabel.Text = tabById[id].title
				TweenService:Create(titleLabel, FAST, { TextTransparency = 0 }):Play()
			end)

			for i = 1, #tabCbs do
				pcall(tabCbs[i], id)
			end
		end
	end

	---------------------------------------------------------------------
	-- KEYBINDS PANEL (small card that spawns at the top left of the main window, top edges level)
	--   * drag it by its title bar; it stays where you put it
	--   * opens / closes with the keyboard button in the top bar (left of minimize) and closes with its x
	--   * click a key box, then press a key or a mouse button to change it (Escape = cancel, Backspace = none)
	--   * plain rows are added by the modules:  win:AddBind({ id = "Aimbot", title = "Aimbot", wired = true,
	--         default = { kind = "Key", key = Enum.KeyCode.E } })      (or pass opts.Binds when creating the window)
	--     and read with  win:IsBind(id, input)  /  win:GetBind(id)
	--   * modules you can turn on / off are added with win:AddToggle (or opts.Toggles). They get the same row
	--     plus a status dot, and their key flips them on / off. See the MODULE TOGGLES notes at the top.
	---------------------------------------------------------------------
	local BINDS = {}
	local bindDef = {}
	local binds = {}

	local function bindName(b)
		if not b then
			return "None"
		end
		if b.kind == "Mouse" then
			return "Mouse " .. tostring(b.n)
		end
		return b.key.Name
	end

	local function bindMatches(id, input)
		local b = binds[id]
		if not b then
			return false
		end
		if b.kind == "Key" then
			return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == b.key
		end
		local t = input.UserInputType
		if b.n == 1 then
			return t == Enum.UserInputType.MouseButton1
		elseif b.n == 2 then
			return t == Enum.UserInputType.MouseButton2
		end
		return t == Enum.UserInputType.MouseButton3
	end

	local KB_W = 232
	local KB_HEAD = 42
	local KB_ROW = 34
	local KB_LINE_HOVER = Color3.fromRGB(96, 96, 102)
	local kbOpen = true
	local kbSuppressed = false
	local kbListening = nil     -- id of the bind that is waiting for a key
	local kbLastBind = 0
	local kbToken = 0
	local kbPills = {}
	local kbLines = {}
	local kbDots = {}           -- [id] = the on / off dot of a toggle row

	local kbPanel = new("CanvasGroup", {
		Name = "Keybinds",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(0, 0),   -- kbDock() puts it next to the window every frame
		Size = UDim2.fromOffset(KB_W, KB_HEAD + KB_ROW + 12),
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
	}, gui)
	corner(kbPanel, 8)
	local kbScale = new("UIScale", { Scale = 0.92 }, kbPanel)
	do
		local outline = new("Frame", {
			Position = UDim2.fromOffset(1, 1),
			Size = UDim2.new(1, -2, 1, -2),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 30,
		}, kbPanel)
		corner(outline, 7)
		stroke(outline, BORDER, 1, 0)
	end

	local kbHead = new("Frame", {
		Name = "Head",
		Size = UDim2.new(1, 0, 0, KB_HEAD),
		BackgroundTransparency = 1,
		Active = true,
		ZIndex = 2,
	}, kbPanel)

	-- keyboard icon (calm red)
	do
		local ico = new("Frame", {
			Position = UDim2.fromOffset(14, 13),
			Size = UDim2.fromOffset(18, 16),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, kbPanel)
		local body = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(14, 10),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, ico)
		corner(body, 3)
		stroke(body, CALM_RED, 2, 0)
		for k = -1, 1 do
			local d = block(ico, 2, 2, -2, CALM_RED, 4, 1)
			d.Position = UDim2.new(0.5, k * 4, 0.5, -2)
		end
		block(ico, 8, 2, 2, CALM_RED, 4, 1)
	end
	label(kbPanel, "Keybinds", UDim2.fromOffset(40, 0), UDim2.new(1, -90, 0, KB_HEAD),
		Enum.Font.GothamBold, 14, TEXT_COLOR).ZIndex = 3

	new("Frame", {
		Position = UDim2.fromOffset(14, KB_HEAD - 1),
		Size = UDim2.new(1, -28, 0, 1),
		BackgroundColor3 = BORDER,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, kbPanel)

	-- shown while there are no rows
	local kbEmpty = label(kbPanel, "Nothing here yet", UDim2.fromOffset(0, KB_HEAD + 4), UDim2.new(1, 0, 0, KB_ROW - 4),
		Enum.Font.GothamMedium, 12, DIM_TEXT, Enum.TextXAlignment.Center)
	kbEmpty.ZIndex = 3

	local function kbRefresh()
		local show = kbOpen and not kbSuppressed
		kbToken = kbToken + 1
		local tk = kbToken
		if show then
			kbPanel.Visible = true
			TweenService:Create(kbScale, POP, { Scale = 1 }):Play()
			TweenService:Create(kbPanel, FAST, { GroupTransparency = 0 }):Play()
		else
			kbListening = nil
			for id, pill in pairs(kbPills) do
				pill.Text = bindName(binds[id])
				pill.TextColor3 = bindDef[id].wired and ICON or DIM_TEXT
				kbLines[id].Color = BORDER
			end
			TweenService:Create(kbScale, LEAVE, { Scale = 0.92 }):Play()
			TweenService:Create(kbPanel, LEAVE, { GroupTransparency = 1 }):Play()
			task.delay(LEAVE.Time + 0.02, function()
				if tk == kbToken then
					kbPanel.Visible = false
				end
			end)
		end
	end

	local function kbSetSuppressed(on)
		kbSuppressed = on
		kbRefresh()
	end

	-- close button (x)
	do
		local x = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0, KB_HEAD / 2),
			Size = UDim2.fromOffset(26, 24),
			BackgroundColor3 = CALM_RED,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 6,
		}, kbPanel)
		corner(x, 6)
		local parts = {}
		for i = 1, 2 do
			local rot = 45
			if i == 2 then
				rot = -45
			end
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(11, 2),
				Rotation = rot,
				BackgroundColor3 = ICON,
				BorderSizePixel = 0,
				ZIndex = 7,
			}, x)
			corner(f, 1)
			parts[i] = f
		end
		x.MouseEnter:Connect(function()
			TweenService:Create(x, FAST, { BackgroundTransparency = 0 }):Play()
			for i = 1, #parts do
				TweenService:Create(parts[i], FAST, { BackgroundColor3 = ICON_HOVER }):Play()
			end
		end)
		x.MouseLeave:Connect(function()
			TweenService:Create(x, FAST, { BackgroundTransparency = 1 }):Play()
			for i = 1, #parts do
				TweenService:Create(parts[i], FAST, { BackgroundColor3 = ICON }):Play()
			end
		end)
		x.Activated:Connect(function()
			kbOpen = false
			kbRefresh()
		end)
	end

	-- one row per bind: name on the left, key box on the right
	local function kbPaint(id)
		local pill = kbPills[id]
		if not pill then
			return
		end
		if kbListening == id then
			pill.Text = "Press a key"
			TweenService:Create(pill, FAST, { TextColor3 = CALM_RED }):Play()
			TweenService:Create(kbLines[id], FAST, { Color = CALM_RED }):Play()
		else
			pill.Text = bindName(binds[id])
			local c = ICON
			if not bindDef[id].wired then
				c = DIM_TEXT
			end
			TweenService:Create(pill, FAST, { TextColor3 = c }):Play()
			TweenService:Create(kbLines[id], FAST, { Color = BORDER }):Play()
		end
	end

	-- adds a row to the panel (safe to call any time, a second call with the same id does nothing)
	-- def.toggle = true adds the small on / off dot in front of the name (win:AddToggle does this for you)
	local function addBind(def)
		if type(def) ~= "table" or type(def.id) ~= "string" or bindDef[def.id] then
			return
		end
		local i = #BINDS + 1
		BINDS[i] = def
		bindDef[def.id] = def
		binds[def.id] = def.default

		local y = KB_HEAD + 4 + (i - 1) * KB_ROW
		local nameColor = TEXT_COLOR
		if not def.wired then
			nameColor = DIM_TEXT
		end

		local nameX = 16
		if def.toggle then
			nameX = 32
			local dot = new("Frame", {
				Name = def.id .. "Dot",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(16, y + (KB_ROW - 4) / 2),
				Size = UDim2.fromOffset(8, 8),
				BackgroundColor3 = DIM_TEXT,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, kbPanel)
			corner(dot, 100)
			kbDots[def.id] = dot
		end
		label(kbPanel, tostring(def.title or def.id), UDim2.fromOffset(nameX, y), UDim2.new(1, -(nameX + 114), 0, KB_ROW - 4),
			Enum.Font.GothamMedium, 13, nameColor).ZIndex = 3

		local pill = new("TextButton", {
			Name = def.id .. "Key",
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0, y + (KB_ROW - 4) / 2),
			Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = WELL,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			Text = bindName(binds[def.id]),
			TextSize = 12,
			TextColor3 = def.wired and ICON or DIM_TEXT,
			ZIndex = 4,
		}, kbPanel)
		corner(pill, 6)
		new("UIPadding", { PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11) }, pill)
		new("UISizeConstraint", { MinSize = Vector2.new(66, 26) }, pill)
		local line = stroke(pill, BORDER, 1, 0)
		kbPills[def.id] = pill
		kbLines[def.id] = line

		pill.MouseEnter:Connect(function()
			if kbListening ~= def.id then
				TweenService:Create(line, FAST, { Color = KB_LINE_HOVER }):Play()
				TweenService:Create(pill, FAST, { TextColor3 = ICON_HOVER }):Play()
			end
		end)
		pill.MouseLeave:Connect(function()
			if kbListening ~= def.id then
				kbPaint(def.id)
			end
		end)
		pill.Activated:Connect(function()
			-- the click that just set a key must not start listening again
			if os.clock() - kbLastBind < 0.2 then
				return
			end
			local prev = kbListening
			if prev == def.id then
				kbListening = nil
			else
				kbListening = def.id
			end
			if prev then
				kbPaint(prev)
			end
			kbPaint(def.id)
		end)

		kbEmpty.Visible = false
		kbPanel.Size = UDim2.fromOffset(KB_W, KB_HEAD + #BINDS * KB_ROW + 12)
	end

	-- the next key / mouse button pressed becomes the bind
	table.insert(conns, UserInputService.InputBegan:Connect(function(input)
		if not kbListening then
			return
		end
		local id = kbListening
		local t = input.UserInputType
		local newBind = nil
		local clear = false
		if t == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape then
				-- cancel: keep the old key
			elseif input.KeyCode == Enum.KeyCode.Backspace then
				clear = true
			elseif input.KeyCode ~= Enum.KeyCode.Unknown then
				newBind = { kind = "Key", key = input.KeyCode }
			else
				return
			end
		elseif t == Enum.UserInputType.MouseButton1 then
			newBind = { kind = "Mouse", n = 1 }
		elseif t == Enum.UserInputType.MouseButton2 then
			newBind = { kind = "Mouse", n = 2 }
		elseif t == Enum.UserInputType.MouseButton3 then
			newBind = { kind = "Mouse", n = 3 }
		else
			return
		end
		if clear then
			binds[id] = nil
		elseif newBind then
			binds[id] = newBind
		end
		kbListening = nil
		kbLastBind = os.clock()
		kbPaint(id)
	end))

	---------------------------------------------------------------------
	-- MODULE TOGGLES: every module you can turn on / off (Trigger Bot, Aimbot, ESP ...) shows up in the
	-- keybinds panel with a status dot (grey = off, green = on). Its key flips it.
	---------------------------------------------------------------------
	local toggles = {}   -- [id] = { def = def, on = bool, listeners = { fn(on) } }

	local function paintDot(id)
		local d = kbDots[id]
		if not d then
			return
		end
		local c = DIM_TEXT
		if toggles[id] and toggles[id].on then
			c = ON_GREEN
		end
		TweenService:Create(d, FAST, { BackgroundColor3 = c }):Play()
	end

	-- sets a toggle. silent = true skips the toast (used when the module's own switch changed it)
	local function setToggle(id, on, silent)
		local t = toggles[id]
		if not t then
			return
		end
		on = on and true or false
		if t.on == on then
			return
		end
		t.on = on
		paintDot(id)
		if type(t.def.onToggle) == "function" then
			pcall(t.def.onToggle, on)
		end
		for i = 1, #t.listeners do
			pcall(t.listeners[i], on)
		end
		if not silent then
			local word = "off"
			if on then
				word = "on"
			end
			win:Toast(tostring(t.def.title or id) .. " " .. word, 1.5)
		end
	end

	-- registers a module: adds its keybind row (with the dot) and makes the key flip it
	local function addToggle(def)
		if type(def) ~= "table" or type(def.id) ~= "string" or toggles[def.id] then
			return
		end
		toggles[def.id] = { def = def, on = false, listeners = {} }
		addBind({
			id = def.id,
			title = def.title or def.id,
			wired = (def.wired ~= false),
			default = def.default,
			toggle = true,
		})
		if def.enabled then
			setToggle(def.id, true, true)
		end
	end

	-- the key / mouse button flips the module (not while typing in a box, not while rebinding)
	-- (connected after the rebinding handler above, so the key that finishes a rebind is ignored by the guard)
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or kbListening or os.clock() - kbLastBind < 0.2 then
			return
		end
		for id, t in pairs(toggles) do
			if bindMatches(id, input) then
				setToggle(id, not t.on)
			end
		end
	end))

	-- starts to the left of the window (top edges level) and then stays where it is: it does NOT follow the window.
	-- Drag it by its title bar to move it.
	local kbAbs = Vector2.new(START_LEFT - (KB_W + 10), START_TOP)
	local kbDragging = false
	local function kbDock()
		local vp = gui.AbsoluteSize
		local ab = kbPanel.AbsoluteSize
		if ab.X <= 0 then
			ab = Vector2.new(KB_W, ab.Y)
		end
		local x = math.clamp(kbAbs.X, 6, math.max(6, vp.X - ab.X - 6))
		local y = math.clamp(kbAbs.Y, 6, math.max(6, vp.Y - ab.Y - 6))
		kbAbs = Vector2.new(x, y)
		kbPanel.Position = UDim2.fromOffset(x, y)
	end
	table.insert(conns, RunService.RenderStepped:Connect(kbDock))
	kbDock()

	do
		local dragStart = nil
		local startOff = nil
		kbHead.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				kbDragging = true
				dragStart = input.Position
				startOff = kbAbs
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						kbDragging = false
					end
				end)
			end
		end)
		table.insert(conns, UserInputService.InputChanged:Connect(function(input)
			if not kbDragging then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				local d = input.Position - dragStart
				kbAbs = startOff + Vector2.new(d.X, d.Y)
			end
		end))
	end

	if type(opts.Binds) == "table" then
		for i = 1, #opts.Binds do
			addBind(opts.Binds[i])
		end
	end
	if type(opts.Toggles) == "table" then
		for i = 1, #opts.Toggles do
			addToggle(opts.Toggles[i])
		end
	end

	kbRefresh()

	---------------------------------------------------------------------
	-- WINDOW CONTROLS (top right): keybinds, minimize, maximize, close
	---------------------------------------------------------------------
	local controls = {}
	do
		local BTN_W = 30
		local BTN_H = 26
		if touch then
			BTN_W = 40
			BTN_H = 32
		end
		local cluster = new("Frame", {
			Name = "Controls",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 12),
			Size = UDim2.fromOffset(BTN_W * 4 + 12, BTN_H),
			BackgroundTransparency = 1,
			ZIndex = 20,
		}, window)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}, cluster)

		local function makeControl(kind, order, hoverColor)
			local btn = new("TextButton", {
				Name = kind,
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = order,
				Size = UDim2.fromOffset(BTN_W, BTN_H),
				BackgroundColor3 = hoverColor,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 21,
			}, cluster)
			corner(btn, 6)

			local parts = {}
			local function line(w, h, rot)
				local f = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(w, h),
					Rotation = rot or 0,
					BackgroundColor3 = ICON,
					BorderSizePixel = 0,
					ZIndex = 22,
				}, btn)
				corner(f, 1)
				table.insert(parts, { f, "BackgroundColor3" })
			end

			if kind == "keybinds" then
				-- a small keyboard: outline + space bar
				local kbd = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(11, 7),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 22,
				}, btn)
				corner(kbd, 2)
				table.insert(parts, { stroke(kbd, ICON, 1.5, 0), "Color" })
				local sp = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, 0, 0.5, 1.5),
					Size = UDim2.fromOffset(6, 1.5),
					BackgroundColor3 = ICON,
					BorderSizePixel = 0,
					ZIndex = 22,
				}, btn)
				corner(sp, 1)
				table.insert(parts, { sp, "BackgroundColor3" })
			elseif kind == "minimize" then
				line(10, 2)
			elseif kind == "maximize" then
				local sq = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(10, 10),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 22,
				}, btn)
				corner(sq, 3)
				table.insert(parts, { stroke(sq, ICON, 1.5, 0), "Color" })
			else
				line(13, 2, 45)
				line(13, 2, -45)
			end

			local over = false
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
				over = true
				paint(true, false)
			end)
			btn.MouseLeave:Connect(function()
				over = false
				paint(false, false)
			end)
			btn.MouseButton1Down:Connect(function()
				paint(true, true)
			end)
			btn.MouseButton1Up:Connect(function()
				paint(over, false)
			end)
			return btn
		end

		controls.keybinds = makeControl("keybinds", 0, HOVER_GREY)
		controls.keybinds.Activated:Connect(function()
			kbOpen = not kbOpen
			kbRefresh()
		end)
		controls.minimize = makeControl("minimize", 1, HOVER_GREY)
		controls.maximize = makeControl("maximize", 2, HOVER_GREY)
		controls.close = makeControl("close", 3, CALM_RED)
	end

	---------------------------------------------------------------------
	-- UNLOAD: stops every module page, disconnects everything, removes the window, runs win:OnUnload callbacks
	---------------------------------------------------------------------
	local function unload()
		if not alive then
			return
		end
		alive = false
		-- every module is switched off first, so nothing keeps running after the window is gone
		for id, t in pairs(toggles) do
			if t.on then
				t.on = false
				if type(t.def.onToggle) == "function" then
					pcall(t.def.onToggle, false)
				end
				for i = 1, #t.listeners do
					pcall(t.listeners[i], false)
				end
			end
		end
		for i = 1, #handles do
			local h = handles[i]
			if type(h) == "table" and type(h.Unload) == "function" then
				pcall(h.Unload)
			end
		end
		handles = {}
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		if env0 and env0.__Y1_UI_STOP == unload then
			env0.__Y1_UI_STOP = nil
		end
		pcall(function()
			gui:Destroy()
		end)
		local cbs = unloadCbs
		unloadCbs = {}
		for i = 1, #cbs do
			pcall(cbs[i])
		end
	end
	if env0 then
		env0.__Y1_UI_STOP = unload
	end

	---------------------------------------------------------------------
	-- WINDOW BEHAVIOUR: minimize square, maximize, close, hide key, drag
	---------------------------------------------------------------------
	do
		local normalPos = window.Position
		local sizeTweens = {}
		local winToken = 0
		local miniToken = 0
		local miniSaved = nil
		local MINI = 44

		-- the small Y1 square that stands in for the window while it is minimized
		local mini = new("TextButton", {
			Name = "MiniButton",
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.new(0, 12, 0.5, -MINI / 2),
			Size = UDim2.fromOffset(MINI, MINI),
			BackgroundColor3 = BG,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 5,
		}, gui)
		corner(mini, 10)
		local miniStroke = stroke(mini, BORDER, 1, 0)
		local miniScale = new("UIScale", { Scale = 0.6 }, mini)
		new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.GothamBlack,
			Text = "<font color=\"rgb(196,92,92)\">" .. string.sub(CONFIG.Logo, 1, -2) .. "</font>" .. string.sub(CONFIG.Logo, -1),
			RichText = true,
			TextSize = 20,
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = 6,
		}, mini)
		mini.MouseEnter:Connect(function()
			TweenService:Create(miniStroke, FAST, { Color = CALM_RED }):Play()
		end)
		mini.MouseLeave:Connect(function()
			TweenService:Create(miniStroke, FAST, { Color = BORDER }):Play()
		end)

		local function miniShow(show)
			miniToken = miniToken + 1
			local tk = miniToken
			if show then
				miniScale.Scale = 0.6
				mini.Visible = true
				TweenService:Create(miniScale, POP, { Scale = 1 }):Play()
			else
				TweenService:Create(miniScale, LEAVE, { Scale = 0.6 }):Play()
				task.delay(LEAVE.Time + 0.02, function()
					if tk == miniToken then
						mini.Visible = false
					end
				end)
			end
		end

		local function baseScale()
			if maximized then
				return 1
			end
			return fitScale
		end

		local function minimizeWindow()
			if minimized or not alive then
				return
			end
			minimized = true
			hidden = false
			kbSetSuppressed(true)
			winToken = winToken + 1
			local tk = winToken
			TweenService:Create(windowScale, LEAVE, { Scale = baseScale() * 0.85 }):Play()
			TweenService:Create(window, LEAVE, { GroupTransparency = 1 }):Play()
			task.delay(LEAVE.Time + 0.02, function()
				if tk == winToken then
					window.Visible = false
				end
			end)
			if miniSaved then
				mini.Position = miniSaved
			else
				mini.Position = UDim2.new(0, 12, 0.5, -MINI / 2)
			end
			miniShow(true)
		end

		local function restore()
			if not minimized then
				return
			end
			minimized = false
			kbSetSuppressed(false)
			winToken = winToken + 1
			miniShow(false)
			windowScale.Scale = baseScale() * 0.85
			window.GroupTransparency = 1
			window.Visible = true
			TweenService:Create(windowScale, POP, { Scale = baseScale() }):Play()
			TweenService:Create(window, FAST, { GroupTransparency = 0 }):Play()
		end

		controls.minimize.Activated:Connect(minimizeWindow)

		controls.maximize.Activated:Connect(function()
			if minimized then
				return
			end
			for i = 1, #sizeTweens do
				sizeTweens[i]:Cancel()
			end
			sizeTweens = {}
			local t1 = nil
			local t2 = nil
			if maximized then
				maximized = false
				t1 = TweenService:Create(window, SMOOTH, { Size = UDim2.fromOffset(WIN_W, WIN_H), Position = normalPos })
				t2 = TweenService:Create(windowScale, SMOOTH, { Scale = fitScale })
			else
				normalPos = window.Position
				maximized = true
				t1 = TweenService:Create(window, SMOOTH, {
					Size = UDim2.new(1, -48, 1, -48),
					Position = UDim2.fromScale(0.5, 0.5),
				})
				t2 = TweenService:Create(windowScale, SMOOTH, { Scale = 1 })
			end
			sizeTweens = { t1, t2 }
			t1:Play()
			t2:Play()
		end)

		controls.close.Activated:Connect(function()
			if not alive then
				return
			end
			TweenService:Create(window, LEAVE, { GroupTransparency = 1 }):Play()
			TweenService:Create(windowScale, LEAVE, { Scale = windowScale.Scale * 0.92 }):Play()
			task.delay(LEAVE.Time + 0.03, unload)
		end)

		-- drag the little square anywhere; a tap without moving opens the window again
		local mDragging = false
		local mMoved = false
		local mGrab = nil
		local mStart = nil

		local function pointer(input)
			local inset = GuiService:GetGuiInset()
			return Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y)
		end

		mini.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				mDragging = true
				mMoved = false
				mStart = pointer(input)
				mGrab = mStart - mini.AbsolutePosition
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
				if not mMoved and (p - mStart).Magnitude > 4 then
					mMoved = true
				end
				if mMoved then
					local vp = gui.AbsoluteSize
					local nx = math.clamp(p.X - mGrab.X, 0, math.max(0, vp.X - MINI))
					local ny = math.clamp(p.Y - mGrab.Y, 0, math.max(0, vp.Y - MINI))
					mini.Position = UDim2.fromOffset(nx, ny)
				end
			end
		end))

		-- hide / show with the key (the window shrinks a little and fades)
		local animToken = 0
		local function setHidden(hide)
			if minimized or hidden == hide then
				return
			end
			hidden = hide
			kbSetSuppressed(hide)
			animToken = animToken + 1
			local tk = animToken
			if hide then
				TweenService:Create(windowScale, LEAVE, { Scale = baseScale() * 0.92 }):Play()
				TweenService:Create(window, LEAVE, { GroupTransparency = 1 }):Play()
				task.delay(LEAVE.Time + 0.02, function()
					if tk == animToken then
						window.Visible = false
					end
				end)
			else
				window.Visible = true
				TweenService:Create(windowScale, POP, { Scale = baseScale() }):Play()
				TweenService:Create(window, FAST, { GroupTransparency = 0 }):Play()
			end
		end
		win.SetHidden = function(_, hide)
			setHidden(hide and true or false)
		end

		table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.KeyCode == CONFIG.HideKey then
				setHidden(not hidden)
			end
		end))

		-- drag the window by the top bar (not while maximized)
		local dragging = false
		local dragStart = nil
		local startPos = nil
		bar.InputBegan:Connect(function(input)
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
	-- WATERMARK (spawns above the left of the main window and then stays on screen; drag it to move it)
	--   two layers: [Y1] | account name   on top,   game | time in the script   below
	--   * account name: the username from the login (main.lua puts it in getgenv().Y1_SESSION); "Guest" otherwise
	--   * game: the name of the experience you are in
	--   * time: how long this window has been running
	--   Turn it off with  Watermark = false  in the options.
	---------------------------------------------------------------------
	if CONFIG.Watermark then
		local session = nil
		if env0 and type(env0.Y1_SESSION) == "table" then
			session = env0.Y1_SESSION
		end

		local accountName = "Guest"
		if session and type(session.username) == "string" and session.username ~= "" then
			accountName = session.username
		end
		local startedAt = os.time()
		if session and type(session.started) == "number" then
			startedAt = session.started
		end

		local function shorten(s, maxChars)
			local ok, res = pcall(function()
				local n = utf8.len(s)
				if n and n > maxChars then
					return string.sub(s, 1, utf8.offset(s, maxChars) - 1) .. "..."
				end
				return s
			end)
			if ok and res then
				return res
			end
			if #s > maxChars then
				return string.sub(s, 1, maxChars - 1) .. "..."
			end
			return s
		end

		local wm = new("Frame", {
			Name = "Watermark",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromOffset(0, 0),   -- wmDock() keeps it on screen every frame
			Size = UDim2.fromOffset(0, 68),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = BG,
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			Active = true,
			ZIndex = 50,
		}, gui)
		corner(wm, 12)
		stroke(wm, BORDER, 1, 0)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 5),
			PaddingBottom = UDim.new(0, 5),
		}, wm)
		local function makeRow(y, h)
			local row = new("Frame", {
				Position = UDim2.fromOffset(0, y),
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(0, h),
				AutomaticSize = Enum.AutomaticSize.X,
				ZIndex = 51,
			}, wm)
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 9),
			}, row)
			return row
		end
		local rowTop = makeRow(0, 30)
		local midLine = new("Frame", {
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.fromOffset(0, 1),
			BackgroundColor3 = BORDER,
			BorderSizePixel = 0,
			ZIndex = 51,
		}, wm)
		local rowBottom = makeRow(31, 27)
		wm:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local w = math.max(0, wm.AbsoluteSize.X - 28)
			midLine.Size = UDim2.fromOffset(w, 1)
		end)

		local order = 0
		local function item(row, text, color, font, size, rich)
			order = order + 1
			return new("TextLabel", {
				LayoutOrder = order,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(0, 27),
				AutomaticSize = Enum.AutomaticSize.X,
				Font = font,
				Text = text,
				TextSize = size,
				TextColor3 = color,
				RichText = rich or false,
				ZIndex = 52,
			}, row)
		end
		local function divider(row)
			order = order + 1
			new("Frame", {
				LayoutOrder = order,
				Size = UDim2.fromOffset(1, 14),
				BackgroundColor3 = BORDER,
				BorderSizePixel = 0,
				ZIndex = 52,
			}, row)
		end

		local head = string.sub(CONFIG.Logo, 1, -2)
		local tail = string.sub(CONFIG.Logo, -1)
		item(rowTop, "<font color=\"rgb(196,92,92)\">" .. head .. "</font>" .. tail, Color3.new(1, 1, 1),
			Enum.Font.GothamBlack, 17, true)
		divider(rowTop)
		item(rowTop, shorten(accountName, 16), TEXT_COLOR, Enum.Font.GothamBold, 15, false)
		local function clockIcon(row)
			order = order + 1
			local holder = new("Frame", {
				LayoutOrder = order,
				Size = UDim2.fromOffset(16, 16),
				BackgroundTransparency = 1,
				ZIndex = 52,
			}, row)
			local face = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(12, 12),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 52,
			}, holder)
			corner(face, 100)
			stroke(face, CALM_RED, 2, 0)
			local up = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(2, 5),
				BackgroundColor3 = CALM_RED,
				BorderSizePixel = 0,
				ZIndex = 53,
			}, holder)
			corner(up, 1)
			local right = new("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(4, 2),
				BackgroundColor3 = CALM_RED,
				BorderSizePixel = 0,
				ZIndex = 53,
			}, holder)
			corner(right, 1)
		end

		local gameLbl = item(rowBottom, "...", ICON, Enum.Font.GothamMedium, 13, false)
		divider(rowBottom)
		clockIcon(rowBottom)
		local timeLbl = item(rowBottom, "00:00", DIM_TEXT, Enum.Font.RobotoMono, 13, false)

		task.spawn(function()
			local name = nil
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(game.PlaceId)
			end)
			if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
				name = info.Name
			end
			if not name then
				name = game.Name
			end
			if alive and gameLbl.Parent then
				gameLbl.Text = shorten(name, 22)
			end
		end)

		task.spawn(function()
			while alive and timeLbl.Parent do
				local s = math.max(0, os.time() - startedAt)
				local h = math.floor(s / 3600)
				local m = math.floor((s % 3600) / 60)
				local sec = s % 60
				if h > 0 then
					timeLbl.Text = string.format("%d:%02d:%02d", h, m, sec)
				else
					timeLbl.Text = string.format("%02d:%02d", m, sec)
				end
				task.wait(1)
			end
		end)

		local wmAbs = Vector2.new(START_LEFT + 5, START_TOP - 4)   -- bottom left corner; starts just above the window's top left
		local wmDragging = false
		local function wmDock()
			local vp = gui.AbsoluteSize
			local ab = wm.AbsoluteSize
			local x = math.clamp(wmAbs.X, 4, math.max(4, vp.X - ab.X - 4))
			local y = math.clamp(wmAbs.Y, ab.Y + 4, math.max(ab.Y + 4, vp.Y - 4))
			wmAbs = Vector2.new(x, y)
			wm.Position = UDim2.fromOffset(x, y)
		end
		table.insert(conns, RunService.RenderStepped:Connect(wmDock))
		wmDock()

		do
			local dragStart = nil
			local startOff = nil
			wm.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					wmDragging = true
					dragStart = input.Position
					startOff = wmAbs
					input.Changed:Connect(function()
						if input.UserInputState == Enum.UserInputState.End then
							wmDragging = false
						end
					end)
				end
			end)
			table.insert(conns, UserInputService.InputChanged:Connect(function(input)
				if not wmDragging then
					return
				end
				if input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch then
					local d = input.Position - dragStart
					wmAbs = startOff + Vector2.new(d.X, d.Y)
				end
			end))
		end
	end

	---------------------------------------------------------------------
	-- TOAST (win:Toast("text") shows a small message at the bottom of the screen)
	---------------------------------------------------------------------
	local toastGroup = new("CanvasGroup", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = BG,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 80,
	}, gui)
	corner(toastGroup, 10)
	stroke(toastGroup, BORDER, 1, 0)
	new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, toastGroup)
	local toastText = new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextSize = 13,
		TextColor3 = TEXT_COLOR,
		ZIndex = 81,
	}, toastGroup)
	local toastToken = 0

	local function toast(text, seconds)
		if not alive then
			return
		end
		toastToken = toastToken + 1
		local tk = toastToken
		toastText.Text = tostring(text or "")
		toastGroup.Position = UDim2.new(0.5, 0, 1, -18)
		toastGroup.Visible = true
		TweenService:Create(toastGroup, SMOOTH, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 1, -28) }):Play()
		task.delay(tonumber(seconds) or 2.5, function()
			if not alive or tk ~= toastToken then
				return
			end
			TweenService:Create(toastGroup, LEAVE, { GroupTransparency = 1 }):Play()
			task.delay(LEAVE.Time + 0.02, function()
				if alive and tk == toastToken then
					toastGroup.Visible = false
				end
			end)
		end)
	end

	---------------------------------------------------------------------
	-- THE WINDOW OBJECT (what main.lua and the modules use)
	---------------------------------------------------------------------
	win.Gui = gui
	win.ScreenGui = gui
	win.Root = window
	win.Window = window
	win.Content = card
	win.Pages = containers          -- [tab id] = the frame a module builds into
	win.MainPage = containers.Server
	win.Theme = T
	win.Helpers = H

	function win:Unload()
		unload()
	end
	function win:OnUnload(fn)
		if type(fn) == "function" then
			unloadCbs[#unloadCbs + 1] = fn
		end
	end
	function win:Toast(text, seconds)
		toast(text, seconds)
	end
	function win:IsAlive()
		return alive
	end
	function win:ShowTab(id)
		showTab(id)
	end
	function win:GetTab()
		return currentTab
	end
	function win:OnTab(fn)
		if type(fn) == "function" then
			tabCbs[#tabCbs + 1] = fn
		end
	end
	function win:GetPage(id)
		return containers[id or currentTab]
	end
	function win:OnSearch(fn)
		if type(fn) == "function" then
			searchCbs[#searchCbs + 1] = fn
		end
	end
	function win:GetSearch()
		return searchQuery
	end
	function win:SetSearch(text)
		if searchBox then
			searchBox.Text = tostring(text or "")
		end
	end
	function win:AddBind(def)
		addBind(def)
	end
	function win:IsBind(id, input)
		return bindMatches(id, input)
	end
	function win:GetBind(id)
		return bindName(binds[id])
	end

	-- module toggles (see the notes at the top of this file)
	function win:AddToggle(def)
		addToggle(def)
	end
	function win:SetToggle(id, on)
		setToggle(id, on, true)
	end
	function win:Toggle(id)
		local t = toggles[id]
		if t then
			setToggle(id, not t.on)
		end
	end
	function win:GetToggle(id)
		local t = toggles[id]
		return t ~= nil and t.on
	end
	function win:OnToggle(id, fn)
		local t = toggles[id]
		if t and type(fn) == "function" then
			t.listeners[#t.listeners + 1] = fn
		end
	end

	-- tells a tab's page that something went wrong (the message replaces the "will go here" text)
	function win:SetPageMessage(id, title, text, isError)
		local ph = placeholders[id]
		if not ph then
			return
		end
		if title then
			ph.title.Text = title
		end
		if text then
			ph.sub.Text = text
		end
		if isError then
			ph.sub.TextColor3 = T.WARN
		end
		ph.frame.Visible = true
	end

	---------------------------------------------------------------------
	-- BUILD THE MODULE PAGES (one after the other, so the window stays smooth while they load)
	--   <Id>Module.build(container, T, H, ctx)  ->  optional { Unload = fn }
	--   ctx = a copy of opts.<Id> with Win (this window), Theme and Helpers added.
	---------------------------------------------------------------------
	local function ctxFor(id)
		local c = {}
		local src = opts[id]
		if type(src) == "table" then
			for k, v in pairs(src) do
				c[k] = v
			end
		end
		c.Win = win
		c.Theme = T
		c.Helpers = H
		return c
	end

	task.spawn(function()
		for i = 1, #TABS do
			if not alive then
				return
			end
			local id = TABS[i].id
			local mod = opts[id .. "Module"]
			if type(mod) == "table" and type(mod.build) == "function" then
				local ok, res = pcall(mod.build, containers[id], T, H, ctxFor(id))
				if ok then
					if type(res) == "table" then
						handles[#handles + 1] = res
					end
				else
					warn("[Y1] the " .. id .. " page failed: " .. tostring(res))
					local msg = tostring(res)
					if #msg > 260 then
						msg = string.sub(msg, 1, 257) .. "..."
					end
					win:SetPageMessage(id, id .. " failed to build", msg, true)
					toast(id .. " page failed - see console (F9)", 4)
				end
				task.wait()
			end
		end
	end)

	---------------------------------------------------------------------
	-- INTRO: the window pops in
	---------------------------------------------------------------------
	TweenService:Create(window, SMOOTH, { GroupTransparency = 0 }):Play()
	TweenService:Create(windowScale, POP, { Scale = fitScale }):Play()

	return win
end

return UI
