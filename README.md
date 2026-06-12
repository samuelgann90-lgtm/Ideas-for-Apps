# Robinhood Trading Agent

An AI-powered trading agent that connects to your Robinhood account through the [Robinhood MCP server](https://cursor.com) in Cursor. It analyzes your portfolio, runs configurable strategies, enforces risk limits, and executes trades only after your confirmation.

## Architecture

```
┌─────────────────┐     MCP Tools      ┌──────────────────┐
│  Cursor Agent   │ ◄──────────────►  │  Robinhood API   │
│  (Skill-driven) │                    └──────────────────┘
└────────┬────────┘
         │ portfolio snapshot JSON
         ▼
┌─────────────────┐
│  Python Engine  │  strategies + risk filtering
│  trading_agent/ │
└─────────────────┘
```

1. **Cursor + Robinhood MCP** — fetches live portfolio, quotes, and places orders
2. **Python strategy engine** — generates trade signals with risk guardrails
3. **Cursor skill** — orchestrates the full workflow (see `.cursor/skills/robinhood-trading-agent/SKILL.md`)

## Quick Start

### 1. Connect Robinhood MCP in Cursor

Enable the Robinhood MCP server in Cursor settings and authenticate your account. You need an account with **agentic trading enabled** (`agentic_allowed: true`).

### 2. Configure the agent

```bash
cp config.example.yaml config.yaml
# Edit account_number and strategy targets
pip install -r requirements.txt
```

### 3. Run via Cursor

Ask Cursor:

> "Run the Robinhood trading agent on my portfolio"

The agent will:
- Pull your portfolio and positions via MCP
- Run strategy analysis
- Present recommended trades
- Execute only after you confirm

### 4. Run analysis manually

```bash
# After saving MCP responses to JSON files:
python scripts/fetch_snapshot.py \
  --account YOUR_ACCOUNT \
  --portfolio data/portfolio.json \
  --positions data/positions.json \
  --quotes data/quotes.json

python -m trading_agent.cli --config config.yaml --input data/portfolio_snapshot.json
```

## Strategies

| Strategy | Description |
|----------|-------------|
| `dca` | Dollar-cost average into symbols below target allocation |
| `momentum` | Buy strong daily movers; trim positions down >3% |
| `rebalance` | Bring portfolio weights back to target allocations |

Enable strategies in `config.yaml`:

```yaml
strategies:
  - dca
  - momentum
```

## Risk Controls

All trades pass through risk filters before recommendation:

- **max_order_dollars** — cap per order (default $100)
- **max_position_pct** — max % of portfolio in one symbol (default 20%)
- **max_daily_trades** — limit trades per run (default 5)
- **min_buying_power_reserve** — cash buffer kept untouched (default $50)

## Safety

- Trades require an agentic-enabled Robinhood account
- Every order is previewed with `review_equity_order` before placement
- The agent never places orders without explicit user confirmation
- Cancel/modify operations also require confirmation

## Project Structure

```
trading_agent/
  agent.py          # Orchestrator
  models.py         # Portfolio, quotes, trade signals
  risk.py           # Risk manager
  mcp_helpers.py    # MCP response parsers
  strategies/       # DCA, momentum, rebalance
  cli.py            # Command-line interface
.cursor/skills/
  robinhood-trading-agent/SKILL.md
config.example.yaml
```

## Tests

```bash
pip install pytest
pytest tests/
```

## Disclaimer

This software is for educational purposes. Automated trading involves real financial risk. Past performance does not guarantee future results. You are solely responsible for all trading decisions.
