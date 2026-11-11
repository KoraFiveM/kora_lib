import React from "react"
import ReactDOM from "react-dom/client"
import App from "./App"
import { ErrorBoundary } from "./components/ErrorBoundary"
import { getNuiViewport } from "./lib/viewport"
import "./styles/globals.css"

const scaleNui = () => {
  const root = document.getElementById("root")!
  const viewport = getNuiViewport()
  root.style.width = `${viewport.width}px`
  root.style.height = `${viewport.height}px`
  root.style.transform = `scale(${viewport.scale})`
  root.style.transformOrigin = "top left"
}

scaleNui()
window.addEventListener("resize", scaleNui)

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>,
)
