"""Data models for the trading agent."""

from __future__ import annotations

from dataclasses import dataclass, field
from decimal import Decimal
from enum import Enum
from typing import Any

# Robinhood MCP returns equity prices scaled 10× (e.g. 995.65 → $99.565).
PRICE_SCALE = Decimal("10")


class OrderSide(str, Enum):
    BUY = "buy"
    SELL = "sell"


class OrderType(str, Enum):
    MARKET = "market"
    LIMIT = "limit"


@dataclass(frozen=True)
class Quote:
    symbol: str
    last_price: Decimal
    previous_close: Decimal | None = None
    bid: Decimal | None = None
    ask: Decimal | None = None

    @property
    def daily_change_pct(self) -> Decimal | None:
        if self.previous_close and self.previous_close > 0:
            return (self.last_price - self.previous_close) / self.previous_close * 100
        return None

    @classmethod
    def from_mcp(cls, symbol: str, quote_data: dict[str, Any]) -> Quote:
        raw_price = quote_data.get("last_trade_price", quote_data.get("price", 0))
        prev = quote_data.get("adjusted_previous_close") or quote_data.get("previous_close")
        return cls(
            symbol=symbol,
            last_price=Decimal(str(raw_price)) / PRICE_SCALE,
            previous_close=_optional_decimal(prev, scale=True) if prev else None,
            bid=_optional_decimal(quote_data.get("bid_price"), scale=True),
            ask=_optional_decimal(quote_data.get("ask_price"), scale=True),
        )


@dataclass(frozen=True)
class Position:
    symbol: str
    quantity: Decimal
    average_cost: Decimal

    @classmethod
    def from_mcp(cls, data: dict[str, Any]) -> Position:
        return cls(
            symbol=data["symbol"],
            quantity=Decimal(str(data["quantity"])),
            average_cost=Decimal(str(data["average_buy_price"])) / PRICE_SCALE,
        )


@dataclass(frozen=True)
class PortfolioSnapshot:
    account_number: str
    total_value: Decimal
    cash: Decimal
    buying_power: Decimal
    positions: tuple[Position, ...] = ()
    quotes: dict[str, Quote] = field(default_factory=dict)

    def position_value(self, symbol: str) -> Decimal:
        pos = next((p for p in self.positions if p.symbol == symbol), None)
        if not pos:
            return Decimal("0")
        quote = self.quotes.get(symbol)
        if not quote:
            return Decimal("0")
        return pos.quantity * quote.last_price

    def equity_exposure(self) -> Decimal:
        return sum(self.position_value(p.symbol) for p in self.positions)

    @classmethod
    def from_mcp(
        cls,
        account_number: str,
        portfolio: dict[str, Any],
        positions: list[dict[str, Any]],
        quotes: dict[str, Quote],
    ) -> PortfolioSnapshot:
        bp = portfolio.get("buying_power", {})
        return cls(
            account_number=account_number,
            total_value=Decimal(str(portfolio["total_value"])),
            cash=Decimal(str(portfolio["cash"])),
            buying_power=Decimal(str(bp.get("buying_power", portfolio["cash"]))),
            positions=tuple(Position.from_mcp(p) for p in positions),
            quotes=quotes,
        )


@dataclass(frozen=True)
class TradeSignal:
    symbol: str
    side: OrderSide
    order_type: OrderType
    quantity: Decimal | None = None
    dollar_amount: Decimal | None = None
    limit_price: Decimal | None = None
    reason: str = ""
    strategy: str = ""
    confidence: float = 0.0

    def to_mcp_review(self, account_number: str) -> dict[str, Any]:
        """Build parameters for Robinhood MCP review_equity_order."""
        params: dict[str, Any] = {
            "account_number": account_number,
            "symbol": self.symbol,
            "side": self.side.value,
            "type": self.order_type.value,
        }
        if self.dollar_amount is not None:
            params["dollar_amount"] = str(self.dollar_amount.quantize(Decimal("0.01")))
        elif self.quantity is not None:
            params["quantity"] = str(self.quantity)
        if self.limit_price is not None:
            params["limit_price"] = str(self.limit_price.quantize(Decimal("0.01")))
        return params


def _optional_decimal(value: Any, scale: bool = False) -> Decimal | None:
    if value is None:
        return None
    result = Decimal(str(value))
    return result / PRICE_SCALE if scale else result
