"""Simple momentum strategy based on daily price change."""

from __future__ import annotations

from decimal import Decimal

from trading_agent.models import OrderSide, OrderType, PortfolioSnapshot, TradeSignal
from trading_agent.strategies.base import Strategy


class MomentumStrategy(Strategy):
    """Buy symbols with strong positive momentum; trim losers."""

    name = "momentum"

    def __init__(
        self,
        watchlist: list[str],
        buy_threshold_pct: Decimal = Decimal("2"),
        sell_threshold_pct: Decimal = Decimal("-3"),
        buy_amount: Decimal = Decimal("25"),
        sell_fraction: Decimal = Decimal("0.25"),
    ):
        self.watchlist = watchlist
        self.buy_threshold_pct = buy_threshold_pct
        self.sell_threshold_pct = sell_threshold_pct
        self.buy_amount = buy_amount
        self.sell_fraction = sell_fraction

    def generate(self, portfolio: PortfolioSnapshot) -> list[TradeSignal]:
        signals: list[TradeSignal] = []

        for symbol in self.watchlist:
            quote = portfolio.quotes.get(symbol)
            if not quote or quote.daily_change_pct is None:
                continue

            change = quote.daily_change_pct
            if change >= self.buy_threshold_pct:
                signals.append(
                    TradeSignal(
                        symbol=symbol,
                        side=OrderSide.BUY,
                        order_type=OrderType.MARKET,
                        dollar_amount=self.buy_amount,
                        reason=f"Momentum buy: +{change:.1f}% today",
                        strategy=self.name,
                        confidence=min(float(change) / 10, 0.9),
                    )
                )

        for pos in portfolio.positions:
            quote = portfolio.quotes.get(pos.symbol)
            if not quote or quote.daily_change_pct is None:
                continue
            change = quote.daily_change_pct
            if change <= self.sell_threshold_pct and pos.quantity > 0:
                sell_qty = (pos.quantity * self.sell_fraction).quantize(Decimal("0.000001"))
                if sell_qty > 0:
                    signals.append(
                        TradeSignal(
                            symbol=pos.symbol,
                            side=OrderSide.SELL,
                            order_type=OrderType.MARKET,
                            quantity=sell_qty,
                            reason=f"Momentum trim: {change:.1f}% today",
                            strategy=self.name,
                            confidence=0.6,
                        )
                    )

        return signals
