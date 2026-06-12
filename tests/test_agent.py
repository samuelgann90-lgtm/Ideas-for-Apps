"""Tests for the trading agent."""

from decimal import Decimal

from trading_agent.agent import AgentConfig, TradingAgent
from trading_agent.models import PortfolioSnapshot, Position, Quote
from trading_agent.risk import RiskConfig, RiskManager
from trading_agent.models import OrderSide, OrderType, TradeSignal


def _sample_portfolio() -> PortfolioSnapshot:
    quotes = {
        "AMD": Quote("AMD", Decimal("120"), Decimal("115")),
        "NVDA": Quote("NVDA", Decimal("500"), Decimal("480")),
    }
    return PortfolioSnapshot(
        account_number="123456789",
        total_value=Decimal("1000"),
        cash=Decimal("400"),
        buying_power=Decimal("400"),
        positions=(Position("AMD", Decimal("2"), Decimal("100")),),
        quotes=quotes,
    )


def test_momentum_generates_buy_on_strong_move():
    cfg = AgentConfig(
        account_number="123",
        strategies=["momentum"],
        risk=RiskConfig(max_order_dollars=Decimal("100")),
        dca_targets={},
        dca_amount=Decimal("25"),
        momentum_watchlist=["NVDA"],
        rebalance_targets={},
    )
    agent = TradingAgent(cfg)
    signals = agent.analyze(_sample_portfolio())
    nvda_buys = [s for s in signals if s.symbol == "NVDA" and s.side == OrderSide.BUY]
    assert len(nvda_buys) >= 1


def test_risk_blocks_oversized_order():
    rm = RiskManager(RiskConfig(max_order_dollars=Decimal("10")))
    signal = TradeSignal(
        symbol="AMD",
        side=OrderSide.BUY,
        order_type=OrderType.MARKET,
        dollar_amount=Decimal("50"),
    )
    ok, reason = rm.validate(signal, _sample_portfolio())
    assert not ok
    assert "exceeds max" in reason


def test_price_scale():
    q = Quote.from_mcp("MU", {"last_trade_price": "995.650000", "previous_close": "995.870000"})
    assert q.last_price == Decimal("99.565")
