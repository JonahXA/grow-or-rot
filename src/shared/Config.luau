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
-- Economy tuning
-- ============================================================

Config.Economy = {
	CoinsPerClick = 1,
	DoubleCoinsMultiplier = 2,

	-- Server-side rate limit. The client can spam the remote all it likes; the
	-- server silently drops anything faster than this.
	ClickCooldownSeconds = 0.15,

	-- If a player exceeds this many rejected clicks in a session, log a
	-- suspicion event. Not a ban — just a signal that something is scripted.
	SuspiciousRejectThreshold = 200,
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
	MinD1RetentionPercent = 20,
	EvaluateAfterOrganicVisits = 5000,
	MinCCUWithinTwoWeeks = 50,
}

return Config
