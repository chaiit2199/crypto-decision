import type { MarketAnalysisData } from "@/lib/api/types";

export type ResolvedStance = "long" | "short" | "neutral";

type Features = MarketAnalysisData["features"];

type IndicatorDef = {
    key: keyof Features;
    name: string;
    description: string;
};

export const CHART_INDICATORS: IndicatorDef[] = [
    {
        key: "ema20",
        name: "EMA20",
        description:
            "Trung bình giá hàm mũ chu kỳ 20 nến 1 giờ, ưu tiên giá gần đây.",
    },
    {
        key: "ema50",
        name: "EMA50",
        description:
            "Trung bình giá hàm mũ chu kỳ 50 nến 1 giờ, ít nhạy hơn EMA20.",
    },
    {
        key: "ema200",
        name: "EMA200",
        description:
            "Trung bình giá hàm mũ chu kỳ 200 nến 1 giờ, mốc xu hướng dài hơn.",
    },
    {
        key: "rsi14",
        name: "RSI14",
        description:
            "Động lượng 14 nến trên thang 0–100; cao nghĩa là phía tăng đang chiếm ưu thế gần đây.",
    },
    {
        key: "macd",
        name: "MACD (12/26)",
        description:
            "Chênh lệch EMA12 và EMA26 — trung bình nhanh so với trung bình chậm.",
    },
    {
        key: "macd_signal",
        name: "Đường tín hiệu MACD (9)",
        description: "Trung bình 9 kỳ của MACD, dùng làm mốc so sánh động lượng.",
    },
    {
        key: "macd_histogram",
        name: "Cột MACD",
        description:
            "MACD trừ đường tín hiệu; dương khi MACD nằm trên đường tín hiệu.",
    },
    {
        key: "atr14",
        name: "ATR14",
        description:
            "Biên độ biến động trung bình 14 nến theo đơn vị giá; không cho biết hướng.",
    },
    {
        key: "adx14",
        name: "ADX14",
        description:
            "Sức mạnh xu hướng 0–100; cao nghĩa là xu hướng rõ, bất kể tăng hay giảm.",
    },
    {
        key: "relative_volume20",
        name: "Khối lượng tương đối (20)",
        description:
            "Khối lượng nến gần nhất chia trung bình 20 nến trước; trên 1 là cao hơn thường lệ.",
    },
    {
        key: "return_1h_percent",
        name: "Biến động 1 giờ (%)",
        description: "Phần trăm đổi giá giữa hai lần đóng nến 1 giờ gần nhất.",
    },
    {
        key: "return_24h_percent",
        name: "Biến động 24 giờ (%)",
        description: "Phần trăm đổi giá đóng cửa gần nhất so với 24 nến 1 giờ trước.",
    },
];

function num(value: string | null | undefined): number | null {
    if (value == null || value === "") {
        return null;
    }
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
}

function compare(
    left: string | null | undefined,
    right: string | null | undefined,
): -1 | 0 | 1 | null {
    const a = num(left);
    const b = num(right);
    if (a == null || b == null) {
        return null;
    }
    if (a === b) {
        return 0;
    }
    return a > b ? 1 : -1;
}

/** Map a fresh Jev signal to indicator reading context; WAIT/NO_DATA stay neutral. */
export function resolveResearchStance(
    jevSignal: MarketAnalysisData["signal"] | null | undefined,
): ResolvedStance {
    if (jevSignal === "BUY") {
        return "long";
    }
    if (jevSignal === "SELL") {
        return "short";
    }
    return "neutral";
}

export function researchStanceLabel(stance: ResolvedStance): string {
    if (stance === "long") {
        return "Long · theo dõi mua / giữ";
    }
    if (stance === "short") {
        return "Short · theo dõi bán / giảm vị thế";
    }
    return "Trung lập · chờ đồng thuận";
}

/** What the current reading implies for research, never an execution order. */
export function indicatorReading(
    key: keyof Features,
    features: Features,
    price: string | undefined,
    stance: ResolvedStance,
): string {
    const priceVs = (emaKey: "ema20" | "ema50" | "ema200") =>
        compare(price, features[emaKey]);

    switch (key) {
        case "ema20": {
            const vs = priceVs("ema20");
            if (vs === 1) {
                return stance === "short"
                    ? "Giá trên EMA20: đà ngắn hạn vẫn nghiêng mua — Short cần chờ giá yếu hơn hoặc xác nhận đảo chiều."
                    : "Giá trên EMA20: đà ngắn hạn nghiêng mua / giữ; Long được hỗ trợ ở khung này.";
            }
            if (vs === -1) {
                return stance === "long"
                    ? "Giá dưới EMA20: đà ngắn hạn yếu — Long cần thận trọng hoặc chờ giá lấy lại EMA20."
                    : "Giá dưới EMA20: đà ngắn hạn nghiêng bán / giảm vị thế.";
            }
            return "Chưa đủ giá hoặc EMA20 để rút kết luận.";
        }
        case "ema50": {
            const vs = priceVs("ema50");
            const stack = compare(features.ema20, features.ema50);
            if (vs === 1 && stack === 1) {
                return "Giá và EMA20 đều trên EMA50: cấu trúc trung hạn nghiêng tăng — thuận Long hơn Short.";
            }
            if (vs === -1 && stack === -1) {
                return "Giá và EMA20 đều dưới EMA50: cấu trúc trung hạn nghiêng giảm — thuận Short / giảm vị thế hơn Long.";
            }
            if (vs === 1) {
                return "Giá trên EMA50 nhưng xếp tầng EMA chưa sạch — xu hướng trung hạn chưa đồng thuận.";
            }
            if (vs === -1) {
                return "Giá dưới EMA50 nhưng xếp tầng EMA chưa sạch — áp lực giảm chưa chắc chắn.";
            }
            return "Chưa đủ dữ liệu EMA50 để rút kết luận.";
        }
        case "ema200": {
            const vs = priceVs("ema200");
            if (vs === 1) {
                return "Giá trên EMA200: bối cảnh dài hạn nghiêng tăng — ưu tiên kịch bản Long / giữ, Short mang tính phản xu hướng.";
            }
            if (vs === -1) {
                return "Giá dưới EMA200: bối cảnh dài hạn nghiêng giảm — ưu tiên thận trọng với Long dài hạn, Short / giảm vị thế hợp ngữ cảnh hơn.";
            }
            return "Chưa đủ dữ liệu EMA200 để rút kết luận.";
        }
        case "rsi14": {
            const rsi = num(features.rsi14);
            if (rsi == null) {
                return "Chưa có RSI để rút kết luận.";
            }
            if (rsi >= 70) {
                return stance === "long"
                    ? `RSI ${rsi.toFixed(1)} vùng cao: Long dễ bị rút ngắn hạn — cân nhắc chờ dịu động lượng.`
                    : `RSI ${rsi.toFixed(1)} vùng cao: động lượng mua đã căng — Short phản hồi có thể được theo dõi, không phải lệnh bán chắc.`;
            }
            if (rsi <= 30) {
                return stance === "short"
                    ? `RSI ${rsi.toFixed(1)} vùng thấp: Short dễ bị bật lại — chờ xác nhận yếu tiếp.`
                    : `RSI ${rsi.toFixed(1)} vùng thấp: áp lực bán mạnh gần đây — Long cần chờ ổn định, không bắt đáy sớm.`;
            }
            if (rsi >= 55) {
                return "RSI nghiêng tích cực vừa phải — hỗ trợ thiên hướng mua/giữ hơn bán mạnh.";
            }
            if (rsi <= 45) {
                return "RSI nghiêng tiêu cực vừa phải — hỗ trợ thận trọng với Long, nghiêng theo dõi giảm vị thế.";
            }
            return "RSI quanh vùng giữa — chưa nghiêng rõ Long hay Short.";
        }
        case "macd":
        case "macd_signal": {
            const side = compare(features.macd, features.macd_signal);
            if (side === 1) {
                return "MACD trên đường tín hiệu: động lượng nghiêng mua — thuận Long hơn Short trong ngắn hạn.";
            }
            if (side === -1) {
                return "MACD dưới đường tín hiệu: động lượng nghiêng bán — thuận Short / giảm vị thế hơn Long.";
            }
            return "MACD và đường tín hiệu chưa tách rõ — động lượng trung lập.";
        }
        case "macd_histogram": {
            const hist = num(features.macd_histogram);
            if (hist == null) {
                return "Chưa có cột MACD.";
            }
            if (hist > 0) {
                return "Cột MACD dương: lực mua đang chiếm ưu thế tương đối.";
            }
            if (hist < 0) {
                return "Cột MACD âm: lực bán đang chiếm ưu thế tương đối.";
            }
            return "Cột MACD quanh 0 — động lượng cân bằng tạm thời.";
        }
        case "atr14": {
            const atr = num(features.atr14);
            if (atr == null) {
                return "Chưa có ATR.";
            }
            return `ATR ≈ ${atr}: biên độ dao động tham chiếu để đặt dừng lỗ / khoảng kỳ vọng — không chỉ hướng Long hay Short.`;
        }
        case "adx14": {
            const adx = num(features.adx14);
            if (adx == null) {
                return "Chưa có ADX.";
            }
            if (adx >= 25) {
                return `ADX ${adx.toFixed(1)} ≥ 25: xu hướng đủ mạnh để ưu tiên đi theo hướng đã xác nhận (Long hoặc Short), tránh đi ngang.`;
            }
            if (adx <= 15) {
                return `ADX ${adx.toFixed(1)} thấp: thị trường yếu xu hướng — Long/Short đều dễ nhiễu, ưu tiên chờ.`;
            }
            return `ADX ${adx.toFixed(1)} trung bình: xu hướng chưa thật sự mạnh.`;
        }
        case "relative_volume20": {
            const vol = num(features.relative_volume20);
            if (vol == null) {
                return "Chưa có khối lượng tương đối.";
            }
            if (vol >= 1.5) {
                return `Khối lượng ×${vol.toFixed(2)} cao: tín hiệu giá kèm thanh khoản mạnh hơn — tăng độ tin cậy hướng đang chạy.`;
            }
            if (vol <= 0.7) {
                return `Khối lượng ×${vol.toFixed(2)} thấp: biến động dễ “ảo” — hạn chế tin Long/Short chỉ dựa vào một nến.`;
            }
            return `Khối lượng ×${vol.toFixed(2)} quanh trung bình — không làm lệch mạnh thiên hướng.`;
        }
        case "return_1h_percent": {
            const ret = num(features.return_1h_percent);
            if (ret == null) {
                return "Chưa có biến động 1 giờ.";
            }
            if (ret > 0) {
                return `1 giờ vừa qua +${ret.toFixed(2)}%: nhịp ngắn nghiêng tăng — hỗ trợ Long tạm thời.`;
            }
            if (ret < 0) {
                return `1 giờ vừa qua ${ret.toFixed(2)}%: nhịp ngắn nghiêng giảm — hỗ trợ thận trọng / Short tạm thời.`;
            }
            return "1 giờ vừa qua gần như đi ngang.";
        }
        case "return_24h_percent": {
            const ret = num(features.return_24h_percent);
            if (ret == null) {
                return "Chưa có biến động 24 giờ.";
            }
            if (ret > 0) {
                return `24 giờ +${ret.toFixed(2)}%: nền ngày nghiêng tăng — Long trong ngày hợp ngữ cảnh hơn nếu khung lớn đồng thuận.`;
            }
            if (ret < 0) {
                return `24 giờ ${ret.toFixed(2)}%: nền ngày nghiêng giảm — Short / giảm vị thế hợp ngữ cảnh hơn nếu khung lớn đồng thuận.`;
            }
            return "24 giờ gần như đi ngang.";
        }
        default:
            return "Chưa có quy tắc diễn giải cho chỉ báo này.";
    }
}
