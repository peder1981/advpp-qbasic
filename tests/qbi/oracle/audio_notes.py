import sys, wave, numpy as np
import struct
data = open(sys.argv[1], 'rb').read()
nch = struct.unpack('<H', data[22:24])[0]
sr = struct.unpack('<I', data[24:28])[0]
sw = struct.unpack('<H', data[34:36])[0] // 8
raw = data[44:]
raw = raw[:len(raw) - len(raw) % (sw*nch)]
dt = {1: np.uint8, 2: np.int16, 4: np.int32}[sw]
x = np.frombuffer(raw, dtype=dt).astype(float)
if sw == 1: x -= 128
x = x.reshape(-1, nch).mean(axis=1)
x /= np.max(np.abs(x)) + 1e-9
print('rate', sr, 'channels', nch, 'width', sw, 'seconds', round(len(x)/sr, 3), file=sys.stderr)
win = int(sr * 0.04)
hop = int(sr * 0.01)
segs = []
for i in range(0, len(x) - win, hop):
    seg = x[i:i+win]
    rms = np.sqrt(np.mean(seg**2))
    if rms < 0.02:
        f = 0
    else:
        spec = np.abs(np.fft.rfft(seg * np.hanning(win)))
        freqs = np.fft.rfftfreq(win, 1/sr)
        spec[freqs < 60] = 0
        k = int(np.argmax(spec))
        if 0 < k < len(spec) - 1:
            a, b, c = np.log(spec[k-1]+1e-12), np.log(spec[k]+1e-12), np.log(spec[k+1]+1e-12)
            p = 0.5*(a-c)/(a-2*b+c) if (a-2*b+c) != 0 else 0
        else:
            p = 0
        f = (k + p) * sr / win
        f = int(round(f / 2.0) * 2)
    segs.append(f)
# agrupa janelas iguais em notas (duracao em ms)
out = []
for f in segs:
    if out and abs(out[-1][0] - f) <= 6:
        out[-1][1] += 1
    else:
        out.append([f, 1])
for f, k in out:
    if k >= 8:
        print(f, k * 10)
