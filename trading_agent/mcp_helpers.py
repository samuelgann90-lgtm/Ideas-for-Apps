"""Helpers to transform Robinhood MCP responses into agent input."""

from __future__ import annotations

from typing import Any

from trading_agent.models import Quote


def parse_quotes_response(response: dict[str, Any]) -> dict[str, Quote]:
    """Parse get_equity_quotes MCP response into Quote objects."""
    quotes: dict[str, Quote] = {}
    for entry in response.get("data", {}).get("results", []):
        quote_data = entry.get("quote", entry)
        symbol = quote_data.get("symbol")
        if symbol:
            quotes[symbol] = Quote.from_mcp(symbol, quote_data)
    return quotes


def build_snapshot_payload(
    account_number: str,
    portfolio_response: dict[str, Any],
    positions_response: dict[str, Any],
    quotes_response: dict[str, Any],
) -> dict[str, Any]:
    """Build JSON payload for trading_agent.cli --input."""
    portfolio = portfolio_response.get("data", portfolio_response)
    positions = positions_response.get("data", {}).get("positions", [])
    quotes = parse_quotes_response(quotes_response)

    return {
        "account_number": account_number,
        "portfolio": portfolio,
        "positions": positions,
        "quotes": {
            sym: {
                "last_trade_price": str(q.last_price * 10),
                "previous_close": str(q.previous_close * 10) if q.previous_close else None,
            }
            for sym, q in quotes.items()
        },
    }
