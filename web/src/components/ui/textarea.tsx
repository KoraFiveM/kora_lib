import * as React from "react"

import { cn } from "@/lib/cn"

export interface TextareaProps extends React.ComponentProps<"textarea"> {}

const Textarea = React.forwardRef<HTMLTextAreaElement, TextareaProps>(
  ({ className, ...props }, ref) => (
    <textarea
      className={cn(
        "focus-ring flex min-h-[72px] w-full resize-y rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground transition-[background-color,border-color,box-shadow] duration-fast ease-entry placeholder:text-muted-foreground hover:border-control-border-hover focus-visible:border-primary focus-visible:bg-card disabled:cursor-not-allowed disabled:opacity-[0.48] aria-[invalid=true]:border-destructive",
        className
      )}
      ref={ref}
      {...props}
    />
  )
)
Textarea.displayName = "Textarea"

export { Textarea }
