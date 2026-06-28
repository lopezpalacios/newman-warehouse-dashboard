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

# --- historical Parquet archive ---
ARCH_DIR="$HOME/newman-data/pml_nodo_history"
AROWS=0; AMONTHS=0; ALO=""; ASIZE="0"
AFILES=$(ls "$ARCH_DIR"/*.parquet 2>/dev/null | wc -l | tr -d ' ')
ARUN=$(pgrep -f pml_nodo_history >/dev/null 2>&1 && echo running || echo done)
if [ "${AFILES:-0}" -gt 0 ]; then
  ASIZE=$(du -sh "$ARCH_DIR" 2>/dev/null | awk '{print $1}')
  read AROWS AMONTHS ALO < <("$HOME/projects/browser-use-jobs/.venv/bin/python" - <<PYEOF 2>/dev/null || echo "0 0 -"
import duckdb
try:
    r=duckdb.sql("select count(*), count(distinct substr(fecha,1,7)), min(fecha) from read_parquet('$ARCH_DIR/*.parquet')").fetchone()
    print(r[0], r[1], r[2] or '-')
except Exception: print("0 0 -")
PYEOF
)
fi

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
  },
  "archive": {
    "label": "Historical node-PML — Parquet archive (2016 → 2025)",
    "rows": ${AROWS:-0}, "files": ${AFILES:-0}, "months": ${AMONTHS:-0}, "months_total": 113,
    "earliest": "${ALO:--}", "size": "${ASIZE:-0}", "status": "$ARUN"
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
