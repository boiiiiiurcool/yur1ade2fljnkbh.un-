-- homepage.lua  (Y1 Home tab content, separate module)
-- ASCII only, conservative syntax (no += and no continue).
--
-- Builds the Home screen INTO a frame (the Home tab of ui.lua). It does not make its own window.
--
--   local HomePage = <this file>
--   HomePage.build(parentFrame, themeTable, helperTable, {
--       Product = "yur1",
--       Subtitle = "yur1 is built for a amazing person like you :)",
--       Access = "Lifetime access",
--       Build = "Beta 0.6",
--       Component = "Rock and Roll by reruinz",
--   })
--
-- Inside: the game name, a green "Ready" pill, "yur1 is ready", a small line of text and
-- Access / Build / Component at the bottom left. On the right a card with the game image.
-- The game image also shows very dim behind the page. Layout follows the window size.

local HomePage = {}

function HomePage.build(parent, T, H, opts)
	opts = opts or {}
	local product = opts.Product or "yur1"
	local subtitle = opts.Subtitle or "yur1 is built for a amazing person like you :)"
	local accessText = opts.Access or "Lifetime access"
	local buildText = tostring(opts.Build or "Beta 0.6")
	local componentText = tostring(opts.Component or "Rock and Roll by reruinz")

	local MarketplaceService = game:GetService("MarketplaceService")
	local new, corner, stroke, label = H.new, H.corner, H.stroke, H.label

	local CARD_S = 200
	local gameIconUrl = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=256&h=256"

	local root = new("Frame", {
		Name = "HomeRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)

	-- very dim game image on the right, with a dark fade so the left side stays clean
	local bgImage = new("ImageLabel", {
		Name = "GameBackdrop",
		Position = UDim2.fromScale(0.35, 0),
		Size = UDim2.fromScale(0.65, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = gameIconUrl,
		ScaleType = Enum.ScaleType.Crop,
		ImageTransparency = 0.78,
		ZIndex = 1,
	}, root)
	corner(bgImage, T.RADIUS)

	local fade = new("Frame", {
		Name = "BackdropFade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.BLACK,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, root)
	corner(fade, T.RADIUS)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.4, 0.1),
			NumberSequenceKeypoint.new(1, 0.55),
		}),
	}, fade)

	-- LEFT: game name, Ready pill, "<product> is ready", small text
	local leftW = UDim2.new(1, -(CARD_S + 24 + 28 + 10), 0, 30)

	local gameName = new("TextLabel", {
		Name = "GameName",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 16),
		Size = leftW,
		Font = Enum.Font.GothamBlack,
		Text = game.Name,
		TextSize = 22,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	}, root)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 250, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 128, 138)),
		}),
	}, gameName)

	-- the real game name comes from the marketplace (background)
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(game.PlaceId)
		end)
		if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
			if gameName.Parent then
				gameName.Text = info.Name
			end
		end
	end)

	local pill = new("Frame", {
		Name = "ReadyPill",
		Position = UDim2.fromOffset(26, 52),
		Size = UDim2.fromOffset(50, 20),
		BackgroundColor3 = Color3.fromRGB(22, 52, 38),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)
	corner(pill, 10)
	stroke(pill, Color3.fromRGB(36, 92, 62), 1, 0)
	local pillText = label(pill, "Ready", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1),
		Enum.Font.GothamBold, 11, T.GREEN, Enum.TextXAlignment.Center)
	pillText.ZIndex = 4

	local ready = label(root, product .. " is ready", UDim2.fromOffset(24, 84),
		UDim2.new(1, -(CARD_S + 24 + 28 + 10), 0, 36), Enum.Font.GothamBold, 28, T.TEXT_COLOR)
	ready.ZIndex = 3

	local sub = label(root, subtitle, UDim2.fromOffset(24, 124),
		UDim2.new(1, -(CARD_S + 24 + 28 + 10), 0, 34), Enum.Font.Gotham, 12, T.DIM_TEXT)
	sub.TextWrapped = true
	sub.TextTruncate = Enum.TextTruncate.None
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.ZIndex = 3

	-- BOTTOM LEFT: Access / Build / Component
	local stats = new("Frame", {
		Name = "Stats",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -16),
		Size = UDim2.new(1, -48, 0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)

	local function stat(x, caption, value, w)
		local c = label(stats, caption, UDim2.fromOffset(x, 0), UDim2.fromOffset(w, 14),
			Enum.Font.Gotham, 10, T.DIM_TEXT)
		c.ZIndex = 3
		local v = label(stats, value, UDim2.fromOffset(x, 18), UDim2.fromOffset(w, 18),
			Enum.Font.GothamBold, 12, T.TEXT_COLOR)
		v.ZIndex = 3
	end
	stat(0, "Access", accessText, 130)
	stat(150, "Build", buildText, 100)
	stat(270, "Component", componentText, 200)

	-- RIGHT: the game image card
	local card = new("Frame", {
		Name = "GameCard",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -28, 0.5, -14),
		Size = UDim2.fromOffset(CARD_S, CARD_S),
		BackgroundColor3 = T.SIDEBAR_BG,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, root)
	corner(card, 16)
	stroke(card, T.BORDER, 1, 0)

	local cardImage = new("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = T.CARD_BG,
		BorderSizePixel = 0,
		Image = gameIconUrl,
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 4,
	}, card)
	corner(cardImage, 16)

	return { Root = root }
end

return HomePage
