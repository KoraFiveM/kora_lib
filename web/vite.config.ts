import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"
import qbtheme from "../../kora_theme/vite-plugin.mjs"

// FiveM's CEF NUI browser loads this page from a local resource path, not
// from a domain root -- asset URLs must be relative ("./assets/..") or every
// script/style 404s in-game. Do NOT change `base` back to "/".
export default defineConfig({
    plugins: [qbtheme(), react()],
    base: "./",
    build: {
        outDir: "build",
        rollupOptions: {
            output: {
                manualChunks(id) {
                    if (id.includes("@fortawesome/free-solid-svg-icons")) return "fa-solid"
                    if (id.includes("@fortawesome/free-regular-svg-icons")) return "fa-regular"
                    if (id.includes("@fortawesome/free-brands-svg-icons")) return "fa-brands"
                    if (id.includes("@fortawesome/react-fontawesome") || id.includes("@fortawesome/fontawesome-svg-core")) return "fa-runtime"
                },
            },
        },
    },
    resolve: {
        alias: {
            "@": path.resolve(__dirname, "./src"),
        },
    },
})
