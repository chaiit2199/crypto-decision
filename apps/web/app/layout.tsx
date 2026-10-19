import type { Metadata } from "next";
import type { ReactNode } from "react";

import "@/styles/globals.scss";

export const metadata: Metadata = {
    title: "Bảng giá | Crypto Decision",
    description:
        "Theo dõi giá Binance giao ngay, biến động 24 giờ và trạng thái đồng bộ dữ liệu.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
    return (
        <html lang="vi">
            <body>{children}</body>
        </html>
    );
}
