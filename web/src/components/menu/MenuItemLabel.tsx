import { isIconImage, resolveIcon } from "@/lib/icon"
import { iconAnimationClass } from "@/lib/iconAnimation"
import { cn } from "@/lib/cn"
import type { MenuItem } from "@/lib/types"
import { Markdown } from "@/components/ui/markdown"

function metadataValue(value: unknown): string {
    if (value === undefined || value === null) return ""
    if (typeof value === "object") {
        try {
            return JSON.stringify(value)
        } catch {
            return String(value)
        }
    }
    return String(value)
}

function progressValue(value?: number): number | undefined {
    return typeof value === "number" && Number.isFinite(value)
        ? Math.max(0, Math.min(100, value))
        : undefined
}

/**
 * The icon + label + optional-description body of a menu row, shared by
 * Menu.tsx's CommandItem and ContextMenu.tsx's button so the two menu
 * surfaces render items identically.
 */
export function MenuItemLabel({ item, valueIndex, checked }: { item: MenuItem; valueIndex?: number; checked?: boolean }) {
    const iconIsImage = isIconImage(item.icon)
    const Icon = iconIsImage ? undefined : resolveIcon(item.icon)
    const selectedValue = item.values?.[valueIndex ?? Math.max(0, (item.defaultIndex ?? 1) - 1)]
    const valueLabel = typeof selectedValue === "object" ? selectedValue.label : selectedValue
    const valueDescription = typeof selectedValue === "object" ? selectedValue.description : undefined
    const progress = progressValue(item.progress)
    const imageStyle = {
        width: item.iconWidth === undefined ? undefined : Math.max(0, Math.min(100, item.iconWidth)),
        height: item.iconHeight === undefined ? undefined : Math.max(0, Math.min(100, item.iconHeight)),
    }

    return (
        <>
            {item.image || iconIsImage ? (
                <img aria-hidden src={item.image ?? item.icon} className="mt-0.5 h-5 w-5 max-h-24 max-w-24 shrink-0 rounded-sm object-contain" style={imageStyle} />
            ) : Icon ? <Icon aria-hidden className={cn("mt-0.5 h-4 w-4 shrink-0", iconAnimationClass(item.iconAnimation))} style={{ color: item.iconColor }} /> : null}
            <span className="flex min-w-0 flex-1 flex-col items-start gap-0.5">
                <span className="flex w-full min-w-0 items-center gap-2">
                    <span className="min-w-0 flex-1 truncate"><Markdown inline>{item.label}</Markdown></span>
                    {valueLabel !== undefined ? <span className="shrink-0 text-xs text-muted-foreground">‹ {valueLabel} ›</span> : null}
                    {item.checked !== undefined ? <span aria-label={checked ? "On" : "Off"} className="relative h-5 w-9 shrink-0 rounded-full bg-muted"><span className={`absolute top-0.5 h-4 w-4 rounded-full bg-foreground transition-transform ${checked ? "translate-x-[18px]" : "translate-x-0.5"}`} /></span> : null}
                </span>
                {progress !== undefined ? <span className="h-1.5 w-full overflow-hidden rounded-full bg-muted"><span className="block h-full rounded-full bg-primary" style={{ width: `${progress}%`, backgroundColor: item.colorScheme }} /></span> : null}
                {valueDescription || item.description ? (
                    <span className="w-full text-xs text-muted-foreground"><Markdown>{valueDescription ?? item.description ?? ""}</Markdown></span>
                ) : null}
                {item.metadata?.length ? (
                    <span className="mt-1 flex w-full flex-col gap-1 border-t border-border pt-1.5 text-xs text-muted-foreground">
                        {item.metadata.map((metadata, index) => {
                            if (typeof metadata === "string") return <span key={`${metadata}-${index}`}><Markdown inline>{metadata}</Markdown></span>
                            const metadataProgress = progressValue(metadata.progress)
                            return (
                                <span key={`${metadata.label}-${index}`} className="flex flex-col gap-1">
                                    <span><span className="text-secondary-foreground">{metadata.label}</span>{metadata.value === undefined ? "" : `: ${metadataValue(metadata.value)}`}</span>
                                    {metadataProgress !== undefined ? (
                                        <span className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
                                            <span className="block h-full rounded-full bg-primary" style={{ width: `${metadataProgress}%`, backgroundColor: metadata.colorScheme ?? item.colorScheme }} />
                                        </span>
                                    ) : null}
                                </span>
                            )
                        })}
                    </span>
                ) : null}
            </span>
        </>
    )
}
