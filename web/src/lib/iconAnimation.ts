import type { IconAnimation } from "@/lib/types"

const ICON_ANIMATION_CLASSES: Record<IconAnimation, string> = {
    spin: "icon-animation-spin",
    spinPulse: "icon-animation-spin-pulse",
    spinReverse: "icon-animation-spin-reverse",
    pulse: "icon-animation-pulse",
    beat: "icon-animation-beat",
    fade: "icon-animation-fade",
    beatFade: "icon-animation-beat-fade",
    bounce: "icon-animation-bounce",
    shake: "icon-animation-shake",
}

export function iconAnimationClass(animation?: IconAnimation): string | undefined {
    return animation ? ICON_ANIMATION_CLASSES[animation] : undefined
}
