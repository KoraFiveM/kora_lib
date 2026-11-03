import type { Config } from "tailwindcss"

// No darkMode/class toggle -- this is a fixed game overlay with exactly one
// permanent theme (see globals.css), not a user-configurable light/dark app.
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    container: {
      center: true,
      padding: "2rem",
      screens: {
        "2xl": "1400px",
      },
    },
    extend: {
      colors: {
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        "brand-hover": "hsl(var(--brand-hover))",
        "brand-pressed": "hsl(var(--brand-pressed))",
        "brand-soft": "hsl(var(--brand-soft))",
        "brand-border": "hsl(var(--brand-border))",
        "surface-raised": "hsl(var(--surface-raised))",
        "surface-hover": "hsl(var(--surface-hover))",
        "border-strong": "hsl(var(--border-strong))",
        "control-border": "hsl(var(--control-border))",
        "control-border-hover": "hsl(var(--control-border-hover))",
        "modal-overlay": "hsl(var(--modal-overlay))",
        hud: "hsl(var(--hud))",
        success: "hsl(var(--success))",
        warning: "hsl(var(--warning))",
        info: "hsl(var(--info))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: {
          DEFAULT: "hsl(var(--primary))",
          foreground: "hsl(var(--primary-foreground))",
        },
        secondary: {
          DEFAULT: "hsl(var(--secondary))",
          foreground: "hsl(var(--secondary-foreground))",
        },
        destructive: {
          DEFAULT: "hsl(var(--destructive))",
          foreground: "hsl(var(--destructive-foreground))",
        },
        muted: {
          DEFAULT: "hsl(var(--muted))",
          foreground: "hsl(var(--muted-foreground))",
        },
        accent: {
          DEFAULT: "hsl(var(--accent))",
          foreground: "hsl(var(--accent-foreground))",
        },
        popover: {
          DEFAULT: "hsl(var(--popover))",
          foreground: "hsl(var(--popover-foreground))",
        },
        card: {
          DEFAULT: "hsl(var(--card))",
          foreground: "hsl(var(--card-foreground))",
        },
      },
      borderRadius: {
        xs: "0.25rem",
        sm: "0.375rem",
        md: "0.5rem",
        lg: "var(--radius)",
        xl: "0.875rem",
      },
      zIndex: {
        hud: "40",
        overlay: "50",
        dev: "100",
      },
      boxShadow: {
        low: "0 4px 12px rgb(0 0 0 / 28%)",
        floating: "0 12px 32px rgb(0 0 0 / 42%)",
        modal: "0 24px 64px rgb(0 0 0 / 55%)",
      },
      // kora_theme sets these variables from theme.json and /config; the
      // fallbacks are its default stacks.
      fontFamily: {
        sans: ['var(--font-sans, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif)'],
        heading: ['var(--font-heading, var(--font-sans, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif))'],
        mono: ['var(--font-mono, "SFMono-Regular", Consolas, "Liberation Mono", monospace)'],
      },
      transitionDuration: {
        fast: "120ms",
        popover: "160ms",
        dialog: "180ms",
      },
      transitionTimingFunction: {
        entry: "cubic-bezier(0.16, 1, 0.3, 1)",
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
} satisfies Config
