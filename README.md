# Newman Energy — Warehouse Status Dashboard

Live status + architecture map for the Mexico electricity data warehouse.
Static site (vanilla HTML/CSS/JS, Newman brand v3). Deploys to GitLab Pages.

## Live data
`data/progress.json` + `data/updates.json` drive the live numbers + CEO feed.
The mini regenerates `progress.json` from the DB every 10 min via `update_progress.sh`
(cron) and pushes → GitLab Pages rebuilds.

## Deploy
GitLab Pages auto-builds from `.gitlab-ci.yml` on push to the default branch.
URL: https://<group-or-user>.gitlab.io/newman-warehouse-dashboard/
