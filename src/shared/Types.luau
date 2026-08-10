--!strict
--[[
	Types — the saved-data schema and the state shape pushed to clients.

	Profile is what lives in the DataStore. Every field must be JSON-serializable
	(no Instances, no mixed-key tables, no NaN). Adding a field means bumping
	Config.DataVersion and handling it in DataService.migrate().
]]

--[[
	One growing plot.

	`plantedAt` is a server-clock unix timestamp, so growth continues while the
	player is offline. `lastPushAt` is deliberately reset on profile load, which
	is what freezes pushing while away — see the offline rule in GAME-SPEC.md.

	An empty plot has seedId = nil and every other field at its zero value.
]]
export type Plot = {
	seedId: string?,
	plantedAt: number,
	mutations: number,
	pushTicks: number,
	lastPushAt: number,
	-- Set when Rot Insurance has already absorbed a rot on this crop, so the
	-- pass saves once per crop rather than making a player immortal.
	insuranceUsed: boolean,
}

export type Profile = {
	version: number,

	-- Economy
	coins: number,
	totalCoinsEarned: number,

	-- Gameplay
	plots: { Plot },
	seeds: { [string]: number },
	upgrades: {
		plotCount: number,
		autoHarvestThreshold: number, -- 0 = off
	},

	--[[
		Not decoration. totalRotted against totalHarvested is the single best
		signal for whether the risk curve is tuned, and segmenting retention by
		it answers the question that decides this game's future: do players who
		lose a big crop come back, or churn?
	]]
	stats: {
		totalHarvested: number,
		totalRotted: number,
		bestSingleHarvest: number,
		biggestLoss: number,
	},

	-- Retention primitives. Unix seconds, server clock (os.time()).
	firstJoinTime: number,
	lastJoinTime: number,
	sessionCount: number,
	totalPlaytimeSeconds: number,

	-- Distinct UTC day-stamps on which this player joined, as "YYYY-MM-DD".
	-- Capped so the profile can't grow without bound.
	daysSeen: { string },
	retentionReported: { [string]: boolean },

	-- Monetization
	robuxSpent: number,
	purchaseCount: number,

	-- Receipt idempotency. PurchaseId -> true for every developer product
	-- receipt already honored. Lives in the profile rather than a separate store
	-- so that granting and marking are one atomic write.
	processedReceipts: { [string]: boolean },
	receiptOrder: { string },
}

--[[
	What the client is told about one plot.

	Note it carries `rotChance` and `value` precomputed by the server rather than
	the raw inputs. The client must never be in a position to disagree with the
	server about what a crop is worth — and shipping the formula to the client
	would also hand exploiters the exact curve.
]]
export type PlotView = {
	index: number,
	seedId: string?,
	displayName: string?,
	ripeAt: number, -- unix seconds; client counts down locally
	isRipe: boolean,
	mutations: number,
	mutationName: string?,
	pushTicks: number,
	nextPushAt: number, -- unix seconds
	value: number, -- coins if harvested right now
	rotChance: number, -- chance the NEXT push tick destroys it
}

export type ClientState = {
	coins: number,
	plots: { PlotView },
	seeds: { [string]: number },
	weather: {
		id: string,
		displayName: string,
		endsAt: number,
	}?,
	passes: {
		rotInsurance: boolean,
		seedLuck: boolean,
		autoHarvest: boolean,
	},
}

return {}
