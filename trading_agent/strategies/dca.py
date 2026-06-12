"""Dollar-cost averaging strategy."""

from __future__ import annotations

from decimal import Decimal

from trading_agent.models import OrderSide, OrderType, PortfolioSnapshot, TradeSignal
from trading_agent.strategies.base import Strategy


class DCAStrategy(Strategy):
    """Buy a fixed dollar amount of target symbols on each run."""

    name = "dca"

    def __init__(self, targets: dict[str, Decimal], amount_per_symbol: Decimal = Decimal("25")):
        self.targets = targets
        self.amount_per_symbol = amount_per_symbol

    def generate(self, portfolio: PortfolioSnapshot) -> list[TradeSignal]:
        signals: list[TradeSignal] = []
        for symbol, target_pct in self.targets.items():
            current_pct = Decimal("0")
            if portfolio.total_value > 0:
                current_pct = portfolio.position_value(symbol) / portfolio.total_value * 100

            if current_pct < target_pct:
                signals.append(
                    TradeSignal(
                        symbol=symbol,
                        side=OrderSide.BUY,
                        order_type=OrderType.MARKET,
                        dollar_amount=self.amount_per_symbol,
                        reason=f"DCA: {current_pct:.1f}% < target {target_pct}%",
                        strategy=self.name,
                        confidence=0.7,
                    )
                )
        return signals
