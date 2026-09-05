# Test logs for apache/hugegraph#3185 (PD /v1/ready), 2026-09-05

Images built from hugegraph/hugegraph tag helm-dev-20260905 (commit 6ec19838:
master 36811483 + #3185 at 70744406 + #3187 + #3189), docker buildx bake,
linux/amd64, org.opencontainers.image.revision=6ec1983889f58a52995b27a4e1ea89bd00932396.
kind v0.33.0, Kubernetes 1.37.0, 3 PD + 3 Store + 3 Server + Hubble, the #3132
chart with pd.readinessPath=/v1/ready and store.waitPath=/v1/ready.

Run 1 (d3q.*): images from the same tree minus #3189 (c1100710), sampler
`curl -m 2`. Run 2 (d3q-b.*): the full tree, sampler `curl -m 10` with
`%{time_total}` appended to the ready column as code/seconds.

- d3q.sh, d3q-b.sh: the scenario scripts (oracle declared before the fault).
- d3q.log, d3q-b.log: script output (pre-fault state, T0, recovery loop, post-recovery checks).
- d3q-samples.log, d3q-b-samples.log: one line per 2 s on the surviving PD
  (pd-0) through a pod port-forward: epoch, /v1/ready, /v1/health, hg_raft_*
  gauges from /actuator/prometheus, the Pod Ready condition.

Fault: `kubectl delete pod pd-1 pd-2` at T0 (run 1: 1788591947, run 2: 1788593447),
`kubectl delete pod store-2` at T0+6 s. ready=000 means curl timed out.
