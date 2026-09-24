#!/bin/bash
# env: SVR, ADMIN_PW, RUN_ID   ledger: /data/ledger.csv (also stdout)
seq=0; prev=""
post() {
  local t0=$(date +%s%3N) out
  out=$(curl -s -w '\n%{http_code}' --connect-timeout 2 --max-time 5 -u "admin:${ADMIN_PW}" \
         -H 'Content-Type: application/json' -X POST "${SVR}$1" -d "$2" 2>/dev/null) || out=$'\n000'
  code=${out##*$'\n'}; body=${out%$'\n'*}; lat=$(( $(date +%s%3N) - t0 ))
}
while :; do
  seq=$((seq+1)); id="${RUN_ID}-${seq}"; now=$(date +%s%3N)
  post /graphs/hugegraph/graph/vertices "{\"label\":\"lifemark\",\"id\":\"${id}\",\"properties\":{\"ts\":\"${now}\",\"run\":\"${RUN_ID}\"}}"
  vcode=$code
  echo "$(date -u +%FT%T.%3NZ),V,${seq},${id},${code},${lat}," | tee -a /data/ledger.csv
  if [ "$vcode" = 201 ] && [ -n "$prev" ]; then
    post /graphs/hugegraph/graph/edges "{\"label\":\"next\",\"outV\":\"${prev}\",\"inV\":\"${id}\",\"outVLabel\":\"lifemark\",\"inVLabel\":\"lifemark\",\"properties\":{\"run\":\"${RUN_ID}\"}}"
    eid=$(printf '%s' "$body" | jq -r '.id // empty' 2>/dev/null)
    echo "$(date -u +%FT%T.%3NZ),E,${seq},${eid:-?},${code},${lat},${prev}>${id}" | tee -a /data/ledger.csv
  fi
  [ "$vcode" = 201 ] && prev="$id"
  sleep 0.5
done
