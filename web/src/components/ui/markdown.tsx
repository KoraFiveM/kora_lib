import ReactMarkdown, { type Components } from "react-markdown"
import type { CSSProperties } from "react"
import remarkGfm from "remark-gfm"

import { cn } from "@/lib/cn"

const blockComponents: Components = {
    h1: ({ node: _node, ...props }) => <h1 className="text-lg font-semibold leading-6" {...props} />,
    h2: ({ node: _node, ...props }) => <h2 className="text-base font-semibold leading-6" {...props} />,
    h3: ({ node: _node, ...props }) => <h3 className="text-sm font-semibold leading-5" {...props} />,
    p: ({ node: _node, ...props }) => <p className="my-1 first:mt-0 last:mb-0" {...props} />,
    ul: ({ node: _node, ...props }) => <ul className="my-1 list-disc space-y-0.5 pl-5" {...props} />,
    ol: ({ node: _node, ...props }) => <ol className="my-1 list-decimal space-y-0.5 pl-5" {...props} />,
    blockquote: ({ node: _node, ...props }) => <blockquote className="my-1 border-l-2 border-control-border pl-3 text-muted-foreground" {...props} />,
    code: ({ node: _node, ...props }) => <code className="rounded-sm bg-surface-raised px-1 py-0.5 font-mono text-[0.9em] text-foreground" {...props} />,
    pre: ({ node: _node, ...props }) => <pre className="my-2 max-w-full overflow-x-auto rounded-md border bg-background p-2 font-mono text-xs" {...props} />,
    table: ({ node: _node, ...props }) => <table className="my-2 min-w-full border-collapse text-left text-xs" {...props} />,
    th: ({ node: _node, ...props }) => <th className="border-b border-border px-2 py-1 font-semibold" {...props} />,
    td: ({ node: _node, ...props }) => <td className="border-b border-border px-2 py-1" {...props} />,
    a: ({ node: _node, ...props }) => <a className="underline underline-offset-2" target="_blank" rel="noreferrer noopener" {...props} />,
}

const inlineComponents: Components = {
    ...blockComponents,
    p: ({ node: _node, ...props }) => <span className="whitespace-pre-wrap" {...props} />,
    h1: ({ node: _node, ...props }) => <span className="font-semibold" {...props} />,
    h2: ({ node: _node, ...props }) => <span className="font-semibold" {...props} />,
    h3: ({ node: _node, ...props }) => <span className="font-semibold" {...props} />,
}

/**
 * Resource-supplied Markdown rendered without raw HTML. ReactMarkdown's URL
 * transform also rejects dangerous protocols, while GFM keeps ox_lib tables,
 * lists, autolinks, and line breaks compatible.
 */
export function Markdown({ children, className, style, inline = false, allowImages = false }: {
    children: string
    className?: string
    style?: CSSProperties
    inline?: boolean
    allowImages?: boolean
}) {
    const components: Components = {
        ...(inline ? inlineComponents : blockComponents),
        img: allowImages
            ? ({ node: _node, ...props }) => <img className="my-2 max-h-80 max-w-full rounded-md object-contain" loading="lazy" {...props} />
            : () => null,
    }

    return (
        <div className={cn("min-w-0 break-words", inline && "contents", className)} style={style}>
            <ReactMarkdown skipHtml remarkPlugins={[remarkGfm]} components={components}>{children}</ReactMarkdown>
        </div>
    )
}
