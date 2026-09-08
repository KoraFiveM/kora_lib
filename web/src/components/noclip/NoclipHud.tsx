import { useState } from "react"

import { EditorControlsHud, EditorKey } from "@/components/editor/EditorControlsHud"
import type { NoclipHudPayload } from "@/lib/types"
import { useNuiEvent } from "@/lib/useNuiEvent"

/** Pointer-transparent instructional HUD for a resource-owned noclip session. */
export function NoclipHud() {
    const [active, setActive] = useState(false)

    useNuiEvent<NoclipHudPayload | null | undefined>("noclip:hud", (payload) => {
        setActive(payload?.active === true)
    })

    if (!active) return null

    return (
        <EditorControlsHud
            title="Noclip"
            status={<span className="font-medium text-success">Active</span>}
            controls={
                <>
                    <p><EditorKey>W A S D</EditorKey> move &middot; <EditorKey>Mouse</EditorKey> look</p>
                    <p><EditorKey>Space</EditorKey> rise &middot; <EditorKey>Ctrl</EditorKey> descend</p>
                    <p><EditorKey>Shift</EditorKey> faster &middot; <EditorKey>Alt</EditorKey> precision speed</p>
                    <p><EditorKey>/noclip</EditorKey> disable</p>
                </>
            }
        />
    )
}
