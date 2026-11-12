import * as React from "react"

import { cn } from "@/lib/cn"

export interface InputProps extends React.ComponentProps<"input"> {}

const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className, type, ...props }, ref) => {
    return (
      <input
        type={type}
        className={cn(
          "focus-ring flex h-9 w-full rounded-md border border-input bg-background px-3 py-1 text-sm text-foreground transition-[background-color,border-color,box-shadow] duration-fast ease-entry file:border-0 file:bg-transparent file:text-sm file:font-medium file:text-foreground placeholder:text-muted-foreground hover:border-control-border-hover focus-visible:border-primary focus-visible:bg-card disabled:cursor-not-allowed disabled:opacity-[0.48] aria-[invalid=true]:border-destructive",
          className
        )}
        ref={ref}
        {...props}
      />
    )
  }
)
Input.displayName = "Input"

export { Input }
