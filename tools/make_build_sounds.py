# Makes the construction sound effects (no recordings needed):
#   assets/sounds/build_place.ogg  - a soft thud as the building lands, then
#                                    three wooden hammer knocks
#   assets/sounds/build_done.ogg   - two bright knocks and a little sparkle
# Run: python3 tools/make_build_sounds.py   (needs numpy, scipy, ffmpeg)
import numpy as np, subprocess, tempfile, os
from scipy.signal import butter, sosfilt
from scipy.io import wavfile

RATE = 44100
rng = np.random.default_rng(7)


def silence(seconds):
    return np.zeros(int(RATE * seconds))


def thud(length=0.35, start=95.0, end=48.0):
    """A soft, heavy landing: a falling low tone plus a puff of dust."""
    t = np.arange(int(RATE * length)) / RATE
    freq = end + (start - end) * np.exp(-t * 18)
    tone = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.exp(-t * 11)
    dust = sosfilt(butter(2, [120, 900], 'bandpass', fs=RATE, output='sos'), rng.standard_normal(len(t)))
    dust *= np.exp(-t * 22) * 0.35
    return tone + dust


def knock(pitch=1.0, length=0.16, bright=1.0):
    """A wooden hammer knock: a click plus resonant 'tok' tones."""
    t = np.arange(int(RATE * length)) / RATE
    click = sosfilt(butter(2, [1500, 6000 * bright], 'bandpass', fs=RATE, output='sos'), rng.standard_normal(len(t)))
    click *= np.exp(-t * 180) * 0.6
    tok = sum(a * np.sin(2 * np.pi * f * pitch * t) * np.exp(-t * d)
              for f, a, d in [(620, 1.0, 38), (1180, 0.5, 55), (2350, 0.25, 80)])
    return click + tok * 0.7


def sparkle(length=0.6):
    t = np.arange(int(RATE * length)) / RATE
    out = np.zeros(len(t))
    for i, f in enumerate([1320, 1760, 2640]):
        start = int(RATE * 0.06 * i)
        tt = t[: len(t) - start]
        out[start:] += np.sin(2 * np.pi * f * tt) * np.exp(-tt * 7) * 0.25
    return out


def mix(parts, length):
    out = silence(length)
    for at, sound in parts:
        i = int(RATE * at)
        out[i:i + len(sound)] += sound[: len(out) - i]
    return out


def save(samples, path):
    samples = samples / np.max(np.abs(samples)) * 0.85
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, 'x.wav')
        wavfile.write(wav, RATE, (samples * 32767).astype(np.int16))
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', wav, '-af', 'loudnorm=I=-18:TP=-2',
                        '-c:a', 'libvorbis', '-q:a', '5', path], check=True)
    print(path)


place = mix([(0.0, thud()), (0.30, knock(1.0)), (0.48, knock(1.08)), (0.66, knock(0.95, bright=1.2))], 0.9)
done = mix([(0.0, knock(1.25, bright=1.3)), (0.12, knock(1.4, bright=1.3)), (0.22, sparkle())], 0.9)
save(place, 'assets/sounds/build_place.ogg')
save(done, 'assets/sounds/build_done.ogg')
