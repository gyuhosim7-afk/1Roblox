--!strict
-- Every tunable number in the game lives here: prices, odds, rewards, timings, map sizes.
-- Pure data only (no Roblox types) so it can be unit-tested outside Roblox.

local Config = {}

Config.GameName = "Steal a Slime [+1 SPEED]"
Config.Version = "1.0.0"
Config.MaxPlayers = 8

--------------------------------------------------------------------------------
-- Speed (the "+1 every second" stat)
--------------------------------------------------------------------------------
Config.Speed = {
	BaseGainPerSecond = 1, -- everyone gets +1 speed per second
	TrainingGainPerLevel = 1, -- each Speed Training level adds this much per second
	WalkBase = 16, -- real WalkSpeed = WalkBase + WalkFactor * Speed ^ WalkExponent (capped)
	WalkFactor = 6,
	WalkExponent = 0.3,
	WalkMax = 300,
	TickSeconds = 1,
}

--------------------------------------------------------------------------------
-- Coin upgrades. cost(level) = Base * Growth ^ level  (level = current level)
--------------------------------------------------------------------------------
Config.Upgrades = {
	Training = {
		Name = "Speed Training",
		Description = "+1 Speed every second",
		Base = 40,
		Growth = 1.5,
		MaxLevel = 150,
	},
	Pedestals = {
		Name = "More Pedestals",
		Description = "+1 slime earning coins",
		Start = 6,
		Base = 150,
		Growth = 2.05,
		MaxLevel = 18, -- 6 -> 24 pedestals
	},
	Incubators = {
		Name = "More Incubators",
		Description = "+1 egg hatching at once",
		Start = 2,
		Base = 750,
		Growth = 9,
		MaxLevel = 4, -- 2 -> 6 incubators (+2 with game pass)
	},
	Lock = {
		Name = "Longer Base Lock",
		Description = "+15 seconds of lock time",
		Base = 2500,
		Growth = 8,
		MaxLevel = 4,
	},
}

Config.UpgradeOrder = { "Training", "Pedestals", "Incubators", "Lock" }

--------------------------------------------------------------------------------
-- Rebirth: resets Speed, Coins and Speed Training. Keeps slimes, base upgrades, gems.
-- requirement(r) = Base * Growth ^ r   (r = current rebirths)
--------------------------------------------------------------------------------
Config.Rebirth = {
	SpeedBase = 25000,
	SpeedGrowth = 3,
	CoinBase = 50000000,
	CoinGrowth = 10,
	SpeedBonusPerRebirth = 0.5, -- +50% speed gain per rebirth
	CoinBonusPerRebirth = 0.25, -- +25% coins per rebirth
	GemReward = 50,
}

--------------------------------------------------------------------------------
-- Rarities and mutations
--------------------------------------------------------------------------------
Config.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

Config.Rarities = {
	Common = { Order = 1, Color = "#C8CDD2", DiscoveryGems = 2 },
	Uncommon = { Order = 2, Color = "#5BD45B", DiscoveryGems = 5 },
	Rare = { Order = 3, Color = "#4DA6FF", DiscoveryGems = 10 },
	Epic = { Order = 4, Color = "#B266FF", DiscoveryGems = 25 },
	Legendary = { Order = 5, Color = "#FFB000", DiscoveryGems = 75 },
	Mythic = { Order = 6, Color = "#FF4FA3", DiscoveryGems = 200 },
}

Config.MutationOrder = { "None", "Gold", "Rainbow" }

Config.Mutations = {
	None = { Name = "Normal", Multiplier = 1, BaseChance = 0 }, -- chance = whatever is left
	Gold = { Name = "Golden", Multiplier = 2, BaseChance = 0.04 },
	Rainbow = { Name = "Rainbow", Multiplier = 5, BaseChance = 0.01 },
}

--------------------------------------------------------------------------------
-- Luck. Luck multiplies the weight of every slime at or above LuckMinRarity,
-- and multiplies mutation chances. Odds shown to players always include luck.
--------------------------------------------------------------------------------
Config.Luck = {
	MinRarityOrder = 3, -- Rare and above
	PassMultiplier = 1.5, -- "Lucky" game pass
	PotionMultiplier = 2, -- Luck Potion
	ServerMultiplier = 2, -- Server Luck product
	RoyalEggMultiplier = 2, -- extra luck inside the Royal Egg
	MaxMutationTotal = 0.5, -- Gold + Rainbow chance never exceeds 50%
}

--------------------------------------------------------------------------------
-- Slimes. Income is coins per second while on a pedestal. Color is a hex string.
-- Accessories are built in code by SlimeBuilder.
--------------------------------------------------------------------------------
export type SlimeDef = {
	Name: string,
	Rarity: string,
	Income: number,
	Color: string,
	Accessory: { string }?,
	Material: string?,
	Size: number?,
	Glow: boolean?,
	Sparkles: boolean?,
}

Config.Slimes = {
	-- Meadow
	BlueSlime = { Name = "Blue Slime", Rarity = "Common", Income = 2, Color = "#4DA6FF" },
	GreenSlime = { Name = "Green Slime", Rarity = "Common", Income = 3, Color = "#5BD45B" },
	PinkSlime = { Name = "Pink Slime", Rarity = "Uncommon", Income = 6, Color = "#FF8AD8", Accessory = { "Ears" } },
	FlowerSlime = { Name = "Flower Slime", Rarity = "Rare", Income = 15, Color = "#FFE066", Accessory = { "Flower" } },
	SunnySlime = {
		Name = "Sunny Slime",
		Rarity = "Epic",
		Income = 40,
		Color = "#FFB000",
		Accessory = { "Star" },
		Glow = true,
	},
	-- Forest
	LeafSlime = { Name = "Leaf Slime", Rarity = "Common", Income = 12, Color = "#6BBF59", Accessory = { "Leaf" } },
	MushroomSlime = {
		Name = "Mushroom Slime",
		Rarity = "Common",
		Income = 18,
		Color = "#F1E3C8",
		Accessory = { "Cap" },
	},
	MossSlime = { Name = "Moss Slime", Rarity = "Uncommon", Income = 35, Color = "#4E7D3A", Accessory = { "Spikes" } },
	OwlSlime = { Name = "Owl Slime", Rarity = "Rare", Income = 90, Color = "#8B6B4A", Accessory = { "Ears" } },
	FairySlime = {
		Name = "Fairy Slime",
		Rarity = "Epic",
		Income = 250,
		Color = "#E0A3FF",
		Accessory = { "Wings" },
		Glow = true,
	},
	TreantSlime = {
		Name = "Ancient Treant Slime",
		Rarity = "Legendary",
		Income = 900,
		Color = "#3E6B2E",
		Accessory = { "Horns", "Leaf" },
		Size = 1.3,
		Sparkles = true,
	},
	-- Desert
	SandSlime = { Name = "Sand Slime", Rarity = "Common", Income = 80, Color = "#E6C48A" },
	CactusSlime = {
		Name = "Cactus Slime",
		Rarity = "Common",
		Income = 120,
		Color = "#3FA34D",
		Accessory = { "Spikes" },
	},
	ScarabSlime = {
		Name = "Scarab Slime",
		Rarity = "Uncommon",
		Income = 250,
		Color = "#1F7A8C",
		Accessory = { "Antenna" },
	},
	MummySlime = { Name = "Mummy Slime", Rarity = "Rare", Income = 650, Color = "#EDE6D6", Accessory = { "Bandage" } },
	PharaohSlime = {
		Name = "Pharaoh Slime",
		Rarity = "Epic",
		Income = 1800,
		Color = "#F4C430",
		Accessory = { "Crown" },
		Glow = true,
	},
	SphinxSlime = {
		Name = "Sphinx Slime",
		Rarity = "Legendary",
		Income = 7000,
		Color = "#D4A44C",
		Accessory = { "Ears", "Crown" },
		Size = 1.3,
		Sparkles = true,
	},
	-- Snow
	SnowballSlime = { Name = "Snowball Slime", Rarity = "Common", Income = 600, Color = "#F2F7FF" },
	PenguinSlime = {
		Name = "Penguin Slime",
		Rarity = "Common",
		Income = 900,
		Color = "#2C3E50",
		Accessory = { "Belly" },
	},
	YetiSlime = { Name = "Yeti Slime", Rarity = "Uncommon", Income = 1900, Color = "#DDE8F0", Accessory = { "Horns" } },
	IceCrystalSlime = {
		Name = "Ice Crystal Slime",
		Rarity = "Rare",
		Income = 5000,
		Color = "#9BE7FF",
		Accessory = { "Spikes" },
		Material = "Glass",
	},
	FrostQueenSlime = {
		Name = "Frost Queen Slime",
		Rarity = "Epic",
		Income = 14000,
		Color = "#B3E5FC",
		Accessory = { "Crown" },
		Glow = true,
	},
	MammothSlime = {
		Name = "Mammoth Slime",
		Rarity = "Legendary",
		Income = 55000,
		Color = "#8D6E63",
		Accessory = { "Tusks", "Ears" },
		Size = 1.35,
		Sparkles = true,
	},
	-- Volcano
	EmberSlime = { Name = "Ember Slime", Rarity = "Common", Income = 4500, Color = "#FF7043" },
	LavaSlime = { Name = "Lava Slime", Rarity = "Common", Income = 7000, Color = "#FF3D00", Material = "Neon" },
	ObsidianSlime = {
		Name = "Obsidian Slime",
		Rarity = "Uncommon",
		Income = 15000,
		Color = "#2B2133",
		Accessory = { "Spikes" },
	},
	PhoenixSlime = {
		Name = "Phoenix Slime",
		Rarity = "Rare",
		Income = 40000,
		Color = "#FF9800",
		Accessory = { "Wings" },
	},
	DragonSlime = {
		Name = "Dragon Slime",
		Rarity = "Epic",
		Income = 110000,
		Color = "#C62828",
		Accessory = { "Horns", "Wings" },
		Glow = true,
	},
	InfernoKingSlime = {
		Name = "Inferno King Slime",
		Rarity = "Legendary",
		Income = 450000,
		Color = "#FF1744",
		Accessory = { "Crown", "Horns" },
		Size = 1.4,
		Sparkles = true,
		Glow = true,
	},
	-- Crystal Cave
	QuartzSlime = { Name = "Quartz Slime", Rarity = "Common", Income = 35000, Color = "#F8F8FF", Material = "Glass" },
	AmethystSlime = { Name = "Amethyst Slime", Rarity = "Common", Income = 55000, Color = "#9B59B6" },
	GeodeSlime = {
		Name = "Geode Slime",
		Rarity = "Uncommon",
		Income = 120000,
		Color = "#7E57C2",
		Accessory = { "Spikes" },
	},
	PrismSlime = { Name = "Prism Slime", Rarity = "Rare", Income = 320000, Color = "#80DEEA", Accessory = { "Star" } },
	DiamondSlime = {
		Name = "Diamond Slime",
		Rarity = "Epic",
		Income = 900000,
		Color = "#E0F7FA",
		Accessory = { "Crown" },
		Material = "Glass",
		Glow = true,
	},
	CrystalTitanSlime = {
		Name = "Crystal Titan Slime",
		Rarity = "Legendary",
		Income = 3500000,
		Color = "#BA68C8",
		Accessory = { "Horns", "Halo" },
		Size = 1.45,
		Sparkles = true,
	},
	StarlightSlime = {
		Name = "Starlight Slime",
		Rarity = "Mythic",
		Income = 12000000,
		Color = "#FFF59D",
		Accessory = { "Halo", "Wings" },
		Size = 1.5,
		Sparkles = true,
		Glow = true,
	},
	-- Void
	ShadowSlime = { Name = "Shadow Slime", Rarity = "Common", Income = 300000, Color = "#263238" },
	NebulaSlime = { Name = "Nebula Slime", Rarity = "Common", Income = 480000, Color = "#5E35B1" },
	CometSlime = {
		Name = "Comet Slime",
		Rarity = "Uncommon",
		Income = 1000000,
		Color = "#4FC3F7",
		Accessory = { "Antenna" },
	},
	BlackHoleSlime = {
		Name = "Black Hole Slime",
		Rarity = "Rare",
		Income = 2800000,
		Color = "#0D0D0D",
		Accessory = { "Ring" },
	},
	GalaxySlime = {
		Name = "Galaxy Slime",
		Rarity = "Epic",
		Income = 8000000,
		Color = "#7C4DFF",
		Accessory = { "Ring" },
		Glow = true,
	},
	CosmicOverlordSlime = {
		Name = "Cosmic Overlord Slime",
		Rarity = "Legendary",
		Income = 30000000,
		Color = "#D500F9",
		Accessory = { "Crown", "Ring" },
		Size = 1.5,
		Sparkles = true,
	},
	CelestialSlime = {
		Name = "Celestial Slime",
		Rarity = "Mythic",
		Income = 100000000,
		Color = "#FFFFFF",
		Accessory = { "Halo", "Wings", "Star" },
		Size = 1.6,
		Sparkles = true,
		Glow = true,
	},
} :: { [string]: SlimeDef }

--------------------------------------------------------------------------------
-- Eggs. Pool weights are relative (they are normalised to 100%).
-- HoldSeconds: how long to hold the steal prompt. CarryMultiplier: walk speed while carrying.
--------------------------------------------------------------------------------
export type EggPoolEntry = { Slime: string, Weight: number }
export type EggDef = {
	Name: string,
	Zone: number,
	HatchSeconds: number,
	CarryMultiplier: number,
	HoldSeconds: number,
	Color: string,
	SpotColor: string,
	Pool: { EggPoolEntry },
}

Config.EggOrder = { "Meadow", "Forest", "Desert", "Snow", "Magma", "Crystal", "Void" }

Config.Eggs = {
	Meadow = {
		Name = "Meadow Egg",
		Zone = 1,
		HatchSeconds = 10,
		CarryMultiplier = 0.85,
		HoldSeconds = 0.4,
		Color = "#B8F2A0",
		SpotColor = "#5BD45B",
		Pool = {
			{ Slime = "BlueSlime", Weight = 60 },
			{ Slime = "GreenSlime", Weight = 25 },
			{ Slime = "PinkSlime", Weight = 10 },
			{ Slime = "FlowerSlime", Weight = 4 },
			{ Slime = "SunnySlime", Weight = 1 },
		},
	},
	Forest = {
		Name = "Forest Egg",
		Zone = 2,
		HatchSeconds = 30,
		CarryMultiplier = 0.8,
		HoldSeconds = 0.6,
		Color = "#7BC86C",
		SpotColor = "#3E6B2E",
		Pool = {
			{ Slime = "LeafSlime", Weight = 55 },
			{ Slime = "MushroomSlime", Weight = 25 },
			{ Slime = "MossSlime", Weight = 12 },
			{ Slime = "OwlSlime", Weight = 6 },
			{ Slime = "FairySlime", Weight = 1.8 },
			{ Slime = "TreantSlime", Weight = 0.2 },
		},
	},
	Desert = {
		Name = "Desert Egg",
		Zone = 3,
		HatchSeconds = 60,
		CarryMultiplier = 0.75,
		HoldSeconds = 0.8,
		Color = "#F2D49B",
		SpotColor = "#C9932E",
		Pool = {
			{ Slime = "SandSlime", Weight = 55 },
			{ Slime = "CactusSlime", Weight = 25 },
			{ Slime = "ScarabSlime", Weight = 12 },
			{ Slime = "MummySlime", Weight = 6 },
			{ Slime = "PharaohSlime", Weight = 1.8 },
			{ Slime = "SphinxSlime", Weight = 0.2 },
		},
	},
	Snow = {
		Name = "Snow Egg",
		Zone = 4,
		HatchSeconds = 120,
		CarryMultiplier = 0.7,
		HoldSeconds = 1,
		Color = "#EAF6FF",
		SpotColor = "#7FC8F8",
		Pool = {
			{ Slime = "SnowballSlime", Weight = 55 },
			{ Slime = "PenguinSlime", Weight = 25 },
			{ Slime = "YetiSlime", Weight = 12 },
			{ Slime = "IceCrystalSlime", Weight = 6 },
			{ Slime = "FrostQueenSlime", Weight = 1.8 },
			{ Slime = "MammothSlime", Weight = 0.2 },
		},
	},
	Magma = {
		Name = "Magma Egg",
		Zone = 5,
		HatchSeconds = 240,
		CarryMultiplier = 0.65,
		HoldSeconds = 1.2,
		Color = "#3B2A2A",
		SpotColor = "#FF5722",
		Pool = {
			{ Slime = "EmberSlime", Weight = 55 },
			{ Slime = "LavaSlime", Weight = 25 },
			{ Slime = "ObsidianSlime", Weight = 12 },
			{ Slime = "PhoenixSlime", Weight = 6 },
			{ Slime = "DragonSlime", Weight = 1.8 },
			{ Slime = "InfernoKingSlime", Weight = 0.2 },
		},
	},
	Crystal = {
		Name = "Crystal Egg",
		Zone = 6,
		HatchSeconds = 420,
		CarryMultiplier = 0.6,
		HoldSeconds = 1.4,
		Color = "#D9C2F0",
		SpotColor = "#8E44AD",
		Pool = {
			{ Slime = "QuartzSlime", Weight = 55 },
			{ Slime = "AmethystSlime", Weight = 25 },
			{ Slime = "GeodeSlime", Weight = 12 },
			{ Slime = "PrismSlime", Weight = 6 },
			{ Slime = "DiamondSlime", Weight = 1.8 },
			{ Slime = "CrystalTitanSlime", Weight = 0.15 },
			{ Slime = "StarlightSlime", Weight = 0.05 },
		},
	},
	Void = {
		Name = "Void Egg",
		Zone = 7,
		HatchSeconds = 600,
		CarryMultiplier = 0.55,
		HoldSeconds = 1.6,
		Color = "#1A1033",
		SpotColor = "#B388FF",
		Pool = {
			{ Slime = "ShadowSlime", Weight = 55 },
			{ Slime = "NebulaSlime", Weight = 25 },
			{ Slime = "CometSlime", Weight = 12 },
			{ Slime = "BlackHoleSlime", Weight = 6 },
			{ Slime = "GalaxySlime", Weight = 1.8 },
			{ Slime = "CosmicOverlordSlime", Weight = 0.15 },
			{ Slime = "CelestialSlime", Weight = 0.05 },
		},
	},
} :: { [string]: EggDef }

-- Royal Egg: bought with Robux or gems. Hatches instantly. Pool = the player's best unlocked zone's egg,
-- only slimes of RoyalMinRarityOrder or better, with extra luck (Config.Luck.RoyalEggMultiplier).
Config.RoyalEgg = {
	Name = "Royal Egg",
	MinRarityOrder = 3, -- Rare or better guaranteed
	MutationLuckBonus = 2, -- mutation chances x2 inside the Royal Egg
	Color = "#FFD54F",
	SpotColor = "#FF4FA3",
}

--------------------------------------------------------------------------------
-- Zones (in order along the runway). GateSpeed = Speed needed to pass the gate.
-- Guards only hit players who are carrying an egg.
--------------------------------------------------------------------------------
export type ZoneDef = {
	Id: string,
	Name: string,
	Egg: string,
	GateSpeed: number,
	RebirthsRequired: number,
	Length: number,
	GroundColor: string,
	AccentColor: string,
	Decor: string,
	Nests: number,
	PatrolGuards: number,
	SweeperGuards: number,
	GuardRadius: number,
	GuardPeriod: number, -- seconds for one full patrol / rotation (lower = faster)
}

Config.Zones = {
	{
		Id = "Meadow",
		Name = "Meadow",
		Egg = "Meadow",
		GateSpeed = 0,
		RebirthsRequired = 0,
		Length = 240,
		GroundColor = "#7CCB5B",
		AccentColor = "#B8F2A0",
		Decor = "Meadow",
		Nests = 6,
		PatrolGuards = 2,
		SweeperGuards = 0,
		GuardRadius = 4,
		GuardPeriod = 7,
	},
	{
		Id = "Forest",
		Name = "Forest",
		Egg = "Forest",
		GateSpeed = 100,
		RebirthsRequired = 0,
		Length = 320,
		GroundColor = "#3F7D3A",
		AccentColor = "#7BC86C",
		Decor = "Forest",
		Nests = 6,
		PatrolGuards = 3,
		SweeperGuards = 0,
		GuardRadius = 4.5,
		GuardPeriod = 6,
	},
	{
		Id = "Desert",
		Name = "Desert",
		Egg = "Desert",
		GateSpeed = 1000,
		RebirthsRequired = 0,
		Length = 480,
		GroundColor = "#E3C27D",
		AccentColor = "#F2D49B",
		Decor = "Desert",
		Nests = 6,
		PatrolGuards = 4,
		SweeperGuards = 1,
		GuardRadius = 5,
		GuardPeriod = 5.5,
	},
	{
		Id = "Snow",
		Name = "Snowy Peaks",
		Egg = "Snow",
		GateSpeed = 5000,
		RebirthsRequired = 0,
		Length = 640,
		GroundColor = "#EEF5FB",
		AccentColor = "#9BD3F5",
		Decor = "Snow",
		Nests = 6,
		PatrolGuards = 5,
		SweeperGuards = 2,
		GuardRadius = 5.5,
		GuardPeriod = 5,
	},
	{
		Id = "Volcano",
		Name = "Volcano",
		Egg = "Magma",
		GateSpeed = 25000,
		RebirthsRequired = 0,
		Length = 800,
		GroundColor = "#3A2E2E",
		AccentColor = "#FF5722",
		Decor = "Volcano",
		Nests = 6,
		PatrolGuards = 6,
		SweeperGuards = 2,
		GuardRadius = 6,
		GuardPeriod = 4.5,
	},
	{
		Id = "Crystal",
		Name = "Crystal Cave",
		Egg = "Crystal",
		GateSpeed = 400000,
		RebirthsRequired = 0,
		Length = 960,
		GroundColor = "#4A3B63",
		AccentColor = "#CE93D8",
		Decor = "Crystal",
		Nests = 6,
		PatrolGuards = 7,
		SweeperGuards = 3,
		GuardRadius = 6.5,
		GuardPeriod = 4,
	},
	{
		Id = "Void",
		Name = "The Void",
		Egg = "Void",
		GateSpeed = 5000000,
		RebirthsRequired = 3,
		Length = 1120,
		GroundColor = "#140C24",
		AccentColor = "#B388FF",
		Decor = "Void",
		Nests = 6,
		PatrolGuards = 8,
		SweeperGuards = 4,
		GuardRadius = 7,
		GuardPeriod = 3.6,
	},
} :: { ZoneDef }

--------------------------------------------------------------------------------
-- Map geometry (studs). The runway runs along +Z. Plots line both sides behind z = 0.
--------------------------------------------------------------------------------
Config.Map = {
	RoadWidth = 60,
	RoadWallHeight = 60,
	GateGap = 40, -- space between zones where the gate stands
	FirstZoneStart = 40,
	PlotSize = 56,
	PlotWallHeight = 6,
	PlotColumnsX = 64, -- plot centers at x = +-64
	PlotZ = { -40, -100, -160, -220 }, -- plot centers along z (per side)
	SpawnZ = -130,
	ZoneSideWidth = 120, -- decorative ground beyond the road on each side
	NestRespawnSeconds = 3,
}

--------------------------------------------------------------------------------
-- Base / plot
--------------------------------------------------------------------------------
Config.Base = {
	LockBaseSeconds = 45,
	LockPerLevelSeconds = 15,
	VipLockBonusSeconds = 60,
	MaxSlimes = 100, -- total slimes a player can own (pedestals + storage)
	SellSeconds = 20, -- selling a slime gives this many seconds of its income
}

--------------------------------------------------------------------------------
-- Stealing / bonk
--------------------------------------------------------------------------------
Config.Steal = {
	StealHoldSeconds = 1.5, -- steal from another player's incubator
	BonkCooldown = 1.2,
	BonkRange = 11,
	KnockbackSpeed = 70,
	GuardKnockbackSpeed = 90,
	StunSeconds = 0.6,
	TeleportSlack = 25, -- studs/second allowed above walk speed before "too fast" drops the egg
	NewPlayerProtectionSeconds = 300, -- first 5 minutes of a brand-new player: eggs can't be stolen
}

--------------------------------------------------------------------------------
-- Potions and boosts
--------------------------------------------------------------------------------
Config.Boosts = {
	PotionSeconds = 900, -- 15 minutes per potion (stacks by adding time)
	MaxPotionSeconds = 7200, -- at most 2 hours stored
	ServerLuckSeconds = 900,
	MaxServerLuckSeconds = 7200,
	SpeedPotionMultiplier = 2,
	CoinPassMultiplier = 2,
	SpeedPassMultiplier = 2,
	VipCoinMultiplier = 1.2,
}

--------------------------------------------------------------------------------
-- Gem shop (spend free/paid gems)
--------------------------------------------------------------------------------
Config.GemShop = {
	LuckPotion = 60,
	SpeedPotion = 40,
	RoyalEgg = 150,
	SkipSecondsPerGem = 10, -- skip hatch: 1 gem per 10 seconds remaining (min 1)
}

--------------------------------------------------------------------------------
-- Free rewards (keep non-paying players progressing)
--------------------------------------------------------------------------------
Config.Rewards = {
	DailyGems = { 10, 15, 20, 30, 40, 50, 100 }, -- 7-day streak cycle
	PlaytimeGiftSeconds = 600, -- every 10 minutes online
	PlaytimeGiftGems = 10,
	OfflineRate = 0.25, -- 25% of income while offline
	VipOfflineRate = 0.5,
	OfflineMaxSeconds = 10800, -- 3 hours
	OfflineMinSeconds = 60,
}

--------------------------------------------------------------------------------
-- Monetization. Set Id to the real asset id after creating the pass/product on the Creator Hub.
-- Id = 0 means "not created yet": in Studio the purchase is simulated, live servers show "coming soon".
-- Price is only shown in UI; Roblox charges the price set on the Creator Hub.
--------------------------------------------------------------------------------
Config.Passes = {
	DoubleCoins = { Id = 0, Price = 249, Name = "2x Coins", Description = "Earn double coins forever." },
	DoubleSpeed = { Id = 0, Price = 199, Name = "2x Speed", Description = "Gain double Speed every second." },
	AutoCollect = { Id = 0, Price = 99, Name = "Auto Collect", Description = "Coins go straight to your wallet." },
	ExtraIncubators = { Id = 0, Price = 149, Name = "+2 Incubators", Description = "Hatch 2 more eggs at once." },
	VIP = {
		Id = 0,
		Price = 299,
		Name = "VIP",
		Description = "+20% coins, +60s base lock, 50% offline earnings, VIP chat tag.",
	},
	Lucky = {
		Id = 0,
		Price = 349,
		Name = "Lucky",
		Description = "Permanent Luck x1.5: Rare+ slimes and mutations are 1.5x more likely. Check the odds in the Index.",
		RandomItemModifier = true,
	},
}

Config.PassOrder = { "DoubleCoins", "DoubleSpeed", "AutoCollect", "ExtraIncubators", "VIP", "Lucky" }

Config.ExtraIncubatorsFromPass = 2

Config.Products = {
	Gems100 = { Id = 0, Price = 49, Name = "100 Gems", Gems = 100 },
	Gems350 = { Id = 0, Price = 149, Name = "350 Gems", Gems = 350 },
	Gems1000 = { Id = 0, Price = 399, Name = "1,000 Gems", Gems = 1000 },
	Gems2800 = { Id = 0, Price = 999, Name = "2,800 Gems", Gems = 2800 },
	LuckPotion = {
		Id = 0,
		Price = 79,
		Name = "Luck Potion",
		Description = "Luck x2 for 15 minutes (Rare+ slimes and mutations 2x more likely).",
		RandomItemModifier = true,
		FallbackGems = 100, -- restricted players get gems instead
	},
	SpeedPotion = { Id = 0, Price = 49, Name = "Speed Potion", Description = "Speed gain x2 for 15 minutes." },
	RoyalEgg = {
		Id = 0,
		Price = 99,
		Name = "Royal Egg",
		Description = "Instantly hatch a Rare-or-better slime from your best zone.",
		RandomItem = true,
		FallbackGems = 150, -- if a restricted player somehow buys it, they get gems instead
	},
	ServerLuck = {
		Id = 0,
		Price = 199,
		Name = "Server Luck",
		Description = "Luck x2 for EVERYONE in this server for 15 minutes.",
		RandomItemModifier = true,
		FallbackGems = 300,
	},
	CashSmall = { Id = 0, Price = 49, Name = "Cash Pack", CashSeconds = 900, MinCoins = 1000 },
	CashLarge = { Id = 0, Price = 149, Name = "Big Cash Pack", CashSeconds = 3600, MinCoins = 5000 },
	InstantHatch = { Id = 0, Price = 25, Name = "Instant Hatch", Description = "Hatch all your eggs right now." },
}

Config.ProductOrder = {
	"Gems100",
	"Gems350",
	"Gems1000",
	"Gems2800",
	"LuckPotion",
	"SpeedPotion",
	"RoyalEgg",
	"ServerLuck",
	"CashSmall",
	"CashLarge",
	"InstantHatch",
}

Config.Monetization = {
	StudioSimulatePurchases = true, -- in Studio only: Id = 0 purchases are simulated through the real grant code
	MaxStoredPurchaseIds = 100,
}

--------------------------------------------------------------------------------
-- Data / networking
--------------------------------------------------------------------------------
Config.Data = {
	StoreName = "StealASlime_PlayerData_v1",
	KeyPrefix = "Player_",
	AutosaveSeconds = 60,
	MaxRetries = 6,
	RetryBaseSeconds = 1, -- exponential backoff: 1, 2, 4, 8 ...
	SessionLockSeconds = 1800, -- a lock older than this is considered dead
	LockWaitAttempts = 5, -- how many times to wait for another server to release the lock
	LockWaitSeconds = 6,
}

Config.Network = {
	RequestBurst = 20,
	RequestsPerSecond = 10,
	SyncInterval = 0.25,
}

Config.Tutorial = {
	Steps = {
		"Run to the Meadow and steal an egg!",
		"Bring the egg back to your base!",
		"Wait for your egg to hatch.",
		"Step on the green pad to collect coins.",
		"Buy Speed Training in Upgrades!",
	},
}

return Config
