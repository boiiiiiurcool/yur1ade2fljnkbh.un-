-- infopage.lua  (Y1 Info tab content, separate module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Info tab INTO a frame (the Info page of ui.lua):
--   OVERVIEW : account (profile picture + username) and plan, license + time remaining
--   YUR1 INFO: yur1 version, yur1 status, supported games
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

	local root = new("Frame", {
		Name = "InfoRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
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

	return { Root = root }
end

return InfoPage
