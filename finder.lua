-- finder.lua  (server system module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Reads the game's server list, finds players, groups and regions, and builds its page
-- inside a window made by ui.lua.
--
--   local Finder = <this file>
--   local finder = Finder.new(win, { RefreshEvery = 2, PageSize = 40 })
--   finder:Stop()      -- optional, it also stops by itself when the window unloads
--
-- Servers tab: every server in the game's list. Click a server to open it (animated) and see its players.
--   Type in the search box: any server with a matching player opens automatically and the match is highlighted.
--   Search a display name, username, user ID, or the start of a Job ID.
--   Region chips above the list show servers per region + average ping. Click one to filter by that region.
-- Group tab: enter a group ID (or paste the group URL) and press Load to see servers with group members in them.
-- Buttons: Join (teleport), Copy Link / Job ID / Script per server, click a player to copy their username,
--   the ID button copies their user ID.

local Finder = {}

function Finder.new(win, opts)
	opts = opts or {}

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local HttpService = game:GetService("HttpService")
	local TeleportService = game:GetService("TeleportService")
	local TweenService = game:GetService("TweenService")
	local player = Players.LocalPlayer

	local REFRESH_EVERY = opts.RefreshEvery or 2        -- seconds between server list reads
	local PAGE_SIZE = opts.PageSize or 40               -- servers shown at a time
	local MAX_PLAYER_ROWS = opts.MaxPlayerRows or 100   -- players shown inside one open server
	local GROUP_MEMBER_CAP = opts.GroupMemberCap or 5000 -- groups bigger than this are checked player by player

	local running = true
	local self = {}

	-- theme + helpers come from the ui module
	local T = win.T
	local H = win.H
	local new = H.new
	local corner = H.corner
	local stroke = H.stroke
	local pad = H.pad
	local label = H.label
	local hoverable = H.hoverable

	local BLACK = T.BLACK
	local BORDER = T.BORDER
	local SIDEBAR_BG = T.SIDEBAR_BG
	local CARD_BG = T.CARD_BG
	local CARD_HOVER = T.CARD_HOVER
	local CLUSTER_BG = T.CLUSTER_BG
	local ICON = T.ICON
	local ICON_HOVER = T.ICON_HOVER
	local HOVER_GREY = T.HOVER_GREY
	local TEXT_COLOR = T.TEXT_COLOR
	local DIM_TEXT = T.DIM_TEXT
	local GREEN = T.GREEN
	local JOIN_BG = T.JOIN_BG
	local MATCH_BG = T.MATCH_BG
	local RADIUS = T.RADIUS
	local FAST = T.FAST
	local EXPAND = T.EXPAND
	local COLLAPSE = T.COLLAPSE

	local function toast(msg)
		win:Toast(msg)
	end

	---------------------------------------------------------------------
	-- executor functions
	---------------------------------------------------------------------
	local httpRequest = nil
	if syn and syn.request then
		httpRequest = syn.request
	elseif http and http.request then
		httpRequest = http.request
	elseif http_request then
		httpRequest = http_request
	elseif request then
		httpRequest = request
	end

	local clip = nil
	if setclipboard then
		clip = setclipboard
	elseif toclipboard then
		clip = toclipboard
	end

	local Servers = ReplicatedStorage:WaitForChild("Servers", 10)

	---------------------------------------------------------------------
	-- HTTP helpers
	---------------------------------------------------------------------
	local function httpJson(method, url, body)
		if not httpRequest then
			return nil, 0
		end
		local req = {
			Url = url,
			Method = method,
			Headers = { ["Content-Type"] = "application/json" },
		}
		if body then
			req.Body = HttpService:JSONEncode(body)
		end
		local ok, res = pcall(function()
			return httpRequest(req)
		end)
		if not ok or not res then
			return nil, 0
		end
		local code = res.StatusCode
		if code ~= 200 then
			return nil, code
		end
		local okJson, data = pcall(function()
			return HttpService:JSONDecode(res.Body)
		end)
		if okJson then
			return data, 200
		end
		return nil, 0
	end

	local function httpRetry(method, url, body, tries)
		local data = nil
		local code = 0
		for i = 1, tries do
			data, code = httpJson(method, url, body)
			if data then
				return data, code
			end
			if code == 429 then
				task.wait(3 + i)
			elseif code ~= 0 then
				return nil, code
			else
				task.wait(1)
			end
		end
		return nil, code
	end

	---------------------------------------------------------------------
	-- DATA: server list
	---------------------------------------------------------------------
	local servers = {}       -- jobId -> { jobId, players = {userIds}, count, max, ping, region, startedAt }
	local located = {}       -- userId -> the server table they are in
	local locatedCount = 0
	local serverCount = 0
	local version = 0        -- bumps whenever servers or their players change
	local refreshServers = function() end

	do
		local function playersIn(entry)
			local seen = {}
			local list = {}
			local raw = tostring(entry:GetAttribute("players") or "")
			for piece in string.gmatch(raw, "[^,]+") do
				local n = tonumber(piece)
				if n and n > 0 and n % 1 == 0 and not seen[n] then
					seen[n] = true
					table.insert(list, n)
				end
			end
			return list
		end

		local function getNewest()
			local newest = {}
			if not Servers then
				return newest
			end
			local children = Servers:GetChildren()
			for i = 1, #children do
				local entry = children[i]
				local serverId = entry:GetAttribute("serverId")
				if type(serverId) == "string" and serverId ~= "" and entry:GetAttribute("placeId") == game.PlaceId then
					local old = newest[serverId]
					local newTicker = tonumber(entry:GetAttribute("Ticker")) or 0
					if old == nil then
						newest[serverId] = entry
					else
						local oldTicker = tonumber(old:GetAttribute("Ticker")) or 0
						if newTicker >= oldTicker then
							newest[serverId] = entry
						end
					end
				end
			end
			return newest
		end

		local function sigOf(srv)
			local sum = 0
			for i = 1, #srv.players do
				sum = (sum + srv.players[i]) % 1000000007
			end
			return tostring(srv.count) .. ":" .. tostring(sum)
		end

		refreshServers = function()
			local newServers = {}
			local newLocated = {}
			local newest = getNewest()

			for _, entry in pairs(newest) do
				local list = playersIn(entry)
				local srv = {
					jobId = tostring(entry:GetAttribute("serverId")),
					players = list,
					count = #list,
					max = tonumber(entry:GetAttribute("maxPlayers")) or Players.MaxPlayers,
					ping = tonumber(entry:GetAttribute("ping")),
					region = entry:GetAttribute("region"),
					startedAt = tonumber(entry:GetAttribute("startedAt")),
				}
				newServers[srv.jobId] = srv
				for i = 1, #list do
					newLocated[list[i]] = srv
				end
			end

			-- your own server always comes from live data
			local own = Players:GetPlayers()
			local ownIds = {}
			for i = 1, #own do
				table.insert(ownIds, own[i].UserId)
			end
			local prev = newServers[game.JobId]
			local ownSrv = {
				jobId = game.JobId,
				players = ownIds,
				count = #ownIds,
				max = Players.MaxPlayers,
				ping = nil,
				region = "Your server",
				startedAt = nil,
			}
			if prev then
				ownSrv.ping = prev.ping
				ownSrv.region = prev.region
				ownSrv.startedAt = prev.startedAt
				if prev.max then
					ownSrv.max = prev.max
				end
			end
			local okPing, livePing = pcall(function()
				return player:GetNetworkPing() * 2000
			end)
			if okPing then
				ownSrv.ping = livePing
			end
			newServers[game.JobId] = ownSrv
			for i = 1, #ownIds do
				newLocated[ownIds[i]] = ownSrv
			end

			local n = 0
			for _ in pairs(newLocated) do
				n = n + 1
			end
			local sc = 0
			for _ in pairs(newServers) do
				sc = sc + 1
			end

			local changed = (n ~= locatedCount) or (sc ~= serverCount)
			if not changed then
				for jid, srv in pairs(newServers) do
					local old = servers[jid]
					if old == nil or sigOf(old) ~= sigOf(srv) then
						changed = true
						break
					end
				end
			end

			servers = newServers
			located = newLocated
			locatedCount = n
			serverCount = sc
			if changed then
				version = version + 1
			end
		end
	end

	local function niceRegion(r)
		local s = tostring(r or "")
		if s == "" or s == "N/A" then
			return "Unknown region"
		end
		s = string.gsub(s, "/", " - ")
		return s
	end

	local function formatUptime(startedAt)
		if not startedAt or startedAt <= 0 then
			return "Unknown"
		end
		local mins = math.max(0, math.floor((os.time() - startedAt) / 60))
		local h = math.floor(mins / 60)
		local m = mins % 60
		if h > 0 then
			return h .. "h " .. m .. "m"
		end
		return m .. "m"
	end

	local function thumbUrl(userId)
		return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
	end

	-- servers per region + average ping (sorted: most servers first)
	local function regionSummary()
		local agg = {}
		local total = 0
		local pSum = 0
		local pN = 0
		for _, srv in pairs(servers) do
			local name = niceRegion(srv.region)
			local a = agg[name]
			if a == nil then
				a = { name = name, count = 0, pSum = 0, pN = 0 }
				agg[name] = a
			end
			a.count = a.count + 1
			total = total + 1
			if srv.ping and srv.ping > 0 then
				a.pSum = a.pSum + srv.ping
				a.pN = a.pN + 1
				pSum = pSum + srv.ping
				pN = pN + 1
			end
		end
		local arr = {}
		for _, a in pairs(agg) do
			table.insert(arr, a)
		end
		table.sort(arr, function(x, y)
			if x.count ~= y.count then
				return x.count > y.count
			end
			return x.name < y.name
		end)
		return arr, total, pSum, pN
	end

	---------------------------------------------------------------------
	-- DATA: names (loaded in the background, everything shows immediately)
	---------------------------------------------------------------------
	local names = {}
	local namesCount = 0
	local setName = function(_id, _username, _display) end
	local resolveNames = function() return false end

	do
		local tried = {}

		setName = function(id, username, display)
			if names[id] == nil then
				namesCount = namesCount + 1
			end
			names[id] = { name = username, display = display }
		end

		-- loads one batch of 100; returns true if more are waiting
		resolveNames = function()
			local own = Players:GetPlayers()
			for i = 1, #own do
				setName(own[i].UserId, own[i].Name, own[i].DisplayName)
			end
			if not httpRequest then
				return false
			end

			local batch = {}
			local more = false
			for id, _ in pairs(located) do
				if names[id] == nil and not tried[id] then
					if #batch < 100 then
						table.insert(batch, id)
					else
						more = true
						break
					end
				end
			end
			if #batch == 0 then
				return false
			end

			local data, code = httpJson("POST", "https://users.roblox.com/v1/users", { userIds = batch, excludeBannedUsers = false })
			if code == 429 then
				task.wait(4)
				return true
			end
			if data and data.data then
				for k = 1, #data.data do
					local u = data.data[k]
					setName(u.id, u.name, u.displayName)
				end
				for k = 1, #batch do
					tried[batch[k]] = true
				end
			elseif code ~= 0 then
				for k = 1, #batch do
					tried[batch[k]] = true
				end
			end
			return more
		end
	end

	---------------------------------------------------------------------
	-- SIZES (switch with Touch Mode)
	---------------------------------------------------------------------
	local METRICS_NORMAL = {
		boxH = 34, boxText = 13, loadW = 64,
		trayH = 30, tabW = 84, tabH = 24, tabText = 12,
		chipH = 24, chipText = 11,
		headerH = 52, titleY = 9, subY = 28, titleText = 13, subText = 11,
		joinW = 54, joinH = 28, joinText = 12,
		smallH = 26, smallText = 11, smallW1 = 88, smallW2 = 92, smallW3 = 92,
		rowH = 40, avatar = 28, nameText = 13, userText = 11, roleText = 10,
		idW = 36, idH = 22, idText = 10,
		moreH = 32, moreText = 12,
	}
	local METRICS_TOUCH = {
		boxH = 44, boxText = 14, loadW = 76,
		trayH = 40, tabW = 96, tabH = 34, tabText = 13,
		chipH = 34, chipText = 12,
		headerH = 66, titleY = 13, subY = 36, titleText = 14, subText = 12,
		joinW = 68, joinH = 40, joinText = 13,
		smallH = 38, smallText = 12, smallW1 = 100, smallW2 = 108, smallW3 = 108,
		rowH = 54, avatar = 38, nameText = 14, userText = 12, roleText = 11,
		idW = 48, idH = 34, idText = 11,
		moreH = 44, moreText = 13,
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
	setMetrics(win.Touch)

	---------------------------------------------------------------------
	-- WIDGETS (inside the main page of the window)
	---------------------------------------------------------------------
	local mainPage = win.MainPage
	local render = function(_force) end
	local layoutFinder = function() end
	local stopGroup = function() end

	local box = new("TextBox", {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = SIDEBAR_BG,
		BorderSizePixel = 0,
		TextColor3 = TEXT_COLOR,
		PlaceholderText = "Search a player: display name, username or ID...",
		PlaceholderColor3 = DIM_TEXT,
		Text = "",
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, mainPage)
	corner(box, RADIUS + 2)
	stroke(box, BORDER, 1, 0)
	pad(box, 12, 0, 12, 0)

	local loadBtn = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 8),
		Size = UDim2.fromOffset(64, 34),
		BackgroundColor3 = CLUSTER_BG,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "Load",
		TextColor3 = ICON_HOVER,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		Visible = false,
	}, mainPage)
	corner(loadBtn, RADIUS + 2)
	stroke(loadBtn, BORDER, 1, 0)
	hoverable(loadBtn, CLUSTER_BG, HOVER_GREY, ICON_HOVER, ICON_HOVER)

	-- tab tray (same look as the button tray in the unload dialog)
	local tray = new("Frame", {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.fromOffset(176, 30),
		BackgroundColor3 = CLUSTER_BG,
		BorderSizePixel = 0,
	}, mainPage)
	corner(tray, RADIUS + 2)

	local function makeTab(text)
		local b = new("TextButton", {
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.fromOffset(84, 24),
			BackgroundColor3 = HOVER_GREY,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = text,
			TextColor3 = ICON,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
		}, tray)
		corner(b, 4)
		return b
	end
	local tabServers = makeTab("Servers")
	local tabGroup = makeTab("Group")

	local status = label(mainPage, "", UDim2.fromOffset(188, 50), UDim2.new(1, -188, 0, 30),
		Enum.Font.Gotham, 11, DIM_TEXT, Enum.TextXAlignment.Right)

	-- region summary row (Servers tab only)
	local regionRow = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 88),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = ICON,
		ScrollBarImageTransparency = 0.5,
		ScrollingDirection = Enum.ScrollingDirection.X,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
	}, mainPage)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, regionRow)

	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.new(1, 0, 1, -124),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = ICON,
		ScrollBarImageTransparency = 0.5,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, mainPage)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	local emptyLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 180),
		Size = UDim2.new(1, -80, 0, 70),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = DIM_TEXT,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextWrapped = true,
		Visible = false,
	}, mainPage)

	local moreBtn = new("TextButton", {
		LayoutOrder = 999999,
		Size = UDim2.new(1, -8, 0, 32),
		BackgroundColor3 = CLUSTER_BG,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "Show more servers",
		TextColor3 = ICON,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		Visible = false,
	}, list)
	corner(moreBtn, RADIUS + 2)
	hoverable(moreBtn, CLUSTER_BG, HOVER_GREY, ICON, ICON_HOVER)

	---------------------------------------------------------------------
	-- LOADING SCREEN (covers the page until enough names are loaded)
	---------------------------------------------------------------------
	do
		local LOAD_SLACK = opts.LoadSlack or 150     -- ready when this many (or fewer) players are still unloaded
		local LOAD_TIMEOUT = opts.LoadTimeout or 60  -- safety: open anyway after this many seconds

		local overlay = new("CanvasGroup", {
			Name = "LoadingOverlay",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = BLACK,
			BorderSizePixel = 0,
			Active = true,
			GroupTransparency = 0,
			ZIndex = 50,
		}, mainPage)

		-- spinner: a faint full ring with a bright arc that rotates on top of it
		local function ringFrame()
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, -22),
				Size = UDim2.fromOffset(36, 36),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 51,
			}, overlay)
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

		local waitLabel = label(overlay, "Please wait", UDim2.new(0.5, -100, 0.5, 8), UDim2.fromOffset(200, 18),
			Enum.Font.GothamMedium, 14, TEXT_COLOR, Enum.TextXAlignment.Center)
		waitLabel.ZIndex = 51
		local progLabel = label(overlay, "", UDim2.new(0.5, -100, 0.5, 30), UDim2.fromOffset(200, 14),
			Enum.Font.Gotham, 11, DIM_TEXT, Enum.TextXAlignment.Center)
		progLabel.ZIndex = 51

		local OPEN_INFO = TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local startedAt = os.clock()

		task.spawn(function()
			local ready = false
			while running and not ready do
				task.wait(0.4)
				-- serverCount > 0 means the first server list read has happened
				if serverCount > 0 then
					local resolved = 0
					for id, _ in pairs(located) do
						if names[id] then
							resolved = resolved + 1
						end
					end
					local need = math.max(0, locatedCount - LOAD_SLACK)
					if need > 0 then
						progLabel.Text = "Loading players  " .. math.min(resolved, need) .. "/" .. need
					end
					if (not httpRequest) or resolved >= need or (os.clock() - startedAt) > LOAD_TIMEOUT then
						ready = true
					end
				end
			end
			if not ready then
				return
			end
			spin:Cancel()
			TweenService:Create(overlay, OPEN_INFO, { GroupTransparency = 1 }):Play()
			task.delay(OPEN_INFO.Time + 0.05, function()
				overlay.Visible = false
			end)
		end)
	end

	---------------------------------------------------------------------
	-- LOGIC: cards, rendering, regions, groups, inputs
	---------------------------------------------------------------------
	do
		local cards = {}
		local expanded = {}   -- jobId -> true/false when you toggled it by hand
		local expandRev = 0
		local group = nil     -- { id, name, members = {userId = roleName}, checked, status, rev }
		local groupToken = 0
		local tab = "servers"
		local shown = PAGE_SIZE
		local lastSig = ""
		local lastMatchCount = 0
		local shownCards = {}
		local savedText = { servers = "", group = "" }
		local styleRev = 0
		local regionFilter = nil   -- nil = all regions
		local regionChips = {}
		local allChip = nil

		-------------------------------------------------------------
		-- Actions
		-------------------------------------------------------------
		local function copyText(text, msg)
			if clip then
				local ok = pcall(clip, text)
				if ok then
					toast(msg)
					return
				end
			end
			print(text)
			toast("No clipboard here - printed to console (F9)")
		end

		local function joinLink(srv)
			return "https://www.roblox.com/games/start?placeId=" .. tostring(game.PlaceId) .. "&gameInstanceId=" .. srv.jobId
		end

		local function joinScript(srv)
			return 'game:GetService("TeleportService"):TeleportToPlaceInstance(' .. tostring(game.PlaceId) .. ', "' .. srv.jobId .. '", game.Players.LocalPlayer)'
		end

		local function joinServer(srv)
			if srv.jobId == game.JobId then
				toast("You are already in this server")
				return
			end
			toast("Teleporting...")
			local ok, err = pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.jobId, player)
			end)
			if not ok then
				toast("Teleport failed")
				warn("[finder] teleport failed:", err)
			end
		end

		-------------------------------------------------------------
		-- Server cards (created once per server, then reused)
		-------------------------------------------------------------
		local function smallBtn(text, order, parent)
			local b = new("TextButton", {
				LayoutOrder = order,
				Size = UDim2.new(0, 88, 1, 0),
				BackgroundColor3 = CLUSTER_BG,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = text,
				TextColor3 = ICON,
				Font = Enum.Font.GothamMedium,
				TextSize = 11,
			}, parent)
			corner(b, RADIUS + 2)
			hoverable(b, CLUSTER_BG, HOVER_GREY, ICON, ICON_HOVER)
			return b
		end

		-- sizes that depend on Touch Mode
		local function styleCard(c)
			c.styleRev = styleRev
			c.header.Size = UDim2.new(1, 0, 0, M.headerH)
			local textW = M.joinW + 50
			c.title.Position = UDim2.new(0, 32, 0, M.titleY)
			c.title.Size = UDim2.new(1, -textW, 0, M.titleText + 5)
			c.title.TextSize = M.titleText
			c.sub.Position = UDim2.new(0, 32, 0, M.subY)
			c.sub.Size = UDim2.new(1, -textW, 0, M.subText + 5)
			c.sub.TextSize = M.subText
			c.joinBtn.Size = UDim2.fromOffset(M.joinW, M.joinH)
			c.joinBtn.TextSize = M.joinText
			c.actions.Size = UDim2.new(1, 0, 0, M.smallH)
			local widths = { M.smallW1, M.smallW2, M.smallW3 }
			for i = 1, 3 do
				c.smalls[i].Size = UDim2.new(0, widths[i], 1, 0)
				c.smalls[i].TextSize = M.smallText
			end
		end

		-- height of the player area follows the animated fraction (0 = closed, 1 = open)
		local function applyClip(c)
			local h = math.floor(c.target * c.frac.Value + 0.5)
			c.clip.Size = UDim2.new(1, 0, 0, h)
		end

		local function getCard(jobId)
			local c = cards[jobId]
			if c then
				return c
			end

			local frame = new("Frame", {
				Size = UDim2.new(1, -8, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = SIDEBAR_BG,
				BorderSizePixel = 0,
			}, nil)
			corner(frame, RADIUS + 4)
			stroke(frame, BORDER, 1, 0)
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, frame)

			local header = new("TextButton", {
				LayoutOrder = 0,
				Size = UDim2.new(1, 0, 0, 52),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
			}, frame)

			-- custom chevron: two rounded bars, rotates when the card opens
			local arrow = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 18, 0.5, 0),
				Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 1,
			}, header)
			local function chevArm(y, rot)
				local f = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(6.7, y),
					Size = UDim2.fromOffset(8, 2),
					Rotation = rot,
					BackgroundColor3 = DIM_TEXT,
					BorderSizePixel = 0,
				}, arrow)
				corner(f, 1)
			end
			chevArm(4.2, 45)
			chevArm(9.8, -45)

			local title = new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 32, 0, 9),
				Size = UDim2.new(1, -104, 0, 18),
				Text = "",
				TextColor3 = TEXT_COLOR,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, header)

			local sub = new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 32, 0, 28),
				Size = UDim2.new(1, -104, 0, 16),
				Text = "",
				TextColor3 = DIM_TEXT,
				Font = Enum.Font.Gotham,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, header)

			local joinBtn = new("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(54, 28),
				BackgroundColor3 = JOIN_BG,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "Join",
				TextColor3 = BLACK,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
			}, header)
			corner(joinBtn, RADIUS + 2)

			-- clip frame: its height is animated, the content inside keeps its full size
			local clipFrame = new("Frame", {
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = true,
			}, frame)

			local content = new("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, clipFrame)
			new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, content)
			pad(content, 8, 0, 8, 8)

			local actions = new("Frame", {
				LayoutOrder = 0,
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 1,
			}, content)
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}, actions)

			local linkBtn = smallBtn("Copy Link", 1, actions)
			local idBtn = smallBtn("Copy Job ID", 2, actions)
			local scriptBtn = smallBtn("Copy Script", 3, actions)

			local frac = new("NumberValue", { Value = 0 }, frame)

			c = {
				frame = frame,
				header = header,
				arrow = arrow,
				title = title,
				sub = sub,
				joinBtn = joinBtn,
				clip = clipFrame,
				content = content,
				actions = actions,
				smalls = { linkBtn, idBtn, scriptBtn },
				frac = frac,
				target = 0,
				rows = {},
				srv = nil,
				open = false,
				mine = nil,
				tween = nil,
				arrowTween = nil,
				styleRev = -1,
			}
			cards[jobId] = c

			frac.Changed:Connect(function()
				applyClip(c)
			end)

			header.Activated:Connect(function()
				expanded[jobId] = not c.open
				expandRev = expandRev + 1
				render(true)
			end)
			header.MouseEnter:Connect(function()
				TweenService:Create(frame, FAST, { BackgroundColor3 = CARD_BG }):Play()
			end)
			header.MouseLeave:Connect(function()
				TweenService:Create(frame, FAST, { BackgroundColor3 = SIDEBAR_BG }):Play()
			end)
			joinBtn.MouseEnter:Connect(function()
				if not c.mine then
					TweenService:Create(joinBtn, FAST, { BackgroundColor3 = Color3.fromRGB(255, 255, 255) }):Play()
				end
			end)
			joinBtn.MouseLeave:Connect(function()
				if not c.mine then
					TweenService:Create(joinBtn, FAST, { BackgroundColor3 = JOIN_BG }):Play()
				end
			end)
			joinBtn.Activated:Connect(function()
				if c.srv then
					joinServer(c.srv)
				end
			end)
			linkBtn.Activated:Connect(function()
				if c.srv then
					copyText(joinLink(c.srv), "Join link copied")
				end
			end)
			idBtn.Activated:Connect(function()
				if c.srv then
					copyText(c.srv.jobId, "Job ID copied")
				end
			end)
			scriptBtn.Activated:Connect(function()
				if c.srv then
					copyText(joinScript(c.srv), "Join script copied")
				end
			end)

			styleCard(c)
			return c
		end

		-- sizes of one player row that depend on Touch Mode
		local function styleRow(r)
			r.styleRev = styleRev
			r.frame.Size = UDim2.new(1, 0, 0, M.rowH)
			r.pic.Size = UDim2.new(0, M.avatar, 0, M.avatar)
			local textX = 6 + M.avatar + 8
			local idRight = 6 + M.idW + 8
			local block = M.nameText + M.userText + 7
			local top = math.floor((M.rowH - block) / 2)
			r.display.Position = UDim2.new(0, textX, 0, top)
			r.display.Size = UDim2.new(1, -(textX + idRight + 48), 0, M.nameText + 4)
			r.display.TextSize = M.nameText
			r.user.Position = UDim2.new(0, textX, 0, top + M.nameText + 4)
			r.user.Size = UDim2.new(1, -(textX + idRight + 48), 0, M.userText + 3)
			r.user.TextSize = M.userText
			r.role.Position = UDim2.new(1, -idRight, 0.5, 0)
			r.role.TextSize = M.roleText
			r.idBtn.Size = UDim2.new(0, M.idW, 0, M.idH)
			r.idBtn.TextSize = M.idText
		end

		local function getPlayerRow(card, userId)
			local r = card.rows[userId]
			if r then
				return r
			end

			local frame = new("TextButton", {
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundColor3 = CARD_BG,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
			}, nil)
			corner(frame, RADIUS + 4)
			local rowStroke = stroke(frame, ICON, 1, 1)

			local pic = new("ImageLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 6, 0.5, 0),
				Size = UDim2.new(0, 28, 0, 28),
				BackgroundColor3 = CLUSTER_BG,
				BorderSizePixel = 0,
				Image = thumbUrl(userId),
			}, frame)
			corner(pic, 8)

			local display = new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 42, 0, 4),
				Size = UDim2.new(1, -140, 0, 17),
				Text = "",
				TextColor3 = TEXT_COLOR,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, frame)

			local user = new("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 42, 0, 21),
				Size = UDim2.new(1, -140, 0, 14),
				Text = "",
				TextColor3 = DIM_TEXT,
				Font = Enum.Font.Gotham,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, frame)

			local role = new("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -50, 0.5, 0),
				Size = UDim2.new(0, 80, 0, 16),
				BackgroundTransparency = 1,
				Text = "",
				TextColor3 = DIM_TEXT,
				Font = Enum.Font.Gotham,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, frame)

			local idBtn = new("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -6, 0.5, 0),
				Size = UDim2.new(0, 36, 0, 22),
				BackgroundColor3 = HOVER_GREY,
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "ID",
				TextColor3 = ICON_HOVER,
				Font = Enum.Font.GothamMedium,
				TextSize = 10,
			}, frame)
			corner(idBtn, RADIUS + 2)

			r = {
				frame = frame, pic = pic, display = display, user = user, role = role,
				idBtn = idBtn, stroke = rowStroke, base = CARD_BG, styleRev = -1,
			}
			card.rows[userId] = r

			frame.MouseEnter:Connect(function()
				TweenService:Create(frame, FAST, { BackgroundColor3 = CARD_HOVER }):Play()
			end)
			frame.MouseLeave:Connect(function()
				TweenService:Create(frame, FAST, { BackgroundColor3 = r.base }):Play()
			end)
			idBtn.MouseEnter:Connect(function()
				TweenService:Create(idBtn, FAST, { BackgroundTransparency = 0 }):Play()
			end)
			idBtn.MouseLeave:Connect(function()
				TweenService:Create(idBtn, FAST, { BackgroundTransparency = 0.55 }):Play()
			end)
			frame.Activated:Connect(function()
				local n = names[userId]
				if n then
					copyText(n.name, "Copied username: " .. n.name)
				else
					toast("Name still loading, try again in a moment")
				end
			end)
			idBtn.Activated:Connect(function()
				copyText(tostring(userId), "Copied user ID")
			end)

			styleRow(r)
			return r
		end

		-------------------------------------------------------------
		-- Region summary chips
		-------------------------------------------------------------
		local ALL_KEY = "*"

		local function escapeRich(s)
			s = string.gsub(s, "&", "&amp;")
			s = string.gsub(s, "<", "&lt;")
			s = string.gsub(s, ">", "&gt;")
			return s
		end

		local function statsText(count, ps, pn)
			local s = count .. " srv"
			if pn > 0 then
				s = s .. " | " .. math.floor(ps / pn + 0.5) .. " ms"
			end
			return s
		end

		local function paintChip(chip)
			local sel = false
			if chip.key == ALL_KEY then
				sel = (regionFilter == nil)
			else
				sel = (regionFilter == chip.key)
			end
			local sig = tostring(sel) .. "|" .. tostring(chip.over) .. "|" .. chip.label .. "|" .. chip.stats
			if chip.sig == sig then
				return
			end
			chip.sig = sig

			local bg = CLUSTER_BG
			local textColor = TEXT_COLOR
			local dim = "#74747C"
			if sel then
				bg = HOVER_GREY
				textColor = ICON_HOVER
				dim = "#B4B4BC"
			elseif chip.over then
				bg = Color3.fromRGB(46, 46, 52)
			end
			TweenService:Create(chip.btn, FAST, { BackgroundColor3 = bg }):Play()
			chip.btn.TextColor3 = textColor
			chip.btn.Text = escapeRich(chip.label) .. "  <font color=\"" .. dim .. "\">" .. escapeRich(chip.stats) .. "</font>"
		end

		local function setRegion(key)
			if key == ALL_KEY or key == regionFilter then
				regionFilter = nil
			else
				regionFilter = key
			end
			shown = PAGE_SIZE
			render(true)
		end

		local function makeChip(key)
			local b = new("TextButton", {
				Size = UDim2.new(0, 0, 0, M.chipH),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = CLUSTER_BG,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				RichText = true,
				TextColor3 = TEXT_COLOR,
				Font = Enum.Font.GothamMedium,
				TextSize = M.chipText,
			}, regionRow)
			corner(b, RADIUS + 1)
			pad(b, 10, 0, 10, 0)
			local chip = { btn = b, key = key, label = "", stats = "", over = false, sig = "" }
			b.MouseEnter:Connect(function()
				chip.over = true
				paintChip(chip)
			end)
			b.MouseLeave:Connect(function()
				chip.over = false
				paintChip(chip)
			end)
			b.Activated:Connect(function()
				setRegion(chip.key)
			end)
			return chip
		end

		local function restyleChips()
			if allChip then
				allChip.btn.Size = UDim2.new(0, 0, 0, M.chipH)
				allChip.btn.TextSize = M.chipText
			end
			for _, chip in pairs(regionChips) do
				chip.btn.Size = UDim2.new(0, 0, 0, M.chipH)
				chip.btn.TextSize = M.chipText
			end
		end

		-- chips are reused, only their text changes, so hovering and clicking never flickers
		local function updateRegions()
			local arr, total, pSum, pN = regionSummary()

			if allChip == nil then
				allChip = makeChip(ALL_KEY)
				allChip.btn.LayoutOrder = 0
			end
			allChip.label = "All"
			allChip.stats = statsText(total, pSum, pN)
			paintChip(allChip)

			local seen = {}
			for i = 1, #arr do
				local a = arr[i]
				local chip = regionChips[a.name]
				if chip == nil then
					chip = makeChip(a.name)
					regionChips[a.name] = chip
				end
				chip.label = a.name
				chip.stats = statsText(a.count, a.pSum, a.pN)
				chip.btn.LayoutOrder = i
				seen[a.name] = true
				paintChip(chip)
			end

			for name, chip in pairs(regionChips) do
				if not seen[name] then
					chip.btn:Destroy()
					regionChips[name] = nil
					if regionFilter == name then
						regionFilter = nil
						task.defer(function()
							render(true)
						end)
					end
				end
			end
		end

		-------------------------------------------------------------
		-- Rendering
		-------------------------------------------------------------
		local function updateStatus()
			win:SetStats(serverCount .. " servers  |  " .. locatedCount .. " players")
			local q = string.match(box.Text, "%S")
			if tab == "servers" then
				if q then
					status.Text = lastMatchCount .. " server(s) found"
				elseif httpRequest then
					local resolved = 0
					for id, _ in pairs(located) do
						if names[id] then
							resolved = resolved + 1
						end
					end
					status.Text = resolved .. "/" .. locatedCount .. " names loaded"
				else
					status.Text = "names need an executor request function"
				end
			else
				if group then
					status.Text = group.status .. " | " .. lastMatchCount .. " server(s)"
				else
					status.Text = "Enter a group ID (or group URL) and press Load"
				end
			end
		end

		render = function(force)
			updateRegions()

			local q = string.lower(box.Text)
			q = string.match(q, "^%s*(.-)%s*$") or ""

			local groupPart = ""
			if group then
				groupPart = tostring(group.id) .. ":" .. tostring(group.rev)
			end
			local sig = tab .. "|" .. q .. "|" .. version .. "|" .. namesCount .. "|" .. shown .. "|" .. expandRev .. "|" .. groupPart .. "|" .. tostring(regionFilter) .. "|" .. styleRev
			if not force and sig == lastSig then
				updateStatus()
				return
			end
			lastSig = sig

			-- 1) pick the servers to show
			local entries = {}
			for jid, srv in pairs(servers) do
				local include = false
				local matches = 0
				local matchSet = {}
				local ids = nil

				if tab == "servers" then
					if q == "" then
						include = true
					else
						for i = 1, #srv.players do
							local id = srv.players[i]
							local hit = false
							if tostring(id) == q then
								hit = true
							else
								local n = names[id]
								if n then
									if string.find(string.lower(n.display), q, 1, true) or string.find(string.lower(n.name), q, 1, true) then
										hit = true
									end
								end
							end
							if hit then
								matchSet[id] = true
								matches = matches + 1
							end
						end
						if matches > 0 then
							include = true
						elseif string.sub(string.lower(jid), 1, #q) == q then
							include = true
						end
					end
					if include and regionFilter ~= nil then
						if niceRegion(srv.region) ~= regionFilter then
							include = false
						end
					end
				else
					if group then
						ids = {}
						for i = 1, #srv.players do
							local id = srv.players[i]
							if group.members[id] ~= nil then
								table.insert(ids, id)
								matchSet[id] = true
								matches = matches + 1
							end
						end
						if matches > 0 then
							include = true
						end
					end
				end

				if include then
					table.insert(entries, { srv = srv, matches = matches, matchSet = matchSet, ids = ids })
				end
			end

			table.sort(entries, function(a, b)
				if tab == "servers" and q == "" then
					local am = (a.srv.jobId == game.JobId)
					local bm = (b.srv.jobId == game.JobId)
					if am ~= bm then
						return am
					end
				end
				if a.matches ~= b.matches then
					return a.matches > b.matches
				end
				if a.srv.count ~= b.srv.count then
					return a.srv.count > b.srv.count
				end
				return a.srv.jobId < b.srv.jobId
			end)

			lastMatchCount = #entries
			local limit = math.min(#entries, shown)
			local autoOpen = (tab == "servers" and q ~= "") or (tab == "group")
			local newShown = {}

			-- 2) update the cards
			for i = 1, limit do
				local e = entries[i]
				local srv = e.srv
				local c = getCard(srv.jobId)
				local wasShown = (c.frame.Parent == list)
				c.srv = srv
				if c.styleRev ~= styleRev then
					styleCard(c)
				end
				local mine = (srv.jobId == game.JobId)

				local titleText = "Server " .. string.sub(srv.jobId, 1, 8)
				if mine then
					titleText = titleText .. "  (you are here)"
					c.title.TextColor3 = GREEN
				else
					c.title.TextColor3 = TEXT_COLOR
				end
				c.title.Text = titleText

				if c.mine ~= mine then
					c.mine = mine
					if mine then
						c.joinBtn.Text = "Here"
						c.joinBtn.BackgroundColor3 = CLUSTER_BG
						c.joinBtn.TextColor3 = DIM_TEXT
					else
						c.joinBtn.Text = "Join"
						c.joinBtn.BackgroundColor3 = JOIN_BG
						c.joinBtn.TextColor3 = BLACK
					end
				end

				local parts = {}
				if e.matches > 0 then
					table.insert(parts, e.matches .. " found")
				end
				table.insert(parts, srv.count .. "/" .. srv.max .. " players")
				table.insert(parts, niceRegion(srv.region))
				if srv.ping then
					table.insert(parts, math.floor(srv.ping + 0.5) .. " ms")
				end
				local up = formatUptime(srv.startedAt)
				if up ~= "Unknown" then
					table.insert(parts, up)
				end
				c.sub.Text = table.concat(parts, "  |  ")

				local open = autoOpen
				if expanded[srv.jobId] ~= nil then
					open = expanded[srv.jobId]
				end
				local wasOpen = c.open

				if open then
					local source = e.ids or srv.players
					local sorted = {}
					for k = 1, #source do
						sorted[k] = source[k]
					end
					table.sort(sorted, function(a, b)
						local ma = (e.matchSet[a] == true)
						local mb = (e.matchSet[b] == true)
						if ma ~= mb then
							return ma
						end
						local na = names[a]
						local nb = names[b]
						if (na ~= nil) ~= (nb ~= nil) then
							return na ~= nil
						end
						if na and nb then
							local da = string.lower(na.display)
							local db = string.lower(nb.display)
							if da ~= db then
								return da < db
							end
						end
						return a < b
					end)

					local used = {}
					local rowCount = math.min(#sorted, MAX_PLAYER_ROWS)
					for k = 1, rowCount do
						local id = sorted[k]
						local r = getPlayerRow(c, id)
						if r.styleRev ~= styleRev then
							styleRow(r)
						end
						local n = names[id]
						if n then
							r.display.Text = n.display
							r.user.Text = "@" .. n.name
						else
							r.display.Text = "Loading..."
							r.user.Text = "ID " .. tostring(id)
						end
						if tab == "group" and group and group.members[id] then
							r.role.Text = group.members[id]
						else
							r.role.Text = ""
						end
						if e.matchSet[id] == true and tab == "servers" then
							r.base = MATCH_BG
							r.stroke.Transparency = 0.5
						else
							r.base = CARD_BG
							r.stroke.Transparency = 1
						end
						r.frame.BackgroundColor3 = r.base
						r.frame.LayoutOrder = k
						r.frame.Parent = c.content
						used[id] = true
					end
					for id, r in pairs(c.rows) do
						if not used[id] then
							r.frame.Parent = nil
						end
					end
					-- actions row + rows + gaps between them + bottom padding
					c.target = M.smallH + rowCount * (M.rowH + 4) + 8
				end

				-- open / close animation (same easing as the account popup); snaps if the card was not on screen
				c.open = open
				if open ~= wasOpen then
					if c.tween then
						c.tween:Cancel()
					end
					if c.arrowTween then
						c.arrowTween:Cancel()
					end
					local goal = 0
					local rot = 0
					if open then
						goal = 1
						rot = 90
					end
					if wasShown then
						local info = COLLAPSE
						if open then
							info = EXPAND
						end
						c.tween = TweenService:Create(c.frac, info, { Value = goal })
						c.tween:Play()
						c.arrowTween = TweenService:Create(c.arrow, info, { Rotation = rot })
						c.arrowTween:Play()
					else
						c.frac.Value = goal
						c.arrow.Rotation = rot
					end
				end
				applyClip(c)

				c.frame.LayoutOrder = i
				c.frame.Parent = list
				newShown[srv.jobId] = c
			end

			for jid, c in pairs(shownCards) do
				if not newShown[jid] then
					c.frame.Parent = nil
				end
			end
			shownCards = newShown

			-- forget cards of servers that no longer exist
			for jid, c in pairs(cards) do
				if servers[jid] == nil then
					c.frame:Destroy()
					cards[jid] = nil
					shownCards[jid] = nil
				end
			end

			if #entries > limit then
				moreBtn.Text = "Show more servers (" .. (#entries - limit) .. " left)"
				moreBtn.Visible = true
			else
				moreBtn.Visible = false
			end

			if #entries == 0 then
				if tab == "servers" then
					if q ~= "" then
						emptyLabel.Text = "No player matches that yet. Names are still loading in the background, so try again in a moment."
					elseif regionFilter ~= nil then
						emptyLabel.Text = "No servers in this region."
					elseif serverCount == 0 then
						emptyLabel.Text = "No servers found in the game's server list yet."
					else
						emptyLabel.Text = ""
					end
				else
					if not group then
						emptyLabel.Text = "Type a group ID above and press Load to see which servers have members in them."
					else
						emptyLabel.Text = "Nobody from this group is in game right now."
					end
				end
				emptyLabel.Visible = (emptyLabel.Text ~= "")
			else
				emptyLabel.Visible = false
			end

			updateStatus()
		end

		moreBtn.MouseButton1Click:Connect(function()
			shown = shown + PAGE_SIZE
			render(true)
		end)

		-------------------------------------------------------------
		-- Group loading
		-------------------------------------------------------------
		local function checkOwnServer(g)
			-- instant check for people in YOUR server (works even without HTTP)
			local own = Players:GetPlayers()
			for i = 1, #own do
				local p = own[i]
				local okIn, inGroup = pcall(function()
					return p:IsInGroup(g.id)
				end)
				if okIn and inGroup then
					local roleName = "Member"
					local okRole, role = pcall(function()
						return p:GetRoleInGroup(g.id)
					end)
					if okRole and role and role ~= "" then
						roleName = role
					end
					if g.members[p.UserId] == nil then
						g.members[p.UserId] = roleName
						g.rev = g.rev + 1
					end
				end
			end
		end

		local function fetchGroupInfo(gid)
			local info, code = httpRetry("GET", "https://groups.roblox.com/v1/groups/" .. gid, nil, 2)
			if info and info.name then
				return info, 200
			end
			local info2 = httpRetry("GET", "https://groups.roblox.com/v2/groups?groupIds=" .. gid, nil, 2)
			if info2 and info2.data and info2.data[1] and info2.data[1].name then
				return info2.data[1], 200
			end
			return nil, code
		end

		-- downloads the whole member list; returns "ok", "fail" or "cancel"
		local function loadMemberList(g, token, gid, total)
			local cursor = nil
			local loaded = 0
			while running do
				if token ~= groupToken then
					return "cancel"
				end
				local url = "https://groups.roblox.com/v1/groups/" .. gid .. "/users?limit=100&sortOrder=Asc"
				if cursor then
					url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
				end
				local res, c = httpRetry("GET", url, nil, 4)
				if token ~= groupToken then
					return "cancel"
				end
				if not res or not res.data then
					return "fail", c
				end
				for i = 1, #res.data do
					local item = res.data[i]
					if item.user then
						local uid = item.user.userId
						local roleName = "Member"
						if item.role and item.role.name then
							roleName = item.role.name
						end
						g.members[uid] = roleName
						if names[uid] == nil and item.user.username then
							setName(uid, item.user.username, item.user.displayName or item.user.username)
						end
					end
				end
				loaded = loaded + #res.data
				g.status = g.name .. " - loaded " .. loaded .. "/" .. total .. " members"
				g.rev = g.rev + 1
				render(true)
				cursor = res.nextPageCursor
				if cursor == nil then
					return "ok"
				end
				task.wait(0.35)
			end
			return "cancel"
		end

		-- checks each in-game player's groups (slower, keeps running to catch new players)
		local function perPlayerLoop(g, token, gid)
			local checkedN = 0
			while running and token == groupToken do
				local pending = {}
				for id, _ in pairs(located) do
					if not g.checked[id] then
						table.insert(pending, id)
					end
				end
				for i = 1, #pending do
					if token ~= groupToken or not running then
						return
					end
					local id = pending[i]
					local res = httpRetry("GET", "https://groups.roblox.com/v2/users/" .. id .. "/groups/roles", nil, 4)
					g.checked[id] = true
					checkedN = checkedN + 1
					if res and res.data then
						for k = 1, #res.data do
							local item = res.data[k]
							if item.group and item.group.id == gid then
								local roleName = "Member"
								if item.role and item.role.name then
									roleName = item.role.name
								end
								g.members[id] = roleName
								g.rev = g.rev + 1
							end
						end
					end
					g.status = g.name .. " - checked " .. checkedN .. "/" .. locatedCount .. " players"
					updateStatus()
					task.wait(0.25)
				end
				checkOwnServer(g)
				render(false)
				task.wait(2)
			end
		end

		local function startGroup(gid)
			groupToken = groupToken + 1
			local token = groupToken
			local g = { id = gid, name = "Group " .. gid, members = {}, checked = {}, status = "Loading group " .. gid .. "...", rev = 0 }
			group = g
			shown = PAGE_SIZE
			expanded = {}
			render(true)

			task.spawn(function()
				checkOwnServer(g)
				render(true)

				local info, code = fetchGroupInfo(gid)
				if token ~= groupToken then
					return
				end

				local total = GROUP_MEMBER_CAP + 1
				if info then
					g.name = info.name
					total = tonumber(info.memberCount) or 0
				elseif code == 404 then
					g.status = "Group " .. gid .. " does not exist (HTTP 404) - check the ID"
					g.rev = g.rev + 1
					render(true)
					return
				else
					g.status = "Group info failed (HTTP " .. tostring(code) .. "), checking players one by one"
					g.rev = g.rev + 1
					render(true)
				end

				local needPerPlayer = true
				if total <= GROUP_MEMBER_CAP then
					local result, c = loadMemberList(g, token, gid, total)
					if result == "cancel" then
						return
					end
					if result == "ok" then
						g.status = g.name .. " (" .. total .. " members)"
						g.rev = g.rev + 1
						render(true)
						needPerPlayer = false
					else
						g.status = "Member list failed (HTTP " .. tostring(c) .. "), checking players one by one"
						g.rev = g.rev + 1
						render(true)
					end
				end

				if needPerPlayer then
					perPlayerLoop(g, token, gid)
				end
			end)
		end

		local function submitGroup()
			local text = box.Text
			local gid = tonumber(string.match(text, "groups/(%d+)") or string.match(text, "communities/(%d+)") or string.match(text, "%d+"))
			if not gid then
				status.Text = "Enter a numeric group ID"
				return
			end
			if not httpRequest then
				status.Text = "Group search needs an executor request function"
				return
			end
			startGroup(gid)
		end

		-------------------------------------------------------------
		-- Layout (positions and sizes for the current mode and tab)
		-------------------------------------------------------------
		layoutFinder = function()
			styleRev = styleRev + 1
			local y = 8

			box.Position = UDim2.fromOffset(0, y)
			box.TextSize = M.boxText
			if tab == "group" then
				box.Size = UDim2.new(1, -(M.loadW + 8), 0, M.boxH)
			else
				box.Size = UDim2.new(1, 0, 0, M.boxH)
			end
			loadBtn.Position = UDim2.new(1, 0, 0, y)
			loadBtn.Size = UDim2.fromOffset(M.loadW, M.boxH)
			loadBtn.TextSize = M.boxText
			y = y + M.boxH + 8

			local trayW = 6 + M.tabW * 2 + 2
			tray.Position = UDim2.fromOffset(0, y)
			tray.Size = UDim2.fromOffset(trayW, M.trayH)
			tabServers.Position = UDim2.fromOffset(3, 3)
			tabServers.Size = UDim2.fromOffset(M.tabW, M.tabH)
			tabServers.TextSize = M.tabText
			tabGroup.Position = UDim2.fromOffset(3 + M.tabW + 2, 3)
			tabGroup.Size = UDim2.fromOffset(M.tabW, M.tabH)
			tabGroup.TextSize = M.tabText
			status.Position = UDim2.fromOffset(trayW + 12, y)
			status.Size = UDim2.new(1, -(trayW + 12), 0, M.trayH)
			y = y + M.trayH + 8

			if tab == "servers" then
				regionRow.Visible = true
				regionRow.Position = UDim2.fromOffset(0, y)
				regionRow.Size = UDim2.new(1, 0, 0, M.chipH + 6)
				y = y + M.chipH + 12
			else
				regionRow.Visible = false
			end

			list.Position = UDim2.fromOffset(0, y)
			list.Size = UDim2.new(1, 0, 1, -y)
			emptyLabel.Position = UDim2.new(0.5, 0, 0, y + 56)
			moreBtn.Size = UDim2.new(1, -8, 0, M.moreH)
			moreBtn.TextSize = M.moreText
			restyleChips()
		end

		-------------------------------------------------------------
		-- Tabs and inputs
		-------------------------------------------------------------
		local function paintTab(btn, active, isOver)
			local bgT = 1
			local textColor = ICON
			if active then
				bgT = 0
				textColor = ICON_HOVER
			elseif isOver then
				bgT = 0.55
				textColor = ICON_HOVER
			end
			TweenService:Create(btn, FAST, { BackgroundTransparency = bgT, TextColor3 = textColor }):Play()
		end

		local function paintTabs()
			paintTab(tabServers, tab == "servers", false)
			paintTab(tabGroup, tab == "group", false)
		end

		local function setTab(name)
			if name == tab then
				return
			end
			savedText[tab] = box.Text
			tab = name
			shown = PAGE_SIZE
			expanded = {}
			if name == "servers" then
				box.PlaceholderText = "Search a player: display name, username or ID..."
				loadBtn.Visible = false
			else
				box.PlaceholderText = "Group ID or group URL, then press Load..."
				loadBtn.Visible = true
			end
			layoutFinder()
			paintTabs()
			box.Text = savedText[name]
			render(true)
		end

		tabServers.MouseEnter:Connect(function()
			paintTab(tabServers, tab == "servers", true)
		end)
		tabServers.MouseLeave:Connect(function()
			paintTab(tabServers, tab == "servers", false)
		end)
		tabGroup.MouseEnter:Connect(function()
			paintTab(tabGroup, tab == "group", true)
		end)
		tabGroup.MouseLeave:Connect(function()
			paintTab(tabGroup, tab == "group", false)
		end)

		tabServers.Activated:Connect(function()
			setTab("servers")
		end)
		tabGroup.Activated:Connect(function()
			setTab("group")
		end)

		box:GetPropertyChangedSignal("Text"):Connect(function()
			if tab == "servers" then
				shown = PAGE_SIZE
				expanded = {}
				render(false)
			end
		end)

		box.FocusLost:Connect(function(enterPressed)
			if enterPressed and tab == "group" then
				submitGroup()
			end
		end)

		loadBtn.Activated:Connect(submitGroup)

		paintTabs()

		-- cancels any running group search (used when stopping)
		stopGroup = function()
			groupToken = groupToken + 1
		end
	end

	---------------------------------------------------------------------
	-- START
	---------------------------------------------------------------------
	if not httpRequest then
		warn("[finder] No executor request function: names and group search only work for players in your own server.")
	end
	if not Servers then
		warn("[finder] ReplicatedStorage.Servers not found: only your own server can be listed.")
	end

	local function stop()
		running = false
		stopGroup()
	end
	win:OnUnload(stop)
	function self:Stop()
		stop()
	end

	-- Touch Mode changes: new sizes, then draw again
	win:OnTouchChange(function(on)
		setMetrics(on)
		layoutFinder()
		render(true)
	end)

	pcall(refreshServers)
	pcall(resolveNames)
	setMetrics(win.Touch)
	layoutFinder()
	render(true)

	task.spawn(function()
		local lastErr = nil
		while running do
			pcall(refreshServers)
			if not win:IsHidden() then
				local ok, err = pcall(render, false)
				if not ok and tostring(err) ~= lastErr then
					lastErr = tostring(err)
					warn("[finder] render error: " .. lastErr)
				end
			end
			task.wait(REFRESH_EVERY)
		end
	end)

	task.spawn(function()
		while running do
			local ok, more = pcall(resolveNames)
			if ok and more then
				task.wait(0.6)
			else
				task.wait(2)
			end
		end
	end)

	return self
end

return Finder
