# What to measure, and what the numbers have to hit

The instrumentation exists to answer exactly one question per Phase 1 game:
**kill it, or double down?** Anything that doesn't feed that decision is noise.

## The kill criteria

Written down before building, so they can't be rationalized afterward.

| Gate | When | Threshold | Where to read it |
|---|---|---|---|
| **0 — Quality** | **first 72 hours** | like ratio **≥ 80%**, avg session **≥ 8 min** | Dashboard → **Overview** and **Engagement** |
| 1 — Retention | ~5,000 organic visits | D1 **≥ 20%** | Dashboard → Analytics → **Engagement** |
| 2 — Traction | 2 weeks | **≥ 50** organic CCU | Dashboard → **Overview** (peak CCU) |

Miss any → kill the game and start the next one.

**Gate 0 exists because Roblox scores it whether you like it or not.** Games clearing
an 80% like ratio and an 8-minute average session in their first 72 hours receive
**3–5× more algorithmic impressions** the following week. That is the platform's own
free test of your game, it arrives before you have enough visits to read D1, and it
costs nothing.

Failing Gate 0 is decisive. Do not wait for 5,000 visits and do not spend a dollar —
if the game cannot hold an eight-minute session, traffic will not fix it, and the
algorithm will stop delivering traffic anyway.

The hardest part of this is not the measurement. It's actually killing the game.

## Do you need to pay to find out?

**No.** The platform samples every new experience and amplifies what performs. Gate 0
is free and is the same signal the algorithm uses.

Money buys **statistical power, not growth**:

- A purchased visit costs **$0.01–0.05**. A visit earns roughly **$0.0019** at decent
  monetization. Paid acquisition needs 5–26 return visits just to break even, so it is
  never a growth strategy for an unproven game.
- The one legitimate use: you cleared Gate 0, but organic sampling is trickling and
  you cannot read D1 off 300 visits. **$50–100 buys 1,000–10,000 visits**, enough for
  a real number.
- Read it knowing **paid traffic retains worse than organic**, so a paid-heavy D1
  understates the truth. If paid clears 20%, the game is genuinely fine.

**Free traffic to exhaust first:** games with organic creator coverage in week one are
**5× more likely** to sustain above-average CCU through month one. Posting your own
clips to TikTok and Shorts costs time rather than money and outperforms a small ad buy.

Order of operations: ship → 72h quality gate → post clips → two weeks organic → only
then consider $50–100 to buy a readable D1.

## Why D1 and not revenue

At beginner monetization (~0.15 Robux/visit) a game needs ~200,000 visits just to clear
the 30,000 Robux minimum cashout. You cannot wait for revenue to tell you whether a
game works — you'd burn a month per signal. **D1 retention is the leading indicator**,
and it's also the input Roblox's own discovery algorithm weights most heavily since it
moved to a 28-day multi-phase retention model.

Revenue per visit is a Phase 2 metric. Retention is the Phase 1 metric.

## What this repo emits

**Built-in, no code required:** D1/D7/D28 retention, DAU, session length, and revenue
all appear on the Creator Dashboard automatically for any published experience. Trust
these for the headline numbers.

**Custom events** (Analytics → Custom Events) exist to answer things the built-in
charts can't segment.

> Verifying they arrive: don't wait on the charts, which lag. Each of the Economy,
> Funnel, and Custom analytics pages has a **View Events** button at the top showing a
> near-real-time feed of the most recent events. That is the tool for confirming
> instrumentation works; the charts are for reading results once data accumulates.
>
> Nothing appears from a Studio playtest — events require a **published** experience
> and fire **server-side only**.

| Event | Why it's here |
|---|---|
| `Retention_D1` … `Retention_D28` | Segmentable retention — lets you ask "did players who bought something retain better?" via the `paid` field |
| `NewPlayer` / `ReturningPlayer` | New-vs-returning split per day |
| `SessionHeartbeat` | Session-length floor that survives a server crash |
| `SessionEnd` | Exit balance and purchase count |
| `PurchaseCompleted` | Robux amount + which product |
| `GamePassPurchased` | Pass conversion |
| `DataLoadFailed` | **Watch this.** Nonzero means some players' progress is silently vanishing, which corrupts every retention number above it |
| `SuspiciousClickRate` | Someone is scripting the click remote |

**Onboarding funnel** (Analytics → Funnels): Joined → DataLoaded → FirstClick →
FirstShopOpen → FirstPurchase. The step with the steepest drop is your next task.

**Economy events** (Analytics → Economy): every coin in or out, tagged with a reason
(`ClickReward`, `ProductPurchase`, `ProductRollback`). The ending-balance field is what
makes currency-duplication exploits visible as a divergence between total sourced and
total held.

## Reading it honestly

- **Don't judge retention on paid traffic.** Sponsored visits cost $0.01–0.05 each
  while a visit earns roughly $0.0019 at good monetization. Paid traffic also retains
  worse than organic, so mixing them makes a game look deader than it is. Measure
  organic, then decide whether ads are worth it.
- **Five thousand visits is the minimum for a D1 read.** Below that you're looking at
  noise and will talk yourself into keeping a dead game.
- **A freshness bump is not traction.** Publishing an update temporarily boosts you in
  Trending. If your CCU spike decays to baseline within 48h of an update, that was the
  algorithm, not your game.
