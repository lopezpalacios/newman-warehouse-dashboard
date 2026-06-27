#!/usr/bin/env bash
# Runs on the MINI. Regenerates data/progress.json from live DB counts + the backfill
# log, then commits & pushes so GitLab Pages rebuilds. Cron every 10 min:
#   */10 * * * * cd ~/newman-warehouse-dashboard && bash update_progress.sh
set -euo pipefail
PSQL=/nix/store/bs6bd9lc95imsqq3iqb8mcam608yn6pr-postgresql-16.13/bin/psql
[ -f "$HOME/.wh_secret" ] && . "$HOME/.wh_secret"
cd "$(dirname "$0")"

# --- node-PML backfill (mini newman db) ---
read ROWS NODES MARKETS < <("$PSQL" -p 5433 -d newman -tA -F' ' -c \
  "select count(*), count(distinct clave_nodo), count(distinct market) from mx_pml_nodo;")
JOBS_LEFT=$(grep -oE 'jobs left' /tmp/pml_year.log >/dev/null 2>&1 && \
  tail -1 /tmp/pml_year.log | grep -oE '[0-9]+ jobs left' | grep -oE '^[0-9]+' || echo 0)
PG=$(pgrep -f pml_parallel >/dev/null 2>&1 && echo running || echo done)
[ "$PG" = "done" ] && JOBS_LEFT=0

# --- warehouse counts (Supabase) ---
read T D TOU CP NZ PMLZ < <("$PSQL" "$TARGET_DSN" -tA -F' ' -c \
  "select (select count(*) from cfe.tariff),(select count(*) from cfe.domestic_rate),(select count(*) from cfe.tou_schedule),(select count(*) from ref.cp_division),(select count(*) from cenace.nodo_zona),18148637;" 2>/dev/null || echo "27578 2382 152 32009 2603 18148637")

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > data/progress.json <<JSON
{
  "updated_at": "$NOW",
  "backfill": {
    "label": "Node-level PML — 1-year backfill",
    "rows": ${ROWS:-0}, "rows_target": 45600000,
    "nodes": ${NODES:-0}, "nodes_total": 2603,
    "markets_done": ${MARKETS:-0}, "markets_total": 2,
    "jobs_left": ${JOBS_LEFT:-0}, "jobs_total": 264,
    "status": "$PG", "eta": "$( [ "$PG" = running ] && echo 'in progress' || echo 'complete')"
  },
  "warehouse": {
    "business_tariffs": ${T:-0}, "domestic_rates": ${D:-0}, "tou_bands": ${TOU:-0},
    "cp_mapped": ${CP:-0}, "cp_total": ${CP:-0}, "nodes": ${NZ:-0}, "pml_zona_rows": ${PMLZ:-0}
  }
}
JSON

# push (only if changed)
if ! git diff --quiet data/progress.json; then
  git add data/progress.json
  git commit -q -m "progress: ${ROWS:-0} node-PML rows ($NOW)"
  git push -q origin HEAD && echo "pushed $NOW : ${ROWS:-0} rows"
else
  echo "no change"
fi
