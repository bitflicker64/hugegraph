#!/usr/bin/env bash
# D3Q: PD majority loss with /v1/ready as readiness. Survivor = pd-0 (current leader).
set -uo pipefail; export PATH=$HOME/.local/bin:$PATH
CTX=kind-hd1; NS=hugegraph; REL=hd1; cd ~/hd1; rm -f D3QB-DONE
K="kubectl --context $CTX -n $NS"
{
echo "=== $(date -Is) D3Q-B start (hd-b images, 10 s sampler timeout)"
PW=$(kubectl --context $CTX -n $NS get secret $REL-admin -o jsonpath="{.data.password}" | base64 -d)
echo "--- oracle (declared before fault): survivor pd-0 /v1/ready -> 503 and hg_raft_has_leader 0 within the window; /v1/health stays 200 throughout; pd-0 Ready condition -> False; store-2 deleted inside the window stays Init until 2 PDs answer /v1/ready; schema create fails inside the window; full recovery (3 PD Ready, store-2 Running, /v1/ready 200 x3) within 600 s"
echo "--- pre-fault state"; $K get pods -l app.kubernetes.io/component=pd -o custom-columns=NAME:.metadata.name,UID:.metadata.uid,IP:.status.podIP,READY:.status.conditions[?\(@.type==\"Ready\"\)].status --no-headers
$K get pod hd1-hugegraph-store-2 -o custom-columns=NAME:.metadata.name,UID:.metadata.uid,IP:.status.podIP --no-headers
kubectl --context $CTX -n $NS port-forward pod/hd1-hugegraph-pd-0 18621:8620 > pf-pd0.log 2>&1 < /dev/null & PF0=$!
kubectl --context $CTX -n $NS port-forward svc/$REL-hugegraph-server 18081:8080 > pf-server2.log 2>&1 < /dev/null & PF1=$!
sleep 3
# sampler: every 2 s
( while :; do T=$(date +%s.%N); R=$(curl -s -m 10 -o /dev/null -w "%{http_code}/%{time_total}" http://127.0.0.1:18621/v1/ready); H=$(curl -s -m 2 -o /dev/null -w "%{http_code}" http://127.0.0.1:18621/v1/health); G=$(curl -s -m 2 http://127.0.0.1:18621/actuator/prometheus | grep -E "^hg_raft_(has_leader|alive_peers)" | sed -E "s/\{[^}]*\}//" | awk "{printf \"%s=%s \", \$1, \$2}"); RC=$($K get pod hd1-hugegraph-pd-0 -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}" 2>/dev/null); echo "$T ready=$R health=$H ${G}podReady=$RC"; sleep 2; done ) > d3q-b-samples.log 2>&1 & SAMP=$!
sleep 8
T0=$(date +%s); echo "--- T0=$T0 $(date -Is) deleting pd-1 and pd-2"
$K delete pod hd1-hugegraph-pd-1 hd1-hugegraph-pd-2 --wait=false
sleep 6
echo "--- T0+6: deleting store-2 (gate test)"; $K delete pod hd1-hugegraph-store-2 --wait=false
for i in 1 2 3; do sleep 4; printf "T0+%ss schema-create -> " $(( $(date +%s) - T0 )); curl -s -m 8 -u admin:$PW -X POST -H "Content-Type: application/json" http://127.0.0.1:18081/graphs/hugegraph/schema/propertykeys -d "{\"name\":\"d3q_$i\",\"data_type\":\"TEXT\",\"cardinality\":\"SINGLE\"}" -o /tmp/d3q-schema-$i.json -w "%{http_code}"; echo " $(head -c 160 /tmp/d3q-schema-$i.json)"; done
echo "--- waiting for recovery (max 600 s)"
for i in $(seq 1 120); do
  READY=$($K get pods -l app.kubernetes.io/component=pd -o jsonpath="{range .items[*]}{.status.conditions[?(@.type==\"Ready\")].status}{\" \"}{end}")
  S2=$($K get pod hd1-hugegraph-store-2 -o jsonpath="{.status.phase}/{.status.initContainerStatuses[0].state.terminated.exitCode}/{.status.containerStatuses[0].ready}" 2>/dev/null)
  echo "T0+$(( $(date +%s) - T0 ))s pdReady=[$READY] store2=$S2"
  [[ "$READY" == "True True True " && "$S2" == *"/true" ]] && { sleep 10; break; }
  sleep 5
done
echo "--- post-recovery"; $K get pods -l app.kubernetes.io/component=pd -o custom-columns=NAME:.metadata.name,UID:.metadata.uid,IP:.status.podIP,READY:.status.conditions[?\(@.type==\"Ready\"\)].status,RESTARTS:.status.containerStatuses[0].restartCount --no-headers
$K get pod hd1-hugegraph-store-2 -o custom-columns=NAME:.metadata.name,UID:.metadata.uid,IP:.status.podIP,PHASE:.status.phase --no-headers
for p in 0 1 2; do $K exec hd1-hugegraph-pd-$p -c pd -- sh -c "printf \"pd-$p ready=\"; curl -s -o /dev/null -w \"%{http_code}\" http://127.0.0.1:8620/v1/ready; printf \" health=\"; curl -s -o /dev/null -w \"%{http_code}\n\" http://127.0.0.1:8620/v1/health"; done
echo "--- store-2 init log"; $K logs hd1-hugegraph-store-2 -c wait-for-pd 2>/dev/null | tail -8
echo "--- pd-0 raft log lines"; $K logs hd1-hugegraph-pd-0 -c pd --since=10m | grep -iE "lost leader|becomes leader|step down|elect" | tail -8
echo "--- blocked/unresolved after churn"; for p in 0 1 2; do L=$($K logs hd1-hugegraph-pd-$p -c pd); printf "pd-%s unresolved=%s blocked=%s\n" $p "$(echo "$L" | grep -c "Could not resolve allowlist entry")" "$(echo "$L" | grep -c "Blocked connection")"; done
echo "--- post-recovery schema create -> "; curl -s -m 8 -u admin:$PW -X POST -H "Content-Type: application/json" http://127.0.0.1:18081/graphs/hugegraph/schema/propertykeys -d "{\"name\":\"d3q_after\",\"data_type\":\"TEXT\",\"cardinality\":\"SINGLE\"}" -o /dev/null -w "%{http_code}\n"
sleep 4; kill $SAMP $PF0 $PF1 2>/dev/null
echo "--- sample summary"; N=$(wc -l < d3q-b-samples.log); R503=$(grep -c "ready=503/" d3q-b-samples.log); R200=$(grep -c "ready=200/" d3q-b-samples.log); H200=$(grep -c "health=200" d3q-b-samples.log); HN=$(grep -vc "health=200" d3q-b-samples.log); echo "samples=$N ready503=$R503 ready200=$R200 health200=$H200 healthNot200=$HN"
F503=$(grep -m1 "ready=503/" d3q-b-samples.log | cut -d" " -f1); L503=$(grep "ready=503/" d3q-b-samples.log | tail -1 | cut -d" " -f1); echo "first503=$F503 last503=$L503 T0=$T0 (offsets: $(python3 -c "print(round(${F503:-0}-$T0,1), round(${L503:-0}-$T0,1))" 2>/dev/null))"
echo "podReady=False samples: $(grep -c "podReady=False" d3q-b-samples.log); has_leader=0 samples: $(grep -c "hg_raft_has_leader=0.0" d3q-b-samples.log)"
echo "=== $(date -Is) D3Q-B end"; touch D3QB-DONE
} > d3q-b.log 2>&1
