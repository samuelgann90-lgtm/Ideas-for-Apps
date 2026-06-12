"""Base strategy interface."""

from __future__ import annotations

from abc import ABC, abstractmethod

from trading_agent.models import PortfolioSnapshot, TradeSignal


class Strategy(ABC):
    name: str = "base"

    @abstractmethod
    def generate(self, portfolio: PortfolioSnapshot) -> list[TradeSignal]:
        """Return trade signals based on current portfolio state."""
