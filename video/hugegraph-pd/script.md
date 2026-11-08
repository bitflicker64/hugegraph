# HugeGraph PD intro video: script

Length 59.8 s, 1920x1080, 30 fps. Six scenes on a dark background with line-art diagrams.
The narration is spoken by Kokoro-82M (voice `af_heart`, speed 1.12). Scene times below are the
real audio lengths measured by `tts.py`; `build.py` writes them into `index.html`, so the voice,
the captions and the animation run on one clock. Captions are the narration text, shown one
sentence at a time, with each word lit as it is spoken.

The spoken text spells some names out so the model says them right ("Huge Graph", "P D",
"Rocks D B", "Sofa J Raft", "sixteen-bit"). The captions use the real names. Both versions live in
`narration.json`.

## Scenes

| # | Time (s) | Scene | Narration (caption text) | On screen |
|---|---|---|---|---|
| 1 | 0.3 to 7.3 | Intro | This is HugeGraph PD, the Placement Driver: the control plane of a distributed HugeGraph cluster. | Title letters rise in, a node network draws out from the center, tagline "PLACEMENT DRIVER" and "metadata, partitions, store health, Raft". |
| 2 | 7.3 to 16.7 | Three roles | Servers run graph queries. Stores hold the graph data. PD holds only the metadata: which stores are alive, and where every partition lives. | Three Server boxes, then three Store boxes with small graphs inside, then the PD box between them with "stores 1 2 3 alive" and "partition to store". |
| 3 | 16.7 to 27.1 | Partitions | Every key hashes to a 16-bit code. PD splits that range into partitions, and places each partition's replicas on different stores, one as the leader. | Key "marko" goes through `calcHashcode` and lands at 0xC830 on the 0 to 0xFFFF bar. The bar splits into P0 to P3, the hit partition lights up, and three replicas of each partition fly into Store 1, 2 and 3. One replica per partition turns amber (leader). |
| 4 | 27.1 to 38.8 | Heartbeats | Stores register with PD and send heartbeats. PD answers with instructions: move a partition, split it, or transfer its leader. A store that goes quiet is marked offline. | `RegisterStore` goes up each link and an id comes back. Heartbeat pulses travel up and ripple PD. `MovePartition`, `SplitPartition` and `TransferLeader` travel down. Store 3 stops pulsing and gets an OFFLINE stamp. |
| 5 | 38.8 to 50.7 | Raft | PD itself runs as three or five nodes on SOFA-JRaft. Every metadata write is a Raft proposal, saved in RocksDB. If the leader fails, the others elect a new one. | Three PD nodes (two dashed ones flash in at "five"), PD 1 is leader. A metadata write reaches the leader, is copied to the followers, each log grows and each RocksDB fills. PD 1 fails, election timers run, a vote goes out and back, PD 3 becomes leader in term 2. |
| 6 | 50.7 to 59.8 | Routing, end card | Servers ask PD where a key lives, cache the answer, and talk to that store directly. PD stays out of the data path. | The Server asks PD where "marko" lives, gets "P3, leader Store 1", caches it, then a thick data path draws to Store 1 with packets on it. PD dims with the label "control plane". End card: "HugeGraph PD", "apache/hugegraph, hugegraph-pd". |

## Sources for each claim

| Claim | Source |
|---|---|
| PD is the control plane; it holds metadata, not graph data | `hugegraph-pd/docs/architecture.md` ("the control plane for HugeGraph distributed deployments"), root `AGENTS.md` ("PD: placement + metadata", "Store: partition data + Raft") |
| Servers serve Gremlin, Cypher and REST | root `AGENTS.md` ("REST/Gremlin API"), `hugegraph-api/.../api/cypher/CypherAPI.java` |
| Stores keep the data in RocksDB and replicate with Raft | `hugegraph-store/hg-store-rocksdb`, `hugegraph-store/hg-store-core/pom.xml` (`jraft-core`), `docs/architecture.md` (Architecture Context) |
| Keys hash to a 16-bit code | `PartitionUtils.calcHashcode` masks with `MAX_VALUE = 0xffff` (`hg-pd-common`). The 0xC830 for "marko" is that function run on the key; the same result came from Java and from the page's JS port. |
| PD splits the code range into partitions and places replicas (shards) with one leader | `docs/architecture.md` (PartitionMeta: `startKey`, `endKey`, shards with `LEADER`/`FOLLOWER`); `partition.default-shard-count` in `application.yml` |
| Stores register and send heartbeats | `pdpb.proto`: `RegisterStore`, `StoreHeartbeat`; `pd_pulse.proto`: `PartitionHeartbeatRequest` |
| PD answers with move, split and transfer-leader instructions | `pd_pulse.proto`: `PartitionHeartbeatResponse` carries `MovePartition`, `SplitPartition`, `TransferLeader` |
| A quiet store is marked offline | `TaskScheduleService.patrolStores()` sets `StoreState.Offline` for stores that are no longer active |
| PD runs as three or five nodes on SOFA-JRaft | `hugegraph-pd/README.md` (Production Deployment Notes), `hg-pd-core/pom.xml` (`jraft-core`), `RaftEngine.java` |
| Metadata writes are Raft proposals saved in RocksDB | `hugegraph-pd/AGENTS.md` ("Trace metadata mutations through `RaftTaskHandler` / `KVOperation`"), `hugegraph-pd/README.md` ("RocksDB for persistent metadata storage"), `meta/MetadataRocksDBStore.java` |
| Servers ask PD for the partition, cache it and go to the store | `docs/architecture.md` (Partition Query Flow), `PDClient` and `ClientCache` in `hg-pd-client` |
| PD is not on the data path | root `AGENTS.md` (Server, then HStore adapter, then Store client, then Store) and `docs/architecture.md` (Partition Query Flow: the Server routes the query to the Store) |

The four partitions and three stores on screen are an example layout. The video does not claim a
partition count.

## Rebuild

```bash
# 1. narration (CPU is fine; about 25 s on an 8-core box)
python tts.py narration.json out/

# 2. timeline into the page, voice start times for the mix
python3 build.py narration.json out/timings.json index.html out/voice_starts.txt

# 3. soundtrack: voice, synthesized pad, ducking, -16 LUFS
./mix.sh out 59.83 mix.wav

# 4. frames and encode (Playwright Chromium, ffmpeg)
node render.cjs index.html hugegraph-pd.mp4 --audio mix.wav
```

Open `index.html?t=20` in a browser to see one frame, or `index.html?play` to watch it without
sound.
