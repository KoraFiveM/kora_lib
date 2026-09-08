import { MenuContainer } from "@/components/menu/Menu"
import { MenuHeader } from "@/components/menu/MenuHeader"
import { ContextMenuContainer } from "@/components/menu/ContextMenu"
import { InputDialogContainer } from "@/components/input/InputDialog"
import { AlertDialogContainer } from "@/components/alert/AlertDialog"
import { ClipboardHandler } from "@/components/clipboard/ClipboardHandler"
import { Toast } from "@/components/notify/Toast"
import { ProgressBar } from "@/components/progressbar/ProgressBar"
import { ZoneCreatorHud } from "@/components/zones/ZoneCreatorHud"
import { NoclipHud } from "@/components/noclip/NoclipHud"
import { ZoneConfirmDialog } from "@/components/zones/ZoneConfirmDialog"
import { PlacementHud } from "@/components/placement/PlacementHud"
import { PlacementConfirmDialog } from "@/components/placement/PlacementConfirmDialog"
import { MinigameContainer } from "@/components/minigames/MinigameContainer"
import { DevHarness } from "@/components/dev/DevHarness"
import { InteractSelect } from "@/components/interact/InteractSelect"
import { RadialMenuContainer } from "@/components/menu/RadialMenu"
import { TargetHud } from "@/components/target/TargetHud"
import { TextUi } from "@/components/textui/TextUi"
import { AppShell } from "@/components/app/AppShell"
import { ScreenshotCapture } from "@/components/screenshot/ScreenshotCapture"
import { ErrorBoundary } from "@/components/ErrorBoundary"

/**
 * Headless root every top-level NUI component mounts under. Each of these
 * self-subscribes to its own NUI action(s) via useNuiEvent and renders
 * nothing until Lua asks for it, so mounting all of them unconditionally here
 * *is* the registry -- there is no separate dispatch layer. DevHarness is the
 * one exception: it renders its own controls, but only outside the real NUI
 * frame (see isBrowserEnv in lib/fetchNui.ts).
 */
export default function App() {
    return (
        <>
            <ErrorBoundary surface="interaction selector"><InteractSelect /></ErrorBoundary>
            <ErrorBoundary surface="target HUD"><TargetHud /></ErrorBoundary>
            <ErrorBoundary surface="text UI"><TextUi /></ErrorBoundary>
            <ErrorBoundary surface="app shell"><AppShell /></ErrorBoundary>
            <ErrorBoundary surface="menu"><MenuContainer /></ErrorBoundary>
            <ErrorBoundary surface="menu header"><MenuHeader /></ErrorBoundary>
            <ErrorBoundary surface="context menu"><ContextMenuContainer /></ErrorBoundary>
            <ErrorBoundary surface="radial menu"><RadialMenuContainer /></ErrorBoundary>
            <ErrorBoundary surface="input dialog"><InputDialogContainer /></ErrorBoundary>
            <ErrorBoundary surface="alert dialog"><AlertDialogContainer /></ErrorBoundary>
            <ErrorBoundary surface="clipboard"><ClipboardHandler /></ErrorBoundary>
            <ErrorBoundary surface="screenshot capture"><ScreenshotCapture /></ErrorBoundary>
            <ErrorBoundary surface="notifications"><Toast /></ErrorBoundary>
            <ErrorBoundary surface="progress bar"><ProgressBar /></ErrorBoundary>
            <ErrorBoundary surface="zone creator HUD"><ZoneCreatorHud /></ErrorBoundary>
            <ErrorBoundary surface="noclip HUD"><NoclipHud /></ErrorBoundary>
            <ErrorBoundary surface="zone dialog"><ZoneConfirmDialog /></ErrorBoundary>
            <ErrorBoundary surface="placement HUD"><PlacementHud /></ErrorBoundary>
            <ErrorBoundary surface="placement dialog"><PlacementConfirmDialog /></ErrorBoundary>
            <ErrorBoundary surface="minigames"><MinigameContainer /></ErrorBoundary>
            <ErrorBoundary surface="development harness"><DevHarness /></ErrorBoundary>
        </>
    )
}
