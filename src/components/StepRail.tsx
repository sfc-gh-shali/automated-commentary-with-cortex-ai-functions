import { ArrowLeft, ArrowRight, Clock3, GitCompareArrows, ListChecks, Table2 } from "lucide-react"
import { cn } from "@/lib/utils"
import { useEffect, useRef } from "react"

export const STEPS = [
  { id: 1, label: "Report & Problem", icon: Table2 },
  { id: 2, label: "Build the SQL", icon: GitCompareArrows },
  { id: 3, label: "Commentary Results", icon: ListChecks },
  { id: 4, label: "Execution & Next Steps", icon: Clock3 },
]

export function StepRail({ current, onSelect }: { current: number; onSelect: (id: number) => void }) {
  const navigation = useRef<HTMLElement>(null)
  useEffect(() => {
    const rail = navigation.current
    const active = rail?.querySelector<HTMLElement>('[aria-current="step"]')
    if (!rail || !active) return
    const bounds = rail.getBoundingClientRect()
    const selected = active.getBoundingClientRect()
    if (selected.right > bounds.right) rail.scrollLeft += selected.right - bounds.right
    else if (selected.left < bounds.left) rail.scrollLeft -= bounds.left - selected.left
  }, [current])
  return (
    <nav ref={navigation} className="step-navigation" aria-label="Report workflow">
      {STEPS.map(({ id, label, icon: Icon }) => (
        <button key={id} type="button" onClick={() => onSelect(id)}
          aria-current={current === id ? "step" : undefined}
          className={cn("step-link", current === id && "is-active")}>
          <Icon size={17} aria-hidden="true" />
          <span>{label}</span>
          <span className="step-number tnum">0{id}</span>
        </button>
      ))}
    </nav>
  )
}

export function StepFooter({ current, onPrev, onNext }: {
  current: number; onPrev: () => void; onNext: () => void
}) {
  return (
    <footer className="workflow-footer">
      <button type="button" className="action-secondary" disabled={current === 1} onClick={onPrev}>
        <ArrowLeft size={16} aria-hidden="true" /> Back
      </button>
      <span className="text-xs text-muted-foreground tnum">{current} / {STEPS.length}</span>
      <button type="button" className="action-primary" disabled={current === STEPS.length} onClick={onNext}>
        {current < STEPS.length ? STEPS[current].label : "Done"}
        <ArrowRight size={16} aria-hidden="true" />
      </button>
    </footer>
  )
}