# TradingView MCP Jackson — Claude Instructions

81 tools for reading and controlling a live TradingView Desktop chart via Chrome DevTools Protocol (port 9222). Exposed two ways: as an MCP server (stdio) and as a `tv` CLI. Fork of [tradesdontlie/tradingview-mcp](https://github.com/tradesdontlie/tradingview-mcp) adding a morning-brief workflow, session persistence, and a Linux launch bug fix.

> Also in this repo: `scalper-run.js`, a standalone live-trading script against the BitGet exchange (unrelated to the TradingView MCP tools). See "Standalone Scripts — Handle With Care" below before touching it.

## Architecture

```
Claude Code / tv CLI  ←→  MCP Server (stdio) or CLI  ←→  CDP (localhost:9222)  ←→  TradingView Desktop (Electron)
```

Three layers, strictly separated:

- **`src/core/*.js`** — all real logic. Talks to TradingView via `src/connection.js` (chrome-remote-interface). No knowledge of MCP or CLI.
- **`src/tools/*.js`** — thin MCP wrappers. One `registerXTools(server)` per domain, calls into `core`, formats with `jsonResult()` from `src/tools/_format.js`.
- **`src/cli/commands/*.js`** — thin CLI wrappers. Calls the *same* `core` functions, registers with `router.js` via `register(name, { description, options, handler })`.

Adding a capability means adding/editing a `core/*.js` function, then exposing it from both `tools/*.js` and `cli/commands/*.js` if it should be available in both places (most things should be).

`src/server.js` is the MCP entrypoint — it registers all `tools/*.js` modules and embeds a tool-selection instructions block for the model. `src/cli/index.js` is the CLI entrypoint — it registers all `cli/commands/*.js` modules then hands off to `router.js`.

Pine graphics (custom indicator drawings) are read via a known internal path:
`study._graphics._primitivesCollection.dwglines.get('lines').get(false)._primitivesDataById`

## Directory Structure

```
src/
  server.js              MCP entrypoint — registers tools/, embeds model instructions
  connection.js          CDP connection management + known internal TradingView API paths
  wait.js                Polling/retry helpers for async chart state
  core/                  Domain logic (chart, data, pine, replay, alerts, batch, watchlist,
                         indicators, ui, pane, tab, capture, health, morning, drawing)
  tools/                 MCP tool registrations — one file per core domain, thin wrappers
  cli/
    index.js             CLI entrypoint — registers commands/, hands off to router
    router.js            Zero-dependency arg parsing (node:util parseArgs) + help text
    commands/            CLI command registrations, mirrors tools/ 1:1 where applicable
scripts/
  launch_tv_debug_*      Per-platform launchers that start TradingView with --remote-debugging-port=9222
  pine_pull.js / pine_push.js   Pull/push Pine Script source directly via CDP (used by pine-develop skill)
  subscribe-prompt.cjs   Cosmetic terminal banner, unrelated to MCP functionality
skills/                  Claude Code skills (SKILL.md) for common workflows — chart-analysis,
                         pine-develop, replay-practice, strategy-report, multi-symbol-scan
agents/                  Claude Code subagent definitions (performance-analyst.md)
tests/
  e2e.test.js            Requires a live, connected TradingView Desktop instance
  cli.test.js            CLI-level tests, some offline, some hit TradingView's hosted compile API
  pine_analyze.test.js   Static Pine analysis (offline) + pine_check (hits hosted compile API)
rules.example.json       Template for rules.json — copy this on first-time setup
rules.json               User's trading rules/watchlist — read by morning_brief. Tracked in git
                         (not gitignored) — be aware its committed contents reflect whatever the
                         repo owner last configured, including scalping strategy parameters
scalper-run.js           Standalone live BitGet trading bot — NOT part of the MCP tool surface
safety-check-log.json    Append-only trade log written by scalper-run.js — tracked in git
```

## Decision Tree — Which Tool When

### "What's on my chart right now?"
1. `chart_get_state` → symbol, timeframe, chart type, list of all indicators with entity IDs
2. `data_get_study_values` → current numeric values from all visible indicators (RSI, MACD, BBands, EMAs, etc.)
3. `quote_get` → real-time price, OHLC, volume for current symbol

### "What levels/lines/labels are showing?"
Custom Pine indicators draw with `line.new()`, `label.new()`, `table.new()`, `box.new()`. These are invisible to normal data tools. Use:

1. `data_get_pine_lines` → horizontal price levels drawn by indicators (deduplicated, sorted high→low)
2. `data_get_pine_labels` → text annotations with prices (e.g., "PDH 24550", "Bias Long ✓")
3. `data_get_pine_tables` → table data formatted as rows (e.g., session stats, analytics dashboards)
4. `data_get_pine_boxes` → price zones / ranges as {high, low} pairs

Use `study_filter` parameter to target a specific indicator by name substring (e.g., `study_filter: "Profiler"`).

### "Give me price data"
- `data_get_ohlcv` with `summary: true` → compact stats (high, low, range, change%, avg volume, last 5 bars)
- `data_get_ohlcv` without summary → all bars (use `count` to limit, default 100, capped at 500)
- `quote_get` → single latest price snapshot

### "Run my morning routine"
1. `morning_brief` → scans `rules.json` watchlist, reads indicators on every symbol, returns structured data
2. Claude applies the `bias_criteria` / `risk_rules` from `rules.json` to generate the session bias text
3. `session_save` → persist the brief to `~/.tradingview-mcp/sessions/YYYY-MM-DD.json`
4. `session_get` → retrieve today's (or yesterday's) saved brief for comparison

### "Analyze my chart" (full report workflow)
1. `quote_get` → current price
2. `data_get_study_values` → all indicator readings
3. `data_get_pine_lines` → key price levels from custom indicators
4. `data_get_pine_labels` → labeled levels with context (e.g., "Settlement", "ASN O/U")
5. `data_get_pine_tables` → session stats, analytics tables
6. `data_get_ohlcv` with `summary: true` → price action summary
7. `capture_screenshot` → visual confirmation

### "Change the chart"
- `chart_set_symbol` → switch ticker (e.g., "AAPL", "ES1!", "NYMEX:CL1!")
- `chart_set_timeframe` → switch resolution (e.g., "1", "5", "15", "60", "D", "W")
- `chart_set_type` → switch chart style (Candles, HeikinAshi, Line, Area, Renko, etc.)
- `chart_manage_indicator` → add or remove studies (use full name: "Relative Strength Index", not "RSI")
- `indicator_set_inputs` / `indicator_toggle_visibility` → tweak settings or show/hide
- `chart_scroll_to_date` → jump to a date (ISO format: "2025-01-15")
- `chart_set_visible_range` → zoom to exact date range (unix timestamps)

### "Work on Pine Script"
1. `pine_set_source` → inject code into editor
2. `pine_smart_compile` → compile with auto-detection + error check
3. `pine_get_errors` → read compilation errors
4. `pine_get_console` → read log.info() output
5. `pine_get_source` → read current code back (WARNING: can be very large for complex scripts)
6. `pine_save` → save to TradingView cloud
7. `pine_new` → create blank indicator/strategy/library
8. `pine_open` → load a saved script by name
9. `pine_analyze` → offline static analysis, no chart/connection needed
10. `pine_check` → server-side compile check against TradingView's hosted API, no chart needed (requires outbound network)

The `pine-develop` skill (`skills/pine-develop/SKILL.md`) codifies this loop, including pulling/pushing source via `scripts/pine_pull.js` / `scripts/pine_push.js` to `scripts/current.pine` for editing outside the MCP tools.

### "Practice trading with replay"
1. `replay_start` with `date: "2025-03-01"` → enter replay mode
2. `replay_step` → advance one bar
3. `replay_autoplay` → auto-advance (set speed with `speed` param in ms)
4. `replay_trade` with `action: "buy"/"sell"/"close"` → execute trades (simulated within TradingView's replay mode only)
5. `replay_status` → check position, P&L, current date
6. `replay_stop` → return to realtime

### "Screen multiple symbols"
- `batch_run` with `symbols: ["ES1!", "NQ1!", "YM1!"]` and `action: "screenshot"` or `"get_ohlcv"`

### "Draw on the chart"
- `draw_shape` → horizontal_line, trend_line, rectangle, text (pass point + optional point2)
- `draw_list` → see what's drawn
- `draw_remove_one` → remove by ID
- `draw_clear` → remove all

### "Manage alerts"
- `alert_create` → set price alert (condition: "crossing", "greater_than", "less_than")
- `alert_list` → view active alerts
- `alert_delete` → remove alerts

### "Navigate the UI"
- `ui_open_panel` → open/close pine-editor, strategy-tester, watchlist, alerts, trading
- `ui_click` → click buttons by aria-label, text, or data-name
- `layout_switch` → load a saved layout by name
- `ui_fullscreen` → toggle fullscreen
- `pane_set_layout` / `pane_set_symbol` / `pane_focus` → multi-chart grids (s, 2h, 2v, 2x2, 4, 6, 8)
- `tab_list` / `tab_new` / `tab_close` / `tab_switch` → manage TradingView browser tabs
- `capture_screenshot` → take a screenshot (regions: "full", "chart", "strategy_tester")

### "TradingView isn't running"
- `tv_launch` → auto-detect and launch TradingView with CDP on Mac/Win/Linux
- `tv_health_check` → verify connection is working

## Context Management Rules

These tools can return large payloads. Follow these rules to avoid context bloat:

1. **Always use `summary: true` on `data_get_ohlcv`** unless you specifically need individual bars
2. **Always use `study_filter`** on pine tools when you know which indicator you want — don't scan all studies unnecessarily
3. **Never use `verbose: true`** on pine tools unless the user specifically asks for raw drawing data with IDs/colors
4. **Avoid calling `pine_get_source`** on complex scripts — it can return 200KB+. Only read if you need to edit the code.
5. **Avoid calling `data_get_indicator`** on protected/encrypted indicators — their inputs are encoded blobs. Use `data_get_study_values` instead for current values.
6. **Use `capture_screenshot`** for visual context instead of pulling large datasets — a screenshot is ~300KB but gives you the full visual picture
7. **Call `chart_get_state` once** at the start to get entity IDs, then reference them — don't re-call repeatedly
8. **Cap your OHLCV requests** — `count: 20` for quick analysis, `count: 100` for deeper work, `count: 500` only when specifically needed

### Output Size Estimates (compact mode)
| Tool | Typical Output |
|------|---------------|
| `quote_get` | ~200 bytes |
| `data_get_study_values` | ~500 bytes (all indicators) |
| `data_get_pine_lines` | ~1-3 KB per study (deduplicated levels) |
| `data_get_pine_labels` | ~2-5 KB per study (capped at 50) |
| `data_get_pine_tables` | ~1-4 KB per study (formatted rows) |
| `data_get_pine_boxes` | ~1-2 KB per study (deduplicated zones) |
| `data_get_ohlcv` (summary) | ~500 bytes |
| `data_get_ohlcv` (100 bars) | ~8 KB |
| `capture_screenshot` | ~300 bytes (returns file path, not image data) |

## Tool Conventions

- All tools return `{ success: true/false, ... }`, formatted via `jsonResult()` (`src/tools/_format.js`)
- Entity IDs (from `chart_get_state`) are session-specific — don't cache across sessions
- Pine indicators must be **visible** on chart for pine graphics tools to read their data
- `chart_manage_indicator` requires **full indicator names**: "Relative Strength Index" not "RSI", "Moving Average Exponential" not "EMA", "Bollinger Bands" not "BB"
- Screenshots save to `screenshots/` directory with timestamps (gitignored)
- OHLCV capped at 500 bars, trades at 20 per request, Pine labels capped at 50 per study by default (pass `max_labels` to override)
- Tool schemas use `zod`; every tool handler wraps its core call in try/catch and returns `jsonResult({ success: false, error }, true)` on failure — follow this pattern for new tools

## Development Workflow

```bash
npm install
npm test            # = test:e2e + pine_analyze.test.js — needs a live TradingView connection
npm run test:unit   # cli.test.js + pine_analyze.test.js — mostly offline
npm run test:cli     # tests/cli.test.js only
npm run test:all     # everything: e2e + pine_analyze + cli
npm link             # install the `tv` CLI globally for manual testing
tv status            # quick way to check CDP connectivity while developing
```

Notes:
- `tests/e2e.test.js` requires TradingView Desktop running with `--remote-debugging-port=9222` (use `scripts/launch_tv_debug_*`) — it will fail with connection errors in any environment without a live chart.
- A handful of `cli.test.js` / `pine_analyze.test.js` cases call `pine_check`, which hits TradingView's **hosted** Pine compile API over the network. In network-restricted environments (e.g. this sandbox) these return HTTP 403 and fail — that's an environment limitation, not a regression. CONTRIBUTING.md's "29 offline tests" claim assumes outbound network access works.
- When adding a tool: add the logic to `src/core/<domain>.js`, wrap it in `src/tools/<domain>.js` (MCP) and `src/cli/commands/<domain>.js` (CLI) using the existing files in that domain as a template, then register the new module in `src/server.js` and/or `src/cli/index.js` if it's a new domain.

## Scope Boundaries (from CONTRIBUTING.md)

This is a **local, read/observe + chart-control bridge** — not a trading bot framework. Contributions to the MCP/CLI surface must not:
- Connect directly to TradingView's servers (everything must go through the local Desktop app via CDP)
- Bypass TradingView authentication/subscription
- Scrape, cache, or redistribute market data
- Enable automated trading or live order execution
- Reverse-engineer/redistribute TradingView's proprietary code or access other users' data

## Standalone Scripts — Handle With Care

`scalper-run.js` is **not** part of the TradingView MCP tool surface and is **not** a TradingView integration — it's a standalone Node script that trades real funds on the BitGet exchange using live API credentials from a local `.env` (`BITGET_API_KEY`/`SECRET`/`PASSPHRASE`, gitignored, not present in this repo). It places real market orders on a 10-second loop driven by a simple VWAP/RSI(3)/EMA(8) signal, and logs every decision to `safety-check-log.json`.

This directly contradicts the "no automated trading/order execution" scope rule above — it was added as demo content for a YouTube video, not as a maintained feature of this project.

**Never run `scalper-run.js`, or any script that places live exchange orders, unless the user explicitly and unambiguously asks you to execute live trades and confirms they understand real funds are at risk.** Don't run it as a side effect of testing, exploring, or "seeing what the code does."

`rules.json` (read by `morning_brief`) is unrelated and safe — it's a static config of bias criteria and watchlist symbols, not credentials, and doesn't execute trades. `rules.example.json` is the template; copy it to `rules.json` for first-time setup. Note `rules.json` is currently committed to git with the repo owner's actual scalping-strategy config rather than gitignored as the setup docs imply — don't assume it's a safe-to-ignore local-only file when reading history.

## Documentation Map

- `README.md` — user-facing setup, full tool reference, troubleshooting
- `SETUP_GUIDE.md` — step-by-step install script written *for* an LLM agent to execute verbatim when a user asks to set this project up
- `RESEARCH.md` — design rationale and open questions behind the tool/context-management choices
- `SECURITY.md` — vulnerability reporting scope (local CDP bridge only)
- `CONTRIBUTING.md` — scope boundaries for PRs (see above)
