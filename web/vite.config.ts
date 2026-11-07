import path from "path"
import { existsSync } from "node:fs"
import { pathToFileURL } from "node:url"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

const themePlugin = ["../../kora_theme/vite-plugin.mjs", "../../../[standalone]/kora_theme/vite-plugin.mjs"]
    .map((candidate) => path.resolve(__dirname, candidate))
    .find(existsSync)
if (!themePlugin) throw new Error("Could not find kora_theme/vite-plugin.mjs")
const { default: qbtheme } = await import(pathToFileURL(themePlugin).href)

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
