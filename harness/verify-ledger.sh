#!/bin/bash
# runs inside hg-probe: verify-ledger.sh <ledger.csv> ; prints summary; lists missing
L=$1; RUN=$(awk -F, '$2=="V"{split($4,a,"-"); print a[1]; exit}' $L)
chk_v() { c=$(curl -s -o /tmp/v.$$ -w '%{http_code}' -m 10 -u "admin:$ADMIN_PW" "$SVR/graphs/hugegraph/graph/vertices/%22$1%22"); r=$(jq -r '.properties.run // empty' /tmp/v.$$ 2>/dev/null); rm -f /tmp/v.$$; [ "$c" = 200 ] && [ -n "$r" ] && echo OK || echo "MISSING V $1 $c"; }
chk_e() { e=$(jq -rn --arg s "$1" '$s|@uri'); c=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -u "admin:$ADMIN_PW" "$SVR/graphs/hugegraph/graph/edges/$e"); [ "$c" = 200 ] && echo OK || echo "MISSING E $1 $c"; }
export -f chk_v chk_e
av=$(awk -F, '$2=="V" && $5==201' $L | wc -l); ae=$(awk -F, '$2=="E" && $5==201 && $4!="?"' $L | wc -l)
tv=$(awk -F, '$2=="V"' $L | wc -l); fv=$(awk -F, '$2=="V" && $5!=201' $L | wc -l)
res=$( { awk -F, '$2=="V" && $5==201{print $4}' $L | xargs -P 8 -I{} bash -c 'chk_v {}'; awk -F, '$2=="E" && $5==201 && $4!="?"{print $4}' $L | xargs -P 8 -I{} bash -c 'chk_e "{}"'; } )
miss=$(echo "$res" | grep -c MISSING)
echo "run=$RUN vertex_attempts=$tv vertex_acked=$av vertex_failed=$fv edge_acked=$ae verified_ok=$(echo "$res" | grep -c '^OK') missing=$miss"
echo "$res" | grep MISSING | head -20
cnt=$(curl -s --compressed -m 30 -u "admin:$ADMIN_PW" -H 'Content-Type: application/json' -X POST $SVR/gremlin -d "{\"gremlin\":\"g.V().hasLabel('lifemark').count()\",\"aliases\":{\"graph\":\"DEFAULT-hugegraph\",\"g\":\"__g_DEFAULT-hugegraph\"}}" | jq -r '.result.data[0] // "ERR"')
echo "gremlin_total_lifemark count=$cnt (all runs; this run acked=$av)"
