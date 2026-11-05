local Options = {}

local SORTS = {
	{ key = "most", name = "Most players" },
	{ key = "fewest", name = "Fewest players" },
	{ key = "ping", name = "Lowest ping" },
	{ key = "newest", name = "Newest" },
	{ key = "oldest", name = "Oldest" },
}

local FILE = "y1_finder_options.json"
local MAX_HISTORY = 5

function Options.new(win, parent, hooks)
	hooks = hooks or {}

	local Players = game:GetService("Players")
	local TweenService = game:GetService("TweenService")
	local HttpService = game:GetService("HttpService")
	local player = Players.LocalPlayer

	local T = win.T
	local H = win.H
	local new = H.new
	local corner = H.corner
	local stroke = H.stroke
	local pad = H.pad
	local label = H.label
	local hoverable = H.hoverable

	local BORDER = T.BORDER
	local CARD_BG = T.CARD_BG
	local CARD_HOVER = T.CARD_HOVER
	local POPUP_BG = T.POPUP_BG
	local CLUSTER_BG = T.CLUSTER_BG
	local ICON = T.ICON
	local ICON_HOVER = T.ICON_HOVER
	local HOVER_GREY = T.HOVER_GREY
	local TEXT_COLOR = T.TEXT_COLOR
	local DIM_TEXT = T.DIM_TEXT
	local JOIN_BG = T.JOIN_BG
	local BLACK = T.BLACK
	local RADIUS = T.RADIUS
	local FAST = T.FAST
	local SMOOTH = T.SMOOTH
	local OVER_BG = Color3.fromRGB(46, 46, 52)

	local PANEL_W = 270
	local PANEL_H_SERVERS = 290
	local PANEL_H_GROUP = 316

	local self = {}
	self.state = { sort = "most", hideFull = false, minFree = 1, friendsOnly = false, role = nil }
	self.friends = {}
	self.friendCount = 0
	self.friendStatus = "idle"

	local history = {}
	local tab = "servers"
	local isOpen = false
	local baseScale = 1
	local panelToken = 0
	local refreshUI = function() end

	local function esc(s)
		s = string.gsub(tostring(s), "&", "&amp;")
		s = string.gsub(s, "<", "&lt;")
		s = string.gsub(s, ">", "&gt;")
		return s
	end

	---------------------------------------------------------------------
	-- saved settings (only when the executor has readfile / writefile)
	---------------------------------------------------------------------
	local function validSort(key)
		for i = 1, #SORTS do
			if SORTS[i].key == key then
				return true
			end
		end
		return false
	end

	local function save()
		if type(writefile) ~= "function" then
			return
		end
		pcall(function()
			writefile(FILE, HttpService:JSONEncode({
				sort = self.state.sort,
				hideFull = self.state.hideFull,
				minFree = self.state.minFree,
				history = history,
			}))
		end)
	end

	pcall(function()
		if type(isfile) == "function" and type(readfile) == "function" and isfile(FILE) then
			local data = HttpService:JSONDecode(readfile(FILE))
			if type(data) == "table" then
				if validSort(data.sort) then
					self.state.sort = data.sort
				end
				if data.hideFull == true then
					self.state.hideFull = true
				end
				local mf = tonumber(data.minFree)
				if mf and mf >= 1 and mf <= 20 then
					self.state.minFree = math.floor(mf)
				end
				if type(data.history) == "table" then
					for i = 1, #data.history do
						local e = data.history[i]
						if type(e) == "table" and tonumber(e.id) and #history < MAX_HISTORY then
							local gid = math.floor(tonumber(e.id))
							table.insert(history, { id = gid, name = tostring(e.name or ("Group " .. gid)) })
						end
					end
				end
			end
		end
	end)

	local function changed()
		refreshUI()
		save()
		if hooks.onChange then
			hooks.onChange()
		end
	end

	---------------------------------------------------------------------
	-- friends list (loaded once, only when Friends only is switched on)
	---------------------------------------------------------------------
	local function loadFriends()
		if self.friendStatus == "loading" or self.friendStatus == "ready" then
			return
		end
		self.friendStatus = "loading"
		refreshUI()
		task.spawn(function()
			local ok, pages = pcall(function()
				return Players:GetFriendsAsync(player.UserId)
			end)
			if not ok or not pages then
				self.friendStatus = "failed"
				refreshUI()
				if hooks.onChange then
					hooks.onChange()
				end
				return
			end
			local count = 0
			local guard = 0
			while guard < 80 do
				guard = guard + 1
				local okP, items = pcall(function()
					return pages:GetCurrentPage()
				end)
				if okP and items then
					for i = 1, #items do
						local f = items[i]
						if f.Id and not self.friends[f.Id] then
							self.friends[f.Id] = true
							count = count + 1
							if hooks.onFriend and f.Username then
								hooks.onFriend(f.Id, f.Username, f.DisplayName or f.Username)
							end
						end
					end
				end
				self.friendCount = count
				if pages.IsFinished then
					break
				end
				local okA = pcall(function()
					pages:AdvanceToNextPageAsync()
				end)
				if not okA then
					break
				end
			end
			self.friendStatus = "ready"
			refreshUI()
			if hooks.onChange then
				hooks.onChange()
			end
		end)
	end

	---------------------------------------------------------------------
	-- GEAR BUTTON + SORT PILL (sit on the tab row, right side)
	---------------------------------------------------------------------
	local gear = new("TextButton", {
		Name = "OptionsGear",
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 50),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = CLUSTER_BG,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, parent)
	corner(gear, RADIUS + 2)

	local gearHolder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, gear)
	local gearScale = new("UIScale", { Scale = 1 }, gearHolder)
	local gearInks = {}

	local function gearShape(w, rot, r, color)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(w, w),
			Rotation = rot,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, gearHolder)
		corner(f, r)
		return f
	end
	table.insert(gearInks, gearShape(14, 0, 4, ICON))
	table.insert(gearInks, gearShape(14, 45, 4, ICON))
	local hollow = gearShape(6, 0, 3, CLUSTER_BG)

	local gearOver = false
	local GEAR_SPIN = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local function paintGear()
		local lit = gearOver or isOpen
		local bg = CLUSTER_BG
		local ink = ICON
		local rot = 0
		if lit then
			bg = HOVER_GREY
			ink = ICON_HOVER
			rot = 90
		end
		TweenService:Create(gear, FAST, { BackgroundColor3 = bg }):Play()
		TweenService:Create(hollow, FAST, { BackgroundColor3 = bg }):Play()
		for i = 1, #gearInks do
			TweenService:Create(gearInks[i], FAST, { BackgroundColor3 = ink }):Play()
		end
		TweenService:Create(gearHolder, GEAR_SPIN, { Rotation = rot }):Play()
	end
	gear.MouseEnter:Connect(function()
		gearOver = true
		paintGear()
	end)
	gear.MouseLeave:Connect(function()
		gearOver = false
		paintGear()
	end)

	local pill = new("TextButton", {
		Name = "SortPill",
		AutoButtonColor = false,
		Text = "",
		RichText = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -36, 0, 50),
		Size = UDim2.fromOffset(128, 30),
		BackgroundColor3 = CLUSTER_BG,
		BorderSizePixel = 0,
		TextColor3 = TEXT_COLOR,
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		ZIndex = 3,
	}, parent)
	corner(pill, RADIUS + 1)
	hoverable(pill, CLUSTER_BG, HOVER_GREY, TEXT_COLOR, ICON_HOVER)

	---------------------------------------------------------------------
	-- PANEL
	---------------------------------------------------------------------
	local catcher = new("TextButton", {
		Name = "OptionsCatcher",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
	}, parent)

	local panel = new("CanvasGroup", {
		Name = "OptionsPanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 90),
		Size = UDim2.fromOffset(PANEL_W, PANEL_H_SERVERS),
		BackgroundColor3 = POPUP_BG,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 41,
	}, parent)
	corner(panel, RADIUS + 4)
	stroke(panel, BORDER, 1, 0)
	local panelScale = new("UIScale", { Scale = 0.94 }, panel)

	local scroll = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = ICON,
		ScrollBarImageTransparency = 0.5,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, panel)
	pad(scroll, 10, 10, 10, 10)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	local order = 0
	local function nextOrder()
		order = order + 1
		return order
	end

	local groupItems = {}   -- things that only show on the group tab

	local function header(text, isGroup)
		local l = label(scroll, text, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 14),
			Enum.Font.GothamMedium, 10, DIM_TEXT)
		l.LayoutOrder = nextOrder()
		if isGroup then
			l.Visible = false
			table.insert(groupItems, l)
		end
		return l
	end

	-- ===== sort =====
	header("SORT BY", false)
	local sortFrame = new("Frame", {
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 86),
		BackgroundTransparency = 1,
	}, scroll)
	new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -2, 0, 26),
		CellPadding = UDim2.fromOffset(4, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, sortFrame)

	local sortBtns = {}
	local function paintSortBtn(sb)
		local sel = (self.state.sort == sb.key)
		local bg = CLUSTER_BG
		local tc = ICON
		if sel then
			bg = HOVER_GREY
			tc = ICON_HOVER
		elseif sb.over then
			bg = OVER_BG
			tc = ICON_HOVER
		end
		TweenService:Create(sb.b, FAST, { BackgroundColor3 = bg, TextColor3 = tc }):Play()
	end
	for i = 1, #SORTS do
		local s = SORTS[i]
		local b = new("TextButton", {
			LayoutOrder = i,
			AutoButtonColor = false,
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
			Text = s.name,
			TextColor3 = ICON,
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
		}, sortFrame)
		corner(b, RADIUS + 1)
		local sb = { b = b, key = s.key, over = false }
		table.insert(sortBtns, sb)
		b.MouseEnter:Connect(function()
			sb.over = true
			paintSortBtn(sb)
		end)
		b.MouseLeave:Connect(function()
			sb.over = false
			paintSortBtn(sb)
		end)
		b.Activated:Connect(function()
			self.state.sort = sb.key
			changed()
		end)
	end

	-- ===== filters =====
	header("FILTERS", false)
	local paints = {}

	local function makeToggle(title, sub, get, set)
		local row = new("TextButton", {
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundColor3 = CARD_BG,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
		}, scroll)
		corner(row, RADIUS + 2)
		label(row, title, UDim2.fromOffset(10, 5), UDim2.new(1, -64, 0, 16),
			Enum.Font.GothamMedium, 12, TEXT_COLOR)
		local subLabel = label(row, sub, UDim2.fromOffset(10, 21), UDim2.new(1, -64, 0, 13),
			Enum.Font.Gotham, 10, DIM_TEXT)

		local track = new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(34, 18),
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
		}, row)
		corner(track, 100)
		stroke(track, BORDER, 1, 0)
		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = DIM_TEXT,
			BorderSizePixel = 0,
		}, track)
		corner(knob, 100)

		local function paint()
			local pos = UDim2.new(0, 3, 0.5, 0)
			local trackColor = CLUSTER_BG
			local knobColor = DIM_TEXT
			if get() then
				pos = UDim2.new(1, -15, 0.5, 0)
				trackColor = JOIN_BG
				knobColor = BLACK
			end
			TweenService:Create(knob, SMOOTH, { Position = pos }):Play()
			TweenService:Create(knob, FAST, { BackgroundColor3 = knobColor }):Play()
			TweenService:Create(track, FAST, { BackgroundColor3 = trackColor }):Play()
		end
		table.insert(paints, paint)

		row.MouseEnter:Connect(function()
			TweenService:Create(row, FAST, { BackgroundColor3 = CARD_HOVER }):Play()
		end)
		row.MouseLeave:Connect(function()
			TweenService:Create(row, FAST, { BackgroundColor3 = CARD_BG }):Play()
		end)
		row.Activated:Connect(function()
			set(not get())
		end)
		return subLabel
	end

	makeToggle("Hide full servers", "Hides servers you cannot join",
		function()
			return self.state.hideFull
		end,
		function(v)
			self.state.hideFull = v
			changed()
		end)

	-- how many free slots a server needs to stay visible
	local stepRow = new("Frame", {
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = CARD_BG,
		BorderSizePixel = 0,
	}, scroll)
	corner(stepRow, RADIUS + 2)
	label(stepRow, "Free slots needed", UDim2.fromOffset(10, 5), UDim2.new(1, -110, 0, 16),
		Enum.Font.GothamMedium, 12, TEXT_COLOR)
	label(stepRow, "Also hides nearly full servers", UDim2.fromOffset(10, 21), UDim2.new(1, -110, 0, 13),
		Enum.Font.Gotham, 10, DIM_TEXT)

	local stepCtl = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(76, 24),
		BackgroundTransparency = 1,
	}, stepRow)
	local stepValue = new("TextLabel", {
		Position = UDim2.fromOffset(24, 0),
		Size = UDim2.fromOffset(28, 24),
		BackgroundTransparency = 1,
		Text = "1",
		TextColor3 = TEXT_COLOR,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
	}, stepCtl)

	local function stepButton(plus, x, delta)
		local b = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
		}, stepCtl)
		corner(b, RADIUS + 1)
		local bars = {}
		local function bar(w, h)
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(w, h),
				BackgroundColor3 = ICON,
				BorderSizePixel = 0,
			}, b)
			corner(f, 1)
			table.insert(bars, f)
		end
		bar(10, 2)
		if plus then
			bar(2, 10)
		end
		b.MouseEnter:Connect(function()
			TweenService:Create(b, FAST, { BackgroundColor3 = HOVER_GREY }):Play()
			for i = 1, #bars do
				TweenService:Create(bars[i], FAST, { BackgroundColor3 = ICON_HOVER }):Play()
			end
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b, FAST, { BackgroundColor3 = CLUSTER_BG }):Play()
			for i = 1, #bars do
				TweenService:Create(bars[i], FAST, { BackgroundColor3 = ICON }):Play()
			end
		end)
		b.Activated:Connect(function()
			local v = self.state.minFree + delta
			if v < 1 then
				v = 1
			end
			if v > 20 then
				v = 20
			end
			if v ~= self.state.minFree then
				self.state.minFree = v
				changed()
			end
		end)
	end
	stepButton(false, 0, -1)
	stepButton(true, 52, 1)

	local friendSub = makeToggle("Friends only", "Show servers with your friends",
		function()
			return self.state.friendsOnly
		end,
		function(v)
			self.state.friendsOnly = v
			if v then
				loadFriends()
			end
			changed()
		end)

	-- ===== group tab only: role filter + recent groups =====
	header("ROLE FILTER", true)
	local roleRow = new("ScrollingFrame", {
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = ICON,
		ScrollBarImageTransparency = 0.5,
		ScrollingDirection = Enum.ScrollingDirection.X,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		Visible = false,
	}, scroll)
	table.insert(groupItems, roleRow)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, roleRow)

	header("RECENT GROUPS", true)
	local historyFrame = new("Frame", {
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
	}, scroll)
	table.insert(groupItems, historyFrame)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, historyFrame)

	-- role chips (reused, only their text changes)
	local roleChips = {}
	local allRoleChip = nil

	local function paintRoleChip(c)
		local sel = false
		if c.name == nil then
			sel = (self.state.role == nil)
		else
			sel = (self.state.role == c.name)
		end
		local sig = tostring(sel) .. "|" .. tostring(c.over) .. "|" .. c.text
		if c.sig == sig then
			return
		end
		c.sig = sig
		local bg = CLUSTER_BG
		local tc = TEXT_COLOR
		if sel then
			bg = HOVER_GREY
			tc = ICON_HOVER
		elseif c.over then
			bg = OVER_BG
		end
		TweenService:Create(c.btn, FAST, { BackgroundColor3 = bg }):Play()
		c.btn.TextColor3 = tc
		c.btn.Text = c.text
	end

	local function makeRoleChip(name)
		local b = new("TextButton", {
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			RichText = true,
			TextColor3 = TEXT_COLOR,
			Font = Enum.Font.GothamMedium,
			TextSize = 11,
		}, roleRow)
		corner(b, RADIUS + 1)
		pad(b, 10, 0, 10, 0)
		local c = { btn = b, name = name, text = "", over = false, sig = "" }
		b.MouseEnter:Connect(function()
			c.over = true
			paintRoleChip(c)
		end)
		b.MouseLeave:Connect(function()
			c.over = false
			paintRoleChip(c)
		end)
		b.Activated:Connect(function()
			if c.name == nil or self.state.role == c.name then
				self.state.role = nil
			else
				self.state.role = c.name
			end
			changed()
		end)
		return c
	end

	allRoleChip = makeRoleChip(nil)
	allRoleChip.text = "All"
	allRoleChip.btn.LayoutOrder = 0

	-- recent group buttons (rebuilt when the list changes, it is only a few rows)
	local historyObjs = {}
	local function rebuildHistory()
		for i = 1, #historyObjs do
			historyObjs[i]:Destroy()
		end
		historyObjs = {}

		if #history == 0 then
			local l = label(historyFrame, "No groups loaded yet", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 20),
				Enum.Font.Gotham, 11, DIM_TEXT)
			l.LayoutOrder = 0
			table.insert(historyObjs, l)
			return
		end

		for i = 1, #history do
			local entry = history[i]
			local b = new("TextButton", {
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = CLUSTER_BG,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = esc(entry.name) .. "  <font color=\"#74747C\">" .. tostring(entry.id) .. "</font>",
				RichText = true,
				TextColor3 = TEXT_COLOR,
				Font = Enum.Font.GothamMedium,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, historyFrame)
			corner(b, RADIUS + 1)
			pad(b, 10, 0, 10, 0)
			hoverable(b, CLUSTER_BG, HOVER_GREY, TEXT_COLOR, ICON_HOVER)
			b.Activated:Connect(function()
				if hooks.onPickGroup then
					hooks.onPickGroup(entry.id)
				end
				self:Close()
			end)
			table.insert(historyObjs, b)
		end

		local clear = new("TextButton", {
			LayoutOrder = 100,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "Clear history",
			TextColor3 = DIM_TEXT,
			Font = Enum.Font.Gotham,
			TextSize = 11,
		}, historyFrame)
		clear.MouseEnter:Connect(function()
			TweenService:Create(clear, FAST, { TextColor3 = ICON_HOVER }):Play()
		end)
		clear.MouseLeave:Connect(function()
			TweenService:Create(clear, FAST, { TextColor3 = DIM_TEXT }):Play()
		end)
		clear.Activated:Connect(function()
			history = {}
			rebuildHistory()
			save()
		end)
		table.insert(historyObjs, clear)
	end
	rebuildHistory()

	---------------------------------------------------------------------
	-- refresh everything that shows a setting
	---------------------------------------------------------------------
	local function sortName()
		for i = 1, #SORTS do
			if SORTS[i].key == self.state.sort then
				return SORTS[i].name
			end
		end
		return ""
	end

	local function friendText()
		if self.friendStatus == "loading" then
			return "Loading your friends..."
		elseif self.friendStatus == "ready" then
			return self.friendCount .. " friends loaded"
		elseif self.friendStatus == "failed" then
			return "Could not load your friends"
		end
		return "Show servers with your friends"
	end

	refreshUI = function()
		for i = 1, #sortBtns do
			paintSortBtn(sortBtns[i])
		end
		for i = 1, #paints do
			paints[i]()
		end
		stepValue.Text = tostring(self.state.minFree)
		if self.state.hideFull then
			stepValue.TextColor3 = TEXT_COLOR
		else
			stepValue.TextColor3 = DIM_TEXT
		end
		friendSub.Text = friendText()
		pill.Text = "Sort  <font color=\"#B4B4BC\">" .. esc(sortName()) .. "</font>"
		paintRoleChip(allRoleChip)
		for _, c in pairs(roleChips) do
			paintRoleChip(c)
		end
	end

	---------------------------------------------------------------------
	-- open / close
	---------------------------------------------------------------------
	local OPEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local CLOSE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local function openPanel()
		if isOpen then
			return
		end
		isOpen = true
		panelToken = panelToken + 1
		catcher.Visible = true
		panelScale.Scale = baseScale * 0.94
		panel.GroupTransparency = 1
		panel.Visible = true
		TweenService:Create(panel, SMOOTH, { GroupTransparency = 0 }):Play()
		TweenService:Create(panelScale, OPEN_INFO, { Scale = baseScale }):Play()
		paintGear()
	end

	local function closePanel()
		if not isOpen then
			return
		end
		isOpen = false
		panelToken = panelToken + 1
		local token = panelToken
		catcher.Visible = false
		TweenService:Create(panel, CLOSE_INFO, { GroupTransparency = 1 }):Play()
		TweenService:Create(panelScale, CLOSE_INFO, { Scale = baseScale * 0.94 }):Play()
		task.delay(CLOSE_INFO.Time + 0.02, function()
			if token == panelToken then
				panel.Visible = false
			end
		end)
		paintGear()
	end

	gear.Activated:Connect(function()
		if isOpen then
			closePanel()
		else
			openPanel()
		end
	end)
	catcher.Activated:Connect(closePanel)

	pill.Activated:Connect(function()
		local idx = 1
		for i = 1, #SORTS do
			if SORTS[i].key == self.state.sort then
				idx = i
			end
		end
		idx = idx + 1
		if idx > #SORTS then
			idx = 1
		end
		self.state.sort = SORTS[idx].key
		changed()
	end)

	---------------------------------------------------------------------
	-- public api
	---------------------------------------------------------------------
	function self:Layout(y, h, touch)
		local pw = 128
		if touch then
			pw = 140
		end
		gear.Position = UDim2.new(1, 0, 0, y)
		gear.Size = UDim2.fromOffset(h, h)
		gearScale.Scale = h / 30
		pill.Position = UDim2.new(1, -(h + 6), 0, y)
		pill.Size = UDim2.fromOffset(pw, h)
		panel.Position = UDim2.new(1, 0, 0, y + h + 6)
		return h + 6 + pw + 8
	end

	function self:SetTab(name)
		tab = name
		for i = 1, #groupItems do
			groupItems[i].Visible = (name == "group")
		end
		local ph = PANEL_H_SERVERS
		if name == "group" then
			ph = PANEL_H_GROUP
		end
		panel.Size = UDim2.fromOffset(PANEL_W, ph)
	end

	function self:SetTouch(on)
		baseScale = 1
		if on then
			baseScale = 1.1
		end
		if isOpen then
			panelScale.Scale = baseScale
		else
			panelScale.Scale = baseScale * 0.94
		end
	end

	function self:SetRoles(list)
		local seen = {}
		for i = 1, #list do
			local a = list[i]
			local c = roleChips[a.name]
			if c == nil then
				c = makeRoleChip(a.name)
				roleChips[a.name] = c
			end
			c.text = esc(a.name) .. "  <font color=\"#74747C\">" .. tostring(a.count) .. "</font>"
			c.btn.LayoutOrder = i
			seen[a.name] = true
			paintRoleChip(c)
		end
		local lostRole = false
		for name, c in pairs(roleChips) do
			if not seen[name] then
				c.btn:Destroy()
				roleChips[name] = nil
				if self.state.role == name then
					self.state.role = nil
					lostRole = true
				end
			end
		end
		if lostRole then
			paintRoleChip(allRoleChip)
			task.defer(function()
				if hooks.onChange then
					hooks.onChange()
				end
			end)
		end
	end

	function self:AddHistory(id, name)
		local nid = tonumber(id)
		if not nid then
			return
		end
		for i = #history, 1, -1 do
			if history[i].id == nid then
				table.remove(history, i)
			end
		end
		table.insert(history, 1, { id = nid, name = tostring(name or ("Group " .. nid)) })
		while #history > MAX_HISTORY do
			table.remove(history)
		end
		rebuildHistory()
		save()
	end

	function self:IsFriend(userId)
		return self.friends[userId] == true
	end

	function self:Compare(a, b)
		local s = self.state.sort
		if s == "most" then
			if a.count ~= b.count then
				return a.count > b.count
			end
		elseif s == "fewest" then
			if a.count ~= b.count then
				return a.count < b.count
			end
		elseif s == "ping" then
			local pa = math.floor(a.ping or 1000000)
			local pb = math.floor(b.ping or 1000000)
			if pa ~= pb then
				return pa < pb
			end
		elseif s == "newest" then
			local ta = a.startedAt or 0
			local tb = b.startedAt or 0
			if ta ~= tb then
				return ta > tb
			end
		elseif s == "oldest" then
			local ta = a.startedAt or 1000000000000
			local tb = b.startedAt or 1000000000000
			if ta ~= tb then
				return ta < tb
			end
		end
		return nil
	end

	function self:Sig()
		local s = self.state
		return s.sort .. ":" .. tostring(s.hideFull) .. ":" .. tostring(s.minFree) .. ":"
			.. tostring(s.friendsOnly) .. ":" .. tostring(s.role) .. ":" .. self.friendStatus .. ":" .. tostring(self.friendCount)
	end

	function self:Close()
		closePanel()
	end

	self:SetTab("servers")
	refreshUI()
	return self
end

return Options
