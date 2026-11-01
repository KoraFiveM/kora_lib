import { createElement, useEffect, useState, type ComponentType } from "react"
import type { LucideProps } from "lucide-react"
import type { IconDefinition, IconName, IconPack, IconPrefix } from "@fortawesome/fontawesome-svg-core"
import type { FontAwesomeIcon as FontAwesomeIconType } from "@fortawesome/react-fontawesome"
import {
    Armchair,
    Camera,
    CircleDot,
    Lightbulb,
    Palette,
    Puzzle,
    Receipt,
    RectangleHorizontal,
    Activity,
    AlertCircle,
    AlertTriangle,
    ArrowLeft,
    ArrowRight,
    Ban,
    Bell,
    Box,
    Briefcase,
    Calendar,
    Car,
    Check,
    CheckCircle,
    ChevronLeft,
    ChevronRight,
    Clock,
    Copy,
    CreditCard,
    Crosshair,
    Database,
    DollarSign,
    Edit,
    FileText,
    Flag,
    List,
    Fuel,
    Gift,
    Hammer,
    Heart,
    Home,
    IdCard,
    Info,
    Key,
    Lock,
    Mail,
    Map,
    MapPin,
    MessageSquare,
    Minus,
    Package,
    Pencil,
    Phone,
    Plus,
    Radio,
    Search,
    Settings,
    Shield,
    ShieldAlert,
    ShoppingBag,
    ShoppingCart,
    Star,
    Trash,
    Trash2,
    Truck,
    Unlock,
    User,
    Users,
    Wallet,
    Wrench,
    X,
} from "lucide-react"

// A curated, statically-imported subset of lucide-react rather than
// `import * as Icons from "lucide-react"` -- a wildcard import pulls in every
// icon in the package regardless of which ones are actually referenced by
// name at runtime (the bundler can't tree-shake a dynamic property lookup),
// which bloated this NUI's bundle by roughly 1MB for a handful of menu icons.
// Add more entries here as real menus need them.
const ICONS: Record<string, ComponentType<LucideProps>> = {
    Armchair,
    Camera,
    CircleDot,
    Lightbulb,
    Palette,
    Puzzle,
    Receipt,
    RectangleHorizontal,
    Activity,
    AlertCircle,
    AlertTriangle,
    ArrowLeft,
    ArrowRight,
    Ban,
    Bell,
    Box,
    Briefcase,
    Calendar,
    Car,
    Check,
    CheckCircle,
    ChevronLeft,
    ChevronRight,
    Clock,
    Copy,
    CreditCard,
    Crosshair,
    Database,
    DollarSign,
    Edit,
    FileText,
    Flag,
    Fuel,
    List,
    Gift,
    Hammer,
    Heart,
    Home,
    IdCard,
    Info,
    Key,
    Lock,
    Mail,
    Map,
    MapPin,
    MessageSquare,
    Minus,
    Package,
    Pencil,
    Phone,
    Plus,
    Radio,
    Search,
    Settings,
    Shield,
    ShieldAlert,
    ShoppingBag,
    ShoppingCart,
    Star,
    Trash,
    Trash2,
    Truck,
    Unlock,
    User,
    Users,
    Wallet,
    Wrench,
    X,
}

// The full ox_lib Font Awesome catalog is split into fixed prefix chunks. Most
// kora_lib screens use the small Lucide set above and never download one; an
// unprefixed ox icon loads solid only, while regular/brand packs are loaded
// solely for explicit `far:name`/`fab:name` requests.
const fontAwesomePacks = new globalThis.Map<IconPrefix, Promise<IconPack>>()
const fontAwesomeComponents = new globalThis.Map<string, ComponentType<LucideProps>>()
const imageComponents = new globalThis.Map<string, ComponentType<LucideProps>>()

export function isIconImage(name?: string): boolean {
    if (!name) return false
    if (/^(?:https?:|nui:|https?:\/\/cfx-nui-)/i.test(name)) return true
    return /^(?:\.\/|\/)?[\w@%+.,()[\]{} -]+\.(?:png|webp|gif|jpe?g|svg)(?:\?.*)?$/i.test(name)
}

function imageIcon(src: string): ComponentType<LucideProps> {
    const cached = imageComponents.get(src)
    if (cached) return cached

    const Icon = ({ className, style, "aria-hidden": ariaHidden }: LucideProps) => {
        const [failed, setFailed] = useState(false)
        return failed ? null : createElement("img", {
            src,
            alt: "",
            className,
            style,
            "aria-hidden": ariaHidden,
            onError: () => setFailed(true),
        })
    }
    Icon.displayName = "ImageIcon"
    imageComponents.set(src, Icon)
    return Icon
}

function loadFontAwesomePack(prefix: IconPrefix): Promise<IconPack> {
    const existing = fontAwesomePacks.get(prefix)
    if (existing) return existing

    const pending = prefix === "far"
        ? import("@fortawesome/free-regular-svg-icons").then((module) => module.far)
        : prefix === "fab"
            ? import("@fortawesome/free-brands-svg-icons").then((module) => module.fab)
            : import("@fortawesome/free-solid-svg-icons").then((module) => module.fas)
    fontAwesomePacks.set(prefix, pending)
    void pending.catch(() => fontAwesomePacks.delete(prefix))
    return pending
}

function lazyFontAwesomeIcon(prefix: IconPrefix, iconName: IconName): ComponentType<LucideProps> {
    const key = `${prefix}:${iconName}`
    const cached = fontAwesomeComponents.get(key)
    if (cached) return cached

    const Icon = ({ className, style, "aria-hidden": ariaHidden }: LucideProps) => {
        const [definition, setDefinition] = useState<IconDefinition>()
        const [FontAwesomeIcon, setFontAwesomeIcon] = useState<typeof FontAwesomeIconType>()

        useEffect(() => {
            let active = true
            void Promise.all([loadFontAwesomePack(prefix), import("@fortawesome/react-fontawesome")]).then(([pack, module]) => {
                if (!active) return
                setDefinition(pack[iconName])
                setFontAwesomeIcon(() => module.FontAwesomeIcon)
            }).catch(() => undefined)
            return () => { active = false }
        }, [])

        return definition && FontAwesomeIcon ? createElement(FontAwesomeIcon, {
            icon: definition,
            className,
            style,
            "aria-hidden": ariaHidden,
        }) : null
    }
    Icon.displayName = `LazyFontAwesomeIcon(${key})`
    fontAwesomeComponents.set(key, Icon)
    return Icon
}

function fontAwesomeIcon(name: string): ComponentType<LucideProps> | undefined {
    const separator = name.indexOf(":")
    const explicitPrefix = separator > 0 ? name.slice(0, separator) : undefined
    const iconName = (separator > 0 ? name.slice(separator + 1) : name) as IconName
    if (!iconName) return undefined
    if (explicitPrefix && explicitPrefix !== "fas" && explicitPrefix !== "far" && explicitPrefix !== "fab") return undefined
    return lazyFontAwesomeIcon((explicitPrefix ?? "fas") as IconPrefix, iconName)
}

function toPascalCase(name: string): string {
    return name
        .split(/[-_\s]+/)
        .filter(Boolean)
        .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
        .join("")
}

/**
 * Resolves a MenuItem.icon string to an icon component, accepting either the
 * exact PascalCase name ("ShoppingCart") or a kebab/snake/space-separated
 * variant ("shopping-cart", "shopping_cart"). Returns null for an
 * unrecognized name rather than throwing -- a Lua-side typo shouldn't be able
 * to break menu rendering. Only resolves names in the curated ICONS set above.
 *
 * Own-property lookups only: a bare bracket read on a plain object walks the
 * prototype chain, so names like "__proto__"/"constructor"/"hasOwnProperty"
 * would resolve truthy and get rendered as "components" -- a render-phase
 * crash that unmounts the whole React root.
 */
function ownIcon(key: string): ComponentType<LucideProps> | undefined {
    return Object.hasOwn(ICONS, key) ? ICONS[key] : undefined
}

export function resolveIcon(name?: string): ComponentType<LucideProps> | null {
    if (!name) return null
    if (isIconImage(name)) return imageIcon(name)
    return ownIcon(name) ?? ownIcon(toPascalCase(name)) ?? fontAwesomeIcon(name) ?? null
}
