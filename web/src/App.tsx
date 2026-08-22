import { MenuContainer } from "@/components/menu/Menu"
import { ContextMenuContainer } from "@/components/menu/ContextMenu"
import { InputDialogContainer } from "@/components/input/InputDialog"
import { AlertDialogContainer } from "@/components/alert/AlertDialog"
import { ClipboardHandler } from "@/components/clipboard/ClipboardHandler"
import { Toast } from "@/components/notify/Toast"
import { ProgressBar } from "@/components/progressbar/ProgressBar"
import { ZoneCreatorHud } from "@/components/zones/ZoneCreatorHud"
import { ZoneConfirmDialog } from "@/components/zones/ZoneConfirmDialog"
import { MinigameContainer } from "@/components/minigames/MinigameContainer"
import { DevHarness } from "@/components/dev/DevHarness"
import { ThemeSynchronizer } from "@/components/theme/ThemeSynchronizer"

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
            <ThemeSynchronizer />
            <MenuContainer />
            <ContextMenuContainer />
            <InputDialogContainer />
            <AlertDialogContainer />
            <ClipboardHandler />
            <Toast />
            <ProgressBar />
            <ZoneCreatorHud />
            <ZoneConfirmDialog />
            <MinigameContainer />
            <DevHarness />
        </>
    )
}
