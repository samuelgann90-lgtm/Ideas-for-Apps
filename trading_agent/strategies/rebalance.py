"""Portfolio rebalancing strategy."""

from __future__ import annotations

from decimal import Decimal

from trading_agent.models import OrderSide, OrderType, PortfolioSnapshot, TradeSignal
from trading_agent.strategies.base import Strategy


class RebalanceStrategy(Strategy):
    """Rebalance toward target allocation weights."""

    name = "rebalance"

    def __init__(
        self,
        targets: dict[str, Decimal],
        threshold_pct: Decimal = Decimal("5"),
        min_trade_dollars: Decimal = Decimal("10"),
    ):
        self.targets = targets
        self.threshold_pct = threshold_pct
        self.min_trade_dollars = min_trade_dollars

    def generate(self, portfolio: PortfolioSnapshot) -> list[TradeSignal]:
        if portfolio.total_value <= 0:
            return []

        signals: list[TradeSignal] = []
        for symbol, target_pct in self.targets.items():
            current_value = portfolio.position_value(symbol)
            current_pct = current_value / portfolio.total_value * 100
            drift = current_pct - target_pct

            if abs(drift) < self.threshold_pct:
                continue

            target_value = portfolio.total_value * target_pct / 100
            delta = target_value - current_value

            if abs(delta) < self.min_trade_dollars:
                continue

            if delta > 0:
                signals.append(
                    TradeSignal(
                        symbol=symbol,
                        side=OrderSide.BUY,
                        order_type=OrderType.MARKET,
                        dollar_amount=delta.quantize(Decimal("0.01")),
                        reason=f"Rebalance: {current_pct:.1f}% → target {target_pct}%",
                        strategy=self.name,
                        confidence=0.8,
                    )
                )
            else:
                quote = portfolio.quotes.get(symbol)
                if not quote or quote.last_price <= 0:
                    continue
                pos = next((p for p in portfolio.positions if p.symbol == symbol), None)
                if not pos:
                    continue
                sell_qty = (abs(delta) / quote.last_price).quantize(Decimal("0.000001"))
                sell_qty = min(sell_qty, pos.quantity)
                if sell_qty > 0:
                    signals.append(
                        TradeSignal(
                            symbol=symbol,
                            side=OrderSide.SELL,
                            order_type=OrderType.MARKET,
                            quantity=sell_qty,
                            reason=f"Rebalance: {current_pct:.1f}% → target {target_pct}%",
                            strategy=self.name,
                            confidence=0.8,
                        )
                    )

        return signals
