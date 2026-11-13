-- pingspoofer.lua  (Y1 module: the Ping Spoofer row on the Misc > Extra page, built by animation.lua)
-- ASCII only, conservative syntax (no += and no continue).
--
-- LOCATION: this module no longer makes its own card at a fixed spot. extra.lua already builds the
-- "Quality Of Life" group (Animations / Anti AFK / Ping Spoofer) and hands the empty third row over in
-- ctx.Rows.ping. This file fills that row the same way animation.lua fills the others:
-- feature name + status text, an Enable switch, and three dots. Because the row lives inside the page's
-- scrolling body, it scrolls with the page and can never overlap anything.
-- The dots open a pop-up with the Ping / Jitter / Speed sliders and live readouts.
--
-- ONE METHOD: value override.
-- Every place the ping is READ or DRAWN gets your number instead of the real one:
--   1) Performance Stats overlay (Esc > Settings): every Ping number in CoreGui is found by looking at the
--      whole overlay (not by a fixed name), and its text is rewritten every frame AND the instant the
--      engine changes it. The original format is kept ("45 ms", "45.12 ms", "Ping: 45").
--   2) StatsItem:GetValue / GetValueString for "Data Ping" and "Ping" and Player:GetNetworkPing()
--      (scripts, ping counters, and the overlay itself if it reads through those calls).
-- It only changes what this client reports. It does not touch your real connection.
-- Needs: access to CoreGui (for the overlay) and hookmetamethod + newcclosure + getnamecallmethod
-- (for scripts). If one is missing the pop-up tells you which part is not active.
-- The little graph line in the overlay is engine-drawn and stays real; only the numbers change.
-- The dot next to "Current:" follows the graph color (green / yellow / orange, same thresholds as Roblox).
-- Jitter: +/- 0..100 ms, random ups and drops. Speed: 1 (slow) .. 10 (fast) = how often it jumps.
--
-- Build signature: PingSpoofer.build(container, T, H, ctx) -> { Unload = fn }
-- ctx.Helpers and ctx.Rows are handed over by extra.lua (through animation.lua).

local PingSpoofer = {}

function PingSpoofer.build(parent, T, H, ctx)
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local Stats = game:GetService("Stats")
	local player = Players.LocalPlayer

	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label

	local X = nil
	local R = nil
	if type(ctx) == "table" then
		X = ctx.Helpers
		R = ctx.Rows
	end
	if type(X) ~= "table" or type(R) ~= "table" or typeof(R.ping) ~= "Instance" then
		warn("[pingspoofer] extra.lua did not pass its helpers / the ping row")
		return { Unload = function() end }
	end

	local GREEN = Color3.fromRGB(52, 199, 120)
	local AMBER = Color3.fromRGB(232, 176, 70)

	---------------------------------------------------------------------
	-- stop an older copy
	---------------------------------------------------------------------
	local okEnv, genv = pcall(function()
		return getgenv()
	end)
	if okEnv and genv and genv.__Y1_PING_STOP then
		pcall(genv.__Y1_PING_STOP)
	end

	---------------------------------------------------------------------
	-- state
	---------------------------------------------------------------------
	local S = {
		on = false,
		ping = 150,        -- ms you want
		jitter = 25,       -- +/- ms wobble (max 100)
		jitterSpeed = 4,   -- 1 (slow) .. 10 (fast)
	}

	local running = true
	local conns = {}
	local shown = S.ping
	local jitterOff = 0

	-- shared with the hook: the hook is installed only once per game session, even if this module is rebuilt
	local shared = nil
	if okEnv and genv and type(genv.__Y1_PING_SHARED) == "table" then
		shared = genv.__Y1_PING_SHARED
	else
		shared = { on = false, shown = S.ping, reading = false, hooked = false, tried = false }
		if okEnv and genv then
			genv.__Y1_PING_SHARED = shared
		end
	end
	shared.on = false
	shared.shown = S.ping

	local canHook = (type(hookmetamethod) == "function") and (type(newcclosure) == "function")
		and (type(getnamecallmethod) == "function")

	-- the real ping in ms (read by this script, so the hook lets it through)
	local function readReal()
		shared.reading = true
		local ok, v = pcall(function()
			return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		shared.reading = false
		if ok and type(v) == "number" then
			return v
		end
		return 0
	end

	---------------------------------------------------------------------
	-- part 1: scripts (namecall hook)
	---------------------------------------------------------------------
	local function installHook()
		if shared.tried then
			return shared.hooked
		end
		shared.tried = true
		if not canHook then
			return false
		end
		local hookOld = nil
		local ok = pcall(function()
			hookOld = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
				if shared.on and not shared.reading then
					local method = getnamecallmethod()
					if method == "GetValue" or method == "GetValueString" or method == "GetNetworkPing" then
						local ours = false
						if type(checkcaller) == "function" then
							ours = checkcaller()
						end
						if not ours and typeof(self) == "Instance" then
							if method == "GetNetworkPing" then
								if self == player then
									return shared.shown / 1000
								end
							elseif self.ClassName == "StatsItem" then
								local n = self.Name
								if n == "Data Ping" or n == "Ping" then
									if method == "GetValue" then
										return shared.shown
									end
									return string.format("%.2f ms", shared.shown)
								end
							end
						end
					end
				end
				return hookOld(self, ...)
			end))
		end)
		shared.hooked = ok and hookOld ~= nil
		return shared.hooked
	end

	---------------------------------------------------------------------
	-- part 2: Performance Stats overlay (CoreGui text)
	---------------------------------------------------------------------
	local coreGui = nil
	pcall(function()
		coreGui = game:GetService("CoreGui")
	end)
	local coreOk = false
	if coreGui then
		coreOk = pcall(function()
			return #coreGui:GetChildren()
		end)
	end

	local labels = {}      -- [TextLabel] = { conn, busy }
	local labelCount = 0
	local dirty = true
	local lastScan = 0

	local function isTextObj(o)
		return o:IsA("TextLabel") or o:IsA("TextButton")
	end

	-- plain number text, e.g. "45", "45.12", "45 ms", "45.12ms"
	local function isNumberText(t)
		if type(t) ~= "string" then
			return false
		end
		return string.match(t, "^%s*%-?%d[%d%.,]*%s*[mM]?[sS]?%s*$") ~= nil
	end

	-- detail panel lines: "Current: 234 ms" and "Average: 236 ms" (Target is left alone)
	local function isStatLine(t)
		if type(t) ~= "string" then
			return false
		end
		local l = string.lower(t)
		return string.match(l, "^%s*current%s*:%s*%d") ~= nil or string.match(l, "^%s*average%s*:%s*%d") ~= nil
	end

	local function isCurrentLine(t)
		if type(t) ~= "string" then
			return false
		end
		return string.match(string.lower(t), "^%s*current%s*:") ~= nil
	end

	local function isPingTitle(t)
		if type(t) ~= "string" then
			return false
		end
		local l = string.lower(t)
		return string.match(l, "^%s*[%a ]*ping%s*:?%s*$") ~= nil
	end

	-- the same text with its first number replaced by ours (same decimals as the original)
	local function withValue(orig, v)
		local s, e = string.find(orig, "%d[%d%.]*")
		if not s then
			return orig
		end
		local numStr = string.sub(orig, s, e)
		local dec = 0
		local dot = string.find(numStr, ".", 1, true)
		if dot then
			dec = #numStr - dot
		end
		local out = string.format("%." .. tostring(dec) .. "f", math.max(0, v))
		return string.sub(orig, 1, s - 1) .. out .. string.sub(orig, e + 1)
	end

	local function paint(lbl)
		local rec = labels[lbl]
		if not rec or not S.on then
			return
		end
		local cur = lbl.Text
		local want = withValue(cur, shown)
		if want ~= cur then
			rec.busy = true
			lbl.Text = want
			rec.busy = false
		end
	end

	local function watch(lbl)
		if labels[lbl] then
			return
		end
		local rec = { busy = false }
		labels[lbl] = rec
		labelCount = labelCount + 1
		rec.conn = lbl:GetPropertyChangedSignal("Text"):Connect(function()
			if rec.busy then
				return
			end
			paint(lbl)
		end)
	end

	-- number labels inside a container, not counting "skip"
	local function numbersIn(container, skip)
		local out = {}
		local list = container:GetDescendants()
		for i = 1, #list do
			local d = list[i]
			if d ~= skip and isTextObj(d) and (isNumberText(d.Text) or isStatLine(d.Text)) then
				out[#out + 1] = d
			end
		end
		return out
	end

	-- graphs: PS_AnnotatedGraph > PS_BarFrame > Bar_0..Bar_N, each bar Position.Y = 1-h, Size.Y = h (h = value / axis top)
	local graphs = {}      -- [graphFrame] = { bars = {}, conns = {}, top = label, busy = false }
	local graphCount = 0
	local history = {}
	local histCol = {}   -- color each bar got when it was added (old bars keep theirs)
	local axisMax = 100
	local histAcc = 0
	local STEPS = { 100, 150, 200, 300, 400, 500, 750, 1000, 1500, 2000, 5000 }

	-- exact colors and thresholds from Roblox's own Performance Stats code (StatsUtils.GetColorForValue):
	--   value < 0.666 * target  -> green
	--   value < 1.333 * target  -> yellow (yellow-green)
	--   otherwise               -> orange-red
	local C_GOOD = Color3.new(126 / 255, 211 / 255, 33 / 255)
	local C_MID = Color3.new(209 / 255, 211 / 255, 33 / 255)
	local C_BAD = Color3.new(211 / 255, 88 / 255, 33 / 255)
	local PING_TARGET = 50

	local function graphColor(v)
		if v < 0.666 * PING_TARGET then
			return C_GOOD
		elseif v < 1.333 * PING_TARGET then
			return C_MID
		end
		return C_BAD
	end

	-- legend dot next to "Current:" follows the graph color
	local dots = {}   -- [obj] = { prop, orig, conn, busy }
	local dotCount = 0

	local function dotProp(o)
		if o:IsA("ImageLabel") or o:IsA("ImageButton") then
			return "ImageColor3"
		end
		return "BackgroundColor3"
	end

	local function paintDot(o)
		local rec = dots[o]
		if not rec or not S.on then
			return
		end
		local want = graphColor(shown)
		if o[rec.prop] ~= want then
			rec.busy = true
			o[rec.prop] = want
			rec.busy = false
		end
	end

	local function watchDot(o)
		if dots[o] then
			return
		end
		local prop = dotProp(o)
		local rec = { prop = prop, orig = o[prop], busy = false }
		dots[o] = rec
		dotCount = dotCount + 1
		rec.conn = o:GetPropertyChangedSignal(prop):Connect(function()
			if not rec.busy then
				paintDot(o)
			end
		end)
	end

	-- find the small dot sitting on the same row as a "Current:" label
	local function findDot(lbl)
		local c = lbl.Parent
		for _ = 1, 2 do
			if not c or c == coreGui then
				break
			end
			local ly = lbl.AbsolutePosition.Y
			local lh = lbl.AbsoluteSize.Y
			local found = false
			local list = c:GetDescendants()
			for i = 1, #list do
				local o = list[i]
				if o ~= lbl and o:IsA("GuiObject") and not isTextObj(o)
					and o.AbsoluteSize.X > 0 and o.AbsoluteSize.X <= 24
					and o.AbsoluteSize.Y > 0 and o.AbsoluteSize.Y <= 24 then
					local cy = o.AbsolutePosition.Y + o.AbsoluteSize.Y / 2
					if cy >= ly and cy <= ly + lh then
						watchDot(o)
						found = true
					end
				end
			end
			if found then
				return
			end
			c = c.Parent
		end
	end

	-- put the original colors back and stop watching
	local function clearDots()
		for o, rec in pairs(dots) do
			pcall(function()
				rec.conn:Disconnect()
			end)
			pcall(function()
				o[rec.prop] = rec.orig
			end)
			dots[o] = nil
		end
		dotCount = 0
	end

	local HIST_CAP = 240
	local maxBars = 20

	-- the axis follows only the bars you can see, so it drops back down once a spike scrolls out
	local function recalcAxis()
		local m = 0
		for i = math.max(1, #history - maxBars + 1), #history do
			if history[i] > m then
				m = history[i]
			end
		end
		local want = STEPS[#STEPS]
		for i = 1, #STEPS do
			if STEPS[i] >= m * 1.1 then
				want = STEPS[i]
				break
			end
		end
		axisMax = want
	end

	local function pushHistory()
		history[#history + 1] = shown
		histCol[#histCol + 1] = graphColor(shown)
		if #history > HIST_CAP then
			table.remove(history, 1)
			table.remove(histCol, 1)
		end
		recalcAxis()
	end

	-- fill the past with your REAL ping (small natural wobble) so the graph looks continuous
	local function prefillHistory(base)
		history = {}
		histCol = {}
		for i = 1, HIST_CAP do
			local v = math.max(1, base * (1 + (math.random() * 2 - 1) * 0.06))
			history[i] = v
			histCol[i] = graphColor(v)
		end
		recalcAxis()
	end

	local function paintGraph(g)
		local rec = graphs[g]
		if not rec or not S.on then
			return
		end
		rec.busy = true
		local bars = rec.bars
		local n = #bars
		for i = 1, n do
			local bar = bars[i]
			if bar.Parent then
				local idx = #history - (n - i)
				local v = history[idx]
				if v == nil then
					v = history[1] or shown
				end
				local col = histCol[idx]
				if col == nil then
					col = graphColor(v)
				end
				if bar.BackgroundColor3 ~= col then
					bar.BackgroundColor3 = col
				end
				local h = math.clamp(v / axisMax, 0, 1)
				if math.abs(bar.Size.Y.Scale - h) > 0.0005 then
					bar.Position = UDim2.new(bar.Position.X.Scale, bar.Position.X.Offset, 1 - h, 0)
					bar.Size = UDim2.new(bar.Size.X.Scale, bar.Size.X.Offset, h, 0)
				end
			end
		end
		if rec.top and rec.top.Parent then
			local want = string.format("%.2f", axisMax)
			if rec.top.Text ~= want then
				rec.top.Text = want
			end
		end
		rec.busy = false
	end

	local function watchGraph(g)
		if graphs[g] then
			return
		end
		local frame = g:FindFirstChild("PS_BarFrame")
		if not frame then
			return
		end
		local bars = {}
		local kids = frame:GetChildren()
		for i = 1, #kids do
			local n = string.match(kids[i].Name, "^Bar_(%d+)$")
			if n and kids[i]:IsA("GuiObject") then
				bars[#bars + 1] = { n = tonumber(n), o = kids[i] }
			end
		end
		if #bars == 0 then
			return
		end
		table.sort(bars, function(a, b)
			return a.n < b.n
		end)
		local list = {}
		for i = 1, #bars do
			list[i] = bars[i].o
		end
		if #list > maxBars then
			maxBars = #list
		end
		local rec = { bars = list, conns = {}, top = g:FindFirstChild("PS_TopAxisLabel"), busy = false }
		graphs[g] = rec
		graphCount = graphCount + 1
		for i = 1, #list do
			rec.conns[#rec.conns + 1] = list[i]:GetPropertyChangedSignal("Size"):Connect(function()
				if not rec.busy then
					paintGraph(g)
				end
			end)
		end
		if rec.top then
			rec.conns[#rec.conns + 1] = rec.top:GetPropertyChangedSignal("Text"):Connect(function()
				if not rec.busy then
					paintGraph(g)
				end
			end)
		end
	end

	-- the graph that belongs to a ping title label
	local function graphForTitle(d)
		if d.Name == "TitleLabel" then
			-- small panel: its graph is the next PS_AnnotatedGraph after the panel in the same row
			local panel = d.Parent
			local row = panel and panel.Parent
			if row then
				local kids = row:GetChildren()
				local seen = false
				for i = 1, #kids do
					if kids[i] == panel then
						seen = true
					elseif seen and kids[i].Name == "PS_AnnotatedGraph" then
						return kids[i]
					end
				end
			end
			return nil
		end
		-- detail view: the title sits in a Frame next to the big graph
		local box = d.Parent and d.Parent.Parent
		if box then
			return box:FindFirstChild("PS_AnnotatedGraph")
		end
		return nil
	end

	local function scan()
		if not coreOk then
			return
		end
		local list = coreGui:GetDescendants()
		for i = 1, #list do
			local d = list[i]
			if isTextObj(d) then
				local t = d.Text
				local picked = nil

				if isPingTitle(t) then
					local gf = graphForTitle(d)
					if gf then
						watchGraph(gf)
					end
					-- the value sits next to the title: widen the search level by level until numbers appear
					local c = d.Parent
					for _ = 1, 3 do
						if not c or c == coreGui then
							break
						end
						local nums = numbersIn(c, d)
						if #nums == 1 or #nums == 2 then
							picked = nums
							break
						elseif #nums > 2 then
							break
						end
						c = c.Parent
					end
				elseif string.match(string.lower(t), "^%s*[%a ]*ping[%a ]*%s*:?%s*%-?%d") then
					-- one label with both words and number: "Ping: 45 ms"
					picked = { d }
				end

				if picked then
					for j = 1, #picked do
						watch(picked[j])
						if isCurrentLine(picked[j].Text) then
							findDot(picked[j])
						end
					end
				end
			end
		end
	end

	local function clearGraphs()
		for g, rec in pairs(graphs) do
			for i = 1, #rec.conns do
				pcall(function()
					rec.conns[i]:Disconnect()
				end)
			end
			graphs[g] = nil
		end
		graphCount = 0
	end

	local function dropDead()
		for g, rec in pairs(graphs) do
			if not g.Parent then
				for i = 1, #rec.conns do
					pcall(function()
						rec.conns[i]:Disconnect()
					end)
				end
				graphs[g] = nil
				graphCount = graphCount - 1
			end
		end
		for lbl, rec in pairs(labels) do
			if not lbl.Parent then
				pcall(function()
					rec.conn:Disconnect()
				end)
				labels[lbl] = nil
				labelCount = labelCount - 1
			end
		end
		for o, rec in pairs(dots) do
			if not o.Parent then
				pcall(function()
					rec.conn:Disconnect()
				end)
				dots[o] = nil
				dotCount = dotCount - 1
			end
		end
	end

	local function clearLabels()
		clearGraphs()
		clearDots()
		for lbl, rec in pairs(labels) do
			pcall(function()
				rec.conn:Disconnect()
			end)
			labels[lbl] = nil
		end
		labelCount = 0
	end

	if coreOk then
		pcall(function()
			conns[#conns + 1] = coreGui.DescendantAdded:Connect(function()
				dirty = true
			end)
		end)
	end

	local function overlayStep(now)
		dropDead()
		if not S.on then
			return
		end
		if dirty or (now - lastScan) >= 1 then
			dirty = false
			lastScan = now
			pcall(scan)
		end
		for lbl, _ in pairs(labels) do
			paint(lbl)
		end
		for g, _ in pairs(graphs) do
			paintGraph(g)
		end
		for o, _ in pairs(dots) do
			paintDot(o)
		end
	end

	local function onEnabled()
		local r = readReal()
		if r > 0 then
			shown = r
		end
		shared.shown = shown
		prefillHistory(math.max(1, shown))
	end

	---------------------------------------------------------------------
	-- the row (Quality Of Life, row 3) + settings pop-up
	---------------------------------------------------------------------
	-- everything this module puts on the row lives in one holder, so unloading removes exactly that
	local holder = new("Frame", {
		Name = "PingSpooferHolder",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, R.ping)

	local sub = X.rowHead(holder, "Ping Spoofer")

	local function refreshSub()
		local state = '<font color="rgb(116,116,124)">Off</font>'
		if S.on then
			state = '<font color="rgb(52,199,120)">Active</font>'
		end
		sub.Text = state
	end
	refreshSub()

	X.makeSwitch(holder, false, function(on)
		S.on = on
		shared.on = on
		if on then
			onEnabled()
			installHook()
			dirty = true
		else
			clearLabels()
		end
		refreshSub()
	end, 23)

	local dotsBtn = X.makeDots(holder, UDim2.new(1, -58, 0, 23))

	local PW = 290
	local PH = 268
	local F = X.makeFloating("PingSpooferSettings", PW, PH)
	local pop = F.frame

	label(pop, "Ping Spoofer", UDim2.fromOffset(16, 12), UDim2.new(1, -32, 0, 20),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR)
	new("Frame", {
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, pop)

	local function makeSlider(c, y, name, labelW, minV, maxV, stepV, startValue, fmt, setValue)
		label(c, name, UDim2.fromOffset(16, y), UDim2.fromOffset(labelW, 20),
			Enum.Font.GothamMedium, 12, T.ICON)
		local valueLabel = label(c, "", UDim2.new(1, -76, 0, y), UDim2.fromOffset(60, 20),
			Enum.Font.GothamMedium, 12, T.TEXT_COLOR, Enum.TextXAlignment.Right)
		local x0 = 16 + labelW + 6

		local track = new("Frame", {
			Position = UDim2.fromOffset(x0, y + 7),
			Size = UDim2.new(1, -(x0 + 82), 0, 6),
			BackgroundColor3 = T.CLUSTER_BG,
			BorderSizePixel = 0,
		}, c)
		corner(track, 3)
		local fill = new("Frame", {
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = T.ICON_HOVER,
			BorderSizePixel = 0,
		}, track)
		corner(fill, 3)
		local knob = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = T.ICON_HOVER,
			BorderSizePixel = 0,
		}, track)
		corner(knob, 100)
		local hitBtn = new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			Position = UDim2.fromOffset(x0, y),
			Size = UDim2.new(1, -(x0 + 82), 0, 20),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, c)

		local value = startValue
		local dragging = false
		local function refresh()
			local f = math.clamp((value - minV) / (maxV - minV), 0, 1)
			fill.Size = UDim2.new(f, 0, 1, 0)
			knob.Position = UDim2.new(f, 0, 0.5, 0)
			valueLabel.Text = string.format(fmt, value)
		end
		refresh()

		local function setFromX(px)
			local w = hitBtn.AbsoluteSize.X
			if w <= 0 then
				return
			end
			local f = math.clamp((px - hitBtn.AbsolutePosition.X) / w, 0, 1)
			value = minV + math.floor(f * (maxV - minV) / stepV + 0.5) * stepV
			value = math.clamp(value, minV, maxV)
			setValue(value)
			refresh()
		end

		hitBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				setFromX(input.Position.X)
			end
		end)
		conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
			if not dragging then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				setFromX(input.Position.X)
			end
		end)
		conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	makeSlider(pop, 54, "Ping", 56, 0, 1000, 5, S.ping, "%d ms", function(v)
		S.ping = v
	end)
	makeSlider(pop, 84, "Jitter", 56, 0, 100, 1, S.jitter, "+/- %d", function(v)
		S.jitter = v
	end)
	makeSlider(pop, 114, "Speed", 56, 1, 10, 1, S.jitterSpeed, "%d", function(v)
		S.jitterSpeed = v
	end)

	new("Frame", {
		Position = UDim2.fromOffset(16, 150),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = T.BORDER,
		BorderSizePixel = 0,
	}, pop)

	local realLbl = label(pop, "Real ping: -", UDim2.fromOffset(16, 158), UDim2.new(1, -32, 0, 16),
		Enum.Font.GothamMedium, 12, T.TEXT_COLOR)
	local shownLbl = label(pop, "Shown ping: -", UDim2.fromOffset(16, 176), UDim2.new(1, -32, 0, 16),
		Enum.Font.GothamMedium, 12, T.TEXT_COLOR)
	local hookLbl = label(pop, "", UDim2.fromOffset(16, 202), UDim2.new(1, -32, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	local overLbl = label(pop, "", UDim2.fromOffset(16, 220), UDim2.new(1, -32, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT)
	label(pop, "Esc > Settings > Performance Stats (not Shift+F3).", UDim2.fromOffset(16, 244),
		UDim2.new(1, -32, 0, 14), Enum.Font.Gotham, 11, T.DIM_TEXT)

	local function statusLines()
		if canHook then
			if shared.hooked then
				hookLbl.Text = "Scripts hook: active"
				hookLbl.TextColor3 = GREEN
			else
				hookLbl.Text = "Scripts hook: ready"
				hookLbl.TextColor3 = T.DIM_TEXT
			end
		else
			hookLbl.Text = "Scripts hook: not supported by executor"
			hookLbl.TextColor3 = AMBER
		end
		if not coreOk then
			overLbl.Text = "Overlay: CoreGui blocked by executor"
			overLbl.TextColor3 = AMBER
		elseif labelCount > 0 then
			overLbl.Text = "Overlay: patched (" .. tostring(labelCount) .. " label" .. (labelCount == 1 and "" or "s")
				.. ", " .. tostring(graphCount) .. " graph" .. (graphCount == 1 and "" or "s")
				.. ", " .. tostring(dotCount) .. " dot" .. (dotCount == 1 and "" or "s") .. ")"
			overLbl.TextColor3 = GREEN
		else
			overLbl.Text = "Overlay: waiting (turn on Perf Stats)"
			overLbl.TextColor3 = T.DIM_TEXT
		end
	end
	statusLines()

	local function openPing()
		if F.isOpen() then
			return
		end
		F.open(X.placeNear(dotsBtn.btn, PW, PH, nil))
		dotsBtn.open = true
		dotsBtn.paint()
	end

	local function closePing()
		F.close()
		dotsBtn.open = false
		dotsBtn.paint()
	end

	dotsBtn.btn.Activated:Connect(function()
		if F.isOpen() then
			closePing()
		else
			openPing()
		end
	end)

	X.addPopup({
		isOpen = function()
			return F.isOpen()
		end,
		close = closePing,
		hit = { pop, dotsBtn.btn },
	})

	---------------------------------------------------------------------
	-- loop: random jumps (ups and drops), overlay painting, readouts
	---------------------------------------------------------------------
	local acc = 0
	local jacc = 0
	local jnext = 1
	local lastJitter = S.jitter
	conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end
		jacc = jacc + dt
		-- speed 1 = about every 6s, speed 10 = about every 0.6s, with random variation in the gap
		if S.jitter ~= lastJitter then
			lastJitter = S.jitter
			jacc = jnext
		end
		if jacc >= jnext then
			jacc = 0
			local base = 6.6 - 0.6 * math.max(1, S.jitterSpeed)
			jnext = base * (0.4 + math.random() * 1.2)
			jitterOff = (math.random() * 2 - 1) * S.jitter
		end
		local target = math.max(0, S.ping + jitterOff)
		-- fast snap (about a tenth of a second) so changes read as ups and drops, not smooth slides
		shown = shown + (target - shown) * math.min(1, dt * 20)
		shared.shown = shown

		histAcc = histAcc + dt
		if histAcc >= 0.5 then
			histAcc = 0
			pushHistory()
		end
		overlayStep(os.clock())

		acc = acc + dt
		if acc >= 0.25 then
			acc = 0
			if F.isOpen() then
				statusLines()
				realLbl.Text = string.format("Real ping: %d ms", math.floor(readReal() + 0.5))
				if S.on then
					shownLbl.Text = string.format("Shown ping: %d ms", math.floor(shown + 0.5))
				else
					shownLbl.Text = "Shown ping: real"
				end
			end
		end
	end)

	-- also paint right before each frame is drawn, so the engine's update is never visible
	pcall(function()
		conns[#conns + 1] = RunService.RenderStepped:Connect(function()
			if running and S.on then
				for lbl, _ in pairs(labels) do
					paint(lbl)
				end
				for g, _ in pairs(graphs) do
					paintGraph(g)
				end
				for o, _ in pairs(dots) do
					paintDot(o)
				end
			end
		end)
	end)

	---------------------------------------------------------------------
	-- unload
	---------------------------------------------------------------------
	local function unload()
		if not running then
			return
		end
		running = false
		S.on = false
		shared.on = false
		clearLabels()
		for i = 1, #conns do
			pcall(function()
				conns[i]:Disconnect()
			end)
		end
		conns = {}
		pcall(function()
			F.close()
		end)
		-- the row itself belongs to extra.lua; only what this module added is removed
		pcall(function()
			holder:Destroy()
			pop:Destroy()
		end)
		if okEnv and genv and genv.__Y1_PING_STOP == unload then
			genv.__Y1_PING_STOP = nil
		end
	end

	if okEnv and genv then
		genv.__Y1_PING_STOP = unload
	end

	return { Unload = unload }
end

return PingSpoofer
