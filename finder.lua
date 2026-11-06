-- finder.lua  (server system module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Reads the game's server list, finds players, groups and regions, and builds its page
-- inside a window made by ui.lua.
--
--   local Finder = <this file>
--   local finder = Finder.new(win, {
--       RefreshEvery = 2,
--       Options = <options.lua table>,   -- optional: gear button, sort, filters
--       Profile = <profile.lua table>,   -- optional: player profile card
--   })
--   finder:Stop()      -- optional, it also stops by itself when the window unloads
--
-- API for your own modules:
--   finder:GetServers()      jobId -> server table { jobId, name, players, count, max, ping, rname, startedAt }
--   finder:GetServer(jobId)
--   finder:Locate(userId)    the server table a player is in (or nil)
--   finder:GetName(userId)   { name, display } or nil
--   finder:Refresh()         read the server list again and redraw
--   finder:Join(jobId)
--
-- Servers tab: square server tiles. Each tile shows the server name, region + ping, five player
--   heads, the player count and a Join button. Click a tile to open a drawer under its row with
--   every player in that server.
--
--   How you see which server is open (you do not have to read the arrow):
--     - the arrow chip on the tile fills white and turns to point down
--     - the tile outline and background light up
--     - a thin stem connects the tile to its drawer
--     - the drawer has the same white chip (pointing up) - click it to close the server again
--
--   Search a display name, username, user ID, or the start of a Job ID. Matching servers open.
--   Region pill: pick a region (Texas etc.) to only show servers there.
-- Group tab: enter a group ID (or paste the group URL) and press Load.
-- Options (gear): sort, hide full servers, free slots needed, friends only, role filter, recent groups.
--
-- Speed: tiles and player rows are virtual. Only what is on screen exists as an Instance, and
--   everything is pooled and reused while you scroll.

local Finder = {}

function Finder.new(win, opts)
	opts = opts or {}

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local HttpService = game:GetService("HttpService")
	local TeleportService = game:GetService("TeleportService")
	local TweenService = game:GetService("TweenService")
	local RunService = game:GetService("RunService")
	local player = Players.LocalPlayer

	local REFRESH_EVERY = opts.RefreshEvery or 2
	local MAX_PLAYER_ROWS = opts.MaxPlayerRows or 100
	local GROUP_MEMBER_CAP = opts.GroupMemberCap or 5000

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
	local POPUP_BG = T.POPUP_BG
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
	local SMOOTH = T.SMOOTH
	local WHITE = Color3.fromRGB(255, 255, 255)

	local function toast(msg)
		win:Toast(msg)
	end

	---------------------------------------------------------------------
	-- CHEVRON: a drawn arrow (two rounded bars) inside a rounded chip
	--   api.chip     the rounded square (Frame, or TextButton when interactive)
	--   api.holder   the part that turns: Rotation 0 = points right, 90 = down, -90 = up
	--   api.inks     the two bars
	--   api.paint(f, h)   f = how open (0..1): fills the chip white and darkens the bars
	--                     h = hover amount (0..1)
	--   api.setSize(s)    chip size in pixels, the arrow scales with it
	---------------------------------------------------------------------
	local function makeChevron(parent, interactive, bare)
		local cls = "Frame"
		if interactive then
			cls = "TextButton"
		end
		local props = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(20, 20),
			BackgroundColor3 = CLUSTER_BG,
			BorderSizePixel = 0,
		}
		if interactive then
			props.AutoButtonColor = false
			props.Text = ""
		end
		if bare then
			props.BackgroundTransparency = 1
		end
		local chip = new(cls, props, parent)
		corner(chip, RADIUS + 2)

		local holder = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, chip)
		local holderScale = new("UIScale", { Scale = 1 }, holder)

		-- two bars that meet at the tip on the right: ">"
		local inks = {}
		local function bar(dy, rot)
			local b = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, dy),
				Size = UDim2.fromOffset(7, 2),
				Rotation = rot,
				BackgroundColor3 = ICON,
				BorderSizePixel = 0,
			}, holder)
			corner(b, 1)
			inks[#inks + 1] = b
		end
		bar(-2.5, 45)
		bar(2.5, -45)

		local api = { chip = chip, holder = holder, inks = inks }

		function api.paint(f, h)
			local bg = CLUSTER_BG:Lerp(HOVER_GREY, h)
			local ink = ICON:Lerp(ICON_HOVER, h)
			local full = JOIN_BG:Lerp(WHITE, h)
			chip.BackgroundColor3 = bg:Lerp(full, f)
			local col = ink:Lerp(BLACK, f)
			for i = 1, #inks do
				inks[i].BackgroundColor3 = col
			end
		end

		function api.setSize(s)
			chip.Size = UDim2.fromOffset(s, s)
			holderScale.Scale = s / 20
		end

		return api
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
	-- small helpers
	---------------------------------------------------------------------
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

	---------------------------------------------------------------------
	-- DATA: server list
	-- Parsed player lists are reused while a server's raw text is unchanged,
	-- and the player -> server map is only rebuilt when something really changed.
	---------------------------------------------------------------------
	local servers = {}       -- jobId -> server table
	local located = {}       -- userId -> the server table they are in
	local locatedCount = 0
	local serverCount = 0
	local version = 0        -- bumps whenever servers or their players change
	local refreshServers = function() end

	do
		local function parsePlayers(raw)
			local seen = {}
			local list = {}
			for piece in string.gmatch(raw, "[^,]+") do
				local n = tonumber(piece)
				if n and n > 0 and n % 1 == 0 and not seen[n] then
					seen[n] = true
					list[#list + 1] = n
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
					if old == nil then
						newest[serverId] = entry
					else
						local newTicker = tonumber(entry:GetAttribute("Ticker")) or 0
						local oldTicker = tonumber(old:GetAttribute("Ticker")) or 0
						if newTicker >= oldTicker then
							newest[serverId] = entry
						end
					end
				end
			end
			return newest
		end

		-- uses a "serverName" / "name" attribute when the game provides one
		local function nameFor(entry, jid)
			if entry then
				local nm = entry:GetAttribute("serverName")
				if type(nm) ~= "string" or nm == "" then
					nm = entry:GetAttribute("name")
				end
				if type(nm) == "string" and nm ~= "" then
					return nm
				end
			end
			if jid == "" then
				return "This server"
			end
			return "Server " .. string.sub(jid, 1, 8)
		end

		refreshServers = function()
			local newest = getNewest()
			local newServers = {}
			local changed = false
			local ownJob = game.JobId

			for jid, entry in pairs(newest) do
				if jid ~= ownJob then
					local raw = tostring(entry:GetAttribute("players") or "")
					local maxP = tonumber(entry:GetAttribute("maxPlayers")) or Players.MaxPlayers
					local region = entry:GetAttribute("region")
					local srv = servers[jid]
					if srv == nil or srv.raw ~= raw or srv.max ~= maxP or srv.region ~= region then
						local list = parsePlayers(raw)
						srv = {
							jobId = jid,
							jl = string.lower(jid),
							raw = raw,
							players = list,
							count = #list,
							max = maxP,
							region = region,
							rname = niceRegion(region),
							name = nameFor(entry, jid),
						}
						changed = true
					end
					srv.ping = tonumber(entry:GetAttribute("ping"))
					srv.startedAt = tonumber(entry:GetAttribute("startedAt"))
					newServers[jid] = srv
				end
			end

			-- your own server always comes from live data
			local own = Players:GetPlayers()
			local ownIds = {}
			local sum = 0
			for i = 1, #own do
				local id = own[i].UserId
				ownIds[i] = id
				sum = (sum + id) % 1000000007
			end
			local ownSig = #ownIds .. ":" .. sum
			local ownSrv = servers[ownJob]
			if ownSrv == nil or ownSrv.sig ~= ownSig then
				ownSrv = {
					jobId = ownJob,
					jl = string.lower(ownJob),
					sig = ownSig,
					players = ownIds,
					count = #ownIds,
					max = Players.MaxPlayers,
					region = "Your server",
					rname = "Your server",
					name = nameFor(nil, ownJob),
				}
				changed = true
			end
			local ownEntry = newest[ownJob]
			if ownEntry then
				local mp = tonumber(ownEntry:GetAttribute("maxPlayers"))
				if mp then
					ownSrv.max = mp
				end
				local rg = ownEntry:GetAttribute("region")
				if rg ~= nil then
					ownSrv.region = rg
					ownSrv.rname = niceRegion(rg)
				end
				ownSrv.startedAt = tonumber(ownEntry:GetAttribute("startedAt"))
				ownSrv.name = nameFor(ownEntry, ownJob)
			end
			local okPing, livePing = pcall(function()
				return player:GetNetworkPing() * 2000
			end)
			if okPing then
				ownSrv.ping = livePing
			end
			newServers[ownJob] = ownSrv

			if not changed then
				for jid, _ in pairs(servers) do
					if newServers[jid] == nil then
						changed = true
						break
					end
				end
			end

			servers = newServers
			if changed then
				local newLocated = {}
				local n = 0
				local sc = 0
				for _, srv in pairs(newServers) do
					sc = sc + 1
					local list = srv.players
					for i = 1, #list do
						local uid = list[i]
						if newLocated[uid] == nil then
							n = n + 1
						end
						newLocated[uid] = srv
					end
				end
				located = newLocated
				locatedCount = n
				serverCount = sc
				version = version + 1
			end
		end
	end

	-- servers per region + average ping
	local function regionSummary()
		local agg = {}
		local arr = {}
		local total = 0
		local pSum = 0
		local pN = 0
		for _, srv in pairs(servers) do
			local name = srv.rname
			local a = agg[name]
			if a == nil then
				a = { name = name, count = 0, pSum = 0, pN = 0 }
				agg[name] = a
				arr[#arr + 1] = a
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
		return arr, total, pSum, pN
	end

	---------------------------------------------------------------------
	-- DATA: names (loaded in the background, everything shows immediately)
	-- lowercase copies are stored once so searching does not allocate.
	---------------------------------------------------------------------
	local names = {}
	local namesCount = 0
	local setName = function(_id, _username, _display) end
	local resolveNames = function() return false end

	do
		local tried = {}
		local idleVersion = -1

		setName = function(id, username, display)
			if names[id] == nil then
				namesCount = namesCount + 1
			end
			local user = tostring(username or "")
			local disp = tostring(display or username or "")
			names[id] = { name = user, display = disp, nl = string.lower(user), dl = string.lower(disp) }
		end

		-- loads one batch of 100; returns true if more are waiting
		resolveNames = function()
			local own = Players:GetPlayers()
			for i = 1, #own do
				local p = own[i]
				if names[p.UserId] == nil then
					setName(p.UserId, p.Name, p.DisplayName)
				end
			end
			if not httpRequest then
				return false
			end
			if idleVersion == version then
				return false
			end

			local batch = {}
			local more = false
			for id, _ in pairs(located) do
				if names[id] == nil and not tried[id] then
					if #batch < 100 then
						batch[#batch + 1] = id
					else
						more = true
						break
					end
				end
			end
			if #batch == 0 then
				idleVersion = version
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
	local M = {}
	local setMetrics = function(_on) end
	do
		local NORMAL = {
			boxH = 34, boxText = 13, loadW = 64,
			trayH = 30, tabW = 84, tabH = 24, tabText = 12,
			pillW = 190, pillText = 12,
			pad = 12, gap = 10, tileMin = 150, chip = 20,
			titleText = 13, subText = 11, infoText = 11, countText = 13,
			joinW = 54, joinH = 26, joinText = 12,
			head = 58, smallH = 26, smallText = 11, smallW1 = 88, smallW2 = 92, smallW3 = 92,
			rowH = 44, rowMin = 196, avatar = 30, nameText = 13, userText = 11, idW = 32, idH = 22, idText = 10,
		}
		local TOUCH = {
			boxH = 44, boxText = 14, loadW = 76,
			trayH = 40, tabW = 96, tabH = 34, tabText = 13,
			pillW = 210, pillText = 13,
			pad = 14, gap = 12, tileMin = 170, chip = 26,
			titleText = 14, subText = 12, infoText = 12, countText = 14,
			joinW = 66, joinH = 36, joinText = 13,
			head = 68, smallH = 38, smallText = 12, smallW1 = 100, smallW2 = 108, smallW3 = 108,
			rowH = 56, rowMin = 220, avatar = 38, nameText = 14, userText = 12, idW = 44, idH = 34, idText = 11,
		}
		setMetrics = function(on)
			local src = NORMAL
			if on then
				src = TOUCH
			end
			for k, v in pairs(src) do
				M[k] = v
			end
		end
	end
	local touchNow = win.Touch
	setMetrics(touchNow)

	---------------------------------------------------------------------
	-- PAGE WIDGETS
	---------------------------------------------------------------------
	local mainPage = win.MainPage
	local render = function(_force) end
	local layoutFinder = function() end
	local stopAll = function() end

	-- search box: dark pill with a drawn magnifier
	local boxBack = new("Frame", {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = SIDEBAR_BG,
		BorderSizePixel = 0,
	}, mainPage)
	corner(boxBack, RADIUS + 2)
	local boxStroke = stroke(boxBack, BORDER, 1, 0)

	local ring = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 19, 0.5, -1),
		Size = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, boxBack)
	corner(ring, 100)
	stroke(ring, DIM_TEXT, 1.5, 0)
	local handle = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 25, 0.5, 5),
		Size = UDim2.fromOffset(5, 2),
		Rotation = 45,
		BackgroundColor3 = DIM_TEXT,
		BorderSizePixel = 0,
	}, boxBack)
	corner(handle, 1)

	local box = new("TextBox", {
		Position = UDim2.fromOffset(36, 0),
		Size = UDim2.new(1, -48, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextColor3 = TEXT_COLOR,
		PlaceholderText = "Search a player: display name, username or ID...",
		PlaceholderColor3 = DIM_TEXT,
		Text = "",
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClipsDescendants = true,
	}, boxBack)

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

	-- tabs: a tray with one highlight that slides between the two
	local tray = new("Frame", {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.fromOffset(176, 30),
		BackgroundColor3 = CLUSTER_BG,
		BorderSizePixel = 0,
	}, mainPage)
	corner(tray, RADIUS + 2)

	local slider = new("Frame", {
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.fromOffset(84, 24),
		BackgroundColor3 = HOVER_GREY,
		BorderSizePixel = 0,
	}, tray)
	corner(slider, 4)

	local function makeTab(text)
		return new("TextButton", {
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.fromOffset(84, 24),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = text,
			TextColor3 = ICON,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
		}, tray)
	end
	local tabServers = makeTab("Servers")
	local tabGroup = makeTab("Group")

	local status = label(mainPage, "", UDim2.fromOffset(200, 50), UDim2.new(1, -200, 0, 30),
		Enum.Font.Gotham, 11, DIM_TEXT, Enum.TextXAlignment.Right)

	-- region pill (Servers tab only) + its dropdown
	local regionBtn = new("TextButton", {
		Position = UDim2.fromOffset(184, 50),
		Size = UDim2.fromOffset(190, 30),
		BackgroundColor3 = CLUSTER_BG,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, mainPage)
	corner(regionBtn, RADIUS + 2)
	local regionTitle = label(regionBtn, "Region", UDim2.fromOffset(12, 0), UDim2.new(0, 48, 1, 0),
		Enum.Font.Gotham, 12, DIM_TEXT)
	local regionValue = label(regionBtn, "All regions", UDim2.fromOffset(60, 0), UDim2.new(1, -84, 1, 0),
		Enum.Font.GothamMedium, 12, TEXT_COLOR)

	-- drawn arrow (no chip): points down, turns up while the list is open
	local regionChev = makeChevron(regionBtn, false, true)
	regionChev.setSize(16)
	regionChev.chip.Position = UDim2.new(1, -18, 0.5, 0)
	regionChev.holder.Rotation = 90
	for i = 1, #regionChev.inks do
		regionChev.inks[i].BackgroundColor3 = DIM_TEXT
	end

	local regionMenu = new("CanvasGroup", {
		Name = "RegionMenu",
		Position = UDim2.fromOffset(184, 86),
		Size = UDim2.fromOffset(300, 200),
		BackgroundColor3 = POPUP_BG,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 31,
	}, mainPage)
	corner(regionMenu, RADIUS + 4)
	stroke(regionMenu, BORDER, 1, 0)

	-- the server grid (virtual: only what is on screen exists)
	local list = new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 90),
		Size = UDim2.new(1, 0, 1, -90),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = ICON,
		ScrollBarImageTransparency = 0.5,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ElasticBehavior = Enum.ElasticBehavior.Never,
	}, mainPage)

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

	---------------------------------------------------------------------
	-- LOADING SCREEN (covers the page until enough names are loaded)
	---------------------------------------------------------------------
	do
		local LOAD_SLACK = opts.LoadSlack or 150
		local LOAD_TIMEOUT = opts.LoadTimeout or 60

		local overlay = new("CanvasGroup", {
			Name = "LoadingOverlay",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = BLACK,
			BorderSizePixel = 0,
			Active = true,
			GroupTransparency = 0,
			ZIndex = 50,
		}, mainPage)

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
				overlay:Destroy()
			end)
		end)
	end

	---------------------------------------------------------------------
	-- LOGIC
	---------------------------------------------------------------------
	do
		local opt = nil       -- options module instance
		local profile = nil   -- profile module instance
		local group = nil     -- { id, name, members = {userId = roleName}, checked, status, rev }
		local groupToken = 0
		local tab = "servers"
		local regionFilter = nil
		local regionVersion = -1
		local expanded = {}   -- jobId -> true/false when you toggled it by hand
		local savedText = { servers = "", group = "" }
		local styleRev = 0    -- bumps when sizes change (touch mode, resize)
		local contentRev = 0  -- bumps whenever the data on screen has to be redrawn
		local lastSig = ""
		local lastMatchCount = 0
		local searchToken = 0

		-- geometry
		local entries = {}
		local cols = 1
		local tileS = 150
		local contentW = 676
		local pcols = 1
		local colW = 600
		local geoKey = ""

		-- animation state per server: frac 0 = closed .. 1 = open, hov 0..1 = hover amount
		local frac = {}
		local goal = {}
		local hov = {}
		local hgoal = {}
		local animating = {}
		local animConn = nil

		local EMPTY = {}
		local scaleObj = win.Window:FindFirstChildOfClass("UIScale")

		local layout = function() end
		local placeNow = function() end
		local toggleOpen = function(_jid) end
		local updateRegions = function() end
		local closeRegionMenu = function() end

		-- the window can be scaled; sizes we place are in unscaled units
		local function unit()
			local s = 1
			if scaleObj then
				s = scaleObj.Scale
			end
			if s < 0.05 then
				s = 1
			end
			return s
		end

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
			if srv.count >= srv.max then
				toast("This server is full")
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

		local function openProfile(uid)
			local n = names[uid]
			if profile then
				if n then
					profile:Open(uid, { name = n.name, display = n.display })
				else
					profile:Open(uid)
				end
			elseif n then
				copyText(n.name, "Copied username: " .. n.name)
			else
				toast("Name still loading, try again in a moment")
			end
		end

		-- players of one server in display order: search matches, friends, then A-Z
		local function sortedPlayers(e)
			local source = e.ids or e.srv.players
			local out = {}
			for i = 1, #source do
				out[i] = source[i]
			end
			local ms = e.matchSet
			local o = opt
			table.sort(out, function(a, b)
				local ma = (ms[a] == true)
				local mb = (ms[b] == true)
				if ma ~= mb then
					return ma
				end
				if o then
					local fa = o:IsFriend(a)
					local fb = o:IsFriend(b)
					if fa ~= fb then
						return fa
					end
				end
				local na = names[a]
				local nb = names[b]
				if (na ~= nil) ~= (nb ~= nil) then
					return na ~= nil
				end
				if na and nb and na.dl ~= nb.dl then
					return na.dl < nb.dl
				end
				return a < b
			end)
			return out
		end

		-- the 5 heads shown on a tile: matches first, then friends, then list order
		local function pickPreview(e, out)
			local src = e.ids or e.srv.players
			local total = #src
			local n = 0
			local ms = e.matchSet
			if e.matches > 0 then
				for i = 1, total do
					if n >= 5 then
						break
					end
					local id = src[i]
					if ms[id] == true then
						n = n + 1
						out[n] = id
					end
				end
			end
			if n < 5 and opt and opt.friendStatus == "ready" then
				for i = 1, total do
					if n >= 5 then
						break
					end
					local id = src[i]
					if opt:IsFriend(id) then
						local dup = false
						for k = 1, n do
							if out[k] == id then
								dup = true
							end
						end
						if not dup then
							n = n + 1
							out[n] = id
						end
					end
				end
			end
			for i = 1, total do
				if n >= 5 then
					break
				end
				local id = src[i]
				local dup = false
				for k = 1, n do
					if out[k] == id then
						dup = true
					end
				end
				if not dup then
					n = n + 1
					out[n] = id
				end
			end
			return n
		end

		-------------------------------------------------------------
		-- Animation: one Heartbeat connection that only exists while something moves.
		-- Drawer height and the arrow follow frac, tile hover follows hov.
		-------------------------------------------------------------
		local function stepAnim(dt)
			if not running then
				if animConn then
					animConn:Disconnect()
					animConn = nil
				end
				return
			end
			local k = 1 - math.exp(-dt * 15)
			local kh = 1 - math.exp(-dt * 22)
			local moved = false
			for jid, _ in pairs(animating) do
				local f = frac[jid] or 0
				local g = goal[jid] or 0
				if f ~= g then
					f = f + (g - f) * k
					if math.abs(g - f) < 0.003 then
						f = g
					end
					frac[jid] = f
					moved = true
				end
				local h = hov[jid] or 0
				local hg = hgoal[jid] or 0
				if h ~= hg then
					h = h + (hg - h) * kh
					if math.abs(hg - h) < 0.03 then
						h = hg
					end
					hov[jid] = h
				end
				if f == g and h == hg then
					animating[jid] = nil
				end
			end
			if moved then
				layout()
			else
				placeNow()
			end
			if next(animating) == nil and animConn then
				animConn:Disconnect()
				animConn = nil
			end
		end

		local function startAnim(jid)
			animating[jid] = true
			if animConn == nil then
				animConn = RunService.Heartbeat:Connect(stepAnim)
			end
		end

		toggleOpen = function(jid)
			local isOpen = (goal[jid] or 0) > 0.5
			local nextOpen = not isOpen
			expanded[jid] = nextOpen
			if nextOpen then
				goal[jid] = 1
			else
				goal[jid] = 0
			end
			if frac[jid] == nil then
				frac[jid] = 0
			end
			startAnim(jid)
		end

		-------------------------------------------------------------
		-- VIEW: tiles, drawers and player rows (all pooled)
		-------------------------------------------------------------
		do
			local MAXR = MAX_PLAYER_ROWS
			local ROW_GAP_X = 6

			-- tile look: closed -> hover -> open
			local OVER_STROKE = Color3.fromRGB(58, 58, 65)
			local OPEN_COL = Color3.fromRGB(104, 104, 114)   -- outline of an open tile, the stem and the drawer
			local HOVER_BG = Color3.fromRGB(21, 21, 24)
			local OPEN_BG = Color3.fromRGB(27, 27, 31)

			local tileOf = {}
			local tilePool = {}
			local drawerOf = {}
			local drawerPool = {}
			local rowPool = {}
			local stamp = 0
			local totalH = 0

			---------------- tile ----------------
			-- f = how open, h = hover. Everything that shows "this one is open" is drawn from f.
			local function paintTile(c)
				local f = c.f
				local h = c.h
				local base = BORDER:Lerp(OVER_STROKE, h)
				c.stroke.Color = base:Lerp(OPEN_COL, f)
				c.frame.BackgroundColor3 = SIDEBAR_BG:Lerp(HOVER_BG, h):Lerp(OPEN_BG, f)
				c.chev.paint(f, h)
				c.chev.holder.Rotation = c.rot
			end

			-- every inner position follows the tile size, so one tile design fits any window width
			local function styleTile(c)
				c.styleRev = styleRev
				local S = tileS
				local P = M.pad
				local chipS = M.chip
				local ty = P
				local chipCy = ty + math.floor((M.titleText + 4) / 2)
				local sy = math.max(ty + M.titleText + 5, chipCy + math.floor(chipS / 2) + 3)
				local ay = sy + M.subText + 10
				local av = math.floor(S * 0.2)
				local step = math.floor((S - 2 * P - av) / 4)
				local iy = ay + av + 7
				local by = S - P - M.joinH

				c.frame.Size = UDim2.fromOffset(S, S)
				c.title.Position = UDim2.fromOffset(P, ty)
				c.title.Size = UDim2.fromOffset(S - 2 * P - chipS - 6, M.titleText + 4)
				c.title.TextSize = M.titleText
				c.sub.Position = UDim2.fromOffset(P, sy)
				c.sub.Size = UDim2.fromOffset(S - 2 * P, M.subText + 4)
				c.sub.TextSize = M.subText
				c.chev.setSize(chipS)
				c.chev.chip.Position = UDim2.fromOffset(S - P - math.floor(chipS / 2), chipCy)
				for i = 1, 5 do
					local img = c.avs[i]
					img.Position = UDim2.fromOffset(P + (i - 1) * step, ay)
					img.Size = UDim2.fromOffset(av, av)
				end
				c.info.Position = UDim2.fromOffset(P, iy)
				c.info.Size = UDim2.fromOffset(S - 2 * P, M.infoText + 4)
				c.info.TextSize = M.infoText

				local leftW = S - 2 * P - M.joinW - 8
				local blockTop = by + math.floor((M.joinH - 23) / 2)
				c.count.Position = UDim2.fromOffset(P, blockTop)
				c.count.Size = UDim2.fromOffset(leftW, 16)
				c.count.TextSize = M.countText
				c.barBg.Position = UDim2.fromOffset(P, blockTop + 20)
				c.barBg.Size = UDim2.fromOffset(leftW, 3)
				c.barW = leftW
				c.join.Position = UDim2.fromOffset(S - P - M.joinW, by)
				c.join.Size = UDim2.fromOffset(M.joinW, M.joinH)
				c.join.TextSize = M.joinText
			end

			local function makeTile()
				local c = {
					uids = {}, avs = {}, preview = {},
					styleRev = -1, boundRev = -1, stamp = 0,
					f = 0, h = 0, rot = 0, pkey = nil, joinMode = "",
				}
				local f = new("TextButton", {
					Size = UDim2.fromOffset(150, 150),
					BackgroundColor3 = SIDEBAR_BG,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Text = "",
				}, nil)
				corner(f, RADIUS + 4)
				c.frame = f
				c.stroke = stroke(f, BORDER, 1, 0)

				c.title = label(f, "", UDim2.fromOffset(12, 12), UDim2.fromOffset(100, 17),
					Enum.Font.GothamMedium, 13, TEXT_COLOR)
				c.sub = label(f, "", UDim2.fromOffset(12, 30), UDim2.fromOffset(100, 15),
					Enum.Font.Gotham, 11, DIM_TEXT)

				-- the drawn arrow chip (top right)
				c.chev = makeChevron(f, false, false)

				-- five heads, each one overlaps the one before it and cuts a thin ring into it
				for i = 1, 5 do
					local img = new("ImageLabel", {
						BackgroundColor3 = CLUSTER_BG,
						BorderSizePixel = 0,
						Image = "",
						Visible = false,
					}, f)
					corner(img, 8)
					stroke(img, SIDEBAR_BG, 2, 0)
					c.avs[i] = img
				end

				c.info = label(f, "", UDim2.fromOffset(12, 90), UDim2.fromOffset(100, 15),
					Enum.Font.Gotham, 11, DIM_TEXT)
				c.count = label(f, "", UDim2.fromOffset(12, 112), UDim2.fromOffset(60, 16),
					Enum.Font.GothamMedium, 13, TEXT_COLOR)
				c.barBg = new("Frame", {
					BackgroundColor3 = CLUSTER_BG,
					BorderSizePixel = 0,
				}, f)
				corner(c.barBg, 2)
				c.barFill = new("Frame", {
					Size = UDim2.new(0, 0, 1, 0),
					BackgroundColor3 = ICON,
					BorderSizePixel = 0,
				}, c.barBg)
				corner(c.barFill, 2)

				c.join = new("TextButton", {
					BackgroundColor3 = JOIN_BG,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Text = "Join",
					TextColor3 = BLACK,
					Font = Enum.Font.GothamMedium,
					TextSize = 12,
				}, f)
				corner(c.join, RADIUS)

				f.MouseEnter:Connect(function()
					if c.srv then
						hgoal[c.srv.jobId] = 1
						startAnim(c.srv.jobId)
					end
				end)
				f.MouseLeave:Connect(function()
					if c.srv then
						hgoal[c.srv.jobId] = 0
						startAnim(c.srv.jobId)
					end
				end)
				f.Activated:Connect(function()
					if c.srv then
						toggleOpen(c.srv.jobId)
					end
				end)
				c.join.MouseEnter:Connect(function()
					if c.joinMode == "join" then
						TweenService:Create(c.join, FAST, { BackgroundColor3 = WHITE }):Play()
					end
				end)
				c.join.MouseLeave:Connect(function()
					if c.joinMode == "join" then
						TweenService:Create(c.join, FAST, { BackgroundColor3 = JOIN_BG }):Play()
					end
				end)
				c.join.Activated:Connect(function()
					if c.srv then
						joinServer(c.srv)
					end
				end)
				return c
			end

			local function takeTile()
				local c = tilePool[#tilePool]
				if c then
					tilePool[#tilePool] = nil
				else
					c = makeTile()
				end
				c.f = 0
				c.h = 0
				c.rot = 0
				c.pkey = nil
				c.joinMode = ""
				c.px = nil
				c.py = nil
				c.frame.Parent = list
				return c
			end

			local function releaseTile(c)
				c.frame.Parent = nil
				c.entry = nil
				c.srv = nil
				tilePool[#tilePool + 1] = c
			end

			local function bindTile(c, e)
				local srv = e.srv
				c.srv = srv
				c.boundRev = contentRev
				if c.styleRev ~= styleRev then
					styleTile(c)
				end
				local mine = (srv.jobId == game.JobId)

				c.title.Text = srv.name
				if mine then
					c.title.TextColor3 = GREEN
				else
					c.title.TextColor3 = TEXT_COLOR
				end
				local sub = srv.rname
				if srv.ping then
					sub = sub .. "  -  " .. math.floor(srv.ping + 0.5) .. " ms"
				end
				c.sub.Text = sub

				local pv = c.preview
				local n = pickPreview(e, pv)
				for i = 1, 5 do
					local img = c.avs[i]
					if i <= n then
						local uid = pv[i]
						if c.uids[i] ~= uid then
							c.uids[i] = uid
							img.Image = thumbUrl(uid)
						end
						img.Visible = true
					else
						c.uids[i] = nil
						img.Visible = false
					end
				end

				local total = e.cnt
				local info = ""
				local infoColor = DIM_TEXT
				if tab == "servers" and e.matches > 0 then
					info = e.matches .. " found"
					infoColor = GREEN
				elseif total == 0 then
					info = "Empty"
				elseif tab == "group" then
					info = total .. " in group"
				elseif total > n then
					info = "+" .. (total - n) .. " more"
				end
				c.info.Text = info
				c.info.TextColor3 = infoColor

				local full = (srv.count >= srv.max)
				c.count.Text = srv.count .. "/" .. srv.max
				if full then
					c.count.TextColor3 = DIM_TEXT
				else
					c.count.TextColor3 = TEXT_COLOR
				end
				local ratio = srv.count / math.max(1, srv.max)
				if ratio > 1 then
					ratio = 1
				end
				c.barFill.Size = UDim2.new(0, math.floor(c.barW * ratio + 0.5), 1, 0)
				if mine then
					c.barFill.BackgroundColor3 = GREEN
				elseif full then
					c.barFill.BackgroundColor3 = DIM_TEXT
				else
					c.barFill.BackgroundColor3 = ICON
				end

				local mode = "join"
				if mine then
					mode = "here"
				elseif full then
					mode = "full"
				end
				if c.joinMode ~= mode then
					c.joinMode = mode
					if mode == "join" then
						c.join.Text = "Join"
						c.join.BackgroundColor3 = JOIN_BG
						c.join.TextColor3 = BLACK
					elseif mode == "here" then
						c.join.Text = "Here"
						c.join.BackgroundColor3 = CLUSTER_BG
						c.join.TextColor3 = DIM_TEXT
					else
						c.join.Text = "Full"
						c.join.BackgroundColor3 = CLUSTER_BG
						c.join.TextColor3 = DIM_TEXT
					end
				end
			end

			---------------- player row (inside a drawer) ----------------
			local function styleRow(r)
				r.styleRev = styleRev
				local h = M.rowH
				local pic = M.avatar
				r.frame.Size = UDim2.fromOffset(colW, h)
				r.pic.Position = UDim2.fromOffset(8, math.floor((h - pic) / 2))
				r.pic.Size = UDim2.fromOffset(pic, pic)
				local tx = 8 + pic + 10
				local right = M.idW + 12
				local block = M.nameText + M.userText + 5
				local top = math.floor((h - block) / 2)
				r.display.Position = UDim2.fromOffset(tx, top)
				r.display.Size = UDim2.fromOffset(colW - tx - right, M.nameText + 3)
				r.display.TextSize = M.nameText
				r.user.Position = UDim2.fromOffset(tx, top + M.nameText + 3)
				r.user.Size = UDim2.fromOffset(colW - tx - right, M.userText + 3)
				r.user.TextSize = M.userText
				r.idBtn.Position = UDim2.fromOffset(colW - M.idW - 6, math.floor((h - M.idH) / 2))
				r.idBtn.Size = UDim2.fromOffset(M.idW, M.idH)
				r.idBtn.TextSize = M.idText
			end

			local function makeRow()
				local r = { styleRev = -1, boundRev = -1, baseT = 1, over = false }
				local f = new("TextButton", {
					Size = UDim2.fromOffset(200, 44),
					BackgroundColor3 = HOVER_GREY,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Text = "",
				}, nil)
				corner(f, RADIUS + 2)
				r.frame = f
				r.pic = new("ImageLabel", {
					BackgroundColor3 = CLUSTER_BG,
					BorderSizePixel = 0,
					Image = "",
				}, f)
				corner(r.pic, 8)
				r.display = label(f, "", UDim2.fromOffset(48, 6), UDim2.fromOffset(100, 16),
					Enum.Font.GothamMedium, 13, TEXT_COLOR)
				r.user = label(f, "", UDim2.fromOffset(48, 23), UDim2.fromOffset(100, 14),
					Enum.Font.Gotham, 11, DIM_TEXT)
				r.idBtn = new("TextButton", {
					BackgroundColor3 = HOVER_GREY,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Text = "ID",
					TextColor3 = DIM_TEXT,
					Font = Enum.Font.GothamMedium,
					TextSize = 10,
				}, f)
				corner(r.idBtn, RADIUS)

				f.MouseEnter:Connect(function()
					r.over = true
					if r.baseT >= 1 then
						TweenService:Create(f, FAST, { BackgroundTransparency = 0.6 }):Play()
					end
				end)
				f.MouseLeave:Connect(function()
					r.over = false
					TweenService:Create(f, FAST, { BackgroundTransparency = r.baseT }):Play()
				end)
				r.idBtn.MouseEnter:Connect(function()
					TweenService:Create(r.idBtn, FAST, { BackgroundTransparency = 0.4, TextColor3 = ICON_HOVER }):Play()
				end)
				r.idBtn.MouseLeave:Connect(function()
					TweenService:Create(r.idBtn, FAST, { BackgroundTransparency = 1, TextColor3 = DIM_TEXT }):Play()
				end)
				f.Activated:Connect(function()
					if r.uid then
						openProfile(r.uid)
					end
				end)
				r.idBtn.Activated:Connect(function()
					if r.uid then
						copyText(tostring(r.uid), "Copied user ID")
					end
				end)
				return r
			end

			local function takeRow()
				local r = rowPool[#rowPool]
				if r then
					rowPool[#rowPool] = nil
				else
					r = makeRow()
				end
				r.over = false
				return r
			end

			local function releaseRow(r)
				r.frame.Parent = nil
				r.holder = nil
				r.uid = nil
				rowPool[#rowPool + 1] = r
			end

			local function bindRow(r, uid, e)
				r.uid = uid
				r.boundRev = contentRev
				if r.styleRev ~= styleRev then
					styleRow(r)
				end
				local role = nil
				if tab == "group" and group then
					role = group.members[uid]
				end
				local n = names[uid]
				if n then
					r.display.Text = n.display
					local u = "@" .. n.name
					if role then
						u = u .. "  -  " .. role
					end
					r.user.Text = u
				else
					r.display.Text = "Loading..."
					local u = "ID " .. tostring(uid)
					if role then
						u = u .. "  -  " .. role
					end
					r.user.Text = u
				end
				if r.picUid ~= uid then
					r.picUid = uid
					r.pic.Image = thumbUrl(uid)
				end
				if tab == "servers" and e.matchSet[uid] == true then
					r.baseT = 0
					r.frame.BackgroundColor3 = MATCH_BG
					r.display.TextColor3 = GREEN
				else
					r.baseT = 1
					r.frame.BackgroundColor3 = HOVER_GREY
					r.display.TextColor3 = TEXT_COLOR
				end
				r.frame.BackgroundTransparency = r.baseT
			end

			---------------- drawer (all players of one server) ----------------
			local function styleDrawer(d)
				d.styleRev = styleRev
				local W = contentW
				local w1 = M.smallW1
				local w2 = M.smallW2
				local w3 = M.smallW3
				local total = w1 + w2 + w3 + 12
				local bx = W - 14 - total
				local by = math.floor((M.head - M.smallH) / 2)
				d.btns[1].Position = UDim2.fromOffset(bx, by)
				d.btns[1].Size = UDim2.fromOffset(w1, M.smallH)
				d.btns[2].Position = UDim2.fromOffset(bx + w1 + 6, by)
				d.btns[2].Size = UDim2.fromOffset(w2, M.smallH)
				d.btns[3].Position = UDim2.fromOffset(bx + w1 + w2 + 12, by)
				d.btns[3].Size = UDim2.fromOffset(w3, M.smallH)
				for i = 1, 3 do
					d.btns[i].TextSize = M.smallText
				end

				-- close chip on the left, the title sits right of it
				local cs = M.chip
				d.chev.setSize(cs)
				d.chev.chip.Position = UDim2.fromOffset(14 + math.floor(cs / 2), math.floor(M.head / 2))
				local tx = 14 + cs + 10

				local titleH = M.titleText + 5
				local subH = M.subText + 4
				local top = math.floor((M.head - (titleH + 2 + subH)) / 2)
				local textW = math.max(60, bx - tx - 14)
				d.title.Position = UDim2.fromOffset(tx, top)
				d.title.Size = UDim2.fromOffset(textW, titleH)
				d.title.TextSize = M.titleText + 1
				d.sub.Position = UDim2.fromOffset(tx, top + titleH + 2)
				d.sub.Size = UDim2.fromOffset(textW, subH)
				d.sub.TextSize = M.subText
				d.line.Position = UDim2.fromOffset(12, M.head)
				d.line.Size = UDim2.fromOffset(W - 24, 1)
				d.more.Size = UDim2.fromOffset(W - 28, 18)
			end

			local function makeDrawer()
				local d = { rows = {}, btns = {}, styleRev = -1, boundRev = -1, stamp = 0 }
				local f = new("Frame", {
					Size = UDim2.fromOffset(676, 0),
					BackgroundColor3 = SIDEBAR_BG,
					BorderSizePixel = 0,
					ClipsDescendants = true,
				}, nil)
				corner(f, RADIUS + 4)
				stroke(f, OPEN_COL, 1, 0)
				d.frame = f

				-- the thin stem that links the drawer to the tile that owns it (lives in the list, not inside the drawer)
				d.stem = new("Frame", {
					Size = UDim2.fromOffset(2, 8),
					BackgroundColor3 = OPEN_COL,
					BorderSizePixel = 0,
				}, nil)
				corner(d.stem, 1)

				-- white "open" chip pointing up: click it to close this server
				d.chev = makeChevron(f, true, false)
				d.chev.holder.Rotation = -90
				d.chev.paint(1, 0)
				d.chev.chip.MouseEnter:Connect(function()
					d.chev.paint(1, 1)
				end)
				d.chev.chip.MouseLeave:Connect(function()
					d.chev.paint(1, 0)
				end)
				d.chev.chip.Activated:Connect(function()
					if d.srv then
						toggleOpen(d.srv.jobId)
					end
				end)

				d.title = label(f, "", UDim2.fromOffset(44, 10), UDim2.fromOffset(300, 18),
					Enum.Font.GothamMedium, 14, TEXT_COLOR)
				d.sub = label(f, "", UDim2.fromOffset(44, 31), UDim2.fromOffset(300, 15),
					Enum.Font.Gotham, 11, DIM_TEXT)
				d.line = new("Frame", {
					BackgroundColor3 = BORDER,
					BorderSizePixel = 0,
				}, f)
				d.more = label(f, "", UDim2.fromOffset(14, 80), UDim2.fromOffset(600, 18),
					Enum.Font.Gotham, 12, DIM_TEXT)
				d.more.Visible = false

				local texts = { "Copy Link", "Copy Job ID", "Copy Script" }
				for i = 1, 3 do
					local b = new("TextButton", {
						BackgroundColor3 = CLUSTER_BG,
						BorderSizePixel = 0,
						AutoButtonColor = false,
						Text = texts[i],
						TextColor3 = ICON,
						Font = Enum.Font.GothamMedium,
						TextSize = 11,
					}, f)
					corner(b, RADIUS)
					hoverable(b, CLUSTER_BG, HOVER_GREY, ICON, ICON_HOVER)
					d.btns[i] = b
				end
				d.btns[1].Activated:Connect(function()
					if d.srv then
						copyText(joinLink(d.srv), "Join link copied")
					end
				end)
				d.btns[2].Activated:Connect(function()
					if d.srv then
						copyText(d.srv.jobId, "Job ID copied")
					end
				end)
				d.btns[3].Activated:Connect(function()
					if d.srv then
						copyText(joinScript(d.srv), "Join script copied")
					end
				end)
				return d
			end

			local function takeDrawer()
				local d = drawerPool[#drawerPool]
				if d then
					drawerPool[#drawerPool] = nil
				else
					d = makeDrawer()
				end
				d.frame.Parent = list
				d.stem.Parent = list
				return d
			end

			local function releaseDrawer(d)
				for k, r in pairs(d.rows) do
					d.rows[k] = nil
					releaseRow(r)
				end
				d.frame.Parent = nil
				d.stem.Parent = nil
				d.entry = nil
				d.srv = nil
				d.sorted = nil
				drawerPool[#drawerPool + 1] = d
			end

			local function bindDrawer(d, e)
				local srv = e.srv
				d.srv = srv
				d.boundRev = contentRev
				if d.styleRev ~= styleRev then
					styleDrawer(d)
				end
				d.title.Text = srv.name
				local parts = { srv.rname }
				if srv.ping then
					parts[#parts + 1] = math.floor(srv.ping + 0.5) .. " ms"
				end
				local up = formatUptime(srv.startedAt)
				if up ~= "Unknown" then
					parts[#parts + 1] = "up " .. up
				end
				parts[#parts + 1] = srv.count .. "/" .. srv.max .. " players"
				d.sub.Text = table.concat(parts, "  -  ")
				d.sorted = sortedPlayers(e)

				local cnt = e.cnt
				if cnt == 0 then
					d.more.Text = "Nobody in this server"
					d.more.Position = UDim2.fromOffset(14, M.head + 12)
					d.more.Visible = true
				elseif cnt > MAXR then
					d.more.Text = "+" .. (cnt - MAXR) .. " more players not shown"
					local rowsN = math.ceil(MAXR / pcols)
					d.more.Position = UDim2.fromOffset(14, M.head + 10 + rowsN * (M.rowH + 4) + 2)
					d.more.Visible = true
				else
					d.more.Visible = false
				end
			end

			-- only the rows inside the viewport are real
			local function fillRows(d, e, top, bottom)
				local sorted = d.sorted
				if sorted == nil then
					return
				end
				local cnt = #sorted
				if cnt > MAXR then
					cnt = MAXR
				end
				local rstep = M.rowH + 4
				local base = e.dy + M.head + 10
				local r0 = math.floor((top - base) / rstep)
				local r1 = math.floor((bottom - base) / rstep)
				if r0 < 0 then
					r0 = 0
				end
				local maxR = math.ceil(cnt / pcols) - 1
				if r1 > maxR then
					r1 = maxR
				end
				local k0 = r0 * pcols + 1
				local k1 = (r1 + 1) * pcols
				if k1 > cnt then
					k1 = cnt
				end
				for k, r in pairs(d.rows) do
					if k < k0 or k > k1 then
						d.rows[k] = nil
						releaseRow(r)
					end
				end
				for k = k0, k1 do
					local uid = sorted[k]
					local r = d.rows[k]
					if r == nil then
						r = takeRow()
						d.rows[k] = r
						r.boundRev = -1
					end
					if r.boundRev ~= contentRev or r.styleRev ~= styleRev or r.uid ~= uid then
						bindRow(r, uid, e)
					end
					local rr = math.floor((k - 1) / pcols)
					local cc = (k - 1) % pcols
					r.frame.Position = UDim2.fromOffset(12 + cc * (colW + ROW_GAP_X), M.head + 10 + rr * rstep)
					if r.holder ~= d then
						r.holder = d
						r.frame.Parent = d.frame
					end
				end
			end

			---------------- geometry + placement ----------------
			local function measure()
				local u = unit()
				local W = math.floor(list.AbsoluteSize.X / u) - 8
				if W < 220 then
					W = 676
				end
				local gap = M.gap
				local c = math.floor((W + gap) / (M.tileMin + gap))
				if c < 1 then
					c = 1
				end
				local S = math.floor((W - (c - 1) * gap) / c)
				local avail = W - 24
				local pc = math.floor((avail + ROW_GAP_X) / (M.rowMin + ROW_GAP_X))
				if pc < 1 then
					pc = 1
				end
				local cw = math.floor((avail - (pc - 1) * ROW_GAP_X) / pc)
				local key = S .. ":" .. cw .. ":" .. M.rowH .. ":" .. W
				if key ~= geoKey then
					geoKey = key
					styleRev = styleRev + 1
				end
				cols = c
				tileS = S
				contentW = W
				pcols = pc
				colW = cw
			end

			-- tiles go in a grid; a drawer opens under the row of the tile that owns it
			local function geometry()
				local S = tileS
				local gap = M.gap
				local y = 0
				local n = #entries
				local i = 1
				while i <= n do
					local last = i + cols - 1
					if last > n then
						last = n
					end
					for k = i, last do
						local e = entries[k]
						e.x = (k - i) * (S + gap)
						e.y = y
					end
					y = y + S + gap
					local lastBottom = y - gap    -- the stem starts at the bottom of the tile row
					for k = i, last do
						local e = entries[k]
						local cnt = e.cnt
						if cnt > MAXR then
							cnt = MAXR
						end
						local body = 28
						if cnt > 0 then
							body = math.ceil(cnt / pcols) * (M.rowH + 4)
						end
						local extra = 0
						if e.cnt > MAXR then
							extra = 22
						end
						e.dfull = M.head + 10 + body + extra + 8
						local f = frac[e.srv.jobId] or 0
						e.dy = y
						e.stemTop = lastBottom
						if f > 0.001 then
							local dh = math.floor(e.dfull * f + 0.5)
							e.dh = dh
							if dh > 0 then
								lastBottom = y + dh
								y = y + dh + 8
							end
						else
							e.dh = 0
						end
					end
					i = last + 1
				end
				totalH = y
				list.CanvasSize = UDim2.fromOffset(0, totalH)
			end

			local function place()
				if not running then
					return
				end
				local u = unit()
				local pos = list.CanvasPosition.Y
				local vh = list.AbsoluteWindowSize.Y / u
				if vh < 50 then
					vh = 400
				end
				local top = pos - tileS
				local bottom = pos + vh + tileS
				stamp = stamp + 1
				local S = tileS

				for i = 1, #entries do
					local e = entries[i]
					local jid = e.srv.jobId

					if e.y + S >= top and e.y <= bottom then
						local c = tileOf[jid]
						if c == nil then
							c = takeTile()
							tileOf[jid] = c
							c.boundRev = -1
						end
						c.stamp = stamp
						c.entry = e
						if c.boundRev ~= contentRev or c.styleRev ~= styleRev or c.srv ~= e.srv then
							bindTile(c, e)
						end
						if c.px ~= e.x or c.py ~= e.y then
							c.px = e.x
							c.py = e.y
							c.frame.Position = UDim2.fromOffset(e.x, e.y)
						end
						-- arrow turn, chip fill, outline and background all come from these two numbers
						local f = frac[jid] or 0
						local h = hov[jid] or 0
						local rot = math.floor(f * 90 + 0.5)
						local pk = rot * 32 + math.floor(h * 20 + 0.5)
						if c.pkey ~= pk then
							c.pkey = pk
							c.f = f
							c.h = h
							c.rot = rot
							paintTile(c)
						end
					end

					if e.dh > 0 and e.dy + e.dh >= top and e.dy <= bottom then
						local d = drawerOf[jid]
						if d == nil then
							d = takeDrawer()
							drawerOf[jid] = d
							d.boundRev = -1
						end
						d.stamp = stamp
						d.entry = e
						if d.boundRev ~= contentRev or d.styleRev ~= styleRev or d.srv ~= e.srv then
							bindDrawer(d, e)
						end
						d.frame.Position = UDim2.fromOffset(0, e.dy)
						d.frame.Size = UDim2.fromOffset(contentW, e.dh)

						-- stem from the tile (or the drawer above) down to this drawer, in the tile's column
						local sh = e.dy - e.stemTop
						if sh > 0 then
							d.stem.Visible = true
							d.stem.Position = UDim2.fromOffset(e.x + math.floor(S / 2) - 1, e.stemTop)
							d.stem.Size = UDim2.fromOffset(2, sh)
							d.stem.BackgroundTransparency = 1 - (frac[jid] or 0)
						else
							d.stem.Visible = false
						end

						fillRows(d, e, top, bottom)
					end
				end

				for jid, c in pairs(tileOf) do
					if c.stamp ~= stamp then
						tileOf[jid] = nil
						hov[jid] = nil
						hgoal[jid] = nil
						releaseTile(c)
					end
				end
				for jid, d in pairs(drawerOf) do
					if d.stamp ~= stamp then
						drawerOf[jid] = nil
						releaseDrawer(d)
					end
				end
			end

			layout = function()
				measure()
				geometry()
				place()
			end
			placeNow = place

			list:GetPropertyChangedSignal("CanvasPosition"):Connect(place)
			list:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				layout()
			end)
		end

		-------------------------------------------------------------
		-- Region picker (pill + dropdown)
		-------------------------------------------------------------
		do
			local ALL_KEY = "*"
			local regionOpen = false
			local regionOver = false
			local regionRows = {}
			local allRow = nil
			local regionToken = 0

			local function statsText(count, ps, pn)
				local s = count .. " servers"
				if pn > 0 then
					s = s .. "  |  " .. math.floor(ps / pn + 0.5) .. " ms"
				end
				return s
			end

			local function paintRegionBtn()
				local bg = CLUSTER_BG
				local ink = DIM_TEXT
				if regionOver or regionOpen then
					bg = HOVER_GREY
					ink = ICON_HOVER
				end
				TweenService:Create(regionBtn, FAST, { BackgroundColor3 = bg }):Play()
				for i = 1, #regionChev.inks do
					TweenService:Create(regionChev.inks[i], FAST, { BackgroundColor3 = ink }):Play()
				end
			end
			regionBtn.MouseEnter:Connect(function()
				regionOver = true
				paintRegionBtn()
			end)
			regionBtn.MouseLeave:Connect(function()
				regionOver = false
				paintRegionBtn()
			end)

			local regionCatcher = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Visible = false,
				ZIndex = 30,
			}, mainPage)

			local menuScroll = new("ScrollingFrame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 2,
				ScrollBarImageColor3 = ICON,
				ScrollBarImageTransparency = 0.5,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				CanvasSize = UDim2.new(0, 0, 0, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
			}, regionMenu)
			pad(menuScroll, 8, 8, 8, 8)
			new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, menuScroll)

			closeRegionMenu = function()
				if not regionOpen then
					return
				end
				regionOpen = false
				regionToken = regionToken + 1
				local token = regionToken
				regionCatcher.Visible = false
				TweenService:Create(regionMenu, FAST, { GroupTransparency = 1 }):Play()
				TweenService:Create(regionChev.holder, FAST, { Rotation = 90 }):Play()
				task.delay(FAST.Time + 0.02, function()
					if token == regionToken then
						regionMenu.Visible = false
					end
				end)
				paintRegionBtn()
			end

			local function openRegionMenu()
				if regionOpen then
					return
				end
				regionOpen = true
				regionToken = regionToken + 1
				regionCatcher.Visible = true
				regionMenu.GroupTransparency = 1
				regionMenu.Visible = true
				TweenService:Create(regionMenu, FAST, { GroupTransparency = 0 }):Play()
				TweenService:Create(regionChev.holder, FAST, { Rotation = -90 }):Play()
				paintRegionBtn()
			end

			regionBtn.Activated:Connect(function()
				if regionOpen then
					closeRegionMenu()
				else
					openRegionMenu()
				end
			end)
			regionCatcher.Activated:Connect(closeRegionMenu)

			local function setRegion(key)
				if key == ALL_KEY or key == regionFilter then
					regionFilter = nil
				else
					regionFilter = key
				end
				regionVersion = -1
				closeRegionMenu()
				list.CanvasPosition = Vector2.new(0, 0)
				render(true)
			end

			local function paintRow(r)
				local sel = false
				if r.key == ALL_KEY then
					sel = (regionFilter == nil)
				else
					sel = (regionFilter == r.key)
				end
				local state = 0
				if sel then
					state = 2
				elseif r.over then
					state = 1
				end
				if r.state == state then
					return
				end
				r.state = state
				local bgT = 1
				local tc = ICON
				if state == 2 then
					bgT = 0
					tc = ICON_HOVER
				elseif state == 1 then
					bgT = 0.55
					tc = ICON_HOVER
				end
				TweenService:Create(r.btn, FAST, { BackgroundTransparency = bgT }):Play()
				r.name.TextColor3 = tc
			end

			local function makeRegionRow(key)
				local b = new("TextButton", {
					Size = UDim2.new(1, 0, 0, 36),
					BackgroundColor3 = HOVER_GREY,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Text = "",
				}, menuScroll)
				corner(b, RADIUS)
				local nameLabel = label(b, "", UDim2.fromOffset(12, 0), UDim2.new(1, -170, 1, 0),
					Enum.Font.GothamMedium, 13, ICON)
				local statLabel = label(b, "", UDim2.new(1, -164, 0, 0), UDim2.new(0, 152, 1, 0),
					Enum.Font.Gotham, 12, DIM_TEXT, Enum.TextXAlignment.Right)
				local r = { btn = b, key = key, name = nameLabel, stats = statLabel, over = false, state = -1 }
				b.MouseEnter:Connect(function()
					r.over = true
					paintRow(r)
				end)
				b.MouseLeave:Connect(function()
					r.over = false
					paintRow(r)
				end)
				b.Activated:Connect(function()
					setRegion(r.key)
				end)
				return r
			end

			updateRegions = function()
				regionVersion = version
				local arr, total, pSum, pN = regionSummary()
				table.sort(arr, function(x, y)
					return x.name < y.name
				end)

				if allRow == nil then
					allRow = makeRegionRow(ALL_KEY)
					allRow.btn.LayoutOrder = 0
				end
				allRow.name.Text = "All regions"
				allRow.stats.Text = statsText(total, pSum, pN)
				paintRow(allRow)

				local seen = {}
				local current = nil
				for i = 1, #arr do
					local a = arr[i]
					local r = regionRows[a.name]
					if r == nil then
						r = makeRegionRow(a.name)
						regionRows[a.name] = r
					end
					r.name.Text = a.name
					r.stats.Text = statsText(a.count, a.pSum, a.pN)
					r.btn.LayoutOrder = i
					seen[a.name] = true
					if regionFilter == a.name then
						current = a
					end
					paintRow(r)
				end

				for name, r in pairs(regionRows) do
					if not seen[name] then
						r.btn:Destroy()
						regionRows[name] = nil
						if regionFilter == name then
							regionFilter = nil
							regionVersion = -1
							task.defer(function()
								render(true)
							end)
						end
					end
				end

				if current then
					regionValue.Text = current.name
					regionValue.TextColor3 = ICON_HOVER
				else
					regionValue.Text = "All regions"
					regionValue.TextColor3 = TEXT_COLOR
				end

				local h = math.min((#arr + 1) * 38 + 16, 300)
				regionMenu.Size = UDim2.fromOffset(300, h)
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
					status.Text = math.min(namesCount, locatedCount) .. "/" .. locatedCount .. " names loaded"
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
			if version ~= regionVersion then
				updateRegions()
			end

			local q = string.lower(box.Text)
			q = string.match(q, "^%s*(.-)%s*$") or ""

			local groupPart = ""
			if group then
				groupPart = tostring(group.id) .. ":" .. tostring(group.rev)
			end
			local optSig = ""
			if opt then
				optSig = opt:Sig()
			end
			local sig = tab .. "|" .. q .. "|" .. version .. "|" .. namesCount .. "|" .. groupPart .. "|" .. tostring(regionFilter) .. "|" .. styleRev .. "|" .. optSig
			if not force and sig == lastSig then
				updateStatus()
				return
			end
			lastSig = sig
			contentRev = contentRev + 1

			-- role chips for the group tab (count of in-game members per role)
			if opt and tab == "group" then
				local counts = {}
				if group then
					for id, _ in pairs(located) do
						local r = group.members[id]
						if r then
							counts[r] = (counts[r] or 0) + 1
						end
					end
				end
				local roleList = {}
				for rname, n in pairs(counts) do
					roleList[#roleList + 1] = { name = rname, count = n }
				end
				table.sort(roleList, function(x, y)
					if x.count ~= y.count then
						return x.count > y.count
					end
					return x.name < y.name
				end)
				opt:SetRoles(roleList)
			end

			-- 1) pick the servers to show
			local isServers = (tab == "servers")
			local st = nil
			if opt then
				st = opt.state
			end
			local qn = tonumber(q)
			if qn and qn % 1 ~= 0 then
				qn = nil
			end
			local built = {}

			for jid, srv in pairs(servers) do
				local include = false
				local matches = 0
				local matchSet = EMPTY
				local ids = nil

				if isServers then
					if q == "" then
						include = true
					else
						local pl = srv.players
						for i = 1, #pl do
							local id = pl[i]
							local hit = false
							if qn and id == qn then
								hit = true
							else
								local n = names[id]
								if n and (string.find(n.dl, q, 1, true) or string.find(n.nl, q, 1, true)) then
									hit = true
								end
							end
							if hit then
								if matchSet == EMPTY then
									matchSet = {}
								end
								matchSet[id] = true
								matches = matches + 1
							end
						end
						if matches > 0 then
							include = true
						elseif string.sub(srv.jl, 1, #q) == q then
							include = true
						end
					end
					if include and regionFilter ~= nil and srv.rname ~= regionFilter then
						include = false
					end
				else
					if group then
						local pl = srv.players
						for i = 1, #pl do
							local id = pl[i]
							local role = group.members[id]
							if role ~= nil and (st == nil or st.role == nil or st.role == role) then
								if ids == nil then
									ids = {}
									matchSet = {}
								end
								ids[#ids + 1] = id
								matchSet[id] = true
								matches = matches + 1
							end
						end
						if matches > 0 then
							include = true
						end
					end
				end

				-- options: hide full servers + friends only (your own server is never hidden for being full)
				if include and st then
					if st.hideFull and srv.jobId ~= game.JobId and (srv.max - srv.count) < st.minFree then
						include = false
					end
					if include and st.friendsOnly then
						local hasFriend = false
						local pl = srv.players
						for i = 1, #pl do
							if opt:IsFriend(pl[i]) then
								hasFriend = true
								break
							end
						end
						if not hasFriend then
							include = false
						end
					end
				end

				if include then
					local cnt = #srv.players
					if ids then
						cnt = #ids
					end
					built[#built + 1] = {
						srv = srv, matches = matches, matchSet = matchSet, ids = ids, cnt = cnt,
						x = 0, y = 0, dy = 0, dh = 0, dfull = 0, stemTop = 0,
					}
				end
			end

			table.sort(built, function(a, b)
				if isServers and q == "" then
					local am = (a.srv.jobId == game.JobId)
					local bm = (b.srv.jobId == game.JobId)
					if am ~= bm then
						return am
					end
				end
				if a.matches ~= b.matches then
					return a.matches > b.matches
				end
				if opt then
					local r = opt:Compare(a.srv, b.srv)
					if r ~= nil then
						return r
					end
				end
				if a.srv.count ~= b.srv.count then
					return a.srv.count > b.srv.count
				end
				return a.srv.jobId < b.srv.jobId
			end)

			entries = built
			lastMatchCount = #built

			-- 2) open state of every drawer (new ones snap, known ones slide)
			local autoOpen = (isServers and q ~= "") or (tab == "group")
			for i = 1, #built do
				local jid = built[i].srv.jobId
				local open = autoOpen
				if expanded[jid] ~= nil then
					open = expanded[jid]
				end
				local g = 0
				if open then
					g = 1
				end
				goal[jid] = g
				if frac[jid] == nil then
					frac[jid] = g
				elseif frac[jid] ~= g then
					startAnim(jid)
				end
			end
			for jid, _ in pairs(frac) do
				if servers[jid] == nil then
					frac[jid] = nil
					goal[jid] = nil
					hov[jid] = nil
					hgoal[jid] = nil
					animating[jid] = nil
					expanded[jid] = nil
				end
			end

			-- 3) place everything
			layout()

			if #built == 0 then
				local filtered = false
				if st then
					filtered = st.hideFull or st.friendsOnly
				end
				if isServers then
					if q ~= "" then
						emptyLabel.Text = "No player matches that yet. Names are still loading in the background, so try again in a moment."
					elseif filtered then
						emptyLabel.Text = "No servers match your filters."
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
					elseif filtered or (st and st.role ~= nil) then
						emptyLabel.Text = "No servers match your filters."
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

		local function safeRender(force)
			local ok, err = pcall(render, force)
			if not ok then
				warn("[finder] render error: " .. tostring(err))
			end
		end

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
				safeRender(true)
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
						pending[#pending + 1] = id
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
				safeRender(false)
				task.wait(2)
			end
		end

		local function startGroup(gid)
			groupToken = groupToken + 1
			local token = groupToken
			local g = { id = gid, name = "Group " .. gid, members = {}, checked = {}, status = "Loading group " .. gid .. "...", rev = 0 }
			group = g
			expanded = {}
			if opt then
				opt.state.role = nil
			end
			list.CanvasPosition = Vector2.new(0, 0)
			render(true)

			task.spawn(function()
				checkOwnServer(g)
				safeRender(true)

				local info, code = fetchGroupInfo(gid)
				if token ~= groupToken then
					return
				end

				local total = GROUP_MEMBER_CAP + 1
				if info then
					g.name = info.name
					total = tonumber(info.memberCount) or 0
					if opt then
						opt:AddHistory(gid, info.name)
					end
				elseif code == 404 then
					g.status = "Group " .. gid .. " does not exist (HTTP 404) - check the ID"
					g.rev = g.rev + 1
					safeRender(true)
					return
				else
					g.status = "Group info failed (HTTP " .. tostring(code) .. "), checking players one by one"
					g.rev = g.rev + 1
					safeRender(true)
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
						safeRender(true)
						needPerPlayer = false
					else
						g.status = "Member list failed (HTTP " .. tostring(c) .. "), checking players one by one"
						g.rev = g.rev + 1
						safeRender(true)
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
		-- Tabs + page layout
		-------------------------------------------------------------
		local function paintTabs(animate)
			local xs = 3
			if tab == "group" then
				xs = 3 + M.tabW + 2
			end
			local pos = UDim2.fromOffset(xs, 3)
			if animate then
				TweenService:Create(slider, SMOOTH, { Position = pos }):Play()
			else
				slider.Position = pos
			end
			local a = ICON
			local b = ICON
			if tab == "servers" then
				a = ICON_HOVER
			else
				b = ICON_HOVER
			end
			TweenService:Create(tabServers, FAST, { TextColor3 = a }):Play()
			TweenService:Create(tabGroup, FAST, { TextColor3 = b }):Play()
		end

		layoutFinder = function()
			styleRev = styleRev + 1
			local y = 8

			boxBack.Position = UDim2.fromOffset(0, y)
			box.TextSize = M.boxText
			if tab == "group" then
				boxBack.Size = UDim2.new(1, -(M.loadW + 8), 0, M.boxH)
			else
				boxBack.Size = UDim2.new(1, 0, 0, M.boxH)
			end
			loadBtn.Position = UDim2.new(1, 0, 0, y)
			loadBtn.Size = UDim2.fromOffset(M.loadW, M.boxH)
			loadBtn.TextSize = M.boxText
			y = y + M.boxH + 8

			local trayW = 6 + M.tabW * 2 + 2
			tray.Position = UDim2.fromOffset(0, y)
			tray.Size = UDim2.fromOffset(trayW, M.trayH)
			slider.Size = UDim2.fromOffset(M.tabW, M.tabH)
			tabServers.Position = UDim2.fromOffset(3, 3)
			tabServers.Size = UDim2.fromOffset(M.tabW, M.tabH)
			tabServers.TextSize = M.tabText
			tabGroup.Position = UDim2.fromOffset(3 + M.tabW + 2, 3)
			tabGroup.Size = UDim2.fromOffset(M.tabW, M.tabH)
			tabGroup.TextSize = M.tabText
			paintTabs(false)

			local x = trayW + 8
			if tab == "servers" then
				regionBtn.Visible = true
				regionBtn.Position = UDim2.fromOffset(x, y)
				regionBtn.Size = UDim2.fromOffset(M.pillW, M.trayH)
				regionTitle.TextSize = M.pillText
				regionValue.TextSize = M.pillText
				regionMenu.Position = UDim2.fromOffset(x, y + M.trayH + 6)
				x = x + M.pillW + 12
			else
				regionBtn.Visible = false
				closeRegionMenu()
				x = x + 4
			end

			-- gear sits on the right of this row; the status text uses what is left
			local usedRight = 0
			if opt then
				opt:SetTouch(touchNow)
				opt:SetTab(tab)
				usedRight = opt:Layout(y, M.trayH, touchNow)
			end
			status.Position = UDim2.fromOffset(x, y)
			status.Size = UDim2.new(1, -(x + usedRight), 0, M.trayH)
			y = y + M.trayH + 10

			list.Position = UDim2.fromOffset(0, y)
			list.Size = UDim2.new(1, 0, 1, -y)
			emptyLabel.Position = UDim2.new(0.5, 0, 0, y + 56)
		end

		local function setTab(name)
			if name == tab then
				return
			end
			savedText[tab] = box.Text
			tab = name
			expanded = {}
			if name == "servers" then
				box.PlaceholderText = "Search a player: display name, username or ID..."
				loadBtn.Visible = false
			else
				box.PlaceholderText = "Group ID or group URL, then press Load..."
				loadBtn.Visible = true
			end
			if opt then
				opt:Close()
			end
			layoutFinder()
			paintTabs(true)
			box.Text = savedText[name]
			list.CanvasPosition = Vector2.new(0, 0)
			render(true)
		end

		tabServers.MouseEnter:Connect(function()
			if tab ~= "servers" then
				TweenService:Create(tabServers, FAST, { TextColor3 = ICON_HOVER }):Play()
			end
		end)
		tabServers.MouseLeave:Connect(function()
			if tab ~= "servers" then
				TweenService:Create(tabServers, FAST, { TextColor3 = ICON }):Play()
			end
		end)
		tabGroup.MouseEnter:Connect(function()
			if tab ~= "group" then
				TweenService:Create(tabGroup, FAST, { TextColor3 = ICON_HOVER }):Play()
			end
		end)
		tabGroup.MouseLeave:Connect(function()
			if tab ~= "group" then
				TweenService:Create(tabGroup, FAST, { TextColor3 = ICON }):Play()
			end
		end)
		tabServers.Activated:Connect(function()
			setTab("servers")
		end)
		tabGroup.Activated:Connect(function()
			setTab("group")
		end)

		-- typing: wait a moment so every keystroke does not redraw the grid
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if tab ~= "servers" then
				return
			end
			searchToken = searchToken + 1
			local t = searchToken
			task.delay(0.12, function()
				if t == searchToken and running then
					expanded = {}
					list.CanvasPosition = Vector2.new(0, 0)
					safeRender(false)
				end
			end)
		end)

		box.Focused:Connect(function()
			TweenService:Create(boxStroke, FAST, { Color = HOVER_GREY }):Play()
		end)
		box.FocusLost:Connect(function(enterPressed)
			TweenService:Create(boxStroke, FAST, { Color = BORDER }):Play()
			if enterPressed and tab == "group" then
				submitGroup()
			end
		end)

		loadBtn.Activated:Connect(submitGroup)

		-------------------------------------------------------------
		-- Extra modules: options (gear, sort, filters) and profile card
		-------------------------------------------------------------
		if opts.Options then
			local okO, o = pcall(opts.Options.new, win, mainPage, {
				onChange = function()
					render(true)
				end,
				onPickGroup = function(id)
					setTab("group")
					box.Text = tostring(id)
					submitGroup()
				end,
				onFriend = function(id, username, display)
					setName(id, username, display)
				end,
			})
			if okO then
				opt = o
			else
				warn("[finder] options module failed: " .. tostring(o))
			end
		end

		if opts.Profile then
			local okP, p = pcall(opts.Profile.new, win, {
				http = function(method, url)
					local data = httpJson(method, url)
					return data
				end,
				copy = copyText,
			})
			if okP then
				profile = p
			else
				warn("[finder] profile module failed: " .. tostring(p))
			end
		end

		-------------------------------------------------------------
		-- API + stop
		-------------------------------------------------------------
		function self:Join(jobId)
			local srv = servers[jobId]
			if srv then
				joinServer(srv)
			end
		end

		function self:Refresh()
			pcall(refreshServers)
			safeRender(true)
		end

		stopAll = function()
			groupToken = groupToken + 1
			if animConn then
				animConn:Disconnect()
				animConn = nil
			end
			if opt then
				opt:Close()
			end
			if profile then
				profile:Close()
			end
		end
	end

	function self:GetServers()
		return servers
	end

	function self:GetServer(jobId)
		return servers[jobId]
	end

	function self:Locate(userId)
		return located[userId]
	end

	function self:GetName(userId)
		return names[userId]
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
		stopAll()
	end
	win:OnUnload(stop)
	function self:Stop()
		stop()
	end

	-- Touch Mode changes: new sizes, then draw again
	win:OnTouchChange(function(on)
		touchNow = on
		setMetrics(on)
		layoutFinder()
		render(true)
	end)

	pcall(refreshServers)
	pcall(resolveNames)
	touchNow = win.Touch
	setMetrics(touchNow)
	layoutFinder()
	render(true)

	-- server list loop (sleeps longer while the window is hidden or minimized)
	task.spawn(function()
		local lastErr = nil
		while running do
			local idle = win:IsHidden() or win:IsMinimized()
			if not idle then
				pcall(refreshServers)
				local ok, err = pcall(render, false)
				if not ok and tostring(err) ~= lastErr then
					lastErr = tostring(err)
					warn("[finder] render error: " .. lastErr)
				end
				task.wait(REFRESH_EVERY)
			else
				task.wait(REFRESH_EVERY * 2)
			end
		end
	end)

	-- names loop
	task.spawn(function()
		while running do
			if win:IsHidden() or win:IsMinimized() then
				task.wait(3)
			else
				local ok, more = pcall(resolveNames)
				if ok and more then
					task.wait(0.6)
				else
					task.wait(2)
				end
			end
		end
	end)

	return self
end

return Finder
