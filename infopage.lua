-- infopage.lua  (Y1 Info tab content, separate module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Info tab INTO a frame (the Info page of ui.lua). The page scrolls if it is taller
-- than the window:
--   Overview     : account (profile picture + username) and plan, license + time remaining
--   yur1 info    : yur1 version, yur1 status, supported games
--   Executor info: which executor is running (if it can be detected) and its version
--   Credits      : who made yur1 + Discord symbol
--
--   local InfoPage = <this file>
--   InfoPage.build(parentFrame, themeTable, helperTable, {
--       Plan = "Tester",
--       Version = "0.6 Beta",
--       Status = "Up to date",
--       Games = "Zee Hood and Universal",
--   })

local InfoPage = {}

function InfoPage.build(parent, T, H, opts)
	opts = opts or {}
	local planText = opts.Plan or "Tester"
	local versionText = opts.Version or "0.6 Beta"
	local statusText = opts.Status or "Up to date"
	local gamesText = opts.Games or "Zee Hood and Universal"

	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label

	local INF = utf8.char(8734)   -- infinity symbol (kept out of the file so it stays ASCII)
	local LEFT = Enum.TextXAlignment.Left
	local RIGHT = Enum.TextXAlignment.Right

	local root = new("ScrollingFrame", {
		Name = "InfoRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 560),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = T.HOVER_GREY,
		ScrollBarImageTransparency = 0.3,
	}, parent)

	---------------------------------------------------------------------
	-- small builders
	---------------------------------------------------------------------
	local function section(text, y)
		local l = label(root, text, UDim2.fromOffset(2, y), UDim2.new(1, -8, 0, 18),
			Enum.Font.GothamBold, 15, T.TEXT_COLOR)
		return l
	end

	local function card(y, h)
		local f = new("Frame", {
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, -8, 0, h),
			BackgroundColor3 = T.SIDEBAR_BG,
			BorderSizePixel = 0,
		}, root)
		corner(f, T.RADIUS + 4)
		stroke(f, T.BORDER, 1, 0)
		return f
	end

	local function divider(parentCard, pos, size)
		new("Frame", {
			Position = pos,
			Size = size,
			BackgroundColor3 = T.BORDER,
			BorderSizePixel = 0,
		}, parentCard)
	end

	-- one cell: dim caption on top, bold value under it.
	-- col 0 = left column (left aligned), col 1 = right column (right aligned), col 2 = full width (left aligned)
	local function cell(parentCard, col, rowY, caption, value, valueColor, valueSize)
		local capPos
		local valPos
		local size
		local align = LEFT
		if col == 0 then
			capPos = UDim2.fromOffset(14, rowY + 9)
			valPos = UDim2.fromOffset(14, rowY + 26)
			size = UDim2.new(0.5, -28, 0, 12)
		elseif col == 1 then
			capPos = UDim2.new(0.5, 14, 0, rowY + 9)
			valPos = UDim2.new(0.5, 14, 0, rowY + 26)
			size = UDim2.new(0.5, -28, 0, 12)
		else
			capPos = UDim2.fromOffset(14, rowY + 9)
			valPos = UDim2.fromOffset(14, rowY + 26)
			size = UDim2.new(1, -28, 0, 12)
		end
		label(parentCard, caption, capPos, size, Enum.Font.Gotham, 11, T.DIM_TEXT, align)
		local v = label(parentCard, value, valPos, UDim2.new(size.X.Scale, size.X.Offset, 0, 22),
			Enum.Font.GothamBold, valueSize or 14, valueColor or T.TEXT_COLOR, align)
		v.TextYAlignment = Enum.TextYAlignment.Center
		return v
	end

	---------------------------------------------------------------------
	-- OVERVIEW
	---------------------------------------------------------------------
	section("Overview", 4)

	-- account (profile picture + username) | plan
	local acc = card(28, 58)
	divider(acc, UDim2.new(0.5, 0, 0, 10), UDim2.fromOffset(1, 38))

	label(acc, "Account", UDim2.fromOffset(14, 9), UDim2.new(0.5, -28, 0, 12),
		Enum.Font.Gotham, 11, T.DIM_TEXT, LEFT)

	local avatar = new("ImageLabel", {
		Name = "Avatar",
		Position = UDim2.fromOffset(14, 26),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = T.CARD_BG,
		BorderSizePixel = 0,
		Image = "",
	}, acc)
	corner(avatar, 100)

	local nameLabel = label(acc, player.Name, UDim2.fromOffset(44, 26), UDim2.new(0.5, -58, 0, 22),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR, LEFT)
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center

	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and url and avatar.Parent then
			avatar.Image = url
		end
	end)

	-- plan is right aligned (like the reference)
	label(acc, "Plan", UDim2.new(0.5, 14, 0, 9), UDim2.new(0.5, -28, 0, 12),
		Enum.Font.Gotham, 11, T.DIM_TEXT, RIGHT)
	local planV = label(acc, planText, UDim2.new(0.5, 14, 0, 26), UDim2.new(0.5, -28, 0, 22),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR, RIGHT)
	planV.TextYAlignment = Enum.TextYAlignment.Center

	-- license | time remaining
	local lic = card(94, 66)
	divider(lic, UDim2.new(0.5, 0, 0, 10), UDim2.fromOffset(1, 46))

	label(lic, "License", UDim2.fromOffset(14, 9), UDim2.new(0.5, -28, 0, 12),
		Enum.Font.Gotham, 11, T.DIM_TEXT, LEFT)
	local licTitle = label(lic, "Active License", UDim2.fromOffset(14, 24), UDim2.new(0.5, -28, 0, 18),
		Enum.Font.GothamBold, 14, T.TEXT_COLOR, LEFT)
	licTitle.TextYAlignment = Enum.TextYAlignment.Center
	label(lic, "Valid until " .. INF, UDim2.fromOffset(14, 44), UDim2.new(0.5, -28, 0, 14),
		Enum.Font.Gotham, 11, T.DIM_TEXT, LEFT)

	label(lic, "Time Remaining", UDim2.new(0.5, 14, 0, 9), UDim2.new(0.5, -28, 0, 12),
		Enum.Font.Gotham, 11, T.DIM_TEXT, RIGHT)
	local timeV = label(lic, INF, UDim2.new(0.5, 14, 0, 24), UDim2.new(0.5, -28, 0, 26),
		Enum.Font.GothamBold, 20, T.TEXT_COLOR, RIGHT)
	timeV.TextYAlignment = Enum.TextYAlignment.Center

	---------------------------------------------------------------------
	-- YUR1 INFO
	---------------------------------------------------------------------
	section("yur1 info", 180)

	local info = card(206, 116)
	divider(info, UDim2.new(0.5, 0, 0, 10), UDim2.fromOffset(1, 38))
	divider(info, UDim2.fromOffset(14, 58), UDim2.new(1, -28, 0, 1))

	cell(info, 0, 0, "yur1 Version", versionText)
	cell(info, 1, 0, "yur1 Status", statusText, T.GREEN)
	cell(info, 2, 58, "Supported Games", gamesText)

	---------------------------------------------------------------------
	-- EXECUTOR INFO (detected with identifyexecutor when the executor has it)
	---------------------------------------------------------------------
	local execName = "Unknown"
	local execVersion = "Unknown"
	local okExec, nameResult, verResult = pcall(function()
		if identifyexecutor then
			return identifyexecutor()
		end
		if getexecutorname then
			return getexecutorname()
		end
		return nil
	end)
	if okExec and type(nameResult) == "string" and nameResult ~= "" then
		execName = nameResult
		if type(verResult) == "string" and verResult ~= "" then
			execVersion = verResult
		end
	end

	section("Executor info", 342)
	local exec = card(366, 58)
	divider(exec, UDim2.new(0.5, 0, 0, 10), UDim2.fromOffset(1, 38))
	cell(exec, 0, 0, "Executor", execName)
	cell(exec, 1, 0, "Version", execVersion)

	---------------------------------------------------------------------
	-- CREDITS
	---------------------------------------------------------------------
	section("Credits", 444)
	local cred = card(468, 76)

	-- text on the left
	local credText = label(cred, "<b>reruinz</b> made all of yur1 alone, for any issues dm <b>reruinz</b> on discord",
		UDim2.fromOffset(18, 10), UDim2.new(1, -206, 1, -20), Enum.Font.GothamMedium, 13, T.TEXT_COLOR, LEFT)
	credText.RichText = true
	credText.TextWrapped = true
	credText.TextTruncate = Enum.TextTruncate.None
	credText.TextYAlignment = Enum.TextYAlignment.Center

	-- Discord lockup on the right: white Clyde mark + bold "Discord" wordmark (drawn with shapes)
	local lock = new("Frame", {
		Name = "DiscordLockup",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.fromOffset(148, 36),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, cred)

	-- Discord mark: the real Discord logo shape, taken from the official outline and drawn with
	-- small frames. Each entry is { x, y, width, height, opacity in sixteenths }. Edge pixels use a
	-- lower opacity so the curves look smooth. The eyes are real holes (nothing is drawn there).
	local WHITE = Color3.new(1, 1, 1)
	local MARK_W = 32
	local MARK_H = 26
	local MARK = {
		{8,2,1,1,4}, {9,2,1,1,8}, {10,2,1,1,12}, {11,2,1,1,15}, {12,2,1,1,2}, {19,2,1,1,2},
		{20,2,1,1,14}, {21,2,1,1,12}, {22,2,1,1,8}, {23,2,1,1,4}, {5,3,1,1,2}, {6,3,1,1,8},
		{7,3,1,1,14}, {8,3,4,1,16}, {12,3,1,1,11}, {13,3,1,1,9}, {14,3,1,1,10}, {15,3,2,1,11},
		{17,3,1,1,10}, {18,3,1,1,9}, {19,3,1,1,11}, {20,3,4,1,16}, {24,3,1,1,14}, {25,3,1,1,8},
		{26,3,1,1,2}, {5,4,1,1,13}, {6,4,20,1,16}, {26,4,1,1,13}, {4,5,1,1,7}, {5,5,22,2,16},
		{27,5,1,1,7}, {3,6,1,1,1}, {4,6,1,1,15}, {27,6,1,1,15}, {28,6,1,1,1}, {3,7,1,1,8},
		{4,7,24,2,16}, {28,7,1,1,8}, {2,8,1,1,1}, {3,8,1,1,15}, {28,8,1,1,15}, {29,8,1,1,1},
		{2,9,1,1,6}, {3,9,26,2,16}, {29,9,1,1,6}, {2,10,1,1,12}, {29,10,1,1,12}, {1,11,1,1,1},
		{2,11,7,1,16}, {9,11,1,1,15}, {10,11,1,1,10}, {11,11,1,1,9}, {12,11,1,1,15}, {13,11,6,1,16},
		{19,11,1,1,15}, {20,11,2,1,10}, {22,11,1,1,15}, {23,11,7,1,16}, {30,11,1,1,1}, {1,12,1,1,6},
		{2,12,6,4,16}, {8,12,1,1,15}, {9,12,1,1,2}, {12,12,1,1,2}, {13,12,1,1,14}, {14,12,4,5,16},
		{18,12,1,1,15}, {19,12,1,1,2}, {22,12,1,1,2}, {23,12,1,1,15}, {24,12,6,5,16}, {30,12,1,1,5},
		{1,13,1,1,9}, {8,13,1,1,8}, {13,13,1,1,7}, {18,13,1,1,8}, {23,13,1,1,8}, {30,13,1,1,9},
		{1,14,1,1,12}, {8,14,1,1,5}, {13,14,1,1,4}, {18,14,1,1,4}, {23,14,1,1,5}, {30,14,1,1,12},
		{1,15,1,1,14}, {8,15,1,1,7}, {13,15,1,1,6}, {18,15,1,1,7}, {23,15,1,1,7}, {30,15,1,1,14},
		{1,16,7,1,16}, {8,16,1,1,14}, {9,16,1,1,1}, {12,16,1,1,1}, {13,16,1,1,13}, {18,16,1,1,14},
		{19,16,1,1,1}, {22,16,1,1,1}, {23,16,1,1,14}, {30,16,1,1,15}, {1,17,8,1,16}, {9,17,1,1,14},
		{10,17,2,1,7}, {12,17,1,1,14}, {13,17,6,1,16}, {19,17,1,1,14}, {20,17,2,1,7}, {22,17,1,1,14},
		{23,17,8,1,16}, {1,18,30,2,16}, {31,18,1,1,1}, {1,20,1,1,15}, {2,20,6,1,16}, {8,20,1,1,11},
		{9,20,1,1,15}, {10,20,12,1,16}, {22,20,1,1,15}, {23,20,1,1,11}, {24,20,6,1,16}, {30,20,1,1,15},
		{1,21,1,1,6}, {2,21,1,1,15}, {3,21,5,1,16}, {8,21,1,1,10}, {9,21,1,1,3}, {10,21,1,1,6},
		{11,21,1,1,10}, {12,21,1,1,14}, {13,21,6,1,16}, {19,21,1,1,15}, {20,21,1,1,10}, {21,21,1,1,6},
		{22,21,1,1,3}, {23,21,1,1,10}, {24,21,5,1,16}, {29,21,1,1,15}, {30,21,1,1,5}, {2,22,1,1,2},
		{3,22,1,1,10}, {4,22,6,1,16}, {10,22,1,1,2}, {13,22,1,1,1}, {14,22,1,1,3}, {15,22,2,1,4},
		{17,22,1,1,3}, {18,22,1,1,1}, {21,22,1,1,3}, {22,22,6,1,16}, {28,22,1,1,10}, {29,22,1,1,2},
		{4,23,1,1,3}, {5,23,1,1,10}, {6,23,3,1,16}, {9,23,1,1,11}, {22,23,1,1,11}, {23,23,3,1,16},
		{26,23,1,1,10}, {27,23,1,1,3}, {6,24,1,1,2}, {7,24,1,1,8}, {8,24,1,1,12}, {9,24,1,1,1},
		{22,24,1,1,2}, {23,24,1,1,12}, {24,24,1,1,8}, {25,24,1,1,2},
	}

	local mark = new("Frame", {
		Name = "Mark",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(MARK_W, MARK_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, lock)

	for i = 1, #MARK do
		local r = MARK[i]
		new("Frame", {
			Position = UDim2.fromOffset(r[1], r[2]),
			Size = UDim2.fromOffset(r[3], r[4]),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1 - (r[5] / 16),
			BorderSizePixel = 0,
		}, mark)
	end

	local word = label(lock, "Discord", UDim2.fromOffset(40, 0), UDim2.new(1, -40, 1, 0),
		Enum.Font.GothamBlack, 22, WHITE, LEFT)
	word.TextYAlignment = Enum.TextYAlignment.Center

	return { Root = root }
end

return InfoPage
