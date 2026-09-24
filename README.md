# Evidence for the apache/hugegraph#3234 review follow-ups

Hosted from a test session; each file is listed with its size.

- `fix3/converge.log` (245 bytes)
- `fix3/health.log` (2236 bytes)
- `fix3/ledger.csv.gz` (42484 bytes)
- `fix3/pd-0.log` (1130 bytes)
- `fix3/pd-1.log` (1130 bytes)
- `fix3/pd-2.log` (41541 bytes)
- `fix3/s2b.log` (7721 bytes)
- `fix3/session.yaml` (686 bytes)
- `fix3/shardGroups-final.json` (3538 bytes)
- `fix3/store-0.log` (10799 bytes)
- `fix3/store-1.log` (46093 bytes)
- `fix3/store-2.log.gz` (5822 bytes)
- `fix3/stores-final.json` (7485 bytes)
- `fix3/storeview-0-before.txt` (12582 bytes)
- `fix3/storeview-1-after.txt` (12305 bytes)
- `fix3/storeview-2-after-restart.txt` (16214 bytes)
- `fix3/verify.txt` (177 bytes)
- `unit-tests-summary.txt` (350 bytes)

Rerun of the apache/hugegraph#3227 scenario on the review follow-ups: images built from `0c2a1801` (PR head: `9b6bf414` + `97f5b013` + `0c2a1801`, revision label in `fix3/s2b.log`). Same harness, chart and host as the first evidence set on branch `logs/fix-3227` (harness files are there). The Store leader logs show the new order: `snapshot after create raft node` for all 12 groups, then `doChangeShard result is Status[OK]`.
