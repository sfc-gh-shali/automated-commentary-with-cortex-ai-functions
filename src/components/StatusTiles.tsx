import { useSummary } from "@/lib/api"
import { asInt, formatDate } from "@/lib/format"
import { Tile, Spinner, ErrorNote } from "@/components/ui/primitives"
import { STATUS_META } from "@/lib/format"

/**
 * The six tiles that describe a COB. Shared by steps 2 and 4 so the audience
 * sees the same counts before and after commentary exists -- the only thing
 * that changes between those two steps is coverage.
 */
export default function StatusTiles({
  cob,
  showCoverage = true,
}: {
  cob: string
  showCoverage?: boolean
}) {
  const { data, isPending, error } = useSummary(cob)

  if (isPending) return <Spinner label="Loading batch summary" />
  if (error) return <ErrorNote error={error} />
  if (!data) return null

  const required = asInt(data.REQUIRES_COMMENTARY)
  const covered = asInt(data.HAS_COMMENTARY)

  return (
    <div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
        <Tile
          label="L3 critical"
          value={asInt(data.BREACH_L3)}
          accent={STATUS_META.BREACH_L3.dot}
          tone="tx-l3"
        />
        <Tile
          label="L2 material"
          value={asInt(data.BREACH_L2)}
          accent={STATUS_META.BREACH_L2.dot}
          tone="tx-l2"
        />
        <Tile
          label="L1 breach"
          value={asInt(data.BREACH_L1)}
          accent={STATUS_META.BREACH_L1.dot}
        />
        <Tile
          label="Near miss"
          value={asInt(data.NEAR_MISS)}
          accent={STATUS_META.NEAR_MISS.dot}
        />
        <Tile
          label="No data"
          value={asInt(data.NO_SOURCE_DATA)}
          accent={STATUS_META.NO_SOURCE_DATA.dot}
        />
        {showCoverage && (
          <Tile
            label="Derived coverage"
            value={`${covered}/${required}`}
            sub={
              required === 0
                ? "nothing to narrate"
                : covered >= required
                  ? "all lines narrated"
                  : `${required - covered} outstanding`
            }
          />
        )}
      </div>
      <p className="mt-2 text-xs text-muted-foreground">
        COB {formatDate(data.COB_DATE)} &middot; batch {data.BATCH_IDENTIFIER}{" "}
        &middot; {asInt(data.TOTAL_METRICS)} lines in the report
      </p>
    </div>
  )
}
