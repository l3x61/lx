import { defineConfig } from "vitepress";
import { lx } from "./languages/lx";
import { wsn } from "./languages/wsn";

export default defineConfig({
    lang: "en-US",
    title: "Lx Reference",
    description: "Lambda Expression Language",

    markdown: {
        theme: { light: "github-light", dark: "github-dark" },
        shikiSetup: async (shiki) => {
            await shiki.loadLanguage(lx);
            await shiki.loadLanguage(wsn);
        },
    },

    themeConfig: {
        nav: [
            { text: "Home", link: "/" },
            { text: "Reference", link: "/lxref" },
        ],
        search: {
            provider: "local",
        },
        outline: {
            level: [2, 6],
        },
        socialLinks: [{ icon: "github", link: "https://github.com/l3x61/lx" }],
    },
});
