import { useEffect, useState } from "react"
import { Activity, CalendarDays } from "lucide-react"
import { STEPS, StepRail, StepFooter } from "@/components/StepRail"
import { useCobDates } from "@/lib/api"
import { formatDate } from "@/lib/format"
import { Spinner, ErrorNote } from "@/components/ui/primitives"
import Step1Overview from "@/components/steps/Step1Overview"
import StepBuild, { INITIAL_BUILDER } from "@/components/steps/StepBuild"
import StepResults from "@/components/steps/StepResults"
import Step5Execution from "@/components/steps/Step5Execution"

export default function App() {
  const [step, setStep] = useState(1)
  const [cob, setCob] = useState<string | null>(null)
  const [dirty, setDirty] = useState(false)
  const [busy, setBusy] = useState(false)
  const [builder, setBuilder] = useState(INITIAL_BUILDER)
  const cobDates = useCobDates()

  useEffect(() => {
    if (!cob && cobDates.data?.length) setCob(cobDates.data[0].COB_DATE)
  }, [cob, cobDates.data])

  useEffect(() => {
    const protect = (event: BeforeUnloadEvent) => {
      if (dirty || busy) { event.preventDefault(); event.returnValue = "" }
    }
    window.addEventListener("beforeunload", protect)
    return () => window.removeEventListener("beforeunload", protect)
  }, [dirty, busy])

  const canLeave = () => !busy && (!dirty || window.confirm("Discard unsaved commentary changes?"))
  const navigate = (next: number) => {
    if (next === step || !canLeave()) return
    setDirty(false)
    setStep(next)
    window.scrollTo({ top: 0 })
  }

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="shell-width header-inner">
          <div className="brand-lockup">
            <span className="brand-symbol"><Activity size={23} aria-hidden="true" /></span>
            <div><div className="brand-name">GlobalTrust <span>Financial Group</span></div>
              <div className="brand-caption">Liquidity Risk Intelligence</div></div>
          </div>
          <label className="cob-control">
            <CalendarDays size={16} aria-hidden="true" /><span>COB</span>
            <select aria-label="Close of business date" value={cob ?? ""} disabled={busy}
              onChange={(event) => {
                if (canLeave()) { setDirty(false); setBuilder(INITIAL_BUILDER); setCob(event.target.value) }
              }}>
              {(cobDates.data ?? []).map((date) => (
                <option key={date.COB_DATE} value={date.COB_DATE}>{formatDate(date.COB_DATE)}</option>
              ))}
            </select>
          </label>
        </div>
      </header>
      <div className="navigation-bar"><div className="shell-width">
        <StepRail current={step} onSelect={navigate} />
      </div></div>
      <main className="shell-width main-content">
        <div className="page-heading">
          <div><p className="eyebrow">Limits &amp; Indicators</p><h1>{STEPS[step - 1].label}</h1></div>
          <span className="workspace-label">Commentary workspace</span>
        </div>
        {step <= 3 && cobDates.isPending && <Spinner label="Connecting to report data" />}
        {step <= 3 && cobDates.error && <ErrorNote error={cobDates.error} />}
        {step <= 3 && cobDates.data?.length === 0 && <p>No report dates available.</p>}
        {step === 4 && <Step5Execution />}
        {cob && <div key={cob} className="view-content">
          {step === 1 && <Step1Overview cob={cob} onStart={() => navigate(2)} />}
          {step === 2 && <StepBuild cob={cob} state={builder} onChange={setBuilder} />}
          {step === 3 && <StepResults cob={cob} builder={builder} onBusyChange={setBusy} />}
        </div>}
        <StepFooter current={step} onPrev={() => navigate(Math.max(1, step - 1))}
          onNext={() => navigate(Math.min(STEPS.length, step + 1))} />
      </main>
    </div>
  )
}