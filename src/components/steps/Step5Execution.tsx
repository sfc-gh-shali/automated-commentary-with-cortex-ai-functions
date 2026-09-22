import { ArrowRight, CalendarClock, CheckCheck, Database, FileCheck2, Inbox, Moon, Radio, ShieldCheck, Sparkles, Sunrise, Workflow, type LucideIcon } from "lucide-react"
import { Panel } from "@/components/ui/primitives"

interface ExecutionStage {
  title: string
  detail: string
  icon: LucideIcon
  kind?: "trigger" | "ai" | "output"
}

const nightly: ExecutionStage[] = [
  { title: "Report ready", detail: "Complete batch committed", icon: FileCheck2 },
  { title: "Nightly task", detail: "Scheduled time + timezone", icon: CalendarClock, kind: "trigger" },
  { title: "Prepare input", detail: "Base record or derived facts", icon: Database },
  { title: "AI SQL function", detail: "AI_COMPLETE", icon: Sparkles, kind: "ai" },
  { title: "Store drafts", detail: "AI_COMMENTARY", icon: Inbox },
  { title: "Morning review", detail: "Commentary ready for analyst", icon: Sunrise, kind: "output" },
]

const arrival: ExecutionStage[] = [
  { title: "Report ready", detail: "Publish batch-ready event", icon: FileCheck2 },
  { title: "Ready-event stream", detail: "Track completed batches", icon: Radio, kind: "trigger" },
  { title: "Triggered task", detail: "Stream has data; no schedule", icon: Workflow, kind: "trigger" },
  { title: "Prepare + generate", detail: "Selected input → AI_COMPLETE", icon: Sparkles, kind: "ai" },
  { title: "Store drafts", detail: "AI_COMMENTARY", icon: Inbox },
  { title: "Review available", detail: "After successful processing", icon: CheckCheck, kind: "output" },
]

function ExecutionFlow({ stages, label }: { stages: ExecutionStage[]; label: string }) {
  return <ol className="execution-flow" aria-label={label}>
    {stages.map(({ title, detail, icon: Icon, kind }, index) => <li key={title} className={`execution-stage ${kind ? `execution-${kind}` : ""}`}>
      <span className="execution-stage-index">0{index + 1}</span>
      <Icon size={24} strokeWidth={1.6} aria-hidden="true" />
      <h3>{title}</h3><p>{detail}</p>
      {index < stages.length - 1 && <ArrowRight className="execution-arrow" size={18} aria-hidden="true" />}
    </li>)}
  </ol>
}

export default function Step5Execution() {
  return <div className="space-y-6">
    <div className="execution-intro">
      <div><p className="eyebrow">Snowflake-native orchestration</p><h2>New report in.<br />Commentary ready for review.</h2></div>
      <span className="execution-design-label">Reference architecture · Not deployed</span>
    </div>
    <Panel title="01 / Nightly scheduled execution" right={<span className="execution-timing"><Moon size={16} aria-hidden="true" />Overnight processing</span>}>
      <ExecutionFlow stages={nightly} label="Nightly: completed report to scheduled task, input preparation, AI SQL generation, stored drafts and morning review" />
      <div className="execution-outcome"><Sunrise size={19} aria-hidden="true" /><div><strong>Target: commentary ready the next morning</strong><p>Process completed, pending reports at the nightly cutoff. Morning readiness depends on report arrival and successful completion before the review deadline.</p></div></div>
    </Panel>
    <Panel title="02 / Trigger on report arrival" right={<span className="execution-timing"><Radio size={16} aria-hidden="true" />Event-driven processing</span>}>
      <ExecutionFlow stages={arrival} label="On arrival: completed report event to stream, triggered task, AI SQL generation, stored drafts and review" />
      <div className="execution-outcome"><FileCheck2 size={19} aria-hidden="true" /><div><strong>Trigger on a complete report, not a partial load</strong><p>The loader publishes a batch-ready event after validation. A stream on that event table wakes the task; its handler consumes events into durable work and processes the named batches.</p></div></div>
    </Panel>
    <section className="execution-shared" aria-label="Shared execution controls">
      <div><Sparkles size={20} aria-hidden="true" /><h3>Same AI SQL logic</h3><p>Task → procedure → AI_COMPLETE → stored commentary</p></div>
      <div><CheckCheck size={20} aria-hidden="true" /><h3>Batch-aware processing</h3><p>Track batch, approach and input version. Skip current drafts; retain failed work for retry.</p></div>
      <div><ShieldCheck size={20} aria-hidden="true" /><h3>Analyst stays in control</h3><p>Generated drafts await review. Preserve analyst edits and monitor task failures.</p></div>
    </section>

    {/* Next Steps */}
    <div className="overview-intro"><div><p className="eyebrow">Start small. Add confidence.</p><h2>From a working POC<br />to dependable commentary.</h2></div></div>
    {[
      { title: "Better facts", summary: "When a row is not enough, prepare the important calculations in SQL before asking AI to write.", detail: "Join metric definitions, calculate band deviation and headroom, compare relevant history, and preserve uncertainty such as 'at least five periods'. A SQL view is sufficient; an extra materialised table is not required. The historical band example used 33.2 bps with a midpoint of -8.0: the tested deviation was 41.2, not the raw value." },
      { title: "Consistent responses", summary: "Specify audience, length, tone and what the model must not infer.", detail: "For report prose, give clear wording instructions and prohibit invented causes. When a downstream system requires fields, AI_COMPLETE can use a supported structured response schema. A valid structure is not proof that the content is factually correct." },
      { title: "Evaluate before rollout", summary: "Try representative rows with analyst-reviewed expected outcomes, then compare models and prompts on the same sample.", detail: "Track unsupported claims, completeness, useful wording, latency and token usage. Include missing values, bands, floors and edge cases. SQL checks and AI-assisted judging can help prioritize review, but neither replaces an analyst-reviewed reference set. This is a suggested evaluation workflow, not an evaluation running in this demo." },
      { title: "Keep control as you scale", summary: "Record the prompt and model, retain analyst edits, and avoid regenerating unchanged work.", detail: "Before production, define access, report-readiness checks, retry handling, coverage monitoring and a human approval process. The Execution diagrams show reference options; no tasks or streams are deployed by this app." },
    ].map((item) => <Panel key={item.title} title={item.title}><p className="text-sm leading-relaxed">{item.summary}</p><details className="mt-3"><summary className="muted-note">A little more detail</summary><p className="muted-note mt-3">{item.detail}</p></details></Panel>)}
  </div>
}