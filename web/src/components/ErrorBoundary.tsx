import { Component, type ErrorInfo, type ReactNode } from "react"

interface Props {
    children: ReactNode
}

interface State {
    hasError: boolean
}

/**
 * Root error boundary: a render-phase crash in any one NUI component must not
 * unmount the whole overlay (React 18 unmounts the entire root on an uncaught
 * render error, which would silently kill menus, toasts, the zone creator HUD
 * -- everything -- for the rest of the session). The overlay is headless, so
 * the fallback renders nothing; the error is logged to the NUI console.
 */
export class ErrorBoundary extends Component<Props, State> {
    state: State = { hasError: false }

    static getDerivedStateFromError(): State {
        return { hasError: true }
    }

    componentDidCatch(error: Error, info: ErrorInfo) {
        console.error("[qblib] NUI render error:", error, info.componentStack)
    }

    render() {
        if (this.state.hasError) return null
        return this.props.children
    }
}
