import type { WorkbenchData } from "@/lib/api/trading-types";
import { formatIndicator, formatTime } from "@/lib/format/market";

type OrderBookPanelProps = {
    liquidity: WorkbenchData["liquidity"];
    quoteAsset: string;
};

export function OrderBookPanel({ liquidity, quoteAsset }: OrderBookPanelProps) {
    return (
        <section className="order-book-panel" aria-label="Sổ lệnh">
            <header>
                <h3>Sổ lệnh</h3>
                <p>
                    Ảnh chụp lệnh chờ mua/bán tại một thời điểm. Không đếm số
                    người và không phải vùng hỗ trợ/kháng cự trên nến.
                </p>
            </header>

            {liquidity.status === "unsupported" && (
                <p>Nguồn này chưa có sổ lệnh. Không dùng sổ lệnh từ sàn khác.</p>
            )}
            {liquidity.status === "missing" && <p>Chưa có sổ lệnh.</p>}
            {liquidity.status === "stale" && (
                <p>Sổ lệnh đã cũ; chỉ tham khảo, không dùng để vào lệnh.</p>
            )}

            {["fresh", "stale"].includes(liquidity.status) && (
                <>
                    <dl className="trading-workbench__metrics">
                        <div>
                            <dt>Mua / bán tốt nhất</dt>
                            <dd>
                                {formatIndicator(liquidity.bid)} /{" "}
                                {formatIndicator(liquidity.ask)}
                            </dd>
                        </div>
                        <div>
                            <dt>Giá giữa</dt>
                            <dd>{formatIndicator(liquidity.mid_price)}</dd>
                        </div>
                        <div>
                            <dt>Chênh mua/bán</dt>
                            <dd>
                                {formatIndicator(liquidity.spread_bps)} điểm cơ
                                bản
                                {" · "}
                                {formatIndicator(liquidity.spread_percent)}%
                            </dd>
                        </div>
                        <div>
                            <dt>Độ sâu 100 mức · {quoteAsset}</dt>
                            <dd>
                                {formatIndicator(liquidity.bid_depth)}
                                {" / "}
                                {formatIndicator(liquidity.ask_depth)}
                            </dd>
                        </div>
                        <div>
                            <dt>Lệch mua–bán</dt>
                            <dd>{formatIndicator(liquidity.imbalance)}</dd>
                            <dd>
                                Lệch dương không có nghĩa giá sẽ tăng.
                            </dd>
                        </div>
                        <div>
                            <dt>Thời điểm chụp</dt>
                            <dd>
                                {liquidity.fetched_at
                                    ? `${formatTime(liquidity.fetched_at)} · giờ Việt Nam`
                                    : "—"}
                            </dd>
                        </div>
                    </dl>

                    {liquidity.bands && liquidity.bands.length > 0 && (
                        <div className="order-book-panel__bands">
                            <h4>Thanh khoản theo khoảng cách giá giữa</h4>
                            <table>
                                <thead>
                                    <tr>
                                        <th scope="col">Khoảng</th>
                                        <th scope="col">Mua · {quoteAsset}</th>
                                        <th scope="col">Bán · {quoteAsset}</th>
                                        <th scope="col">Lệch</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {liquidity.bands.map((band) => (
                                        <tr key={band.band_pct}>
                                            <td>±{band.band_pct}%</td>
                                            <td>
                                                {formatIndicator(
                                                    band.bid_notional,
                                                )}
                                            </td>
                                            <td>
                                                {formatIndicator(
                                                    band.ask_notional,
                                                )}
                                            </td>
                                            <td>
                                                {formatIndicator(
                                                    band.imbalance,
                                                )}
                                            </td>
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
