# Review Fix Checklist

- [x] Fix the README credential regex/value capture and reject malformed dotenv
      values without executing `.env`.
- [x] Add a dotenv-aware, non-evaluating verification path for the documented
      authenticated curl command.
- [x] Move Hubble H2 persistence to the real file boundary and use explicit
      stable volume names shared by attach and combined Compose projects.
- [x] Make image compatibility/auth readiness fail closed or prove auth with a
      smoke check instead of relying on public `/versions`.
- [x] Bind PD/Store control-plane ports safely by default or make exposure an
      explicit opt-in with matching docs and CI assertions.
- [x] Add configurable advertised Server addresses that are resolvable by
      external PD-aware clients while retaining container-local defaults.
- [x] Expand CI required environment assertions to `server0`, `server1`, and
      `server2`, and assert `pd.enabled=true` in Hubble properties.
- [x] Add combined and attach Docker smoke coverage using the authorized
      SSH/Tailscale Docker endpoint when available.
- [ ] Run targeted validation and relevant tests; fix failures.
- [ ] Obtain exactly 3 independent implementation reviews; apply fixes and
      re-review all affected findings.
- [ ] Run the single final Design Audit and resolve/classify every finding.
- [ ] Commit the verified local milestone; leave all remote refs unchanged for
      the user's final audit.

## Waiting / Deferred

None at initialization.
