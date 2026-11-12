import type { DialogSize } from "@/lib/types"

const DIALOG_SIZE_CLASSES: Record<DialogSize, string> = {
    xs: "sm:max-w-xs",
    sm: "sm:max-w-sm",
    md: "sm:max-w-md",
    lg: "sm:max-w-lg",
    xl: "sm:max-w-xl",
}

export function dialogSizeClass(size?: DialogSize, fallback: DialogSize = "md"): string {
    return DIALOG_SIZE_CLASSES[size ?? fallback]
}
