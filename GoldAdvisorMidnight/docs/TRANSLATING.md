# Translating Gold Advisor Midnight

The English source strings live in `Locale.lua`. Locale overrides live in
`Locale/<locale>.lua` for German, Spanish (EU and Mexico), French, Italian,
Korean, Brazilian Portuguese, Russian, Simplified Chinese, and Traditional
Chinese.

To update a translation:

1. Keep the key on the left unchanged and translate only the value.
2. Preserve WoW color codes, escaped newlines (`\n`), slash commands, and
   format placeholders such as `%s`, `%d`, and `%.4f`.
3. Prefer Blizzard's localized profession terminology where it is known.
4. Keep short labels compact enough for the existing buttons and columns; put
   explanation in the corresponding tooltip body.
5. Run `python tests/check_locales.py` from the addon directory.
6. Reload WoW and inspect the planner at its narrow and full three-panel widths.

The locale check requires every string referenced by shipped Lua code to be
defined by every supported locale and verifies that formatting placeholders
match English. English remains the fallback for unused historical keys, but an
active release string may not rely on that fallback.
