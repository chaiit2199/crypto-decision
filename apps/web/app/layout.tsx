import type { Metadata } from "next";
import type { ReactNode } from "react";

import "@/styles/globals.scss";

export const metadata: Metadata = {
    title: "Bảng giá | Crypto Decision",
    description:
        "Theo dõi giá Binance giao ngay, biến động 24 giờ và trạng thái đồng bộ dữ liệu.",
    // public/favicon.png + app/icon.png (Next file convention) after web deploy.
    icons: {
        icon: [{ url: "/favicon.png", type: "image/png", sizes: "200x200" }],
        shortcut: "/favicon.png",
        apple: [{ url: "/logo.png", type: "image/png", sizes: "200x200" }],
    },
};

export default function RootLayout({ children }: { children: ReactNode }) {
    return (
        <html lang="vi">
            <body>{children}</body>
        </html>
    );
}
