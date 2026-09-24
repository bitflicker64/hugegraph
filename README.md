# Evidence for the apache/hugegraph#3227 fix

Hosted from a test session; each file is listed with its size.

- `control/converge.log` (12051 bytes)
- `control/ledger.csv.gz` (91848 bytes)
- `control/pd-0.log` (2825 bytes)
- `control/pd-1.log` (24111 bytes)
- `control/pd-2.log` (2825 bytes)
- `control/s2b.log` (6684 bytes)
- `control/session.yaml` (695 bytes)
- `control/shardGroups-final.json` (3526 bytes)
- `control/store-0.log` (16011 bytes)
- `control/store-1.log` (16875 bytes)
- `control/store-2.log.gz` (25951 bytes)
- `control/stores-final.json` (4841 bytes)
- `control/storeview-0-before.txt` (12570 bytes)
- `control/storeview-1-after.txt` (8676 bytes)
- `control/verify.txt` (180 bytes)
- `fix-run1/converge.log` (122 bytes)
- `fix-run1/ledger.csv.gz` (12500 bytes)
- `fix-run1/pd-0.log` (0 bytes)
- `fix-run1/pd-1.log` (32022 bytes)
- `fix-run1/pd-2.log` (0 bytes)
- `fix-run1/s2b.log` (6740 bytes)
- `fix-run1/session.yaml` (683 bytes)
- `fix-run1/shardGroups-final.json` (3538 bytes)
- `fix-run1/store-0.log` (17959 bytes)
- `fix-run1/store-1.log` (33868 bytes)
- `fix-run1/store-2.log.gz` (3273 bytes)
- `fix-run1/stores-final.json` (6162 bytes)
- `fix-run1/storeview-0-before.txt` (12576 bytes)
- `fix-run1/storeview-1-after.txt` (12327 bytes)
- `fix-run1/verify.txt` (170 bytes)
- `fix-run2/converge.log` (245 bytes)
- `fix-run2/health.log` (2236 bytes)
- `fix-run2/ledger.csv.gz` (42552 bytes)
- `fix-run2/pd-0.log` (41753 bytes)
- `fix-run2/pd-1.log` (1130 bytes)
- `fix-run2/pd-2.log` (1130 bytes)
- `fix-run2/s2b.log` (7719 bytes)
- `fix-run2/session.yaml` (683 bytes)
- `fix-run2/shardGroups-final.json` (3550 bytes)
- `fix-run2/store-0.log` (28924 bytes)
- `fix-run2/store-1.log` (28719 bytes)
- `fix-run2/store-2.log.gz` (5818 bytes)
- `fix-run2/stores-final.json` (7485 bytes)
- `fix-run2/storeview-0-before.txt` (12576 bytes)
- `fix-run2/storeview-1-after.txt` (12311 bytes)
- `fix-run2/storeview-2-after-restart.txt` (16214 bytes)
- `fix-run2/verify.txt` (176 bytes)
- `harness/kind.yaml` (123 bytes)
- `harness/probe.Dockerfile` (63 bytes)
- `harness/verify-ledger.sh` (1625 bytes)
- `harness/writer.sh` (1195 bytes)
- `s2b-run.sh` (13493 bytes)
- `unit-tests-summary.txt` (762 bytes)

Regression evidence for apache/hugegraph#3227 (a Store rebuilt with an empty volume never rejoins its raft groups), measured 2026-09-24 on kind v0.33 (Kubernetes 1.37.0), 3 PD + 3 Store + 3 Server + Hubble, chart at hugegraph/hugegraph `26bbbcefb`, NetworkPolicy on.

- `s2b-run.sh`: the harness. One argument, the image tag. `OBSERVE_S` adds the health watch, second patrol and store-2 restart.
- `harness/`: files `s2b-run.sh` reads from the older harness (`kind.yaml`, the writer, the ledger verifier, the probe image).
- `control/`: images apache master `83ef9f3` (Docker Hub `:latest` of 2026-09-21, store `sha256:7bc0cbd81550`). Does not converge.
- `fix-run1/`, `fix-run2/`: images built from `9b6bf414` (revision label in `s2b.log`). Converge at the first sample.
- Per run: `s2b.log` (step log), `converge.log` (15 s samples), `health.log` (run 2 only, 30 s samples), `storeview-*.txt` (every Store's own `/v1/partition/{id}` per group: role, commit index, per-table key counts), `stores-final.json` and `shardGroups-final.json` (PD after DELETE of the old id), `pd-*.log` and `store-*.log` (from the Tombstone on), `verify.txt` (every acknowledged write read back), `ledger.csv.gz`, `session.yaml` (the values used on top of `values-cluster.yaml`).
- `unit-tests-summary.txt`: baseline and patched unit suites.
