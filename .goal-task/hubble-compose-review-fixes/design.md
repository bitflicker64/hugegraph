# Confirmed Design Decisions

- Keep the Hubble add-on attachable and independent of cluster service
  lifecycle; do not add `depends_on` that recreates or restarts the cluster.
- Treat the external shared network as a security boundary. Control-plane
  ports should bind to loopback by default, with explicit host overrides for
  operators who need remote access.
- Use stable, explicit volume names for Hubble state so attach and combined
  Compose projects address the same physical data. Mount the H2 parent/data
  boundary that matches `jdbc:h2:file:./db`.
- Keep a single PD operations endpoint as the current Hubble runtime contract,
  but make the limitation explicit and configurable; do not claim automatic
  HTTP failover without a Hubble code change.
- Preserve container-local Server registration defaults while exposing a
  configurable advertised address for clients outside the Docker network.
- Never source an operator-controlled dotenv file as shell code in documented
  verification/setup. Parse only the required keys and validate them.
- CI must assert the same required Server settings on all three replicas and
  explicitly assert Hubble PD mode.
- Runtime smoke checks should prove the authentication contract and Hubble
  reachability when Docker is available; render-only checks remain useful but
  are not sufficient evidence.
- Keep the final result local. Do not push, create PRs, or mutate remote refs;
  the user will audit the final state before deciding whether to push.
