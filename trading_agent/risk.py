"""Risk management rules for trade signals."""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

from trading_agent.models import OrderSide, PortfolioSnapshot, TradeSignal


@dataclass
class RiskConfig:
    max_order_dollars: Decimal = Decimal("100")
    max_position_pct: Decimal = Decimal("20")
    max_daily_trades: int = 5
    min_buying_power_reserve: Decimal = Decimal("50")
    allowed_symbols: frozenset[str] | None = None
    blocked_symbols: frozenset[str] = frozenset()


class RiskManager:
    def __init__(self, config: RiskConfig):
        self.config = config
        self._trades_today = 0

    def validate(self, signal: TradeSignal, portfolio: PortfolioSnapshot) -> tuple[bool, str]:
        if signal.symbol in self.config.blocked_symbols:
            return False, f"{signal.symbol} is blocked"

        if self.config.allowed_symbols and signal.symbol not in self.config.allowed_symbols:
            return False, f"{signal.symbol} not in allowed list"

        if self._trades_today >= self.config.max_daily_trades:
            return False, f"Daily trade limit ({self.config.max_daily_trades}) reached"

        order_value = self._estimate_order_value(signal, portfolio)
        if order_value > self.config.max_order_dollars:
            return False, f"Order ${order_value:.2f} exceeds max ${self.config.max_order_dollars}"

        if signal.side == OrderSide.BUY:
            available = portfolio.buying_power - self.config.min_buying_power_reserve
            if order_value > available:
                return False, f"Insufficient buying power (need ${order_value:.2f}, have ${available:.2f})"

            new_exposure = portfolio.position_value(signal.symbol) + order_value
            max_allowed = portfolio.total_value * self.config.max_position_pct / 100
            if new_exposure > max_allowed:
                return False, (
                    f"Position would be ${new_exposure:.2f}, "
                    f"exceeding {self.config.max_position_pct}% cap (${max_allowed:.2f})"
                )

        if signal.side == OrderSide.SELL:
            pos = next((p for p in portfolio.positions if p.symbol == signal.symbol), None)
            if not pos:
                return False, f"No position in {signal.symbol} to sell"
            if signal.quantity and signal.quantity > pos.quantity:
                return False, f"Cannot sell {signal.quantity} shares (hold {pos.quantity})"

        return True, "ok"

    def filter_signals(
        self, signals: list[TradeSignal], portfolio: PortfolioSnapshot
    ) -> list[TradeSignal]:
        approved: list[TradeSignal] = []
        for signal in signals:
            ok, _ = self.validate(signal, portfolio)
            if ok:
                approved.append(signal)
        return approved

    def record_trade(self) -> None:
        self._trades_today += 1

    def _estimate_order_value(self, signal: TradeSignal, portfolio: PortfolioSnapshot) -> Decimal:
        if signal.dollar_amount is not None:
            return signal.dollar_amount
        quote = portfolio.quotes.get(signal.symbol)
        price = quote.last_price if quote else Decimal("0")
        qty = signal.quantity or Decimal("0")
        return qty * price
