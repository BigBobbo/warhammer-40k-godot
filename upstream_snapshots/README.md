# Upstream data snapshots

Raw copies of the third-party 40K data sources this project pulls from, kept so we
can rebuild our data if a source goes offline. Many 40K data sources were taken
down around 2026-11-25, so this folder holds a backup of everything the project
still uses. Each dated folder is one snapshot. Files are stored byte-for-byte as
downloaded. Check them with `sha256sum -c SHA256SUMS`.

## 2026-11-26

| Folder | Source | Notes |
|---|---|---|
| `wahapedia_wh40k11ed/` | `https://wahapedia.ru/wh40k11ed/<Name>.csv` | Full 11e export, 20 pipe-separated CSVs. Wahapedia `Last_update`: 2026-11-23 01:43:36 |
| `wahapedia_wh40k10ed/` | `https://wahapedia.ru/wh40k10ed/<Name>.csv` | Full 10e export (used by `server/tools/build-datasheet-db.js`). `Last_update`: 2026-06-13 12:02:41 |
| `npm_40kdc-data/` | `https://registry.npmjs.org/@alpaca-software/40kdc-data` | `40kdc-data-1.4.5.tgz` (the version pinned in `scripts/40kdc/package.json`), `40kdc-data-1.5.3.tgz` (npm `latest`, published 2026-11-24), plus the registry metadata JSON |

### Restoring

- **Wahapedia:** point the import tools at the folder instead of the live site,
  e.g. `node server/tools/build-datasheet-db.js --local upstream_snapshots/2026-11-26/wahapedia_wh40k10ed`,
  or `python3 -I .llm/codex_11e_wahapedia/extract_snapshot.py upstream_snapshots/2026-11-26/wahapedia_wh40k11ed <FACTION_ID> <out_dir>`.
- **40kdc-data:** `cd scripts/40kdc && npm install ../../upstream_snapshots/2026-11-26/npm_40kdc-data/40kdc-data-1.4.5.tgz`
  This installs the dataset from the local file. Its ordinary dependencies
  (ajv, glob, …) still come from npm.

Data © its respective owners (Games Workshop rules content, Wahapedia, Alpaca
Software / the 40kdc community). See `40k/data/40kdc/ATTRIBUTION.md`.
