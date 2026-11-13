-- Y1UI.lua  (standalone preview UI, no modules needed)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Run it by itself:
--   loadstring(game:HttpGet("https://.../Y1UI.lua"))()      or paste the whole file in your executor
--
-- Same look as Welcome.lua / Auth.lua: flat dark card, "Y" in calm red, the 1 in white,
-- thin borders, red accent. NO features: every tab is an empty placeholder, only the window
-- itself works (switch tabs, drag, minimize to the Y1 square, maximize, close, hide key).
--
-- LAYOUT
--   top bar      logo, the name of the current tab, a search box (centre), minimize / maximize / close
--   middle       the content card (the page of the current tab)
--   bottom       a horizontal tab bar: icon + name for every tab, a red marker slides along its top edge
--
-- Tabs (left to right): Home, Info, Combat, Visuals, World, Misc, Server, Config, Settings.
-- To rename or reorder tabs, edit the TABS table near the bottom of the helpers section.
-- Left / Right arrow keys do NOT switch tabs on purpose (games use them to move); click the tabs.
--
-- ICON NOTE: the Visuals, World and Misc icons (and the search magnifier) are drawn with real outlines (UIStroke) and
-- clipped shapes instead of "cut-out" frames painted in the bar colour, so nothing shows a dark patch on the hover
-- pill, and every line is a full 2 - 2.5 px wide.

local CONFIG = {
	Name = "Y1Preview",
	Logo = "Y1",                          -- first letter(s) red, last character white
	HideKey = Enum.KeyCode.RightShift,    -- hides / shows the window
	StartTab = "Home",
}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- only one copy at a time (also stops an older run of this script)
do
	local ok, env = pcall(getgenv)
	if ok and type(env) == "table" and env.__Y1_PREVIEW_STOP then
		pcall(env.__Y1_PREVIEW_STOP)
	end
	local old = playerGui:FindFirstChild(CONFIG.Name)
	if old then
		old:Destroy()
	end
end

---------------------------------------------------------------------
-- THEME (same colours as Welcome.lua)
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

local RADIUS = 4

local FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SMOOTH = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LEAVE = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local GROW = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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
-- The stroke is added to inks, so the tab bar tints it like every other part of the icon.
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

local function buildHome(glyph)
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

local function buildInfo(glyph)
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

local function buildCombat(glyph)
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
-- 24 wide, 17 tall, centred in the icon box; the pupil is small enough to leave a clear gap to both lids.
local function buildVisuals(glyph)
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
local function buildWorld(glyph)
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
local function buildMisc(glyph)
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

-- CONFIG: a rounded square split into four panes by a cross (22 x 22, 2px lines, true outline so no dark patches)
local function buildConfig(glyph)
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
	shape(10, 0, 5, CUT)
	return { sq1, sq2 }
end

---------------------------------------------------------------------
-- TABS (edit here: id, title in the top bar, name under the icon, short text, icon). Left to right.
---------------------------------------------------------------------
local TABS = {
	{ id = "Home",     title = "Home",     tip = "Home",     sub = "Nothing here yet",            icon = buildHome },
	{ id = "Info",     title = "Info",     tip = "Info",     sub = "Your info will show here",    icon = buildInfo },
	{ id = "Combat",   title = "Combat",   tip = "Combat",   sub = "Combat options will go here", icon = buildCombat },
	{ id = "Visuals",  title = "Visuals",  tip = "Visuals",  sub = "Visual options will go here", icon = buildVisuals },
	{ id = "World",    title = "World",    tip = "World",    sub = "World options will go here",  icon = buildWorld },
	{ id = "Misc",     title = "Misc",     tip = "Misc",     sub = "Extra options will go here",  icon = buildMisc },
	{ id = "Server",   title = "Server",   tip = "Server",   sub = "Server tools will go here",   icon = buildServer },
	{ id = "Config",   title = "Config",   tip = "Config",   sub = "Config options will go here", icon = buildConfig },
	{ id = "Settings", title = "Settings", tip = "Settings", sub = "Settings will go here",       icon = buildGear },
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

local gui = new("ScreenGui", {
	Name = CONFIG.Name,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
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
-- PAGES (empty placeholders: just a short message in the middle)
---------------------------------------------------------------------
local PAGE_POS = UDim2.fromOffset(0, 0)
local pages = {}

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
		Size = UDim2.fromOffset(320, 70),
		BackgroundTransparency = 1,
	}, p)
	label(mid, tab.title, UDim2.fromOffset(0, 8), UDim2.new(1, 0, 0, 26),
		Enum.Font.GothamBold, 20, TEXT_COLOR, Enum.TextXAlignment.Center)
	label(mid, tab.sub, UDim2.fromOffset(0, 40), UDim2.new(1, 0, 0, 16),
		Enum.Font.GothamMedium, 12, DIM_TEXT, Enum.TextXAlignment.Center)
	pages[tab.id] = p
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
-- You can click it and type, but it shows no results yet: onSearch() is the empty hook where the
-- results will be built later. Escape clears it, the small x clears it, Enter just leaves the box.
---------------------------------------------------------------------
local searchQuery = ""
local searchBox = nil

local function onSearch(query)
	-- nothing shows up yet
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

	-- magnifier: a ring and a handle, 2.5px lines, about 20 x 20 in total
	--   ring: 16 across (outside), centred at (9, 9) of the 22 x 22 holder
	--   handle: 9 long, along the 45 degree line from the ring, ends at about (20, 20)
	local LINE = 2.5
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(21, PILL_H / 2),
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		ZIndex = 11,
	}, pill)
	local ring = new("Frame", {
		Position = UDim2.fromOffset(1 + LINE, 1 + LINE),
		Size = UDim2.fromOffset(16 - LINE * 2, 16 - LINE * 2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 12,
	}, holder)
	corner(ring, 100)
	local ringStroke = stroke(ring, ICON, LINE, 0)
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
	end
end

---------------------------------------------------------------------
-- KEYBINDS PANEL (small card docked on the right side of the screen)
--   * opens / closes with the keyboard button in the top bar (left of minimize), closes with its x,
--     drag it by its title bar
--   * click a key box, then press a key or a mouse button to change it (Escape = cancel, Backspace = none)
--   * right now it has NO rows: it is only a visual (the window still hides with CONFIG.HideKey).
--     Add rows in the BINDS table when the binds should work.
--   * IsBind(id, input) and GetBind(id) are returned at the bottom of the file so other code can use the binds
---------------------------------------------------------------------
-- empty for now: the panel is only a visual. Add rows here later, for example:
--   { id = "Menu", title = "Menu", wired = true, default = { kind = "Key", key = Enum.KeyCode.RightShift } },
local BINDS = {
}
local bindDef = {}
local binds = {}
for i = 1, #BINDS do
	bindDef[BINDS[i].id] = BINDS[i]
	binds[BINDS[i].id] = BINDS[i].default
end

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

local kbPanel = new("CanvasGroup", {
	Name = "Keybinds",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, 0),
	Size = UDim2.fromOffset(KB_W, KB_HEAD + math.max(#BINDS, 1) * KB_ROW + 12),
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
if #BINDS == 0 then
	label(kbPanel, "Nothing here yet", UDim2.fromOffset(0, KB_HEAD + 4), UDim2.new(1, 0, 0, KB_ROW - 4),
		Enum.Font.GothamMedium, 12, DIM_TEXT, Enum.TextXAlignment.Center).ZIndex = 3
end

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

for i = 1, #BINDS do
	local def = BINDS[i]
	local y = KB_HEAD + 4 + (i - 1) * KB_ROW
	local nameColor = TEXT_COLOR
	if not def.wired then
		nameColor = DIM_TEXT
	end
	label(kbPanel, def.title, UDim2.fromOffset(16, y), UDim2.new(1, -130, 0, KB_ROW - 4),
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

-- drag the panel by its title bar
do
	local dragging = false
	local dragStart = nil
	local startPos = nil
	kbHead.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = kbPanel.Position
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
			kbPanel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
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
-- WINDOW BEHAVIOUR: minimize square, maximize, close, hide key, drag
---------------------------------------------------------------------
local function unload()
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
	local ok, env = pcall(getgenv)
	if ok and type(env) == "table" and env.__Y1_PREVIEW_STOP == unload then
		env.__Y1_PREVIEW_STOP = nil
	end
	gui:Destroy()
end
do
	local ok, env = pcall(getgenv)
	if ok and type(env) == "table" then
		env.__Y1_PREVIEW_STOP = unload
	end
end

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
-- INTRO: the window pops in
---------------------------------------------------------------------
TweenService:Create(window, SMOOTH, { GroupTransparency = 0 }):Play()
TweenService:Create(windowScale, POP, { Scale = fitScale }):Play()

return {
	ShowTab = showTab,
	Unload = unload,
	IsBind = bindMatches,
	GetBind = function(id)
		return bindName(binds[id])
	end,
	GetSearch = function()
		return searchQuery
	end,
	SetSearch = function(text)
		if searchBox then
			searchBox.Text = tostring(text or "")
		end
	end,
}
