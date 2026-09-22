import { APPROACH_ORDER, type Approach } from "@/lib/api"

export const APPROACH_LABELS: Record<Approach, string> = {
  GROUNDED: "Derived facts",
  DIRECT_FULL: "Base table",
}

export default function ApproachSelect({ value, onChange, disabled = false }: {
  value: Approach; onChange: (value: Approach) => void; disabled?: boolean
}) {
  return <label className="control-label">Input approach
    <select className="field-control" value={value} disabled={disabled}
      onChange={(event) => onChange(event.target.value as Approach)}>
      {APPROACH_ORDER.map((approach) => <option key={approach} value={approach}>{APPROACH_LABELS[approach]}</option>)}
    </select>
  </label>
}