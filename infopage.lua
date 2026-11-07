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

	-- Discord symbol drawn with shapes: blurple tile, white face, two eyes
	local BLURPLE = Color3.fromRGB(88, 101, 242)
	local tile = new("Frame", {
		Name = "DiscordSymbol",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = BLURPLE,
		BorderSizePixel = 0,
	}, cred)
	corner(tile, 12)

	local function tileShape(x, y, w, h, r, color, rot)
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, x, 0.5, y),
			Size = UDim2.fromOffset(w, h),
			Rotation = rot or 0,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, tile)
		corner(f, r)
		return f
	end
	local WHITE = Color3.new(1, 1, 1)
	tileShape(0, 0, 28, 20, 9, WHITE)            -- face
	tileShape(-11, -9, 7, 6, 3, WHITE, -20)      -- left ear
	tileShape(11, -9, 7, 6, 3, WHITE, 20)        -- right ear
	tileShape(-5.5, 0, 4, 7, 2, BLURPLE)         -- left eye
	tileShape(5.5, 0, 4, 7, 2, BLURPLE)          -- right eye
	tileShape(0, 7, 10, 2, 1, BLURPLE)           -- small mouth

	local credText = label(cred, "<b>reruinz</b> made all of yur1 alone, for any issues dm <b>reruinz</b> on discord",
		UDim2.fromOffset(74, 10), UDim2.new(1, -90, 1, -20), Enum.Font.GothamMedium, 13, T.TEXT_COLOR, LEFT)
	credText.RichText = true
	credText.TextWrapped = true
	credText.TextTruncate = Enum.TextTruncate.None
	credText.TextYAlignment = Enum.TextYAlignment.Center

	return { Root = root }
end

return InfoPage
