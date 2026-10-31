# kora_lib web design system

## Purpose and authority

This file is the canonical visual specification for kora_lib NUI and the reference for other QBCore resources that want the same look. Use it when editing an existing component, installing a shadcn component, or creating a new resource UI. The goal is a compact, modern game overlay built from neutral charcoal surfaces with QBCore crimson used as a focused accent.

This guide is prescriptive: reuse its semantic tokens and component recipes instead of inventing a parallel palette or one-off treatment. The parent `../AGENTS.md` still governs NUI architecture, focus, build output, and request/response behavior. If a visual choice conflicts with the headless-overlay rules there, the parent rules win.

The current stack is React, Tailwind CSS 3, shadcn's `new-york` style, Radix primitives, Lucide icons, and HSL CSS variables. Keep additions compatible with that stack.

### Current implementation status

The neutral palette, Tailwind extensions, shared primitives, and kora_lib-owned UI surfaces implement this contract. Future shadcn installs and new resource UI must continue to use the same tokens and recipes; do not reintroduce stock blue/slate styling or bypass the shared primitives.

## Non-negotiable direction

- The UI has one permanent dark theme. Do not add a light palette or theme toggle.
- Large backgrounds and surfaces are neutral grey, never blue, slate, navy, or blue-tinted black.
- `#DC143C` is the default brand colour. Use the configured brand token for primary actions, focus, selection, progress, and small branded details; do not turn whole menus, dialogs, or headers into a solid accent.
- The page itself stays fully transparent. Only visible components paint a surface.
- The visual density is compact but readable: default controls are 36px high and interactive targets must never be smaller than 32px.
- Rounded corners are consistent and restrained. Controls use 8-10px radii; floating surfaces use 10-14px radii.
- Prefer crisp borders and neutral shadow over glassmorphism. Do not use backdrop blur: FiveM's transparent NUI canvas cannot blur the live game world behind it reliably.
- Motion is quick and functional. Do not add bouncy springs, long transitions, parallax, or decorative looping animation.

## Colour system

### Core palette

| Role | Value | Use |
| --- | --- | --- |
| Overlay background | `#101010` | Opaque dialog and application background |
| Card | `#171717` | Cards, panels, HUD containers |
| Popover | `#1B1B1B` | Menus, selects, tooltips, floating content |
| Raised | `#242424` | Secondary controls and inset interactive areas |
| Hover | `#2A2A2A` | Neutral hover and highlighted rows |
| Border | `#343434` | Default borders and separators |
| Strong border | `#444444` | High-emphasis decorative dividers |
| Control border | `#666666` | Accessible boundary for inputs and unchecked controls |
| Control border hover | `#7A7A7A` | Hovered boundary for inputs and unchecked controls |
| Foreground | `#F5F5F5` | Primary text and icons |
| Secondary text | `#C7C7C7` | Supporting copy that still needs emphasis |
| Muted text | `#949494` | Descriptions, placeholders, metadata |
| Disabled text | `#686868` | Disabled content only; never normal body copy |
| Default brand | `#DC143C` | Default primary action, active state, focus, progress; server-configurable |
| Brand hover | `#C41236` | Hovered primary controls |
| Brand pressed | `#AA102F` | Pressed primary controls |
| Brand soft | `rgb(220 20 60 / 14%)` | Selected rows, subtle badges, active backgrounds |
| Brand border | `rgb(220 20 60 / 45%)` | Selected or branded outlines |

Pure white `#FFFFFF` is the foreground on solid brand controls. It has approximately a 4.99:1 contrast ratio on `#DC143C` and passes WCAG AA for normal text. Use `#F5F5F5` for normal foreground content unless a component recipe defines another contrast-safe pairing, such as the dark foreground on a filled destructive control.

### Semantic colours

| State | Value | Treatment |
| --- | --- | --- |
| Success | `#22C55E` | Icon, slim edge, status dot, or text on charcoal |
| Warning | `#F59E0B` | Icon, slim edge, status dot, or text on charcoal |
| Error/destructive | `#F04444` | Validation text, icon, slim edge, destructive outline |
| Information | `#D4D4D4` | Neutral icon and text; information must not introduce a blue accent |

Semantic surfaces remain charcoal. When a tint is useful, use the semantic colour at 10-14% opacity and keep the border/icon at full colour. Never rely on colour alone: pair status colour with an icon, label, or message. `#F04444` normal-size text is only approved on `#101010`, `#171717`, or `#1B1B1B`; on raised, hover, or tinted surfaces use foreground text with an error icon/edge instead. `#F04444` is not a large filled button colour with white text. Destructive actions normally use a tonal/outline treatment and a confirmation step.

### Tailwind/shadcn token contract

Keep shadcn's semantic names. When the system is implemented, the base variables should resolve to this mapping (HSL triples deliberately match the existing Tailwind 3 configuration):

```css
:root {
  --background: 0 0% 6.3%;
  --foreground: 0 0% 96.1%;

  --card: 0 0% 9%;
  --card-foreground: 0 0% 96.1%;

  --popover: 0 0% 10.6%;
  --popover-foreground: 0 0% 96.1%;

  --primary: 348 83.3% 47.1%;
  --primary-foreground: 0 0% 100%;

  --secondary: 0 0% 14.1%;
  --secondary-foreground: 0 0% 96.1%;

  --muted: 0 0% 14.1%;
  --muted-foreground: 0 0% 58%;

  --accent: 0 0% 16.5%;
  --accent-foreground: 0 0% 96.1%;

  --destructive: 0 85.1% 60.4%;
  --destructive-foreground: 0 0% 6.3%;

  --border: 0 0% 20.4%;
  --input: 0 0% 40%;
  --ring: 348 83.3% 47.1%;

  --radius: 0.625rem;

  --brand-hover: 348 83.2% 42%;
  --brand-pressed: 347.9 82.8% 36.5%;
  --brand-soft: 348 83.3% 47.1% / 0.14;
  --brand-border: 348 83.3% 47.1% / 0.45;
  --surface-raised: 0 0% 14.1%;
  --surface-hover: 0 0% 16.5%;
  --border-strong: 0 0% 26.7%;
  --control-border: 0 0% 40%;
  --control-border-hover: 0 0% 47.8%;
  --success: 142.1 70.6% 45.3%;
  --warning: 37.7 92.1% 50.2%;
  --info: 0 0% 83.1%;
}
```

Do not overload `accent` with crimson: in shadcn, `accent` is the neutral hover surface, while `primary` is the brand. The extra variables above are part of the contract even if only one component initially consumes them.

The implementation phase must also give the nonstandard scales stable Tailwind names instead of scattering arbitrary values:

```ts
extend: {
  colors: {
    "brand-hover": "hsl(var(--brand-hover))",
    "brand-pressed": "hsl(var(--brand-pressed))",
    "brand-soft": "hsl(var(--brand-soft))",
    "brand-border": "hsl(var(--brand-border))",
    "surface-raised": "hsl(var(--surface-raised))",
    "surface-hover": "hsl(var(--surface-hover))",
    "border-strong": "hsl(var(--border-strong))",
    "control-border": "hsl(var(--control-border))",
    "control-border-hover": "hsl(var(--control-border-hover))",
    success: "hsl(var(--success))",
    warning: "hsl(var(--warning))",
    info: "hsl(var(--info))",
  },
  borderRadius: {
    xs: "0.25rem",
    sm: "0.375rem",
    md: "0.5rem",
    lg: "0.625rem",
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
}
```

### Server-configured accent

`#DC143C` is the default accent, not a hard-coded component dependency. Server
owners configure semantic colours in `kora_theme/config.lua`; kora_lib imports
kora_theme's stylesheet and browser loader. Components must use those semantic
tokens. kora_theme derives hover, pressed, translucent, focus, and readable
foreground variants.

Never add raw Tailwind slate, zinc, neutral, grey, sky, or blue utilities inside reusable components when an appropriate semantic token exists. Neutral palette values above are the source of truth even if a Tailwind named colour happens to look close.

New UI consumers should depend directly on kora_theme and import its client bridge,
stylesheet, and loader. `Kora.theme.tokens()` remains a kora_lib compatibility
forward only; never re-derive the HSL math locally.

## Foundations

### Typography

Use a local/system stack; the NUI must not depend on Google Fonts or another remote font host.

```css
font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont,
  "Segoe UI", sans-serif;
```

`Inter` is optional and must be bundled locally before it is treated as available. The system fallbacks are the default. For code, coordinates, key values, and numeric telemetry use:

```css
font-family: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
```

| Role | Size / line height | Weight |
| --- | --- | --- |
| Dialog title | 18px / 24px | 600 |
| Section title | 16px / 22px | 600 |
| Body and control | 14px / 20px | 400 or 500 |
| Supporting text | 12px / 18px | 400 |
| HUD shortcut/meta | 10px / 14px | 500 |

- Use 600 for headings and important labels. Reserve 700 for rare numeric emphasis.
- Use normal sentence case. Avoid all-caps headings except tiny, established category labels.
- Keep tracking normal; use slight positive tracking only for 10-12px category labels or keyboard shortcuts.
- Never place required instructions or validation below 12px. The 10px size is only for secondary HUD hints.
- Truncate single-line labels deliberately and wrap descriptions/messages. Do not let text silently overflow a surface.

### Spacing and density

Use a 4px base grid. Preferred steps are `4, 8, 12, 16, 20, 24, 32`px.

- Compact control: 32px high, used for dense menus, toolbars, and development controls.
- Default control: 36px high, used for buttons and text inputs.
- Comfortable control: 40px high, used for selects or prominent actions where space permits.
- Default horizontal control padding: 12-16px. Icon-only controls are square.
- Menu row: at least 36px; use 44-52px when it includes a description.
- Panel padding: 12px compact, 16px default, 24px for a dialog body.
- Related fields: 12px apart. Separate sections: 20-24px apart.
- Screen-edge inset: 16px minimum, including notification stacks and HUDs.
- Dialog action gap: 8px. Do not use margin hacks between buttons when a flex/grid gap is available.

### Radius

| Token | Value | Use |
| --- | --- | --- |
| `radius-xs` | 4px | Status marks, tiny code/key chips |
| `radius-sm` | 6px | Menu rows, badges, check indicators |
| `radius-md` | 8px | Inputs and compact buttons |
| `radius-lg` | 10px | Default buttons, cards, popovers |
| `radius-xl` | 14px | Dialogs, sheets, large floating panels |
| `radius-full` | 9999px | Dots, progress pills, avatars only |

Nested elements should have a smaller radius than their container. Avoid making every rectangular surface a pill. A component must use this scale rather than an arbitrary bracketed Tailwind radius.

### Borders and elevation

- Default decorative surface border/separator: 1px `#343434`.
- Strong decorative border: 1px `#444444`.
- Input and unchecked-control boundary: 1px `#666666`; hover uses `#7A7A7A`. These higher-contrast tokens are required wherever the boundary identifies a control.
- Selected border: `rgb(220 20 60 / 45%)`; selection should also have a non-colour cue such as an indicator or check icon.
- Do not use double borders or gradients as borders.
- Low elevation: `0 4px 12px rgb(0 0 0 / 28%)`.
- Floating elevation: `0 12px 32px rgb(0 0 0 / 42%)`.
- Modal elevation: `0 24px 64px rgb(0 0 0 / 55%)`.
- Shadows are black/neutral only. No crimson glow or coloured shadow.
- Use one elevation treatment per surface. Do not stack multiple dramatic shadows.

### Icons

- Use Lucide icons and the existing icon resolver. Do not mix icon families without a specific compatibility need.
- Inline and menu icons are 16px; primary-action or empty-state icons may be 20px; rare hero/status illustrations may be 24px.
- Use 1.75-2px stroke weight where configurable.
- Icons inherit the current text colour unless they convey a documented semantic status.
- Icon-only buttons require an accessible label and tooltip. Decorative icons use `aria-hidden`.

### Motion

- Colour, border, and opacity transitions: 120ms.
- Popover/menu enter and exit: 140-160ms.
- Dialog/sheet enter and exit: 180ms maximum.
- Preferred easing: `cubic-bezier(0.16, 1, 0.3, 1)` on entry and `ease-in` on exit.
- Popovers may fade while translating 4px. Dialogs may fade and scale from 98%. Avoid larger movement.
- A pressed button may scale to 98% only if it does not cause layout movement.
- Loading indicators may rotate; progress movement must communicate real activity.
- Under `prefers-reduced-motion: reduce`, remove transforms and nonessential animation and reduce transitions to effectively instant.

### Overlay and layering

- `html`, `body`, and `#root` remain `background: transparent`, `pointer-events: none`, full viewport, and overflow hidden.
- Informational UI such as toasts and the zone HUD remains `pointer-events: none` for its entire lifetime.
- An interactive component opts into `pointer-events: auto` only while visible. Remember that Radix portals mount outside the triggering component; portal content must opt in independently.
- Closed interactive UI must be unmounted or marked `hidden`/`inert`; pointer-event removal alone does not prevent tab focus or accessibility-tree exposure. Hidden portal content must not remain tabbable.
- A focus-owning UI must return its result/cancellation, restore DOM focus to the logical trigger when one exists, and release NUI focus immediately on submit, selection, Escape, backdrop dismissal, or close.
- Use the existing layer model through its target semantic utilities: world HUD `z-hud` (40), interactive overlays/popovers/toasts `z-overlay` (50), and development tooling `z-dev` (100). Add a new level only when this model cannot express the relationship.
- Modal backdrop: black at 68% opacity. It may fade but must not tint blue or crimson.
- HUDs, dialogs, menus, and forms use no backdrop blur. The transparent NUI canvas cannot supply a reliable backdrop for it.

## Universal interaction states

Every interactive component must specify all applicable states; a default and hover style alone is incomplete.

| State | Required treatment |
| --- | --- |
| Default | Clear surface, readable label, and border where the boundary is otherwise ambiguous |
| Hover | One neutral surface step lighter, or brand hover for a solid primary action |
| Focus-visible | 2px crimson ring or inset ring; never remove focus without replacement |
| Pressed/open | Brand pressed for primary controls; stronger border or darker neutral surface elsewhere |
| Selected/current | Brand-soft background plus a check, marker, left rail, or font-weight change |
| Disabled | No pointer events, 48% visual opacity, and no hover/press response |
| Loading | Preserve width, prevent duplicate action, retain an accessible label, and show a 16px spinner when useful |
| Error/invalid | Error border or icon plus concise error text; set `aria-invalid` and connect the description |
| Read-only | Normal legibility with a subdued surface; do not make it look disabled if selection/copy remains possible |

Use `focus-visible`, not unconditional focus rings after mouse clicks. The crimson focus treatment keeps the indicator visible against neutral surfaces and unpredictable gameplay without a white outer halo. Hover styling must never be the only way to discover an action.

Custom controls must match the keyboard behavior supplied by Radix primitives: Tab and Shift+Tab traverse controls, Enter/Space activate buttons, Escape closes or cancels transient UI, arrow keys plus Home/End move through roving menus/tabs, and modal dialogs trap focus until closed. Restore focus to the logical trigger after a modal or popup closes whenever that trigger still exists.

## Component recipes

### Buttons and icon buttons

- Default/primary: solid brand, white text, 10px radius, 36px height, medium weight, neutral shadow. Hover uses brand hover; pressed uses brand pressed.
- Secondary: raised charcoal background, foreground text, subtle border. Hover moves to the neutral hover surface.
- Outline: transparent/dark background, `#666666` control border, foreground text. Hover uses the neutral hover surface and `#7A7A7A` border.
- Ghost: transparent with no border. Hover uses the neutral hover surface. Use for secondary dialog actions and compact toolbars.
- Destructive: use transparent or 10% error tint with error text/border on background, card, or popover surfaces. On a raised/hover surface keep the label foreground and use an error icon/border. If an exceptional filled variant uses `#F04444`, its foreground is `#101010`, never white.
- Link: foreground text with a persistent underline; hover/focus strengthens or offsets that underline. The configured accent may be used for a separate icon or underline only where it reaches 3:1 against the immediate surface; do not use it for normal-size link text.
- Small is 32px, default 36px, large 40px. Icon-only sizes match these heights exactly.
- Put the leading icon before the label and keep an 8px gap. Loading replaces that icon; it does not shift the label.
- A primary button should normally be unique within its immediate action group.

### Labels, inputs, textareas, and field messages

- Labels are 14px/500 and sit 6px above their control. Required markers use error colour and are accompanied by semantic required state.
- Input/textarea surface is `#101010`, with a `#666666` control border, 8px radius, and 12px horizontal padding.
- Hover moves the border to `#7A7A7A`. Focus uses the crimson focus treatment and brand border.
- Placeholder text uses muted text. User-entered text uses foreground.
- Textareas share the input treatment, have at least 72px height, and resize vertically only when resizing is appropriate to the overlay.
- Help text is muted and 12px. Error text is `#F04444`, 12px, and placed in the same location so the layout does not jump unpredictably.
- Prefixes, suffixes, and clear buttons stay inside the field boundary with a separator only when needed.

### Checkbox, radio, and switch

- Checkbox and radio targets are at least 32px even when their visible indicator is 16-18px.
- Unchecked indicators use a `#101010` surface and `#666666` control border. Checked indicators use brand fill, white icon/mark, and brand border.
- Radios are circular; checkboxes use 6px radius rather than a pill.
- Switch tracks are raised charcoal when off and brand when on. The thumb is near-white and uses a small neutral shadow.
- Focus belongs to the complete control, not only the label. Disabled state affects label and indicator together.

### Select and combobox

- Triggers follow input sizing and states. Chevron is 16px and muted until hover/open.
- Content uses popover background, 10px radius, default border, floating shadow, 4px internal padding, and `pointer-events: auto`.
- Items are at least 36px high with 8-12px horizontal padding and 6px radius.
- Hover/focused item uses neutral hover. Selected item uses brand-soft, a foreground check, and a slim brand rail against the popover; do not use a solid crimson row or crimson label text.
- Group labels are muted 12px/600. Separators use the default border.
- A combobox search field is visually integrated into the popover but retains a visible lower divider and focus state.

### Cards and panels

- Cards use card background, default border, 10px radius, and 16px padding. Add shadow only when the card floats independently over gameplay.
- An inset area moves one neutral step darker or lighter and uses a smaller radius.
- Card titles are 16px/600; descriptions are 12-14px muted. Actions align to the top-right only when they do not compete with the title.
- Do not wrap every section in a card. Use spacing and separators for related content within the same surface.

### Dialogs, sheets, and drawers

- Dialog content is opaque `#101010`, 14px radius, default decorative border, modal shadow, and 24px padding. Compact command dialogs may intentionally remove inner padding.
- Default dialog width is 448-512px; use 576px for code previews or dense confirmation data. Always retain a 16px viewport gutter.
- Overlay is neutral black at 68% opacity. Never tint it with the brand.
- Title is 18px/600; description is muted 14px. Keep 16-20px between header, body, and footer regions.
- Every visible dialog or menu heading uses a slim 3px configured-accent title rail on its left. It is a decorative hierarchy cue, not a filled title bar, logo, or text treatment; omit it when the heading is screen-reader-only.
- Close button is a 32px ghost icon control at the top-right with a visible focus ring and accessible name.
- Footer actions use an 8px gap, secondary/cancel first and primary/confirm last. Stack safely on narrow viewports.
- Sheets/drawers use the same surface and border system, with a border on the edge adjoining gameplay. Their motion comes from the edge they occupy and stays under 180ms.

### Popovers, dropdowns, context menus, and tooltips

- Floating surfaces use popover background, default border, 10px radius, floating shadow, and 4px menu padding.
- Context menus must clamp or flip to remain at least 8px from viewport edges.
- Menu items use the select-item state recipe. Destructive items use error text on the base popover. On hover, the label becomes foreground over a 10% error tint while an error icon/edge preserves meaning.
- Nested menu indicators and shortcuts are muted and aligned to the trailing edge.
- Tooltips are compact, max 280px, 12px text, 6px radius, and opaque `#1B1B1B`. They supplement accessible names; they do not replace them.

### Command menus and searchable lists

- Command root inherits the containing dialog/popover surface; avoid a second card boundary inside it.
- Search row is 44px high with a bottom border. Search icon is 16px and muted.
- Results scroll independently with a practical maximum height. Empty state is centred, muted, and padded 24px.
- Rows follow the menu item recipe and are 40px minimum, or 48px with a description.
- Match highlighting uses foreground weight or underline. Do not use normal-size crimson text or paint every match with a solid block.

### Tabs, accordion, and collapsible content

- Tabs use a neutral raised track or a border-bottom layout. The active tab uses foreground text plus a crimson underline/indicator or brand-soft background.
- Inactive tabs are muted; hover brings them to foreground without changing selection.
- Accordion triggers are at least 40px, with a 16px chevron that rotates in 140ms. Content uses spacing rather than an extra card unless it is independently grouped.
- Focus and keyboard behavior come from the Radix primitive and must remain visible after styling.

### Tables and data lists

- Header text is 12px/600 and muted. Rows use foreground 14px text and 44px minimum height.
- Use separators instead of boxing every cell. Hover may use a subtle neutral background; selection uses brand-soft with a separate marker/check.
- Numeric columns align right and may use tabular numerals or monospace where rapid comparison matters.
- Empty and loading states occupy the table body and explain what is happening. Do not render an unexplained blank panel.
- Horizontal overflow must use a deliberate scroll container; never shrink essential values into unreadability.

### Badge, alert, and notification

- Neutral badges use raised charcoal and secondary text. Brand badges use brand-soft, brand border, and foreground text. Crimson is an indicator/background treatment, not normal-size badge text.
- Status badges use a 10% semantic tint, semantic icon/dot, and foreground text. Pills are acceptable for short badges only.
- Alerts use a neutral surface, border, 4px semantic left edge, 16px icon, title, and optional message.
- Notifications use the same alert anatomy in a compact 320px-wide floating card. Keep the base surface neutral even for errors and warnings.
- Toast stacks remain pointer-transparent, stay 16px from the viewport, use an 8px gap, and animate in from their anchored edge.
- A toast may include one 1px semantic lifetime strip driven by its existing timeout. It is noninteractive and `aria-hidden`; reduced motion removes the strip animation without changing dismissal timing.
- Routine updates use `role="status"`/`aria-live="polite"`; reserve `role="alert"` for urgent errors. Announce only the new toast, not the full stack again.
- Nonessential transient toasts remain for at least 5 seconds. Because kora_lib toasts are pointer-transparent and cannot be paused or dismissed, essential/actionable information and important errors must also remain visible in the persistent workflow state. A resource claiming full WCAG 2.2 timing compliance must additionally mirror every timed notification in a persistent accessible history or provide a user-adjustable duration.

### Progress, skeleton, separator, and scrollbar

- Progress track is raised charcoal; progress indicator is brand. Use semantic colour only when progress itself represents a semantic result. Determinate progress exposes `aria-valuemin`, `aria-valuemax`, and `aria-valuenow`; indeterminate progress has an accessible label.
- A loading region sets `aria-busy`. Decorative spinners and skeleton blocks use `aria-hidden`; any changing loading label is exposed once without repeatedly announcing animation frames.
- Skeleton uses two close neutral surface values with a subtle pulse; it must respect reduced motion and approximate the final layout.
- Separator is a single default-border line. Use whitespace instead when a line does not improve grouping.
- Show the thumb only: preserve the platform scrollbar width and target behavior, but make the track fully transparent with no border, inset, or corner treatment. Use a rounded `#666666` thumb on background/card/popover surfaces and `#7A7A7A` beside raised or hover surfaces. Hover lightens the thumb one step. Do not force a thin custom scrollbar that is difficult to acquire with a pointer.

## kora_lib-specific patterns

### Main menu

- Use the compact dialog/command composition already established by `Menu.tsx`.
- The title region gets 16px horizontal/top padding and the shared slim title rail, never a heavy branded header.
- Search stays visually connected to the list. Described rows are 48px minimum and align their 16px icon to the first text line.
- Active keyboard row uses neutral hover; confirmed/current selection, when present, uses brand-soft plus an indicator.

### Context menu

- Match main-menu item typography and state styling exactly so the two menu systems feel identical.
- Use popover background, 10px radius, 4px padding, and the floating shadow.
- Preserve roving focus, outside-click dismissal, Escape handling, and viewport flipping. Visual changes must not weaken those behaviors.

### Radial menu

- The radial menu is an interactive, temporary overlay: use the standard modal overlay with a transparent graph interior—never an opaque circular plate. Keep every control compact, neutral, and free of blur or gradients.
- Place icon nodes clockwise from twelve o'clock and connect each to the central action node with a crisp neutral-grey line. On hover or keyboard focus, only that node's linked line and endpoint change to the configured brand; other links remain grey. Crimson remains a focused selection detail, never a ring or backdrop treatment.
- The centre control closes at root and goes Back inside a submenu. Escape and a backdrop click cancel the entire request. Paging through long lists belongs to a labelled `More` wedge; never overcrowd or silently discard an item.
- Render real buttons with visible keyboard focus. Disabled items remain visible but cannot receive focus or selection; arrow keys, Home/End, Enter, and Space must remain usable alongside pointer input.

### Interact selector

- The interact selector is a display-only, left-edge gameplay overlay. Keep it pointer-transparent and do not grant NUI focus; its owning resource retains all game-control behavior.
- Use the compact HUD surface, a 10px radius, low neutral shadow, and 40px minimum rows. The current row uses brand-soft plus the shared slim crimson rail; do not turn the whole panel crimson.
- The selected row may carry one compact confirm-key chip. Labels truncate rather than widening the panel into the gameplay centre.
- Its kora_lib interaction contract is `openInteract` carrying `[{ label }]`, `scroll` carrying `1` or `-1`, `select` confirming the highlighted row, and `hideInteract` hiding it. Confirmation POSTs the one-based numeric choice to `selectOption`.

### Input dialog

- Keep fields in a 12px vertical rhythm and separate the form from footer actions by 16-20px.
- Number fields hide browser-native spinners and use matching 36px outline decrease/increase arrow controls with visible focus rings and accessible labels. Preserve native keyboard entry and enforce configured min/max values for arrow adjustments. Range fields pair the slider with a compact editable numeric readout; commit typed values on blur or Enter and clamp them to the configured range.
- Checkbox rows align the indicator with the first label line and make the label itself clickable.
- Use the shared input, textarea, select, label, help, and error recipes. Do not maintain a parallel textarea class list once a shared textarea primitive exists.
- Validation must be visible before submission is blocked. Confirm is the sole primary button; Cancel is outline or ghost.

### Toasts

- Toast surface is `#1B1B1B` with a default decorative border and floating shadow.
- Preserve the 4px semantic left edge and compact matching icon chip. Information uses the neutral information colour, not sky blue.
- Title is 14px/600; message is 12px muted with a 4px top gap. Do not make the whole toast a status colour.
- A subtle 1px semantic countdown sits at the bottom. It is visual-only and must use the existing toast lifetime rather than introduce a second timer.
- Toasts stay noninteractive and must never steal game input.

### Zone creator HUD

- The HUD uses one compact opaque charcoal card with a border and low neutral shadow so it remains readable over bright or detailed gameplay. Do not use backdrop blur.
- HUD remains noninteractive. Its job is glanceable state, not decoration.
- Place mode/placement state in the card header, then active parameter and enabled confirm as compact brand-soft chips. Use monospace/tabular numerals for values.
- Instructions sit in the same card below a default-border separator at 12px. They may never use backdrop blur; the card itself supplies their background and readability.

### Zone confirmation and code blocks

- Use the standard dialog and footer. The generated snippet sits in an inset `#101010` surface with default border, 8px radius, and 12px monospace text.
- Code blocks scroll instead of wrapping code and have a visible neutral scrollbar.
- Copy is a small outline action beside or immediately below the code block. Temporary `Copied` feedback uses a success icon/text and must not resize the button.
- `Create Zone` is primary; `Keep Editing` is ghost or outline.

### Development harness

- The harness uses the same tokens and components as production UI so it remains a trustworthy visual test bed. Include representative long-copy, overflow, disabled, validation, viewport-edge, toast, and HUD states.
- Keep it at `z-dev`, interactive, compact, and clearly labelled as development tooling without using a separate novelty palette.
- New visual variants or primitives should receive a representative harness state where practical, including disabled, validation, overflow, and long-copy cases.

### Headless components and error fallback

`ClipboardHandler` and the root error fallback intentionally render no UI. Do not add success panels, error screens, or permanent surfaces to them. User-facing feedback belongs to the requesting workflow; diagnostics remain in the NUI console unless a specific product flow defines otherwise.

## Implementation conventions

- Start with or adapt the shadcn New York primitive, then replace its stock slate palette and state styling with this contract.
- Put stable variants in the primitive using `class-variance-authority`; use `cn` for consumer layout adjustments, not to redefine the design system per screen.
- Prefer semantic utilities such as `bg-card`, `text-muted-foreground`, `border-border`, and `ring-ring` over raw colour utilities.
- If the same class recipe appears twice, promote it to a shared primitive or variant. Existing duplicated textarea styling is a candidate when implementation begins.
- Component APIs should describe meaning (`variant="destructive"`, `size="sm"`) rather than a colour (`variant="red"`).
- Preserve Radix state attributes, focus management, keyboard navigation, portal behavior, and accessible labelling when changing classes.
- Do not add a dependency solely for a visual effect that Tailwind/CSS already provides.
- Do not edit `web/build/` by hand. After an implementation change, run `pnpm build` and commit Vite's generated output as required by the parent guide.

## Do and do not

Do:

- Use charcoal hierarchy, spacing, border, and elevation to separate surfaces.
- Use crimson to make the next action, current selection, or keyboard focus obvious.
- Keep important content legible over both bright and dark gameplay.
- Review long labels, empty data, overflow, keyboard focus, and disabled states.
- Reuse the exact tokens in other resources so kora_lib interfaces feel related.

Do not:

- Use blue/slate-tinted backgrounds or restore shadcn's default slate dark palette.
- Fill large panels, title bars, or whole selected lists with crimson.
- Add crimson glow, coloured shadows, decorative gradients, neon bloom, or heavy glass effects.
- fetch fonts, icons, or visual assets from remote hosts at runtime.
- Use arbitrary spacing, radius, z-index, or hard-coded colours when a token covers the need.
- Hide focus rings, communicate state by colour alone, or make hover the only visible affordance.
- Let an informational overlay acquire pointer events or let a closed interaction retain NUI focus.

## Review checklist

Before considering a UI styling change complete, verify:

- Surfaces are neutral charcoal with no blue cast, and the root is still transparent.
- The rendered brand matches kora_theme's configured primary (default `#DC143C`); hover/pressed and brand-soft states derive from that same token.
- Text/background pairs meet WCAG AA. In particular, white on the brand is valid, muted copy is not replaced with disabled grey, and semantic text remains on charcoal.
- Every control has default, hover, focus-visible, pressed/open, disabled, loading, and invalid states where applicable.
- Mouse, keyboard, Escape, backdrop dismissal, and Radix focus behavior still work.
- Interactive targets are at least 32px; default controls remain compact and readable.
- Radius, spacing, shadow, icon, and motion choices come from the defined scales.
- Portalled interactive content has `pointer-events: auto`; HUDs and toasts remain pointer-transparent.
- Dialogs, popovers, notifications, and context menus stay within a 16px screen gutter or intentionally clamp to at least 8px.
- Reduced motion, long content, scroll overflow, empty state, and error state have been checked.
- `pnpm typecheck` and `pnpm build` pass after code changes, and the committed `web/build/` output is regenerated rather than hand-edited.
