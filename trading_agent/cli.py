"""CLI for the Robinhood trading agent."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from trading_agent.agent import AgentConfig, TradingAgent


def main() -> None:
    parser = argparse.ArgumentParser(description="Robinhood trading agent — analyze portfolio and generate trade signals")
    parser.add_argument(
        "--config",
        type=Path,
        default=Path("config.yaml"),
        help="Path to agent config YAML (default: config.yaml)",
    )
    parser.add_argument(
        "--input",
        type=Path,
        help="JSON file with MCP portfolio/positions/quotes data",
    )
    parser.add_argument(
        "--output",
        choices=["report", "json"],
        default="report",
        help="Output format (default: report)",
    )
    args = parser.parse_args()

    if not args.config.exists():
        print(f"Config not found: {args.config}", file=sys.stderr)
        print("Copy config.example.yaml to config.yaml and edit it.", file=sys.stderr)
        sys.exit(1)

    config = AgentConfig.from_yaml(args.config)
    agent = TradingAgent(config)

    if not args.input:
        print(
            "No --input provided. Fetch portfolio data via Robinhood MCP, "
            "save as JSON, then re-run with --input.",
            file=sys.stderr,
        )
        print(
            json.dumps(
                {
                    "account_number": config.account_number,
                    "portfolio": {"total_value": "...", "cash": "...", "buying_power": {"buying_power": "..."}},
                    "positions": [{"symbol": "AAPL", "quantity": "1", "average_buy_price": "15000"}],
                    "quotes": {"AAPL": {"last_trade_price": "175.50", "previous_close": "170.00"}},
                },
                indent=2,
            ),
            file=sys.stderr,
        )
        sys.exit(0)

    with open(args.input) as f:
        payload = json.load(f)

    portfolio = TradingAgent.portfolio_from_mcp_payload(payload)
    signals = agent.analyze(portfolio)

    if args.output == "json":
        print(
            json.dumps(
                {
                    "signals": [
                        {
                            "symbol": s.symbol,
                            "side": s.side.value,
                            "order_type": s.order_type.value,
                            "quantity": str(s.quantity) if s.quantity else None,
                            "dollar_amount": str(s.dollar_amount) if s.dollar_amount else None,
                            "reason": s.reason,
                            "strategy": s.strategy,
                            "mcp_review": s.to_mcp_review(config.account_number),
                        }
                        for s in signals
                    ]
                },
                indent=2,
            )
        )
    else:
        print(agent.format_report(portfolio, signals))


if __name__ == "__main__":
    main()
