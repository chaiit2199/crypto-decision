import type { WorkbenchData } from "@/lib/api/trading-types";
import { formatIndicator, formatTime } from "@/lib/format/market";
import {
    ELIGIBILITY_LABELS,
    HOLDING_HORIZON_LABELS,
    REGIME_LABELS,
    RISK_FLAG_LABELS,
    SETUP_LABELS,
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

    return (
        <section
            className="trade-setup-panel"
            aria-label="Phiếu lệnh nghiên cứu"
        >
            <header className="trade-setup-panel__header">
                <div>
                    <h3>Phiếu lệnh Spot</h3>
                    <p>
                        {report.exchange.toUpperCase()} · {report.symbol} ·{" "}
                        {report.quote_asset}
                        {" · "}Chỉ mua Spot · Không đặt lệnh
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
                    <dt>Setup</dt>
                    <dd>
                        {report.setup
                            ? `${SETUP_LABELS[report.setup] ?? report.setup} · ${report.setup_quality}`
                            : "Chưa có"}
                    </dd>
                </div>
                <div>
                    <dt>Jev (nghiên cứu)</dt>
                    <dd>{report.ai_signal}</dd>
                    <dd>Không phải xác suất có lãi.</dd>
                </div>
                <div>
                    <dt>Khung giữ gợi ý</dt>
                    <dd>
                        Jev:{" "}
                        {report.holding_horizon
                            ? HOLDING_HORIZON_LABELS[report.holding_horizon]
                            : "Chưa có"}
                    </dd>
                    <dd>
                        Quy tắc nến:{" "}
                        {report.horizon_deterministic
                            ? HOLDING_HORIZON_LABELS[
                                  report.horizon_deterministic
                              ]
                            : "-"}
                    </dd>
                    <dd>Phân loại bối cảnh · không dự báo lãi dài/ngắn hạn.</dd>
                </div>
                <div>
                    <dt>Cập nhật</dt>
                    <dd>{formatTime(report.as_of)} · UTC+7</dd>
                    <dd>Hết hạn {formatTime(report.valid_until)}</dd>
                </div>
            </dl>

            {missing.length > 0 && (
                <div className="trade-setup-panel__checklist">
                    <h4>Thiếu điều kiện</h4>
                    <ul className="trading-workbench__flags">
                        {missing.map((flag) => (
                            <li key={flag}>{RISK_FLAG_LABELS[flag] ?? flag}</li>
                        ))}
                    </ul>
                </div>
            )}

            {report.trade_eligibility === "RESEARCH_CANDIDATE" && !expired && (
                <p className="trade-setup-panel__research" role="status">
                    Research candidate - Unvalidated. Chưa có xác suất có lãi đã
                    hiệu chuẩn.
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
                        <dt>TP1 / TP2 / TP3</dt>
                        <dd>
                            {formatIndicator(
                                plan.take_profit_1 ?? plan.take_profit,
                            )}
                            {" / "}
                            {formatIndicator(
                                plan.take_profit_2 ?? plan.take_profit,
                            )}
                            {" / "}
                            {formatIndicator(plan.take_profit_3 ?? "-")}
                        </dd>
                    </div>
                    <div>
                        <dt>R:R sau phí (TP2)</dt>
                        <dd>1 : {formatIndicator(plan.risk_reward_ratio)}</dd>
                    </div>
                    <div>
                        <dt>Khối lượng · {quoteAsset}</dt>
                        <dd>{formatIndicator(plan.notional)}</dd>
                    </div>
                    <div>
                        <dt>Rủi ro ngân sách</dt>
                        <dd>
                            {formatIndicator(plan.risk_budget)} {quoteAsset}
                        </dd>
                    </div>
                </dl>
            ) : (
                <p>
                    Chưa hiện mức vào / SL / TP cho đến khi có đủ dữ liệu cùng
                    sàn. Không tạo mức giá giả.
                </p>
            )}
        </section>
    );
}
