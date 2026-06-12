"""Trading agent orchestrator."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any

import yaml

from trading_agent.models import PortfolioSnapshot, Quote, TradeSignal
from trading_agent.risk import RiskConfig, RiskManager
from trading_agent.strategies import DCAStrategy, MomentumStrategy, RebalanceStrategy
from trading_agent.strategies.base import Strategy


@dataclass
class AgentConfig:
    account_number: str
    strategies: list[str]
    risk: RiskConfig
    dca_targets: dict[str, Decimal]
    dca_amount: Decimal
    momentum_watchlist: list[str]
    rebalance_targets: dict[str, Decimal]

    @classmethod
    def from_yaml(cls, path: Path) -> AgentConfig:
        with open(path) as f:
            raw = yaml.safe_load(f)

        risk_raw = raw.get("risk", {})
        return cls(
            account_number=raw["account_number"],
            strategies=raw.get("strategies", ["dca"]),
            risk=RiskConfig(
                max_order_dollars=Decimal(str(risk_raw.get("max_order_dollars", 100))),
                max_position_pct=Decimal(str(risk_raw.get("max_position_pct", 20))),
                max_daily_trades=int(risk_raw.get("max_daily_trades", 5)),
                min_buying_power_reserve=Decimal(str(risk_raw.get("min_buying_power_reserve", 50))),
                allowed_symbols=frozenset(risk_raw["allowed_symbols"])
                if risk_raw.get("allowed_symbols")
                else None,
                blocked_symbols=frozenset(risk_raw.get("blocked_symbols", [])),
            ),
            dca_targets={k: Decimal(str(v)) for k, v in raw.get("dca", {}).get("targets", {}).items()},
            dca_amount=Decimal(str(raw.get("dca", {}).get("amount_per_symbol", 25))),
            momentum_watchlist=raw.get("momentum", {}).get("watchlist", []),
            rebalance_targets={
                k: Decimal(str(v)) for k, v in raw.get("rebalance", {}).get("targets", {}).items()
            },
        )


class TradingAgent:
    def __init__(self, config: AgentConfig):
        self.config = config
        self.risk = RiskManager(config.risk)
        self._strategies = self._build_strategies()

    def _build_strategies(self) -> list[Strategy]:
        strategies: list[Strategy] = []
        for name in self.config.strategies:
            if name == "dca":
                strategies.append(DCAStrategy(self.config.dca_targets, self.config.dca_amount))
            elif name == "momentum":
                strategies.append(MomentumStrategy(self.config.momentum_watchlist))
            elif name == "rebalance":
                strategies.append(RebalanceStrategy(self.config.rebalance_targets))
        return strategies

    def analyze(self, portfolio: PortfolioSnapshot) -> list[TradeSignal]:
        all_signals: list[TradeSignal] = []
        for strategy in self._strategies:
            all_signals.extend(strategy.generate(portfolio))
        return self.risk.filter_signals(all_signals, portfolio)

    def format_report(self, portfolio: PortfolioSnapshot, signals: list[TradeSignal]) -> str:
        lines = [
            "# Trading Agent Report",
            "",
            f"Account: ••••{portfolio.account_number[-4:]}",
            f"Total value: ${portfolio.total_value:,.2f}",
            f"Buying power: ${portfolio.buying_power:,.2f}",
            f"Equity exposure: ${portfolio.equity_exposure():,.2f}",
            "",
            "## Positions",
        ]
        for pos in portfolio.positions:
            value = portfolio.position_value(pos.symbol)
            quote = portfolio.quotes.get(pos.symbol)
            change = f" ({quote.daily_change_pct:+.1f}%)" if quote and quote.daily_change_pct else ""
            lines.append(f"- {pos.symbol}: {pos.quantity} shares, ${value:,.2f}{change}")

        lines.extend(["", "## Recommended Trades"])
        if not signals:
            lines.append("No trades recommended.")
        else:
            for i, sig in enumerate(signals, 1):
                amount = (
                    f"${sig.dollar_amount}"
                    if sig.dollar_amount
                    else f"{sig.quantity} shares"
                )
                lines.append(
                    f"{i}. **{sig.side.value.upper()} {sig.symbol}** — {amount} "
                    f"({sig.strategy}: {sig.reason})"
                )

        lines.extend(["", "## MCP Execution Steps"])
        for sig in signals:
            review = sig.to_mcp_review(self.config.account_number)
            lines.append(f"- `review_equity_order({json.dumps(review)})` → confirm → `place_equity_order`")

        return "\n".join(lines)

    @staticmethod
    def portfolio_from_mcp_payload(payload: dict[str, Any]) -> PortfolioSnapshot:
        """Build a PortfolioSnapshot from MCP tool responses."""
        account = payload["account_number"]
        portfolio = payload["portfolio"]
        positions = payload.get("positions", [])
        quotes_raw = payload.get("quotes", {})

        quotes = {
            sym: Quote.from_mcp(sym, q) if isinstance(q, dict) else q
            for sym, q in quotes_raw.items()
        }
        return PortfolioSnapshot.from_mcp(account, portfolio, positions, quotes)
