import type { WorkbenchData } from "@/lib/api/trading-types";
import { formatIndicator, formatTime } from "@/lib/format/market";
import {
    AI_REASON_LABELS,
    AI_SIGNAL_LABELS,
    ELIGIBILITY_LABELS,
    HOLDING_HORIZON_LABELS,
    REGIME_LABELS,
    RISK_FLAG_LABELS,
    SETUP_LABELS,
    SETUP_QUALITY_LABELS,
} from "@/lib/markets/trading-labels";

type TradeSetupPanelProps = {
    report: WorkbenchData;
    quoteAsset: string;
    expired: boolean;
};

export function TradeSetupPanel({
    report,
    quoteAsset,
    expired,
}: TradeSetupPanelProps) {
    const plan = !expired ? report.plan : null;
    const showLevels = plan && report.trade_eligibility !== "NO_DATA";
    const missing = report.missing_requirements ?? [];
    const setupLabel = report.setup
        ? `${SETUP_LABELS[report.setup] ?? report.setup} · ${SETUP_QUALITY_LABELS[report.setup_quality] ?? report.setup_quality}`
        : "Chưa có";

    return (
        <section
            className="trade-setup-panel"
            aria-label="Phiếu lệnh nghiên cứu"
        >
            <header className="trade-setup-panel__header">
                <div>
                    <h3>Phiếu lệnh</h3>
                    <p>
                        {report.exchange.toUpperCase()} · {report.symbol} ·{" "}
                        {report.quote_asset} · Chỉ nghiên cứu, không đặt lệnh
                    </p>
                </div>
                <p
                    className="trade-setup-panel__badge"
                    data-status={expired ? "NO_DATA" : report.trade_eligibility}
                >
                    {expired
                        ? "Dữ liệu đã cũ · chờ cập nhật"
                        : ELIGIBILITY_LABELS[report.trade_eligibility]}
                </p>
            </header>

            <dl className="trading-workbench__metrics">
                <div>
                    <dt>Xu hướng</dt>
                    <dd>{REGIME_LABELS[report.market_regime]}</dd>
                </div>
                <div>
                    <dt>Mẫu hình</dt>
                    <dd>{setupLabel}</dd>
                </div>
                <div>
                    <dt>Nhận định Jev</dt>
                    <dd>
                        {AI_SIGNAL_LABELS[report.ai_signal] ?? report.ai_signal}
                    </dd>
                    {report.ai_signal === "NO_DATA" && report.ai_reason ? (
                        <dd>
                            {AI_REASON_LABELS[report.ai_reason] ??
                                report.ai_reason}
                        </dd>
                    ) : null}
                </div>
                <div>
                    <dt>Thời gian giữ gợi ý</dt>
                    <dd>
                        Theo Jev:{" "}
                        {report.holding_horizon
                            ? HOLDING_HORIZON_LABELS[report.holding_horizon]
                            : "Chưa có"}
                    </dd>
                    <dd>
                        Theo nến:{" "}
                        {report.horizon_deterministic
                            ? HOLDING_HORIZON_LABELS[
                                  report.horizon_deterministic
                              ]
                            : "—"}
                    </dd>
                </div>
                <div>
                    <dt>Cập nhật</dt>
                    <dd>{formatTime(report.as_of)} · giờ Việt Nam</dd>
                    <dd>Hết hạn {formatTime(report.valid_until)}</dd>
                </div>
            </dl>

            {missing.length > 0 && (
                <div className="trade-setup-panel__checklist">
                    <h4>Điều kiện còn thiếu</h4>
                    <ul className="trading-workbench__flags">
                        {missing.map((flag) => (
                            <li key={flag}>{RISK_FLAG_LABELS[flag] ?? flag}</li>
                        ))}
                    </ul>
                </div>
            )}

            {report.trade_eligibility === "RESEARCH_CANDIDATE" && !expired && (
                <p className="trade-setup-panel__research" role="status">
                    Đáng theo dõi để nghiên cứu · chưa kiểm chứng lợi nhuận.
                </p>
            )}

            {showLevels ? (
                <dl className="trading-workbench__metrics">
                    <div>
                        <dt>Vùng vào · {quoteAsset}</dt>
                        <dd>
                            {formatIndicator(plan.entry_min ?? plan.entry)}
                            {" – "}
                            {formatIndicator(plan.entry_max ?? plan.entry)}
                        </dd>
                    </div>
                    <div>
                        <dt>Dừng lỗ</dt>
                        <dd>{formatIndicator(plan.stop_loss)}</dd>
                    </div>
                    <div>
                        <dt>Chốt lời 1 / 2 / 3</dt>
                        <dd>
                            {formatIndicator(
                                plan.take_profit_1 ?? plan.take_profit,
                            )}
                            {" / "}
                            {formatIndicator(
                                plan.take_profit_2 ?? plan.take_profit,
                            )}
                            {" / "}
                            {formatIndicator(plan.take_profit_3 ?? "—")}
                        </dd>
                    </div>
                    <div>
                        <dt>Tỷ lệ lãi/rủi ro sau phí</dt>
                        <dd>1 : {formatIndicator(plan.risk_reward_ratio)}</dd>
                    </div>
                    <div>
                        <dt>Giá trị lệnh · {quoteAsset}</dt>
                        <dd>{formatIndicator(plan.notional)}</dd>
                    </div>
                    <div>
                        <dt>Ngân sách rủi ro</dt>
                        <dd>
                            {formatIndicator(plan.risk_budget)} {quoteAsset}
                        </dd>
                    </div>
                </dl>
            ) : (
                <p>
                    Chưa hiện vùng vào / dừng lỗ / chốt lời vì thiếu dữ liệu cùng
                    sàn.
                </p>
            )}
        </section>
    );
}
