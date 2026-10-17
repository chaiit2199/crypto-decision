import { defineConfig } from "@playwright/test";

export default defineConfig({
    testDir: "./tests",
    fullyParallel: false,
    use: {
        baseURL: process.env.WEB_TEST_URL ?? "http://127.0.0.1:3000",
        channel: "chrome",
        headless: true,
    },
});
