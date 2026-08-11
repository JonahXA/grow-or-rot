--!strict
--[[
	Config — every tunable and every Roblox asset ID lives here.

	IMPORTANT: the IDs below are placeholders (0). Monetization is inert until you
	fill them in. See docs/SETUP.md step 4 for where to get each ID.
]]

local Config = {}

-- ============================================================
-- Identity
-- ============================================================

Config.GameName = "GrowOrRot"

-- Bump this when you change the shape of saved player data. Any profile with an
-- older version runs through DataService's migration path on load.
Config.DataVersion = 1

-- DataStore name. Changing this orphans all existing player data, which is
-- exactly what you want when resetting a test. Add a suffix like "_test2".
--
-- Deliberately namespaced per game. DataStores are scoped to the experience, but
-- keeping the name distinct from phase0's means a place misconfiguration can't
-- quietly read or write the other project's profiles.
--
-- There is deliberately no separate receipt store: purchase receipts are
-- recorded inside the player profile so that granting and marking are a single
-- atomic write. See MonetizationService.
Config.PlayerDataStore = "GrowOrRot_PlayerData_v1"

-- ============================================================
-- Monetization — FILL THESE IN
--
-- Zeroed deliberately. The previous values belonged to the phase0 EXP1
-- experience (universe 10673593342); a pass or product ID only works inside the
-- experience that owns it, and cross-experience sales were disabled platform-wide
-- in May 2026. These must be recreated against this game's own universe.
--
-- Monetization is inert while these are 0, and logs a warning rather than
-- failing — so the game is fully playable before they exist.
--
-- Price them at 1 Robux for self-testing and leave Managed Pricing OFF, so
-- regional price optimization can't make purchase tests non-deterministic.
-- ============================================================

Config.GamePasses = {
	-- One free save when a crop would rot.
	RotInsurance = 0, -- TODO
	-- Raises mutation chance on every push tick.
	SeedLuck = 0, -- TODO
	-- Lets pushing continue offline up to a player-set threshold.
	AutoHarvest = 0, -- TODO
}

Config.DeveloperProducts = {
	ExtraPlot = 0, -- TODO
	CoinsSmall = 0, -- TODO
	InstantGrow = 0, -- TODO
}

-- How many coins each developer product grants. Keyed by the same names above.
-- Only coin products belong here; ExtraPlot and InstantGrow grant something other
-- than currency and get their own handling when the grow systems land.
Config.ProductGrants = {
	CoinsSmall = 100,
}

-- ============================================================
-- Economy
-- ============================================================

Config.Economy = {
	StartingCoins = 0,

	-- Server-side rate limit shared by every gameplay remote. A hooked client can
	-- fire these thousands of times a second; without a floor that is a free
	-- action printer.
	ActionCooldownSeconds = 0.2,

	-- Rejected actions past this count in one session log a suspicion event.
	-- Not a ban — a signal that something is scripted.
	SuspiciousRejectThreshold = 200,
}

-- ============================================================
-- Grow — the core loop. Every number here is a tuning target, not a truth.
--
-- The design goal is that the optimal harvest point is NON-OBVIOUS and moves
-- with weather and seed. If players work out "always harvest at tick 4" then the
-- decision is dead and so is the game. Watch stats.totalRotted against retention.
-- ============================================================

Config.Grow = {
	StartingPlots = 2,
	MaxPlots = 12,

	-- Seconds between push rolls once a crop is ripe.
	PushTickSeconds = 10,

	-- Rot chance on the first push tick, and how much it climbs per tick. This
	-- rising pressure is what makes the decision tighten rather than stay flat.
	RotChanceBase = 0.08,
	RotChancePerTick = 0.02,

	-- Hard ceiling so a very lucky run still ends. Without this the tail is
	-- unbounded and one player can hold a crop forever.
	RotChanceMax = 0.75,

	-- Each mutation multiplies crop value. Stacks multiplicatively, so the
	-- payoff curve is exponential while the risk curve is linear — that gap is
	-- the whole reason pushing is tempting.
	MutationMultiplier = 1.5,

	-- Cosmetic tiers, purely for readout and bragging. Index = mutation count.
	MutationNames = { "Lush", "Golden", "Prismatic", "Radiant", "Mythic" },
}

-- Seed types. `growTime` is seconds from planting to ripe; growth continues
-- while the player is offline, but pushing does not — see PlotService.
Config.Seeds = {
	basic = {
		displayName = "Basic Seed",
		growTime = 60,
		baseValue = 10,
		mutationChance = 0.15,
		cost = 0, -- always available
	},
	swift = {
		displayName = "Swift Seed",
		growTime = 30,
		baseValue = 8,
		mutationChance = 0.12,
		cost = 50,
	},
	volatile = {
		displayName = "Volatile Seed",
		growTime = 90,
		baseValue = 25,
		mutationChance = 0.28,
		cost = 250,
		-- Higher reward AND higher risk: the seed that makes the decision hardest.
		rotChanceBonus = 0.05,
	},
}

Config.DefaultSeed = "basic"

-- ============================================================
-- Weather — a server-wide state machine, broadcast to everyone.
--
-- Cheap to build and it does three jobs: it shifts where the optimal decision
-- sits, it creates shared moments, and it gives a reason to check back in.
-- It is also why the world feels alive at 1 concurrent player.
-- ============================================================

Config.Weather = {
	MinDurationSeconds = 90,
	MaxDurationSeconds = 180,

	States = {
		{ id = "clear", displayName = "Clear", weight = 50, mutationDelta = 0, rotDelta = 0 },
		{ id = "rain", displayName = "Rain", weight = 25, mutationDelta = 0.10, rotDelta = 0 },
		{
			id = "drought",
			displayName = "Drought",
			weight = 20,
			mutationDelta = 0,
			rotDelta = 0.06,
		},
		{
			id = "rainbow",
			displayName = "Rainbow",
			weight = 5,
			mutationDelta = 0.25,
			rotDelta = 0.03,
		},
	},
}

-- ============================================================
-- Persistence
-- ============================================================

Config.Data = {
	AutosaveIntervalSeconds = 120,
	MaxLoadRetries = 4,
	RetryBaseDelaySeconds = 1, -- exponential: 1, 2, 4, 8
}

-- ============================================================
-- Analytics
-- ============================================================

Config.Analytics = {
	-- Heartbeat cadence for session-length tracking. Session length is derived
	-- from join/leave, but a heartbeat means a server crash still leaves a
	-- reasonable lower bound on the dashboard.
	SessionHeartbeatSeconds = 60,

	-- Retention day buckets we emit as discrete custom events. These are what
	-- you read to evaluate the Phase 1 kill criteria.
	RetentionDaysTracked = { 1, 2, 3, 7, 14, 28 },

	OnboardingFunnelName = "Onboarding",
}

-- ============================================================
-- Kill criteria — the numbers from the feasibility report.
-- Nothing reads these at runtime; they live here so the bar is written down
-- before you build, not rationalized after.
-- ============================================================

Config.KillCriteria = {
	-- Gate 0, first 72 hours. These are the thresholds Roblox itself scores:
	-- clearing them earns 3-5x more algorithmic impressions the following week.
	-- Free to measure, arrives before there are enough visits to read D1, and
	-- decisive — failing here means killing the game without spending anything.
	MinLikeRatioPercent = 80,
	MinAvgSessionMinutes = 8,

	-- Gate 1 and 2.
	MinD1RetentionPercent = 20,
	EvaluateAfterOrganicVisits = 5000,
	MinCCUWithinTwoWeeks = 50,
}

return Config
