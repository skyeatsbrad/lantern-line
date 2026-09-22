from __future__ import annotations

import hashlib
import json
import math
import struct
import wave
from pathlib import Path

try:
    import numpy as np
    import soundfile as sf
except ImportError as exc:
    raise SystemExit(
        "Install the audio generator dependencies with "
        "`python -m pip install -r tools/requirements-audio.txt`."
    ) from exc


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "generated" / "audio"
SFX_RATE = 44_100
MUSIC_RATE = 22_050
SEED = 0x1A17E2
BPM = 72.0
BEAT_SECONDS = 60.0 / BPM
BAR_SECONDS = BEAT_SECONDS * 4.0
LOOP_BARS = 16
LOOP_SECONDS = BAR_SECONDS * LOOP_BARS


NOTES = {
    "D1": 36.7081,
    "E1": 41.2034,
    "F1": 43.6535,
    "G1": 48.9994,
    "A1": 55.0,
    "BB1": 58.2705,
    "C2": 65.4064,
    "D2": 73.4162,
    "E2": 82.4069,
    "F2": 87.3071,
    "FS2": 92.4986,
    "G2": 97.9989,
    "A2": 110.0,
    "BB2": 116.541,
    "C3": 130.813,
    "D3": 146.832,
    "E3": 164.814,
    "F3": 174.614,
    "FS3": 184.997,
    "G3": 195.998,
    "A3": 220.0,
    "BB3": 233.082,
    "C4": 261.626,
    "D4": 293.665,
    "E4": 329.628,
    "F4": 349.228,
    "FS4": 369.994,
    "G4": 391.995,
    "A4": 440.0,
    "BB4": 466.164,
    "C5": 523.251,
    "D5": 587.33,
}


def stable_seed(label: str) -> int:
    digest = hashlib.sha256(label.encode("utf-8")).digest()
    return SEED ^ int.from_bytes(digest[:8], "little")


def frame_count(duration: float, sample_rate: int) -> int:
    return max(1, int(round(duration * sample_rate)))


def envelope(
    frames: int,
    sample_rate: int,
    attack: float,
    release: float,
    curve: float = 1.0,
) -> np.ndarray:
    attack_frames = min(frames, max(1, int(attack * sample_rate)))
    release_frames = min(frames, max(1, int(release * sample_rate)))
    env = np.ones(frames, dtype=np.float64)
    env[:attack_frames] = np.linspace(0.0, 1.0, attack_frames, endpoint=False)
    env[-release_frames:] *= np.linspace(1.0, 0.0, release_frames, endpoint=True)
    if curve != 1.0:
        env = np.power(np.clip(env, 0.0, 1.0), curve)
    return env


def equal_power_pan(signal: np.ndarray, pan: float) -> np.ndarray:
    clamped = max(-1.0, min(1.0, pan))
    angle = (clamped + 1.0) * math.pi * 0.25
    return np.column_stack((signal * math.cos(angle), signal * math.sin(angle)))


def add_signal(
    mix: np.ndarray,
    signal: np.ndarray,
    start_seconds: float,
    pan: float = 0.0,
) -> None:
    start = int(round(start_seconds * MUSIC_RATE))
    if start >= len(mix):
        return
    stereo = signal if signal.ndim == 2 else equal_power_pan(signal, pan)
    end = min(len(mix), start + len(stereo))
    if end <= start:
        return
    mix[start:end] += stereo[: end - start]


def oscillator(
    frequency: float,
    duration: float,
    sample_rate: int,
    phase: float = 0.0,
) -> np.ndarray:
    frames = frame_count(duration, sample_rate)
    time = np.arange(frames, dtype=np.float64) / sample_rate
    return np.sin(math.tau * frequency * time + phase)


def sweep(
    start_hz: float,
    end_hz: float,
    duration: float,
    sample_rate: int,
) -> np.ndarray:
    frames = frame_count(duration, sample_rate)
    frequencies = np.linspace(start_hz, end_hz, frames, dtype=np.float64)
    phase = np.cumsum(frequencies) * (math.tau / sample_rate)
    return np.sin(phase)


def periodic_sine(
    frequency: float,
    frames: int,
    sample_rate: int,
    phase: float = 0.0,
) -> np.ndarray:
    duration = frames / sample_rate
    loop_frequency = round(frequency * duration) / duration
    time = np.arange(frames, dtype=np.float64) / sample_rate
    return np.sin(math.tau * loop_frequency * time + phase)


def periodic_noise(
    frames: int,
    sample_rate: int,
    label: str,
    cutoff_hz: float,
    slope: float = 2.0,
) -> np.ndarray:
    rng = np.random.default_rng(stable_seed(label))
    frequencies = np.fft.rfftfreq(frames, 1.0 / sample_rate)
    amplitudes = 1.0 / (1.0 + np.power(frequencies / max(1.0, cutoff_hz), slope))
    amplitudes[0] = 0.0
    phases = rng.uniform(0.0, math.tau, len(frequencies))
    spectrum = amplitudes * (np.cos(phases) + 1j * np.sin(phases))
    signal = np.fft.irfft(spectrum, n=frames)
    peak = float(np.max(np.abs(signal)))
    return signal / max(1e-9, peak)


def short_noise(duration: float, sample_rate: int, label: str, smooth: int = 1) -> np.ndarray:
    rng = np.random.default_rng(stable_seed(label))
    signal = rng.uniform(-1.0, 1.0, frame_count(duration, sample_rate))
    if smooth > 1:
        kernel = np.ones(smooth, dtype=np.float64) / smooth
        signal = np.convolve(signal, kernel, mode="same")
    peak = float(np.max(np.abs(signal)))
    return signal / max(1e-9, peak)


def tone(
    frequency: float,
    duration: float,
    sample_rate: int,
    attack: float = 0.01,
    release: float = 0.08,
    harmonics: tuple[float, ...] = (1.0, 0.24, 0.08),
) -> np.ndarray:
    frames = frame_count(duration, sample_rate)
    time = np.arange(frames, dtype=np.float64) / sample_rate
    signal = np.zeros(frames, dtype=np.float64)
    for index, gain in enumerate(harmonics, start=1):
        signal += np.sin(math.tau * frequency * index * time) * gain
    signal /= max(1.0, sum(abs(gain) for gain in harmonics))
    return signal * envelope(frames, sample_rate, attack, release, 1.25)


def bowed_tone(
    frequency: float,
    duration: float,
    sample_rate: int,
    label: str,
) -> np.ndarray:
    frames = frame_count(duration, sample_rate)
    time = np.arange(frames, dtype=np.float64) / sample_rate
    rng = np.random.default_rng(stable_seed(label))
    wobble = np.sin(math.tau * 0.43 * time + rng.uniform(0.0, math.tau)) * 0.007
    phase = np.cumsum(frequency * (1.0 + wobble)) * (math.tau / sample_rate)
    rasp = short_noise(duration, sample_rate, f"{label}-rasp", 10)
    signal = np.sin(phase) * 0.72 + np.sin(phase * 2.01) * 0.18 + rasp * 0.1
    return signal * envelope(frames, sample_rate, 0.42, 0.7, 1.2)


def rail_hit(variant: int, gain: float = 1.0) -> np.ndarray:
    duration = 0.085 + variant * 0.007
    frames = frame_count(duration, MUSIC_RATE)
    noise = short_noise(duration, MUSIC_RATE, f"rail-{variant}", 3)
    ring = tone(820.0 + variant * 73.0, duration, MUSIC_RATE, 0.001, 0.07)
    env = envelope(frames, MUSIC_RATE, 0.001, duration * 0.88, 2.4)
    return (noise * 0.42 + ring * 0.58) * env * gain


def low_pulse(frequency: float, duration: float, gain: float) -> np.ndarray:
    frames = frame_count(duration, MUSIC_RATE)
    body = (
        sweep(frequency * 1.08, frequency * 0.82, duration, MUSIC_RATE) * 0.72
        + oscillator(frequency * 2.0, duration, MUSIC_RATE) * 0.18
    )
    return body * envelope(frames, MUSIC_RATE, 0.004, duration * 0.78, 1.8) * gain


def add_note(
    mix: np.ndarray,
    frequency: float,
    start: float,
    duration: float,
    gain: float,
    pan: float,
    label: str,
    bowed: bool = False,
) -> None:
    signal = (
        bowed_tone(frequency, duration, MUSIC_RATE, label)
        if bowed
        else tone(
            frequency,
            duration,
            MUSIC_RATE,
            min(0.08, duration * 0.18),
            min(0.32, duration * 0.45),
        )
    )
    add_signal(mix, signal * gain, start, pan)


def add_pad(
    mix: np.ndarray,
    frequencies: tuple[float, ...],
    start: float,
    duration: float,
    gain: float,
    width: float,
    label: str,
) -> None:
    pans = np.linspace(-width, width, len(frequencies))
    for index, frequency in enumerate(frequencies):
        frames = frame_count(duration, MUSIC_RATE)
        time = np.arange(frames, dtype=np.float64) / MUSIC_RATE
        phase = math.tau * frequency * time
        breath = 0.84 + 0.16 * np.sin(
            math.tau * (0.07 + index * 0.013) * time
            + stable_seed(f"{label}-{index}") % 31
        )
        voice = (
            np.sin(phase) * 0.68
            + np.sin(phase * 2.0 + 0.23) * 0.21
            + np.sin(phase * 3.01 + 1.1) * 0.11
        )
        voice *= envelope(frames, MUSIC_RATE, 0.75, 0.9, 1.35) * breath * gain
        add_signal(mix, voice, start, float(pans[index]))


def add_lantern_motif(
    mix: np.ndarray,
    bar: int,
    major: bool,
    gain: float,
    pan: float = 0.2,
) -> None:
    third = NOTES["FS4"] if major else NOTES["F4"]
    notes = (NOTES["D4"], NOTES["A4"], third)
    offsets = (0.0, BEAT_SECONDS * 0.75, BEAT_SECONDS * 1.5)
    lengths = (BEAT_SECONDS * 0.58, BEAT_SECONDS * 0.58, BEAT_SECONDS * 1.1)
    for index, frequency in enumerate(notes):
        add_note(
            mix,
            frequency,
            bar * BAR_SECONDS + offsets[index],
            lengths[index],
            gain,
            pan if index != 1 else -pan,
            f"motif-{bar}-{index}-{major}",
        )


def add_rail_pattern(
    mix: np.ndarray,
    every_beats: float,
    gain: float,
    skip_station_space: bool = False,
) -> None:
    beat = 0.0
    index = 0
    total_beats = LOOP_BARS * 4
    while beat < total_beats:
        bar = int(beat // 4)
        if not skip_station_space or bar not in (3, 7, 11, 15):
            hit = rail_hit(index % 3, gain)
            pan = -0.46 if index % 2 == 0 else 0.46
            add_signal(mix, hit, beat * BEAT_SECONDS, pan)
        index += 1
        beat += every_beats


def add_periodic_bed(
    mix: np.ndarray,
    label: str,
    frequencies: tuple[float, ...],
    gain: float,
    width: float,
) -> None:
    frames = len(mix)
    pans = np.linspace(-width, width, len(frequencies))
    lfo = 0.78 + 0.22 * periodic_sine(
        2.0 / LOOP_SECONDS,
        frames,
        MUSIC_RATE,
        stable_seed(label) % 13,
    )
    for index, frequency in enumerate(frequencies):
        voice = periodic_sine(
            frequency,
            frames,
            MUSIC_RATE,
            (stable_seed(f"{label}-{index}") % 628) / 100.0,
        )
        harmonic = periodic_sine(
            frequency * 2.0,
            frames,
            MUSIC_RATE,
            (stable_seed(f"{label}-h-{index}") % 628) / 100.0,
        )
        add_signal(
            mix,
            (voice * 0.78 + harmonic * 0.22) * lfo * gain,
            0.0,
            float(pans[index]),
        )


def master_audio(mix: np.ndarray, target_peak: float = 0.82) -> np.ndarray:
    mix = mix - np.mean(mix, axis=0, keepdims=True)
    mix = np.tanh(mix * 1.12)
    peak = float(np.max(np.abs(mix)))
    if peak > 0.0:
        mix = mix * (target_peak / peak)
    edge_frames = min(len(mix) // 2, int(MUSIC_RATE * 0.02))
    if edge_frames > 0:
        edge = np.sin(np.linspace(0.0, math.pi * 0.5, edge_frames)) ** 2
        mix[:edge_frames] *= edge[:, None]
        mix[-edge_frames:] *= edge[::-1, None]
    return mix.astype(np.float32)


def build_music(track: str) -> np.ndarray:
    mix = np.zeros((frame_count(LOOP_SECONDS, MUSIC_RATE), 2), dtype=np.float64)
    minor_progression = (
        (NOTES["D2"], NOTES["F2"], NOTES["A2"]),
        (NOTES["BB1"], NOTES["D2"], NOTES["F2"]),
        (NOTES["F2"], NOTES["A2"], NOTES["C3"]),
        (NOTES["C2"], NOTES["E2"], NOTES["G2"]),
    )
    major_progression = (
        (NOTES["D2"], NOTES["FS2"], NOTES["A2"]),
        (NOTES["G1"], NOTES["D2"], NOTES["G2"]),
        (NOTES["BB1"], NOTES["D2"], NOTES["FS2"]),
        (NOTES["A1"], NOTES["E2"], NOTES["A2"]),
    )

    if track == "title":
        add_periodic_bed(mix, track, (NOTES["D1"], NOTES["A1"]), 0.075, 0.34)
        wind = periodic_noise(len(mix), MUSIC_RATE, "title-wind", 520.0)
        add_signal(mix, wind * 0.026, 0.0, -0.58)
        add_signal(mix, np.roll(wind, len(wind) // 7) * 0.02, 0.0, 0.64)
        for bar in (1, 9):
            add_lantern_motif(mix, bar, False, 0.17, 0.3)
        for bar, note_name in ((5, "A2"), (13, "D3")):
            add_note(
                mix,
                NOTES[note_name],
                bar * BAR_SECONDS,
                BAR_SECONDS * 2.6,
                0.09,
                -0.5 if bar == 5 else 0.5,
                f"title-horn-{bar}",
                True,
            )

    elif track == "travel_calm":
        add_periodic_bed(mix, track, (NOTES["D1"], NOTES["A1"]), 0.052, 0.18)
        add_rail_pattern(mix, 1.0, 0.12)
        for bar in range(LOOP_BARS):
            add_pad(
                mix,
                minor_progression[(bar // 2) % len(minor_progression)],
                bar * BAR_SECONDS,
                BAR_SECONDS * 1.08,
                0.036,
                0.48,
                f"calm-pad-{bar}",
            )
        for bar in (2, 6, 10, 14):
            add_lantern_motif(mix, bar, False, 0.11, 0.22)
        for beat in range(0, LOOP_BARS * 4, 4):
            add_signal(
                mix,
                low_pulse(NOTES["D1"], 0.32, 0.08),
                beat * BEAT_SECONDS,
                -0.08,
            )

    elif track == "travel_tension":
        add_periodic_bed(
            mix,
            track,
            (NOTES["D1"], NOTES["F1"], NOTES["A1"]),
            0.065,
            0.28,
        )
        add_rail_pattern(mix, 0.5, 0.14)
        shadow_noise = periodic_noise(
            len(mix),
            MUSIC_RATE,
            "tension-shadow",
            760.0,
            1.5,
        )
        tremolo = 0.35 + 0.65 * np.maximum(
            0.0,
            periodic_sine(8.0 / LOOP_SECONDS, len(mix), MUSIC_RATE),
        )
        add_signal(mix, shadow_noise * tremolo * 0.035, 0.0, 0.0)
        for bar in range(LOOP_BARS):
            add_pad(
                mix,
                minor_progression[(bar // 2) % len(minor_progression)],
                bar * BAR_SECONDS,
                BAR_SECONDS * 1.02,
                0.038,
                0.36,
                f"tension-pad-{bar}",
            )
            for beat in (0.0, 1.5, 2.0, 3.5):
                note = NOTES["D2"] if beat < 2.0 else NOTES["F2"]
                add_note(
                    mix,
                    note,
                    bar * BAR_SECONDS + beat * BEAT_SECONDS,
                    BEAT_SECONDS * 0.42,
                    0.08,
                    -0.18 if int(beat * 2) % 2 == 0 else 0.18,
                    f"tension-pulse-{bar}-{beat}",
                    True,
                )
        for bar in (3, 7, 11, 15):
            add_lantern_motif(mix, bar, False, 0.14, 0.34)

    elif track == "station":
        add_periodic_bed(mix, track, (NOTES["D2"], NOTES["A2"]), 0.038, 0.7)
        steam = periodic_noise(len(mix), MUSIC_RATE, "station-steam", 980.0)
        add_signal(mix, steam * 0.022, 0.0, -0.82)
        add_signal(mix, np.roll(steam, len(steam) // 5) * 0.022, 0.0, 0.82)
        for bar in range(0, LOOP_BARS, 2):
            add_pad(
                mix,
                minor_progression[(bar // 2) % len(minor_progression)],
                bar * BAR_SECONDS,
                BAR_SECONDS * 2.05,
                0.044,
                0.82,
                f"station-pad-{bar}",
            )
        for bar in (1, 5, 9, 13):
            add_lantern_motif(mix, bar, False, 0.12, 0.72)
        for bar in (4, 12):
            add_note(
                mix,
                NOTES["D5"],
                bar * BAR_SECONDS + BEAT_SECONDS,
                BAR_SECONDS * 1.3,
                0.05,
                0.82 if bar == 4 else -0.82,
                f"station-bell-{bar}",
                True,
            )

    elif track == "longshadow":
        add_periodic_bed(
            mix,
            track,
            (NOTES["D1"], NOTES["E1"], NOTES["BB1"]),
            0.085,
            0.22,
        )
        pressure = periodic_noise(
            len(mix),
            MUSIC_RATE,
            "longshadow-pressure",
            340.0,
            2.6,
        )
        pressure_lfo = 0.28 + 0.72 * np.maximum(
            0.0,
            periodic_sine(16.0 / LOOP_SECONDS, len(mix), MUSIC_RATE),
        )
        add_signal(mix, pressure * pressure_lfo * 0.055, 0.0, 0.0)
        for bar in range(LOOP_BARS):
            add_signal(
                mix,
                low_pulse(
                    NOTES["D1"] if bar % 4 != 3 else NOTES["E1"],
                    0.68,
                    0.15,
                ),
                bar * BAR_SECONDS,
                -0.12 if bar % 2 == 0 else 0.12,
            )
            reversed_metal = bowed_tone(
                NOTES["D3"] if bar % 2 == 0 else NOTES["BB2"],
                BAR_SECONDS * 0.92,
                MUSIC_RATE,
                f"shadow-metal-{bar}",
            )[::-1]
            add_signal(
                mix,
                reversed_metal * 0.075,
                bar * BAR_SECONDS + BAR_SECONDS * 0.05,
                -0.62 if bar % 2 == 0 else 0.62,
            )
        for bar in (2, 6, 10, 14):
            add_lantern_motif(mix, bar, False, 0.085, 0.18)

    elif track == "dawn":
        add_periodic_bed(
            mix,
            track,
            (NOTES["D1"], NOTES["A1"], NOTES["D2"]),
            0.048,
            0.46,
        )
        add_rail_pattern(mix, 2.0, 0.055, True)
        warm_air = periodic_noise(len(mix), MUSIC_RATE, "dawn-air", 1600.0)
        add_signal(mix, warm_air * 0.014, 0.0, -0.72)
        add_signal(mix, np.roll(warm_air, len(warm_air) // 6) * 0.014, 0.0, 0.72)
        for bar in range(LOOP_BARS):
            add_pad(
                mix,
                major_progression[(bar // 2) % len(major_progression)],
                bar * BAR_SECONDS,
                BAR_SECONDS * 1.08,
                0.044,
                0.64,
                f"dawn-pad-{bar}",
            )
        for bar in (0, 4, 8, 12):
            add_lantern_motif(mix, bar, True, 0.14, 0.46)
        for bar in (3, 11):
            add_note(
                mix,
                NOTES["A3"],
                bar * BAR_SECONDS,
                BAR_SECONDS * 2.4,
                0.065,
                -0.48 if bar == 3 else 0.48,
                f"dawn-horn-{bar}",
                True,
            )
    else:
        raise ValueError(f"Unknown music track: {track}")

    return master_audio(mix, 0.8)


def make_click(variant: int) -> np.ndarray:
    duration = 0.05 + variant * 0.004
    signal = sweep(980.0 + variant * 55.0, 1320.0 + variant * 80.0, duration, SFX_RATE)
    return signal * envelope(len(signal), SFX_RATE, 0.001, duration * 0.92, 2.0) * 0.28


def make_confirm(variant: int) -> np.ndarray:
    duration = 0.19 + variant * 0.012
    frequencies = (
        NOTES["A3"] * (1.0 + variant * 0.008),
        NOTES["D4"],
        NOTES["FS4"] if variant == 2 else NOTES["F4"],
    )
    signal = sum(
        tone(frequency, duration, SFX_RATE, 0.006, 0.15) for frequency in frequencies
    ) / len(frequencies)
    return signal * 0.34


def make_reject(variant: int) -> np.ndarray:
    duration = 0.23 + variant * 0.018
    signal = sweep(285.0 + variant * 12.0, 128.0 - variant * 5.0, duration, SFX_RATE)
    grit = short_noise(duration, SFX_RATE, f"reject-{variant}", 6)
    pulse = 0.45 + 0.55 * np.maximum(
        0.0,
        oscillator(5.0 + variant * 0.4, duration, SFX_RATE),
    )
    return (
        (signal * 0.52 + grit * 0.18)
        * pulse
        * envelope(len(signal), SFX_RATE, 0.002, duration * 0.82, 1.8)
    )


def make_alarm(variant: int) -> np.ndarray:
    duration = 0.46 + variant * 0.035
    frames = frame_count(duration, SFX_RATE)
    time = np.arange(frames, dtype=np.float64) / SFX_RATE
    segment = np.floor(time * (8.0 + variant * 0.4)).astype(np.int32)
    frequency = np.where(segment % 2 == 0, 392.0, 523.251 + variant * 9.0)
    phase = np.cumsum(frequency) * (math.tau / SFX_RATE)
    pulse = np.where(np.mod(time * 16.0, 1.0) < 0.72, 1.0, 0.25)
    return (
        (np.sin(phase) * 0.4 + np.sin(phase * 0.5) * 0.18)
        * pulse
        * envelope(frames, SFX_RATE, 0.012, 0.09)
    )


def make_departure() -> np.ndarray:
    duration = 0.95
    frames = frame_count(duration, SFX_RATE)
    time = np.arange(frames, dtype=np.float64) / SFX_RATE
    frequency = 466.164 + np.sin(np.linspace(0.0, math.pi, frames)) * 18.0
    phase = np.cumsum(frequency) * (math.tau / SFX_RATE)
    tremolo = 0.88 + np.sin(math.tau * 4.4 * time) * 0.12
    signal = np.sin(phase) + np.sin(phase * 2.0) * 0.24
    return signal * tremolo * envelope(frames, SFX_RATE, 0.08, 0.3) * 0.24


def make_mechanical_tick(variant: int) -> np.ndarray:
    duration = 0.08 + variant * 0.009
    ring = sweep(180.0 + variant * 35.0, 790.0 + variant * 70.0, duration, SFX_RATE)
    noise = short_noise(duration, SFX_RATE, f"tick-{variant}", 2)
    return (
        (ring * 0.46 + noise * 0.14)
        * envelope(len(ring), SFX_RATE, 0.001, duration * 0.9, 2.8)
    )


def make_impact(variant: int) -> np.ndarray:
    duration = 0.24 + variant * 0.025
    body = sweep(118.0 + variant * 8.0, 48.0 + variant * 4.0, duration, SFX_RATE)
    crack = short_noise(duration, SFX_RATE, f"impact-{variant}", 2 + variant)
    ring = oscillator(410.0 + variant * 73.0, duration, SFX_RATE)
    env = envelope(len(body), SFX_RATE, 0.001, duration * 0.9, 2.5)
    return (body * 0.48 + crack * 0.4 + ring * 0.12) * env * 0.8


def make_salvo(variant: int) -> np.ndarray:
    duration = 0.31 + variant * 0.022
    crack = short_noise(duration, SFX_RATE, f"salvo-{variant}", 2)
    body = sweep(104.0 + variant * 9.0, 42.0, duration, SFX_RATE)
    metal = sweep(1260.0 + variant * 95.0, 510.0, duration, SFX_RATE)
    env = envelope(len(body), SFX_RATE, 0.001, duration * 0.94, 3.1)
    return (crack * 0.52 + body * 0.38 + metal * 0.1) * env * 0.92


def make_repair(variant: int) -> np.ndarray:
    duration = 0.34 + variant * 0.025
    signal = np.zeros(frame_count(duration, SFX_RATE), dtype=np.float64)
    for index, frequency in enumerate((392.0, 523.251, 783.991)):
        start = int((0.035 + index * 0.07) * SFX_RATE)
        note = tone(
            frequency * (1.0 + variant * 0.006),
            duration - start / SFX_RATE,
            SFX_RATE,
            0.002,
            0.14,
        )
        signal[start : start + len(note)] += note * (0.25 - index * 0.035)
    tick = make_mechanical_tick(variant)
    signal[: len(tick)] += tick * 0.55
    return signal


def make_overcharge(variant: int) -> np.ndarray:
    duration = 0.43 + variant * 0.03
    rise = sweep(148.0 + variant * 12.0, 980.0 + variant * 90.0, duration, SFX_RATE)
    buzz = oscillator(60.0 + variant * 5.0, duration, SFX_RATE)
    pulse = 0.45 + 0.55 * np.square(
        np.maximum(0.0, oscillator(6.0 + variant * 0.35, duration, SFX_RATE))
    )
    return (
        (rise * 0.47 + buzz * 0.2)
        * pulse
        * envelope(len(rise), SFX_RATE, 0.012, 0.18)
    )


def make_flare(variant: int) -> np.ndarray:
    duration = 0.52 + variant * 0.03
    wind = short_noise(duration, SFX_RATE, f"flare-{variant}", 10)
    rise = sweep(360.0 + variant * 20.0, 1320.0 + variant * 100.0, duration, SFX_RATE)
    bell = tone(880.0 + variant * 55.0, duration, SFX_RATE, 0.01, 0.28)
    return (
        (wind * 0.22 + rise * 0.24 + bell * 0.28)
        * envelope(len(rise), SFX_RATE, 0.01, 0.24)
    )


def make_detach(variant: int) -> np.ndarray:
    duration = 0.58 + variant * 0.035
    snap = short_noise(duration, SFX_RATE, f"detach-{variant}", 2)
    drop = sweep(210.0 + variant * 10.0, 48.0, duration, SFX_RATE)
    ring = tone(540.0 + variant * 37.0, duration, SFX_RATE, 0.001, 0.45)
    env = envelope(len(drop), SFX_RATE, 0.001, duration * 0.9, 2.2)
    return (snap * 0.34 + drop * 0.5 + ring * 0.16) * env * 0.86


def make_defense_fire(variant: int) -> np.ndarray:
    duration = 0.14 + variant * 0.012
    crack = short_noise(duration, SFX_RATE, f"defense-{variant}", 2)
    snap = sweep(720.0 + variant * 90.0, 160.0, duration, SFX_RATE)
    env = envelope(len(snap), SFX_RATE, 0.001, duration * 0.93, 3.0)
    return (crack * 0.48 + snap * 0.4) * env * 0.7


def make_focus(variant: int) -> np.ndarray:
    duration = 0.38 + variant * 0.022
    rise = sweep(520.0 + variant * 24.0, 1120.0 + variant * 70.0, duration, SFX_RATE)
    harmonic = sweep(1040.0, 2240.0 + variant * 90.0, duration, SFX_RATE)
    return (
        (rise * 0.38 + harmonic * 0.13)
        * envelope(len(rise), SFX_RATE, 0.015, 0.18)
    )


def make_ward_break(variant: int) -> np.ndarray:
    duration = 0.44 + variant * 0.025
    glass = short_noise(duration, SFX_RATE, f"ward-{variant}", 1)
    fall = sweep(1280.0 + variant * 85.0, 180.0, duration, SFX_RATE)
    shadow = sweep(92.0, 42.0 + variant * 3.0, duration, SFX_RATE)
    env = envelope(len(fall), SFX_RATE, 0.001, duration * 0.94, 2.1)
    return (glass * 0.28 + fall * 0.3 + shadow * 0.28) * env


def make_ward_warning(variant: int) -> np.ndarray:
    duration = 0.62 + variant * 0.035
    reverse = bowed_tone(
        NOTES["BB2"] * (1.0 + variant * 0.012),
        duration,
        SFX_RATE,
        f"ward-warning-{variant}",
    )[::-1]
    pulse_gate = np.maximum(
        0.0,
        oscillator(4.5 + variant * 0.3, duration, SFX_RATE),
    )
    pulse = oscillator(
        680.0 + variant * 45.0,
        duration,
        SFX_RATE,
    ) * pulse_gate
    low = sweep(96.0 + variant * 4.0, 58.0, duration, SFX_RATE)
    env = envelope(len(low), SFX_RATE, 0.015, 0.22, 1.3)
    return (reverse * 0.24 + pulse * 0.13 + low * 0.3) * env


def make_threat(kind: str, variant: int) -> np.ndarray:
    duration = 0.5 + variant * 0.035
    frames = frame_count(duration, SFX_RATE)
    env = envelope(frames, SFX_RATE, 0.01, 0.24, 1.4)
    if kind == "pursuer":
        scrape = short_noise(duration, SFX_RATE, f"{kind}-{variant}", 4)
        growl = sweep(115.0 + variant * 5.0, 72.0, duration, SFX_RATE)
        return (scrape * 0.25 + growl * 0.42) * env
    if kind == "boarder":
        hook = sweep(920.0 + variant * 80.0, 330.0, duration, SFX_RATE)
        knock = np.maximum(0.0, oscillator(7.0 + variant, duration, SFX_RATE))
        metal = short_noise(duration, SFX_RATE, f"{kind}-{variant}", 2)
        return (hook * 0.3 + metal * knock * 0.28) * env
    suction = sweep(380.0 + variant * 20.0, 92.0, duration, SFX_RATE)
    air = short_noise(duration, SFX_RATE, f"{kind}-{variant}", 18)
    wobble = oscillator(4.0 + variant * 0.35, duration, SFX_RATE)
    return (suction * 0.34 + air * (0.18 + wobble * 0.08)) * env


def make_boss_cue(kind: str, variant: int) -> np.ndarray:
    duration = (0.9 if kind != "impact" else 0.72) + variant * 0.035
    frames = frame_count(duration, SFX_RATE)
    env = envelope(frames, SFX_RATE, 0.012, 0.32, 1.35)
    if kind == "veil":
        source = bowed_tone(
            NOTES["D3"] * (1.0 + variant * 0.01),
            duration,
            SFX_RATE,
            f"boss-veil-{variant}",
        )[::-1]
        low = sweep(92.0 + variant * 4.0, 54.0, duration, SFX_RATE)
        return (source * 0.32 + low * 0.3) * env
    if kind == "tether":
        chain = short_noise(duration, SFX_RATE, f"boss-tether-{variant}", 3)
        ring = sweep(720.0 + variant * 55.0, 188.0, duration, SFX_RATE)
        pulses = np.maximum(
            0.0,
            oscillator(6.0 + variant * 0.35, duration, SFX_RATE),
        )
        return (chain * pulses * 0.24 + ring * 0.34) * env
    if kind == "charge":
        rise = sweep(72.0 + variant * 4.0, 640.0 + variant * 65.0, duration, SFX_RATE)
        pulse = 0.4 + 0.6 * np.maximum(
            0.0,
            oscillator(5.0 + variant * 0.28, duration, SFX_RATE),
        )
        return rise * pulse * env * 0.52
    low = sweep(82.0 + variant * 5.0, 34.0, duration, SFX_RATE)
    blast = short_noise(duration, SFX_RATE, f"boss-impact-{variant}", 4)
    return (low * 0.56 + blast * 0.34) * env * 0.92


def make_route_commit(variant: int) -> np.ndarray:
    duration = 0.3 + variant * 0.018
    signal = sweep(320.0 + variant * 18.0, 670.0 + variant * 35.0, duration, SFX_RATE)
    tick = make_mechanical_tick(variant)
    signal[: len(tick)] += tick * 0.65
    return signal * envelope(len(signal), SFX_RATE, 0.004, 0.15) * 0.38


def make_station_enter(variant: int) -> np.ndarray:
    duration = 0.72 + variant * 0.035
    signal = np.zeros(frame_count(duration, SFX_RATE), dtype=np.float64)
    for index, frequency in enumerate((NOTES["D4"], NOTES["A4"])):
        start = int(index * 0.16 * SFX_RATE)
        bell = tone(
            frequency * (1.0 + variant * 0.004),
            duration - start / SFX_RATE,
            SFX_RATE,
            0.002,
            0.38,
            (1.0, 0.42, 0.18),
        )
        signal[start : start + len(bell)] += bell * 0.28
    return signal


def make_stinger(victory: bool) -> np.ndarray:
    duration = 3.4 if victory else 3.1
    mix = np.zeros((frame_count(duration, MUSIC_RATE), 2), dtype=np.float64)
    if victory:
        chord_notes = (NOTES["D3"], NOTES["FS3"], NOTES["A3"], NOTES["D4"])
        for index, frequency in enumerate(chord_notes):
            add_note(
                mix,
                frequency,
                index * 0.16,
                duration - index * 0.16,
                0.16,
                -0.55 + index * 0.36,
                f"victory-{index}",
                index < 2,
            )
        for index, frequency in enumerate((NOTES["D4"], NOTES["FS4"], NOTES["A4"], NOTES["D5"])):
            add_note(
                mix,
                frequency,
                0.32 + index * 0.38,
                0.72,
                0.18,
                -0.34 + index * 0.22,
                f"victory-motif-{index}",
            )
    else:
        chord_notes = (NOTES["D3"], NOTES["F3"], NOTES["A3"])
        for index, frequency in enumerate(chord_notes):
            add_note(
                mix,
                frequency,
                index * 0.12,
                duration - index * 0.12,
                0.15,
                -0.42 + index * 0.42,
                f"defeat-{index}",
                True,
            )
        for index, frequency in enumerate((NOTES["A3"], NOTES["F3"], NOTES["D3"], NOTES["D2"])):
            add_note(
                mix,
                frequency,
                0.34 + index * 0.46,
                0.82,
                0.14,
                0.34 - index * 0.22,
                f"defeat-motif-{index}",
            )
    return master_audio(mix, 0.82)


def write_wav(path: Path, samples: np.ndarray, sample_rate: int = SFX_RATE) -> None:
    mono = np.asarray(samples, dtype=np.float64)
    peak = float(np.max(np.abs(mono)))
    if peak > 0.98:
        mono *= 0.98 / peak
    pcm = np.clip(mono, -1.0, 1.0)
    pcm = np.round(pcm * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(pcm.tobytes())


def write_ogg(path: Path, samples: np.ndarray) -> None:
    audio = np.ascontiguousarray(samples, dtype=np.float32)
    with sf.SoundFile(
        str(path),
        mode="w",
        samplerate=MUSIC_RATE,
        channels=audio.shape[1],
        format="OGG",
        subtype="VORBIS",
        compression_level=0.56,
    ) as output:
        for start in range(0, len(audio), 65_536):
            output.write(audio[start : start + 65_536])
    normalize_ogg_container(path)


def normalize_ogg_container(path: Path) -> None:
    data = bytearray(path.read_bytes())
    serial = stable_seed(path.name) & 0xFFFFFFFF
    offset = 0
    while offset < len(data):
        if data[offset : offset + 4] != b"OggS":
            raise ValueError(f"Invalid Ogg page at byte {offset}: {path.name}")
        segment_count = data[offset + 26]
        table_start = offset + 27
        table_end = table_start + segment_count
        page_end = table_end + sum(data[table_start:table_end])
        if page_end > len(data):
            raise ValueError(f"Truncated Ogg page at byte {offset}: {path.name}")
        data[offset + 14 : offset + 18] = struct.pack("<I", serial)
        data[offset + 22 : offset + 26] = b"\0\0\0\0"
        checksum = ogg_crc(data[offset:page_end])
        data[offset + 22 : offset + 26] = struct.pack("<I", checksum)
        offset = page_end
    path.write_bytes(data)


def ogg_crc(page: bytes | bytearray) -> int:
    checksum = 0
    for value in page:
        checksum ^= value << 24
        for _ in range(8):
            checksum = (
                ((checksum << 1) ^ 0x04C11DB7)
                if checksum & 0x80000000
                else checksum << 1
            ) & 0xFFFFFFFF
    return checksum


def audio_stats(path: Path) -> dict:
    audio, sample_rate = sf.read(path, dtype="float64", always_2d=True)
    peak = float(np.max(np.abs(audio)))
    rms = float(np.sqrt(np.mean(np.square(audio))))
    return {
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "duration_seconds": round(len(audio) / sample_rate, 3),
        "sample_rate": sample_rate,
        "channels": audio.shape[1],
        "peak_dbfs": round(20.0 * math.log10(max(1e-9, peak)), 2),
        "rms_dbfs": round(20.0 * math.log10(max(1e-9, rms)), 2),
    }


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)

    sfx_builders = {
        "ui_click": make_click,
        "ui_confirm": make_confirm,
        "ui_reject": make_reject,
        "critical_alarm": make_alarm,
        "impact": make_impact,
        "salvo": make_salvo,
        "repair": make_repair,
        "overcharge": make_overcharge,
        "flare": make_flare,
        "detach": make_detach,
        "defense_fire": make_defense_fire,
        "focus": make_focus,
        "ward_break": make_ward_break,
        "ward_warning": make_ward_warning,
        "route_commit": make_route_commit,
        "station_enter": make_station_enter,
    }
    written: dict[str, dict] = {}
    groups: dict[str, list[str]] = {}

    for group, builder in sfx_builders.items():
        groups[group] = []
        for variant in range(3):
            filename = f"{group}_{variant + 1:02d}.wav"
            samples = builder(variant)
            path = OUTPUT / filename
            write_wav(path, samples)
            written[filename] = audio_stats(path)
            groups[group].append(filename)

    for threat in ("pursuer", "boarder", "drainer"):
        group = f"threat_{threat}"
        groups[group] = []
        for variant in range(3):
            filename = f"{group}_{variant + 1:02d}.wav"
            samples = make_threat(threat, variant)
            path = OUTPUT / filename
            write_wav(path, samples)
            written[filename] = audio_stats(path)
            groups[group].append(filename)

    departure_path = OUTPUT / "departure_whistle.wav"
    departure = make_departure()
    write_wav(departure_path, departure)
    written[departure_path.name] = audio_stats(departure_path)
    groups["departure"] = [departure_path.name]

    for boss_cue in ("veil", "tether", "charge", "impact"):
        group = f"boss_{boss_cue}"
        groups[group] = []
        for variant in range(3):
            filename = f"{group}_{variant + 1:02d}.wav"
            samples = make_boss_cue(boss_cue, variant)
            path = OUTPUT / filename
            write_wav(path, samples)
            written[filename] = audio_stats(path)
            groups[group].append(filename)

    music_files: dict[str, str] = {}
    for track in (
        "title",
        "travel_calm",
        "travel_tension",
        "station",
        "longshadow",
        "dawn",
    ):
        filename = f"music_{track}.ogg"
        path = OUTPUT / filename
        samples = build_music(track)
        write_ogg(path, samples)
        stats = audio_stats(path)
        stats["loop"] = True
        stats["bpm"] = BPM
        stats["bars"] = LOOP_BARS
        written[filename] = stats
        music_files[track] = filename

    stingers: dict[str, str] = {}
    for name, victory in (("victory", True), ("defeat", False)):
        filename = f"{name}_stinger.ogg"
        path = OUTPUT / filename
        samples = make_stinger(victory)
        write_ogg(path, samples)
        stats = audio_stats(path)
        stats["loop"] = False
        written[filename] = stats
        stingers[name] = filename

    manifest = {
        "generator": Path(__file__).name,
        "generator_version": 3,
        "license": "Original generated project audio; no external samples or recordings.",
        "seed": SEED,
        "music": {
            "bpm": BPM,
            "loop_bars": LOOP_BARS,
            "loop_seconds": round(LOOP_SECONDS, 3),
            "sample_rate": MUSIC_RATE,
            "channels": 2,
            "files": music_files,
        },
        "stingers": stingers,
        "sfx_sample_rate": SFX_RATE,
        "groups": groups,
        "files": {name: written[name] for name in sorted(written)},
        "total_bytes": sum(item["bytes"] for item in written.values()),
    }
    (OUTPUT / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
