import sys, subprocess
ours = []
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) == 3 and p[0] == 'SOUND':
        ours.append((int(p[1]), int(p[2]) / 8.0))   # ms
orig_txt = subprocess.run(["python3", sys.argv[2], sys.argv[3]], capture_output=True, text=True).stdout
orig = []
for line in orig_txt.split('\n'):
    p = line.split()
    if len(p) == 2 and p[0].isdigit():
        orig.append((int(p[0]), int(p[1])))
# descarta silencios e segmentos muito curtos
o = [(f, d) for f, d in ours if f > 0 and d >= 150]
r = [(f, d) for f, d in orig if f > 0 and d >= 150]
print('nossa :', [(f, int(d)) for f, d in o])
print('QBASIC:', r)
ok = len(o) == len(r)
for (a, da), (b, db) in zip(o, r):
    good = abs(a - b) <= max(5, 0.03 * a) and abs(da - db) <= max(120, 0.25 * da)
    ok = ok and good
print('CONFERE' if ok else 'DIVERGE')
