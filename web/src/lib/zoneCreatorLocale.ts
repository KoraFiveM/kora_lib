import type { ZoneCreatorLabels } from "@/lib/types"

export const defaultZoneCreatorLabels: ZoneCreatorLabels = {
    types: { box: "box", sphere: "sphere", poly: "polygon" },
    building: "Building: %s", starting: "Starting…", shiftFast: "Shift: fast adjust", enterConfirm: "Enter confirm",
    pointOne: "%d point placed", pointMany: "%d points placed", centerPlaced: "Center placed",
    aimPlace: "Aim and press %s to place", editingPoint: "Editing point %d of %d — %s moves it here",
    editingPointsEmpty: "Editing points — place some first", editingPointsAim: "Editing points — aim near one to grab it",
    params: { size: "size", height: "height", rotation: "rotation", radius: "radius", thickness: "thickness", zOffset: "height offset", editPoint: "point editing" },
    stepScroll: "(±%s/scroll)", confirmTitle: "Confirm %s zone", generatedData: "Generated zone data",
    clipboardFailed: "Clipboard copy failed. The zone creator is still open.", keepEditing: "Keep Editing",
    copied: "Copied", copyFailed: "Copy failed", copyCode: "Copy code", copyConfirm: "Copy & Confirm",
    copiedAnnouncement: "Zone data copied to clipboard.", copyFailedAnnouncement: "Could not copy zone data.",
}

export function formatZoneCreatorLabel(template: string, ...values: Array<string | number>) {
    let index = 0
    return template.replace(/%[sd]/g, () => String(values[index++] ?? ""))
}
