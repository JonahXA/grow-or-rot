# grow-or-rot

Phase 1, first bet. A push-your-luck growing game: plant a crop, watch it mutate, and
decide when to harvest — every extra second grows the payout and the chance you lose
it all.

Working title. The published name gets chosen deliberately before launch.

## Where this came from

Concept A of three in [docs/PHASE1-CONCEPTS.md](docs/PHASE1-CONCEPTS.md), picked as
the best risk-adjusted first bet: proven genre shape, one genuine novel twist, lowest
art burden of the proven formats, and the hard problem is curve tuning rather than
art.

Built on the pipeline proven in [phase0](https://github.com/JonahXA/phase0) — Rojo
source of truth, DataStore persistence with retries and migration, an idempotent
`ProcessReceipt`, and retention instrumentation. All of that is verified against
production, so this project starts with the plumbing solved and only the game as the
variable.

## Read first

- [docs/GAME-SPEC.md](docs/GAME-SPEC.md) — the design, the numbers, the two-week plan
- [docs/METRICS.md](docs/METRICS.md) — what to measure and the kill criteria

## Quickstart

```bash
rokit install
rojo serve
```

Then connect the Rojo plugin in Studio. Full setup in [docs/SETUP.md](docs/SETUP.md).

## The bar

Decided before any of this was designed, and not negotiable after the fact:

| Gate | Threshold |
|---|---|
| D1 retention | ≥ 20% after 5,000 organic visits |
| Organic CCU | ≥ 50 within 2 weeks |

Miss either → kill it and start Concept C. The portfolio only works if the bets stay
small enough that killing one doesn't hurt.
