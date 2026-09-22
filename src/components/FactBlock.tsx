import { cn } from "@/lib/utils"

/**
 * The fact block, verbatim.
 *
 * Rendered as pre-wrapped text rather than a code block with horizontal scroll:
 * the previous UI clipped this panel and the whole argument of the step is that
 * a reviewer can read every line the model was given. If it does not wrap, it
 * does not do its job.
 */
export default function FactBlock({
  text,
  className,
}: {
  text: string | null | undefined
  className?: string
}) {
  if (!text) {
    return (
      <div className="rounded-md border border-dashed border-border px-3 py-6 text-center text-sm text-muted-foreground">
        No fact block — this line does not require commentary.
      </div>
    )
  }
  return (
    <pre
      className={cn(
        "max-h-[420px] overflow-y-auto whitespace-pre-wrap break-words rounded-md border border-border bg-muted/50 p-3 font-mono text-[12px] leading-relaxed text-foreground",
        className,
      )}
    >
      {text}
    </pre>
  )
}
