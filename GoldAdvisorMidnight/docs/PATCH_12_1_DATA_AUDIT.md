# Retail 12.1 commodity data audit

Audit date: 2026-08-15

Retail build: `12.1.0.69299`
Interface: `120100`

This audit is the release-data boundary for the post-launch 12.1 additions.
Recipe identity, reagents, outputs, and base yields were joined from the live
Retail DB2 spell, recipe, crafting-data, and item tables. Commodity eligibility
was then checked against the four TradeSkillMaster regional commodity snapshots
and structurally validated with live `ItemSparse` data.

| Profession | Strategy | Recipe ID | Output IDs | Base yield |
|---|---|---:|---|---:|
| Alchemy | Concentrated Silvermoon Health Potion | `1289744` | `271883`, `271884` | 5 |
| Alchemy | Liquid Luster | `1289745` | `271886`, `271887` | 5 |
| Alchemy | Alluring Nostrum | `1289746` | `271889`, `271890` | 5 |
| Enchanting | Enchant Weapon - Rite of the Hash'ey | `1291694` | `273071`, `273072` | 1 |
| Engineering | R0CKY-To-Go | `1305148` | `275676` | 3 |
| Inscription | Vantus Rune: Tides | `1290561` | `272194`, `272195` | 1 |
| Inscription | Contract: Zul'jarra's Forces | `1303144` | `277968`, `277969` | 1 |
| Jewelcrafting | Refine Crystalline Glass | `1307462` | `242786` | 1 |
| Jewelcrafting | Refine Dusk-Shrouded Stone | `1307466` | `242789` | 1 |

`Alluring Nostrum` is a reviewed new-item exception because its quality item
IDs were present as unbound, stackable live items before they appeared in the
pinned regional TSM union. The exception is deliberately explicit and can be
removed once ordinary market observation catches up.

`Odious Alloy` (`1291682`) was not added: its proposed output item `273057` is
absent from the live build's item table and from the market snapshots. This is
a deliberate exclusion, not missing catalog work.

The checked-in manifest result is:

- 606 raw definitions
- 282 retained commodity strategies
- 324 excluded definitions
- 477 eligible output item IDs
- zero retained recipe audit issues

Primary public cross-checks:

- Blizzard 12.1 quality-of-life notes:
  <https://worldofwarcraft.blizzard.com/en-us/news/24288418/quality-of-life-improvements-coming-in-curse-of-ulatek>
- Community-maintained 12.1 recipe discovery list:
  <https://us.forums.blizzard.com/en/wow/t/new-recipes-in-121/2318513>
- Wowhead 12.1 consumable coverage:
  <https://www.wowhead.com/ptr/news/new-combat-potions-and-consumables-in-patch-12-1-382192>
