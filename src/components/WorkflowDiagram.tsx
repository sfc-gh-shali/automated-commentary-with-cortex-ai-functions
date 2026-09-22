import { ArrowRight, Database, ShieldCheck, Sparkles } from "lucide-react"

export default function WorkflowDiagram() {
  return <ol className="starter-pipeline" aria-label="Base table to AI SQL generation, commentary store and analyst review">
    {[
      { title: "Base table", detail: "The report you already have", icon: Database },
      { title: "AI_COMPLETE", detail: "Instructions + column values", icon: Sparkles },
      { title: "Commentary store", detail: "Draft, prompt and model used", icon: Database },
      { title: "Analyst review", detail: "Check, edit and save", icon: ShieldCheck },
    ].map(({ title, detail, icon: Icon }, index) => <li key={title}>
      <Icon size={24} aria-hidden="true" /><strong>{title}</strong><span>{detail}</span>
      {index < 3 && <ArrowRight className="starter-arrow" size={18} aria-hidden="true" />}
    </li>)}
  </ol>
}