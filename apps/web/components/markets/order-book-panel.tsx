import type { WorkbenchData } from "@/lib/api/trading-types";
import { formatIndicator, formatTime } from "@/lib/format/market";

type OrderBookPanelProps = {
    liquidity: WorkbenchData["liquidity"];
    quoteAsset: string;
};

export function OrderBookPanel({ liquidity, quoteAsset }: OrderBookPanelProps) {
    return (
        <section className="order-book-panel" aria-label="Phân tích sổ lệnh">
            <header>
                <h3>Sổ lệnh hiển thị</h3>
                <p>
                    Bid/ask resting orders từ một ảnh chụp depth. Không phải số người mua/bán
                    và không phải order block trên nến.
                </p>
            </header>

            {liquidity.status === "unsupported" && (
                <p>Nguồn này chưa hỗ trợ sổ lệnh Binance. Không mượn depth từ sàn khác.</p>
            )}
            {liquidity.status === "missing" && <p>Chưa đồng bộ sổ lệnh.</p>}
            {liquidity.status === "stale" && (
                <p>Sổ lệnh đã cũ; số liệu chỉ để tham khảo, không dùng để vào lệnh.</p>
            )}

            {["fresh", "stale"].includes(liquidity.status) && (
                <>
                    <dl className="trading-workbench__metrics">
                        <div>
                            <dt>Best Bid / Ask</dt>
                            <dd>
                                {formatIndicator(liquidity.bid)} / {formatIndicator(liquidity.ask)}
                            </dd>
                        </div>
                        <div>
                            <dt>Mid</dt>
                            <dd>{formatIndicator(liquidity.mid_price)}</dd>
                        </div>
                        <div>
                            <dt>Spread</dt>
                            <dd>
                                {formatIndicator(liquidity.spread_bps)} bps
                                {" · "}
                                {formatIndicator(liquidity.spread_percent)}%
                            </dd>
                        </div>
                        <div>
                            <dt>Depth 100 mức · {quoteAsset}</dt>
                            <dd>
                                {formatIndicator(liquidity.bid_depth)}
                                {" / "}
                                {formatIndicator(liquidity.ask_depth)}
                            </dd>
                        </div>
                        <div>
                            <dt>Imbalance toàn sổ</dt>
                            <dd>{formatIndicator(liquidity.imbalance)}</dd>
                            <dd>Không đồng nghĩa giá sẽ tăng khi imbalance dương.</dd>
                        </div>
                        <div>
                            <dt>Ảnh chụp</dt>
                            <dd>
                                {liquidity.fetched_at
                                    ? `${formatTime(liquidity.fetched_at)} · UTC+7`
                                    : "—"}
                            </dd>
                        </div>
                    </dl>

                    {liquidity.bands && liquidity.bands.length > 0 && (
                        <div className="order-book-panel__bands">
                            <h4>Thanh khoản theo khoảng cách mid</h4>
                            <p>Tường bid/ask nhìn thấy không được gắn nhãn support/resistance.</p>
                            <table>
                                <thead>
                                    <tr>
                                        <th scope="col">Band</th>
                                        <th scope="col">Bid {quoteAsset}</th>
                                        <th scope="col">Ask {quoteAsset}</th>
                                        <th scope="col">Imbalance</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {liquidity.bands.map((band) => (
                                        <tr key={band.band_pct}>
                                            <td>±{band.band_pct}%</td>
                                            <td>{formatIndicator(band.bid_notional)}</td>
                                            <td>{formatIndicator(band.ask_notional)}</td>
                                            <td>{formatIndicator(band.imbalance)}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </>
            )}
        </section>
    );
}
