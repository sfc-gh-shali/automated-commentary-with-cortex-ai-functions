import { ArrowRight } from "lucide-react"
import { Panel } from "@/components/ui/primitives"
import WorkflowDiagram from "@/components/WorkflowDiagram"
import Step2Report from "./Step2Report"

export default function Step1Overview({ cob, onStart }: { cob: string; onStart: () => void }) {
  return <div className="space-y-6">
    <div className="overview-intro">
      <div><p className="eyebrow">Daily liquidity reporting</p>
        <h2>Your report. One AI SQL function.<br />A first draft ready for review.</h2>
        <p className="muted-note mt-3">Analysts turn positions and limits into written commentary by hand. Start with the report already in Snowflake and let AI draft the wording.</p></div>
      <button className="action-primary" onClick={onStart}>Build the SQL <ArrowRight size={16} /></button>
    </div>
    <Panel title="From source report to analyst review">
      <WorkflowDiagram />
      <p className="muted-note mt-4">No model-serving infrastructure or external LLM API integration to build. Snowflake access, compute and model permissions are required. With data and access ready, a scoped POC can be built in days; production controls come next.</p>
      <p className="muted-note mt-2">This local UI is a presentation client. The AI SQL pattern also works from a Snowflake worksheet, without this app.</p>
    </Panel>
    <Step2Report cob={cob} />
  </div>
}