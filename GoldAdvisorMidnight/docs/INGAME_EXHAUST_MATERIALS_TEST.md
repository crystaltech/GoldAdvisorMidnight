# Exhaust Materials live-client acceptance

This is the release acceptance test for the mass-crafting model. Deterministic
formula and integration behavior is covered by `lua tests/run.lua`; this pass
checks only behavior that requires Blizzard's live profession and Auction
House APIs.

## Accepted reference cases

- Dawn Shatter (`1280401`), Resourcefulness only: 18.78% Resourcefulness,
  5% extra saved-material bonus, 1,000 starting crafts, 1,062.869 effective
  attempts, and 3,188.608 expected output.
- Sin'dorei Lens (`1230475`), both stats: 16.09% Multicraft with 50% extra
  output and 28.78% Resourcefulness with 50% extra savings. Twenty starting
  crafts produced 22.975 expected attempts and 30.646 expected output.
- Lucky Keychain (`1229916`): selecting Refresh Recipe captured 12.7%
  Multicraft and 28.8% Resourcefulness, plus recipe-local +100% Multicraft
  output and +45% Resourcefulness-saving bonuses. One thousand starting crafts
  produced 1,143.1 expected attempts and 1,521 expected output.
- Imbued Bright Linen Bolt (`1228940`): root and intermediate recipe stats were
  independent, and VI correctly preferred the cheaper direct intermediate at
  the observed prices.

## Expected model

- Starting crafts describe the initial reagent pool.
- Expected Resourcefulness savings are reinvested into additional attempts.
- Multicraft increases expected output per attempt without adding material
  consumption.
- The initial material pool is charged once; it is not discounted again for
  the same Resourcefulness savings.
- Precise expected attempts remain available in help text while the visible
  actionable recommendation rounds down to a whole craft.

For base crafts `B`, base yield `y`, Multicraft chance `m`, Resourcefulness
chance `r`, node modifiers `mExtra`/`rExtra`, and Multicraft constant `k`:

```text
saveFraction = 0.30 * (1 + rExtra)
effectiveCrafts = B / (1 - r * saveFraction)
averageExtraOnMulticraft = (1 + k * y * (1 + mExtra)) / 2
actualYield = y + m * averageExtraOnMulticraft
expectedOutput = effectiveCrafts * actualYield
```

## Recipe and gear capture

1. Open the Auction House and Gold Advisor.
2. Select a learned commodity recipe and click `Refresh Recipe`; verify that
   Blizzard opens the exact recipe.
3. Compare the detail panel's Multicraft and Resourcefulness values with the
   profession window. The addon may show one extra decimal place.
4. Confirm the recipe bonuses belong to that recipe and not another recipe in
   the same profession.
5. Equip a Multicraft set and use `Stat Gear > Save MC`; equip a
   Resourcefulness set and use `Save Res`.
6. Compare Auto, MC, and Res. Auto should choose the most profitable captured
   setup at current prices. A missing forced preset must warn instead of using
   the other one silently.
7. Repeat on a second recipe to confirm saved sets do not cross recipe IDs.

On a character without the profession, the detail panel should name the most
recent exact cached crafter and must not attempt to open Blizzard's profession
window. Profile-only data must not cross character boundaries.

## Vertical integration

1. Choose a retained commodity with a craftable intermediate.
2. Toggle VI off and on; Materials must switch immediately between direct
   intermediates and the expanded material plan.
3. Open `Show craft steps`. Vendor purchases must be grouped first, Auction
   House purchases second, and every intermediate craft before the final craft.
4. Repeated intermediate recipes must be combined and rounded to whole crafts.
5. Disable VI and confirm direct intermediate pricing is restored.

## Real-batch sanity check

Use inexpensive materials for at least 100 ordinary starting crafts. Record
the recipe ID, initial materials, captured stats, expected attempts/output,
actual attempts/output, and leftovers. Random results need not equal the
expectation; validate direction and plausibility. If output differs by more
than roughly 15%, collect at least 500 starting crafts before treating it as a
formula defect.

## Cooldowns and Quick Buy

- Track daily, weekly, and charge-based recipes where available. Verify the
  current crafter refreshes live, offline crafters retain last-known state, and
  a reset is not claimed until the owning character verifies it.
- In Quick Buy, verify one explicit click per commodity, a new quote before
  purchase, and confirmation when a live quote exceeds the estimate by more
  than 5% or no estimate exists.

## Failure report

Use `/gam log` and copy the latest entries. Include the recipe name/ID, crafter,
starting craft count, current gear mode, VI state, relevant screenshots, and
the recorded batch values. Developer-only formula, audit, and scanner checks
run from `tests/` and `tools/`; their retired slash commands are not part of the
2.0 release.
