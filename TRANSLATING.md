# Translating Gold Advisor Midnight

Thank you for helping bring Gold Advisor Midnight to more players!
This guide explains everything you need to know to translate the addon into your language.

---

## How WoW Localization Works

World of Warcraft passes a locale code to addons at load time.
You can read it in Lua with `GetLocale()`, which returns one of the strings in the table below.

When the addon loads, `Locale.lua` creates the `GAM.L` table filled with English (enUS) defaults.
Then the per-locale file for your region runs — it checks `GetLocale()`, exits early if it does not
match, and then overrides only the keys you have translated.
Any key you leave commented out will automatically fall back to the English default,
so partial translations are perfectly fine.

---

## Supported WoW Locales

| `GetLocale()` string | Language | File to edit |
|---|---|---|
| `enUS` | English (US) — **default** | `Locale.lua` (source of truth) |
| `deDE` | German | `GoldAdvisorMidnight/Locale/deDE.lua` |
| `frFR` | French | `GoldAdvisorMidnight/Locale/frFR.lua` |
| `esES` | Spanish (EU) | `GoldAdvisorMidnight/Locale/esES.lua` |
| `esMX` | Spanish (Latin America) | `GoldAdvisorMidnight/Locale/esMX.lua` |
| `ruRU` | Russian | `GoldAdvisorMidnight/Locale/ruRU.lua` |
| `zhCN` | Simplified Chinese | `GoldAdvisorMidnight/Locale/zhCN.lua` |
| `zhTW` | Traditional Chinese | `GoldAdvisorMidnight/Locale/zhTW.lua` |
| `koKR` | Korean | `GoldAdvisorMidnight/Locale/koKR.lua` |
| `itIT` | Italian | `GoldAdvisorMidnight/Locale/itIT.lua` |
| `ptBR` | Portuguese (Brazil) | `GoldAdvisorMidnight/Locale/ptBR.lua` |

---

## How to Translate

### Step 1 — Open your locale file

Open the file for your language from the table above.
Every string key is listed as a commented-out line pre-filled with the English value.

```lua
-- L["BTN_SCAN_ALL"]  = "Scan All"
```

### Step 2 — Uncomment and translate

Remove the leading `--` and replace the English text on the **right side** of `=`
with your translation.

```lua
L["BTN_SCAN_ALL"]  = "Alle scannen"
```

**Critical rules:**
- **Only translate the value** (the text on the right side of `=`).
- **Never change the key** (the text on the left side of `=` in square brackets).
- Keep the Lua syntax intact: quotes, commas, and the `=` sign must stay in place.

### Step 3 — Handle format strings

Some strings contain `%s` (text placeholder) or `%d` (number placeholder).
Keep these in your translation — WoW substitutes real values at runtime.

```lua
-- English:
L["LOADED_MSG"] = "Gold Advisor Midnight v%s loaded. /gam to toggle."

-- German:
L["LOADED_MSG"] = "Gold Advisor Midnight v%s geladen. /gam zum Umschalten."
```

### Step 4 — Handle color codes

Some strings contain WoW color escape sequences like `|cffffffff` … `|r`.
Keep these unchanged in your translation; they control text color in-game.

```lua
-- English:
L["CONFIRM_DELETE_BODY"] = "Delete strategy:\n\"|cffffffff%s|r\"\n\nThis cannot be undone."

-- German:
L["CONFIRM_DELETE_BODY"] = "Strategie löschen:\n\"|cffffffff%s|r\"\n\nDies kann nicht rückgängig gemacht werden."
```

---

## Testing In-Game

1. Place the edited locale file in your addon folder:
   `World of Warcraft/_retail_/Interface/AddOns/GoldAdvisorMidnight/Locale/`
2. Log in (or use an existing session) and type `/reload` in the chat box.
3. Open the Gold Advisor window with `/gam` and verify your strings appear.

If a key shows the English default instead of your translation, double-check that:
- The `--` comment prefix was removed from that line.
- The key name (left side) is spelled exactly as in the source file.
- Your WoW client locale matches the `GetLocale()` check at the top of the file.

---

## Submitting Your Translation

**Option A — GitHub Pull Request (preferred)**

1. Fork the repository on GitHub.
2. Edit the locale file on your fork.
3. Open a Pull Request with a title like `Add deDE translation`.
4. We will review and merge it.

**Option B — Share the file**

If you are not familiar with GitHub, share the edited `.lua` file directly
(Discord, email, or open a GitHub Issue and paste the content).
We will integrate it for you.

---

## Tips

- You do not need to translate every string at once. Partial translations are welcome.
  Untranslated strings show English automatically.
- Focus first on strings players see most often:
  main window buttons, scan status messages, and column headers.
- If a translation is technically correct but feels unnatural in-game,
  prefer the phrasing a native WoW player would expect.
- For profession names, use the exact localized name shown in the WoW game client
  so players can match them to the Professions UI.

---

## Questions?

Open an issue on GitHub or ask in the project Discord.
