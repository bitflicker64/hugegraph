#!/bin/bash
# s2b-run.sh TAG : apache/hugegraph#3227 regression (S2b of lifecycle-20260922T161440Z).
# Fresh kind cluster hg3227-TAG with hg3227/{pd,store,server}:TAG, 3 PD + 3 Store + 3 Server +
# Hubble, values-cluster.yaml (NetworkPolicy on). Empty-PVC replacement of store-2, then the
# README retirement (Tombstone old id on the PD leader + patrolPartitions), then wait.
# Evidence: ~/hg-3227/runs/TAG/. Tears the cluster down at the end (host fits one at a time).
set -u
TAG=$1; KEEP=${KEEP:-0}; WAIT_S=${WAIT_S:-1500}
C=hg3227-$TAG; CTX=kind-$C; K="kubectl --context $CTX"; NS=hg
CH=~/hg-3227/chart/helm/hugegraph; W=~/hg-3227/runs/$TAG
mkdir -p $W/cap; cd $W; LOG=$W/s2b.log; : > $LOG
say() { echo "$(date -u +%FT%T.%3NZ) $*" | tee -a $LOG; }
PIDS=()
cleanup() { for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT

# ---- 0. cluster, images, install ----
say "0 chart $(cat ~/hg-3227/chart/SHA) tag $TAG"
kind delete cluster --name $C >/dev/null 2>&1
kind create cluster --name $C --config ~/hg-lifecycle/kind.yaml --wait 180s > cap/kind-create.log 2>&1 || { say "kind create failed"; exit 1; }
for i in pd:$TAG store:$TAG server:$TAG hubble:control probe:1; do
  kind load docker-image hg3227/$i --name $C > /dev/null 2>&1 || { say "kind load hg3227/$i failed"; exit 1; }
  say "0 loaded hg3227/$i $(docker image inspect hg3227/$i --format '{{.Id}} rev={{index .Config.Labels "org.opencontainers.image.revision"}}')"
done
cat > session.yaml <<EOF
pd:     { image: { repository: hg3227/pd,     tag: "$TAG", pullPolicy: IfNotPresent } }
store:  { image: { repository: hg3227/store,  tag: "$TAG", pullPolicy: IfNotPresent } }
server: { image: { repository: hg3227/server, tag: "$TAG", pullPolicy: IfNotPresent } }
hubble: { enabled: true, image: { repository: hg3227/hubble, tag: control, pullPolicy: IfNotPresent } }
networkPolicy:
  server:
    extraIngress:
      - from: [ { podSelector: { matchLabels: { hg3227/role: probe } } } ]
        ports: [ { protocol: TCP, port: 8080 } ]
  store:
    extraIngress:
      - from: [ { podSelector: { matchLabels: { hg3227/role: probe } } } ]
        ports: [ { protocol: TCP, port: 8520 } ]
EOF
T0=$(date +%s)
helm --kube-context $CTX install hugegraph $CH -n $NS --create-namespace -f $CH/values-cluster.yaml -f session.yaml --wait --timeout 30m > cap/helm-install.log 2>&1
say "0 helm install rc=$? in $(( $(date +%s)-T0 ))s"
$K -n $NS get pods -o wide > cap/pods-installed.txt
for c in pd store server; do say "0 running $c imageID $($K -n $NS get pod hugegraph-$c-0 -o jsonpath='{.status.containerStatuses[0].imageID}' 2>/dev/null || $K -n $NS get pods -l app.kubernetes.io/component=$c -o jsonpath='{.items[0].status.containerStatuses[0].imageID}')"; done

# ---- helpers ----
for N in 0 1 2; do ( while :; do $K port-forward -n $NS pod/hugegraph-pd-$N 1872$N:8620 >/dev/null 2>&1; sleep 2; done ) & PIDS+=($!); done
sleep 5
PD_SECRET="$($K -n $NS get secret hugegraph-pd-auth -o jsonpath='{.data.secret-key}' | base64 --decode)"
lead() { for N in 0 1 2; do curl -s -m 5 127.0.0.1:1872$N/v1/ready | grep -q '"isLeader":true' && echo $N; done | head -1; }
pd() { curl -s -m 10 -u "hg:${PD_SECRET}" "http://127.0.0.1:1872$(lead)$1"; }
pdpost() { curl -s -m 10 -w ' [%{http_code}]' -u "hg:${PD_SECRET}" -X POST -H 'Content-Type: application/json' -d "$2" "http://127.0.0.1:1872$(lead)$1"; }
cat <<Y | $K apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: { name: hg-probe, namespace: $NS, labels: { hg3227/role: probe } }
spec:
  containers:
    - name: probe
      image: hg3227/probe:1
      imagePullPolicy: Never
      command: ["sleep","infinity"]
      env:
        - { name: SVR, value: "http://hugegraph-server.$NS.svc:8080" }
        - name: ADMIN_PW
          valueFrom: { secretKeyRef: { name: hugegraph-admin, key: password } }
Y
$K -n $NS wait --for=condition=Ready pod/hg-probe --timeout=120s >/dev/null
P() { $K -n $NS exec -i hg-probe -- bash -c "$1"; }
# per-group view from every Store's own REST (the only surface that showed the loss in the original run)
storeview() {
  P 'for n in 0 1 2; do for g in $(seq 0 11); do r=$(curl -s -m 2 -w " %{http_code}" http://hugegraph-store-$n.hugegraph-store.hg.svc:8520/v1/partition/$g); c=${r##* }; b=${r% *}; echo "s$n g$g $c $(echo "$b" | jq -c "[.role, .logIndex, (.partitions|length), [.partitions[]?.metric]]" 2>/dev/null)"; done; done'
}
dsize() { for n in 0 1 2; do echo "s$n $($K -n $NS exec hugegraph-store-$n -c store -- du -sm /hugegraph-store/storage 2>/dev/null | cut -f1)MB"; done | tr '\n' ' '; }

# ---- 1. schema + bulk data (about 9k vertices, as in the original report) + writer ----
P 'A="-s -o /dev/null -w %{http_code} -u admin:$ADMIN_PW -H Content-Type:application/json -X POST"
for b in "propertykeys {\"name\":\"ts\",\"data_type\":\"TEXT\",\"cardinality\":\"SINGLE\"}" \
         "propertykeys {\"name\":\"run\",\"data_type\":\"TEXT\",\"cardinality\":\"SINGLE\"}" \
         "vertexlabels {\"name\":\"lifemark\",\"id_strategy\":\"CUSTOMIZE_STRING\",\"properties\":[\"ts\",\"run\"],\"nullable_keys\":[],\"enable_label_index\":true}" \
         "edgelabels {\"name\":\"next\",\"source_label\":\"lifemark\",\"target_label\":\"lifemark\",\"frequency\":\"SINGLE\",\"properties\":[\"run\"],\"nullable_keys\":[\"run\"]}"; do
  echo "schema ${b%% *} $(curl $A $SVR/graphs/hugegraph/schema/${b%% *} -d "${b#* }")"; done' | tee -a $LOG
P 'for i in $(seq 0 17); do body=$(jq -nc --arg i $i "[range(0;500)|{label:\"lifemark\",id:\"bulk-\(\$i)-\(.)\",properties:{ts:\"0\",run:\"bulk\"}}]"); echo -n "$(curl -s -o /dev/null -w %{http_code} -u admin:$ADMIN_PW -H Content-Type:application/json -X POST $SVR/graphs/hugegraph/graph/vertices/batch -d "$body") "; done; echo' | tee -a $LOG
$K -n $NS create configmap hg-writer-script --from-file=writer.sh=$HOME/hg-lifecycle/scripts/writer.sh >/dev/null
cat <<Y | $K apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: { name: hg-writer, namespace: $NS, labels: { hg3227/role: probe } }
spec:
  containers:
    - name: writer
      image: hg3227/probe:1
      imagePullPolicy: Never
      command: ["bash","/s/writer.sh"]
      env:
        - { name: SVR, value: "http://hugegraph-server.$NS.svc:8080" }
        - { name: RUN_ID, value: "s2b$TAG" }
        - name: ADMIN_PW
          valueFrom: { secretKeyRef: { name: hugegraph-admin, key: password } }
      volumeMounts: [{ name: s, mountPath: /s }, { name: data, mountPath: /data }]
  volumes: [{ name: s, configMap: { name: hg-writer-script } }, { name: data, emptyDir: {} }]
Y
sleep 60
ADDR="hugegraph-store-2.hugegraph-store.$NS.svc:8500"
X=$(pd /v1/stores | jq -r --arg a "$ADDR" '.data.stores[] | select(.address==$a) | .storeId')
say "S2b.0 leader pd-$(lead) X=$X groups_with_X=$(pd /v1/shardGroups | jq --arg x $X '[.shardGroups[]|select([.shards[].storeId]|index($x))]|length') datasize $(dsize)"
storeview > cap/storeview-0-before.txt

# ---- 2. S2b.1: delete the PVC, then the Pod ----
say "S2b.1 delete PVC then pod"; T=$(date +%s)
$K delete pvc -n $NS store-data-hugegraph-store-2 --wait=false >/dev/null
$K delete pod -n $NS hugegraph-store-2 --wait=false >/dev/null
sleep 20
[ "$($K get pod -n $NS hugegraph-store-2 -o jsonpath='{.status.phase}' 2>/dev/null)" = Pending ] && { say "S2b.1 pod Pending, deleting once more"; $K delete pod -n $NS hugegraph-store-2 --wait=false >/dev/null; }
while :; do r=$($K get pod -n $NS hugegraph-store-2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null); [ "$r" = True ] && break; [ $(( $(date +%s)-T )) -gt 900 ] && { say "S2b.1 pod not Ready in 900s"; break; }; sleep 5; done
Y=""; for i in $(seq 1 30); do Y=$(pd /v1/stores | jq -r --arg a "$ADDR" --arg x "$X" '.data.stores[] | select(.address==$a and .storeId!=$x) | .storeId'); [ -n "$Y" ] && break; sleep 5; done
say "S2b.1 pod Ready after $(( $(date +%s)-T ))s; Y=$Y rows_at_addr=$(pd /v1/stores | jq -r --arg a "$ADDR" '[.data.stores[]|select(.address==$a)|"\(.storeId):\(.state)"]|join(",")') reg=$($K logs -n $NS hugegraph-store-2 -c store | grep -m1 -o 'Register Store id= [0-9]*')"

# ---- 3. S2b.2/5: Tombstone X on the leader while it is still Up (what the original run did) ----
tcall=$(date -u +%FT%TZ); TT=$(date +%s)
say "S2b.5 Tombstone X on leader pd-$(lead) -> $(pdpost /v1/store/$X '{"storeState":"Tombstone"}' | cut -c1-240)"
say "S2b.6 patrolPartitions -> $(curl -s -m 30 -w ' [%{http_code}]' -u "hg:${PD_SECRET}" http://127.0.0.1:1872$(lead)/v1/task/patrolPartitions | cut -c1-200)"

# ---- 4. wait for convergence (or WAIT_S), sampling PD and every Store ----
ok=0
while [ $(( $(date +%s)-TT )) -lt $WAIT_S ]; do
  UP=$(pd /v1/stores | jq -c '[.data.stores[]|select(.state=="Up")|.storeId]')
  R=$(pd /v1/shardGroups | jq --argjson up "$UP" --arg x "$X" --arg y "$Y" -c '{groups:(.shardGroups|length), full:[.shardGroups[]|select((.shards|length)==3)]|length, oneleader:[.shardGroups[]|select(([.shards[]|select(.role=="Leader")]|length)==1)]|length, badstore:[.shardGroups[]|select(([.shards[].storeId]-$up|length)>0)]|length, withX:[.shardGroups[]|select([.shards[].storeId]|index($x))]|length, withY:[.shardGroups[]|select([.shards[].storeId]|index($y))]|length}')
  SV=$(storeview); y200=$(echo "$SV" | awk '$1=="s2" && $3==200' | wc -l)
  echo "$(date -u +%FT%TZ) +$(( $(date +%s)-TT ))s $R s2_partitions_200=$y200/12" >> cap/converge.log
  echo "$R" | grep -q '"full":12,"oneleader":12,"badstore":0,"withX":0,"withY":12' && [ "$y200" = 12 ] && { ok=1; break; }
  sleep 15
done
say "S2b.7 converged=$ok after $(( $(date +%s)-TT ))s since Tombstone: $(tail -1 cap/converge.log | cut -d' ' -f3-)"
storeview > cap/storeview-1-after.txt
say "S2b.7 datasize $(dsize)"
say "S2b.7 stores $(pd /v1/stores | jq -c '[.data.stores[]|{id:.storeId,state,partitionCount}]') counts=$(pd /v1/stores | jq -c '.data.stateCountMap') cluster=$(pd /v1/cluster | jq -c '{state:(.data.state // .state), stores:(.data.storeSize // .storeSize)}' 2>/dev/null)"

# ---- 4b. health over time (OBSERVE_S), a second patrol, then a store-2 restart with its PVC ----
health() { echo "stores=$(pd /v1/stores | jq -c '[.data.stores[]|"\(.storeId|tostring|.[0:6]):\(.state):\(.partitionCount)"]') counts=$(pd /v1/stores | jq -c '.data.stateCountMap') cluster=$(pd /v1/cluster | jq -r '.data.state // .state') groups=$(pd /v1/shardGroups | jq --arg x "$X" --arg y "$Y" -c '{withX:[.shardGroups[]|select([.shards[].storeId]|index($x))]|length, withY:[.shardGroups[]|select([.shards[].storeId]|index($y))]|length, state:([.shardGroups[].state]|group_by(.)|map("\(.[0]):\(length)"))}') s2_200=$(storeview | awk '$1=="s2" && $3==200' | wc -l)/12"; }
if [ "${OBSERVE_S:-0}" -gt 0 ]; then
  TO=$(date +%s)
  while [ $(( $(date +%s)-TO )) -lt $OBSERVE_S ]; do echo "$(date -u +%FT%TZ) +$(( $(date +%s)-TT ))s $(health)" >> cap/health.log; sleep 30; done
  say "4b health after ${OBSERVE_S}s: $(tail -1 cap/health.log | cut -d' ' -f3-)"
  say "4b second patrolPartitions -> $(curl -s -m 30 -w ' [%{http_code}]' -u "hg:${PD_SECRET}" http://127.0.0.1:1872$(lead)/v1/task/patrolPartitions | cut -c1-120)"
  sleep 30; say "4b after second patrol: $(health)"
  say "4b restart store-2 keeping its PVC"; TR=$(date +%s); $K delete pod -n $NS hugegraph-store-2 --wait=false >/dev/null; sleep 20
  while :; do r=$($K get pod -n $NS hugegraph-store-2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null); [ "$r" = True ] && break; [ $(( $(date +%s)-TR )) -gt 900 ] && break; sleep 5; done
  sleep 60
  say "4b store-2 Ready after $(( $(date +%s)-TR - 60 ))s, restarts=$($K get pod -n $NS hugegraph-store-2 -o jsonpath='{.status.containerStatuses[0].restartCount}') reg=$($K logs -n $NS hugegraph-store-2 -c store | grep -m1 -o 'Register Store id= [0-9]*') exit_illegal=$($K logs -n $NS hugegraph-store-2 -c store | grep -c 'is illegal') $(health)"
  storeview > cap/storeview-2-after-restart.txt
fi

# ---- 5. README optional cleanup: DELETE X, then look again ----
say "extra DELETE X -> $(curl -s -m 10 -w ' [%{http_code}]' -u "hg:${PD_SECRET}" -X DELETE http://127.0.0.1:1872$(lead)/v1/store/$X | cut -c1-120)"
sleep 30
say "extra after DELETE: groups naming X=$(pd /v1/shardGroups | jq --arg x $X '[.shardGroups[]|select([.shards[].storeId]|index($x))]|length') naming Y=$(pd /v1/shardGroups | jq --arg y $Y '[.shardGroups[]|select([.shards[].storeId]|index($y))]|length') X_record=$(pd /v1/stores | jq -r --arg x $X '[.data.stores[]|select(.storeId==$x)]|length')"
pd /v1/shardGroups > cap/shardGroups-final.json; pd /v1/stores > cap/stores-final.json

# ---- 6. ledger, logs ----
$K -n $NS exec hg-writer -- cat /data/ledger.csv > cap/ledger.csv 2>/dev/null
$K -n $NS exec -i hg-probe -- bash -c 'cat > /tmp/ledger.csv' < cap/ledger.csv
$K -n $NS exec -i hg-probe -- bash -s < $HOME/hg-lifecycle/scripts/verify-ledger.sh /tmp/ledger.csv > cap/verify.txt 2>&1
say "data $(head -1 cap/verify.txt)"
for n in 0 1 2; do $K logs -n $NS hugegraph-pd-$n --since-time=$tcall > cap/pd-$n.log 2>/dev/null; $K logs -n $NS hugegraph-store-$n -c store --since-time=$tcall > cap/store-$n.log 2>/dev/null; done
$K logs -n $NS hugegraph-store-2 -c store > cap/store-2-full.log 2>/dev/null
say "logs changePeers=$(cat cap/store-*.log | grep -c 'changePeers start') installSnapshot=$(grep -ci 'snapshot' cap/store-2-full.log) onConfigurationCommitted_withX=$(cat cap/store-*.log | grep 'onConfigurationCommitted, shardGroup' | grep -c "$X")"
echo DONE >> $LOG
[ "$KEEP" = 1 ] || kind delete cluster --name $C >/dev/null 2>&1
