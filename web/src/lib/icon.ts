import type { ComponentType } from "react"
import type { LucideProps } from "lucide-react"
import {
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
    Flag,
    List,
    Fuel,
    Gift,
    Hammer,
    Heart,
    Home,
    Info,
    Key,
    Lock,
    Mail,
    MapPin,
    MessageSquare,
    Minus,
    Package,
    Pencil,
    Phone,
    Plus,
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
    Flag,
    Fuel,
    List,
    Gift,
    Hammer,
    Heart,
    Home,
    Info,
    Key,
    Lock,
    Mail,
    MapPin,
    MessageSquare,
    Minus,
    Package,
    Pencil,
    Phone,
    Plus,
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
    return ownIcon(name) ?? ownIcon(toPascalCase(name)) ?? null
}
