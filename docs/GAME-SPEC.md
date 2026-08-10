# Grow or Rot — game spec

Working title. The published name matters a lot for discovery and gets chosen
deliberately before launch, not now.

**Concept A from `PHASE1-CONCEPTS.md`.** Two-week build on the Phase 0 pipeline.

---

## The pitch, in one sentence

Plant a crop, watch it mutate, and decide when to harvest — every extra second
grows the payout and the chance you lose it all.

---

## Why this concept

Grow a Garden is pure idle: waiting is strictly good, so there is no decision. This
takes the same proven, low-friction shape and puts **one real choice** at the centre
of it. That choice is the whole game.

It survives the two filters that eliminated the alternatives:

- **Fun at 1 CCU.** Fully solo. A new game has no players; anything needing a
  populated server is dead on arrival.
- **Content is data, not art.** Mutations, weather and value curves are tables.
  Three plant meshes at three growth stages, colour-tinted per mutation, covers the
  entire visual surface.

---

## Core loop

1. **Plant** a seed in an empty plot.
2. **Grow** — the crop advances through stages on a timer.
3. **Ripe** — the crop is now harvestable at base value. The decision unlocks.
4. **Push** — each tick past ripeness rolls:
   - a chance to **mutate** (multiplies value, stacking)
   - a chance to **rot** (crop lost, payout zero)
   - rot chance **rises every tick**; mutation chance does not
5. **Harvest** whenever you choose → coins.
6. **Spend** on more plots, better seeds, upgrades. Return to 1.

Expected value rises, peaks, then falls. The skill is reading where the peak is —
and the peak *moves* with weather and seed type, so it can't be memorised once and
forgotten.

**Time to first action: under 30 seconds.** Player spawns next to an empty plot with
one free seed and a single prompt. Planting is the first thing they do. This is the
metric the breakout games share and it is the thing to protect during every later
scope decision.

---

## The offline problem, and its resolution

Grow a Garden's reviewers name its central virtue: it doesn't punish you for stepping
away. Push-your-luck cuts against that, because the decision needs you present.

**Resolution: crops grow offline but freeze at ripe.** Rot never occurs while you're
away. You come back to a field of ripe crops holding at guaranteed value, and every
push-decision happens with you at the keyboard.

This keeps the "safe to leave" virtue intact while making the decision meaningful,
and it means a returning player is greeted by a field of choices rather than a field
of rotted stumps — which matters enormously for D1 retention.

A later **Auto-Harvest** upgrade lets players set a threshold (e.g. "auto-harvest at
3 mutations") so pushing can continue while offline. That is a monetizable
convenience, not a requirement.

---

## Starting numbers

All of these are tuning targets, not truths. Instrument them and move them.

| Parameter | Start value |
|---|---|
| Basic seed: plant → ripe | 60s |
| Push tick length | 10s |
| Mutation chance per tick | 15% |
| Rot chance, first tick past ripe | 8% |
| Rot chance increase per tick | +2% (compounding pressure) |
| Base crop value | 10 coins |
| Value multiplier per mutation | ×1.5 (stacking) |
| Starting plots | 2 |

With these, EV peaks somewhere around tick 3–5, which is where it should sit: long
enough to feel like a real gamble, short enough that a session contains many
decisions.

**The tuning goal is that the optimal play is non-obvious and situational.** If
players work out "always harvest at tick 4" then the decision is dead and so is the
game. Weather and seed variance exist to keep the answer moving.

---

## Weather — the live-service layer

A server-wide state machine broadcasting to everyone in the server. Cheap to build,
and it does three jobs: shifts the optimal decision, creates shared moments, gives a
reason to check back in.

| Event | Effect |
|---|---|
| Clear | baseline |
| Rain | +mutation chance |
| Drought | +rot chance |
| Rainbow (rare) | mutation rolls can hit rare tiers |

Announced on screen with a countdown. Weather is why the world feels alive at 1 CCU.

---

## Monetization

Built on the Phase 0 `MonetizationService`, which is already verified against
production.

**Passes:** Rot Insurance (one free save per crop), Seed Luck (+mutation chance),
Auto-Harvest (offline pushing with a threshold).

**Developer products:** extra plots, coin packs, instant-grow.

Simulator-family monetization has the highest revenue-per-visit on the platform, and
Rot Insurance in particular sells directly against the emotion the core loop
generates. That is the right shape — the pass is desirable *because* the loop works,
not as a substitute for it.

---

## Data model

Extends the Phase 0 `Profile`. Everything must stay JSON-serializable.

```
plots: { { seedId, plantedAt, mutations, pushTicks, harvestedAt } }
seeds: { [seedId]: count }
upgrades: { autoHarvestThreshold, plotCount }
stats: { totalHarvested, totalRotted, bestSingleHarvest, biggestLoss }
```

`stats` is not decoration. `totalRotted` vs `totalHarvested` is the single best
signal for whether the risk curve is tuned right — and segmenting retention by it
answers the question that decides this game's future: **do players who lose a big
crop come back, or churn?**

---

## Two-week build

| Days | Work |
|---|---|
| 1–3 | Plot/plant/grow core, data model, server-authoritative growth |
| 4–6 | Mutation + rot rolls, harvest decision, HUD showing live value and risk |
| 7–8 | Weather state machine and broadcast |
| 9–10 | Shop, upgrades, monetization wiring |
| 11–12 | **The first 60 seconds** — onboarding, feedback, juice |
| 13–14 | Analytics, balance pass, publish |

Days 11–12 are not polish and must not be cut. Time-to-first-action is the pattern
every breakout game shares, and the first minute is what discovery actually tests.

---

## What would kill this

- **The decision becomes solvable.** One optimal harvest tick, memorised, forever.
  Mitigated by weather and seed variance; watch for it in the data.
- **Rot feels unfair rather than exciting.** The line between tension and rage-quit
  is a tuning problem. `totalRotted` segmented against D1 is the instrument.
- **It reads as another idle clone in the first five seconds.** The push decision has
  to be visible in the thumbnail and the first minute, or nobody discovers the twist.

Kill criteria are unchanged and were set before any of this existed: see
`METRICS.md`. **≥20% D1 after 5,000 organic visits, ≥50 organic CCU within 2 weeks.**
