#!/usr/bin/env python3
"""
Build a portfolio snapshot JSON from Robinhood MCP tool outputs.

Usage (from Cursor agent):
  1. Call get_portfolio, get_equity_positions, get_equity_quotes via MCP
  2. Save raw responses, then run:
     python scripts/fetch_snapshot.py --portfolio portfolio.json --positions positions.json --quotes quotes.json

Or paste MCP JSON via stdin with --merge flag (see skill docs).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from trading_agent.mcp_helpers import build_snapshot_payload


def main() -> None:
    parser = argparse.ArgumentParser(description="Build portfolio snapshot for trading agent")
    parser.add_argument("--account", required=True, help="Agentic account number")
    parser.add_argument("--portfolio", type=Path, required=True)
    parser.add_argument("--positions", type=Path, required=True)
    parser.add_argument("--quotes", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("data/portfolio_snapshot.json"))
    args = parser.parse_args()

    portfolio = json.loads(args.portfolio.read_text())
    positions = json.loads(args.positions.read_text())
    quotes = json.loads(args.quotes.read_text())

    payload = build_snapshot_payload(args.account, portfolio, positions, quotes)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2))
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
