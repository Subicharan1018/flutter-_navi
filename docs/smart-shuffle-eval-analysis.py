import json,sqlite3,statistics as st,collections
from datetime import datetime
D="/DATA/AppData/navivibe/listening_logs/"
cat=sqlite3.connect("file:/opt/shuffle-server/catalog.db?mode=ro",uri=True)
songs={r[0]:r[1:] for r in cat.execute("select id,artist,language,energy,valence,duration from songs")}
logs=[json.loads(l) for l in open(D+"ai_order_log.jsonl")]
ev={}
def events(u):
    if u not in ev:
        try:
            c=sqlite3.connect(f"file:{D}{u}_listening_log.db?mode=ro",uri=True)
            ev[u]=[(r[0],r[1],r[2],r[3]) for r in c.execute("select played_at,file_path,listen_ratio,end_reason from play_events order by played_at")]
        except Exception as e: ev[u]=[]
    return ev[u]
def outcome(e,order):
    ts=datetime.fromisoformat(e["ts"]).timestamp()
    ids=set(e["v3"]);seen={};
    for p,f,r,er in events(e["user"]):
        if ts<=p<=ts+10800 and f in ids and f not in seen: seen[f]=(r,er,p)
    return seen
def metrics(e,key,seen):
    order=e.get(key) if key!="served" else None
    if not order: return None
    n=len(order)
    arts=[(songs.get(i) or [None])[0] for i in order]
    adj=sum(1 for a,b in zip(arts,arts[1:]) if a and a==b)
    langs=[(songs.get(i) or [None,None])[1] for i in order]
    runs=sum(1 for a,b in zip(langs,langs[1:]) if a!=b)
    vals=[(songs.get(i) or [0]*5)[3] for i in order]
    vv=[v for v in vals if v is not None]
    ens=[(songs.get(i) or [0]*5)[2] for i in order]
    jumps=[abs(a-b) for a,b in zip(ens,ens[1:]) if a is not None and b is not None]
    vj=[abs(a-b) for a,b in zip(vals,vals[1:]) if a is not None and b is not None]
    return dict(adj=adj,langsw=runs/(n-1),ejump=st.mean(jumps) if jumps else None,vjump=st.mean(vj) if vj else None)
def agg(rows,k):
    x=[r[k] for r in rows if r.get(k) is not None]
    return round(st.mean(x),3) if x else None
# 1. structural metrics per order, per mode
print("== structural (all logged queues)")
for mode in ("shadow","on"):
    es=[e for e in logs if e["mode"]==mode]
    for key in ("v3","memory","ai"):
        rows=[m for e in es if (m:=metrics(e,key,None))]
        print(mode,key,len(rows),{k:agg(rows,k) for k in("adj","langsw","ejump","vjump")})
# 2. outcome: served-order only valid for 'on'. play outcome
print("== outcomes for queues served")
def pstats(es,servedkey):
    first=[];skip30=[];comp=[];nplay=0;q=0
    for e in es:
        order=e.get(servedkey) or e["memory"] if e["mode"]=="on" else e["v3"]
        seen=outcome(e,order)
        if not seen: continue
        q+=1
        pl=[i for i in order if i in seen]
        if pl: first.append(seen[pl[0]][0]>=0.3)
        for i in pl:
            r,er,_=seen[i];nplay+=1
            skip30.append(r<0.3); comp.append(r>=0.85)
    f=lambda x:round(sum(x)/len(x),3) if x else None
    return dict(queues_with_plays=q,plays=nplay,first_kept=f(first),skip_rate=f(skip30),completion=f(comp))
on=[e for e in logs if e["mode"]=="on"]
sh=[e for e in logs if e["mode"]=="shadow"]
print("on-served",pstats(on,"ai"))
print("shadow (v3 served)",pstats(sh,"v3"))
for u in ("admin","sandeep"):
    print(u,"shadow",pstats([e for e in sh if e["user"]==u],"v3"),"on",pstats([e for e in on if e["user"]==u],"ai"))
# 3. counterfactual shadow: skipped position by order
print("== skipped_pos by order (shadow, >=4 played & >=1 skip)")
for key in("v3","memory","ai"):
    pos=[];fk=[];n=0
    for e in sh:
        seen=outcome(e,e["v3"])
        o=e.get(key)
        if not o: continue
        pl=[i for i in o if i in seen]
        if len(pl)<4 or not any(seen[i][0]<0.3 for i in pl): continue
        sk=[k/(len(pl)-1) for k,i in enumerate(pl) if seen[i][0]<0.3]
        pos.append(st.mean(sk));fk.append(seen[pl[0]][0]>=0.3);n+=1
    print(key,n,round(st.mean(pos),3) if pos else None,round(sum(fk)/len(fk),3) if fk else None)
# 4. failures / latency
print("== latency / failures")
for mode in("shadow","on"):
    es=[e for e in logs if e["mode"]==mode]
    ok=[e["ms"] for e in es if e["ai"]]
    bad=[e for e in es if not e["ai"]]
    print(mode,"n",len(es),"ai ok",len(ok),"failed",len(bad),"fail ms",sorted(e["ms"] for e in bad))
    if ok: 
        ok.sort();print(" ok ms p50",ok[len(ok)//2],"p90",ok[int(len(ok)*.9)],"max",ok[-1])
print("models",collections.Counter(e["model"] for e in logs))
# how often ai differs
d=[sum(a!=b for a,b in zip(e["ai"],e["v3"]))/len(e["v3"]) for e in logs if e["ai"]]
print("share positions changed vs v3 mean",round(st.mean(d),2))
print("first song same as memory's:",round(st.mean([e["ai"][0]==e["memory"][0] for e in logs if e["ai"]]),2))
print("queue sizes",collections.Counter(len(e["v3"]) for e in logs))
print("on rows:")
for e in on:
    seen=outcome(e,e["ai"] or e["memory"]);o=e["ai"] or e["memory"]
    print(e["ts"],e["user"],"ai" if e["ai"] else "FALLBACK",e["ms"],"played",[(round(seen[i][0],2)) for i in o if i in seen])
# 5. production-wide skip rate by period for admin, play_events
print("== admin play_events weekly skip(<0.3)/completion(>=.85)")
c=sqlite3.connect(f"file:{D}admin_listening_log.db?mode=ro",uri=True)
for r in c.execute("select substr(ist_timestamp,1,10) d,count(*),round(avg(listen_ratio<0.3),3),round(avg(listen_ratio>=0.85),3),round(avg(end_reason='fwdbtn'),3) from play_events where ist_timestamp>='2026-10-15' group by d"): print(r)
