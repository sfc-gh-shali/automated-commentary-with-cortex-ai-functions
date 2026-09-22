import { cn } from "@/lib/utils"
import { statusMeta } from "@/lib/format"

/** Small caps label used above every panel. */
export function PanelLabel({ children }: { children: React.ReactNode }) {
  return (
    <div className="text-[11px] font-semibold uppercase tracking-[0.08em] text-muted-foreground">
      {children}
    </div>
  )
}

export function Panel({
  title,
  hint,
  right,
  className,
  children,
}: {
  title?: string
  hint?: string
  right?: React.ReactNode
  className?: string
  children: React.ReactNode
}) {
  return (
    <section
      className={cn(
        "workspace-section",
        className,
      )}
    >
      {(title || right) && (
        <header className="section-heading">
          <div className="min-w-0">
            {title && <h2>{title}</h2>}
            {hint && (
              <p className="mt-1 text-xs text-muted-foreground">{hint}</p>
            )}
          </div>
          {right}
        </header>
      )}
      <div className="section-body">{children}</div>
    </section>
  )
}

/** Status pill. Uses the short label -- long labels truncate in table cells. */
export function StatusBadge({
  status,
  long = false,
  className,
}: {
  status: unknown
  long?: boolean
  className?: string
}) {
  const meta = statusMeta(status)
  return (
    <span
      className={cn(
        "inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border px-2 py-0.5 text-xs font-medium",
        meta.tone,
        className,
      )}
    >
      <span className={cn("size-1.5 rounded-full", meta.dot)} />
      {long ? meta.long : meta.short}
    </span>
  )
}

export function Tile({
  label,
  value,
  sub,
  tone,
  accent,
}: {
  label: string
  value: React.ReactNode
  sub?: string
  tone?: string
  accent?: string
}) {
  return (
    <div className="metric-tile">
      <div className="flex items-center gap-1.5">
        {accent && <span className={cn("size-1.5 rounded-full", accent)} />}
        <div className="text-[11px] font-medium uppercase tracking-[0.06em] text-muted-foreground">
          {label}
        </div>
      </div>
      <div className={cn("tnum mt-1 text-2xl font-semibold leading-none", tone)}>
        {value}
      </div>
      {sub && <div className="mt-1 text-[11px] text-muted-foreground">{sub}</div>}
    </div>
  )
}

export function Spinner({ label }: { label?: string }) {
  return (
    <div className="flex items-center gap-2 text-sm text-muted-foreground">
      <span className="size-3.5 animate-spin rounded-full border-2 border-current border-t-transparent" />
      {label ?? "Loading"}
    </div>
  )
}

export function ErrorNote({ error }: { error: unknown }) {
  const message = error instanceof Error ? error.message : String(error)
  return (
    <div className="rounded-md border sev-l3 px-3 py-2 text-sm tx-l3">
      {message}
    </div>
  )
}

export function Empty({ children }: { children: React.ReactNode }) {
  return (
    <div className="rounded-md border border-dashed border-border px-3 py-6 text-center text-sm text-muted-foreground">
      {children}
    </div>
  )
}
