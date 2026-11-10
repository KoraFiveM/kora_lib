import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"
import kora_theme from "../../kora_theme/vite-plugin.mjs"

export default defineConfig({
    plugins: [kora_theme(), react()],
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
