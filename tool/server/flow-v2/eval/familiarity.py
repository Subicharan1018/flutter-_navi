import os, sys, sqlite3, collections, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_world as w
eng = w.build()
D = w.DATA
# skip rate by prior plays of the same song (all live plays) and for Flow-served songs
s = sqlite3.connect(D + '/state.db')
served = collections.defaultdict(list)
for u, se, so, ts in s.execute('select user,session,song,ts from flow_seen'):
    served[u].append((so, ts))


def wilson(k, n):
    if not n: return (0, 0)
    p = k / n; z = 1.96
    c = (p + z*z/(2*n)) / (1 + z*z/n); h = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n)) / (1 + z*z/n)
    return round(c-h, 3), round(c+h, 3)

for u in ['admin', 'sandeep', 'vijay']:
    ev = sorted([e for e in eng.events if e.user == u and e.source == 'live'], key=lambda e: e.ts)
    cnt = collections.Counter(); b = collections.defaultdict(lambda: [0, 0])
    first_time = {}
    for e in ev:
        n = cnt[e.song]; k = 'never' if n == 0 else ('1-2' if n < 3 else '3+')
        b[k][0] += e.ratio < 0.3; b[k][1] += 1
        cnt[e.song] += 1
    print(u, 'live plays', len(ev), {k: (v[0], v[1], round(v[0]/v[1], 3), wilson(*v)) for k, v in b.items()})
# Flow-served songs: played? skipped? split by whether the user had played the song before the serve
for u in ['admin', 'sandeep', 'vijay']:
    db = sqlite3.connect(f'{D}/logs/{u}_listening_log.db')
    allev = [e for e in eng.events if e.user == u]
    first = {}
    for e in sorted(allev, key=lambda e: e.ts):
        first.setdefault(e.song, e.ts)
    stats = collections.defaultdict(lambda: [0, 0, 0])
    for so, ts in served[u]:
        fam = so in first and first[so] < ts - 60
        k = 'familiar' if fam else 'fresh'
        stats[k][0] += 1
        m = db.execute('select max(listen_ratio) from play_events where file_path=? and played_at between ? and ?', (so, ts - 5, ts + 6*3600)).fetchone()[0]
        if m is not None:
            stats[k][1] += 1; stats[k][2] += m < 0.3
    print('FLOW', u, {k: dict(served=v[0], played=v[1], skipped=v[2], skip=round(v[2]/v[1], 3) if v[1] else None) for k, v in stats.items()})
