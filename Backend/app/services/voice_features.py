"""
voice_features.py — Extract acoustic / prosodic features from speech audio.

Uses only numpy + scipy + soundfile (already in requirements).
Returns a human-readable summary string suitable for injection into LLM prompts,
plus a structured dict for programmatic use.

Features extracted:
  - Pitch (F0): mean, std, range  → indicates vocal tension / excitement
  - Energy (RMS): mean, std       → indicates loudness / intensity
  - Speaking rate proxy            → syllable-density estimate
  - Voice quality: jitter approximation
"""
from __future__ import annotations

import io
import logging
from typing import TypedDict

import numpy as np
import soundfile as sf
from scipy.signal import find_peaks

logger = logging.getLogger(__name__)


class VoiceFeatures(TypedDict):
    pitch_mean_hz: float
    pitch_std_hz: float
    pitch_range_hz: float
    energy_mean: float
    energy_std: float
    speaking_rate: str        # "slow" | "normal" | "fast"
    pitch_level: str          # "low" | "normal" | "high"
    energy_level: str         # "low" | "normal" | "high"
    pitch_variability: str    # "monotone" | "normal" | "expressive"


def _autocorrelation_pitch(signal: np.ndarray, sr: int) -> np.ndarray:
    """Estimate F0 per frame using autocorrelation method."""
    frame_len = int(0.03 * sr)   # 30 ms frames
    hop = int(0.01 * sr)         # 10 ms hop
    min_lag = int(sr / 500)      # 500 Hz max pitch
    max_lag = int(sr / 70)       # 70 Hz min pitch

    pitches = []
    for start in range(0, len(signal) - frame_len, hop):
        frame = signal[start : start + frame_len]
        frame = frame - np.mean(frame)
        if np.max(np.abs(frame)) < 1e-4:
            pitches.append(0.0)
            continue

        # Normalized autocorrelation
        corr = np.correlate(frame, frame, mode="full")
        corr = corr[len(corr) // 2 :]
        if corr[0] == 0:
            pitches.append(0.0)
            continue
        corr = corr / corr[0]

        # Search for peak in valid lag range
        search = corr[min_lag : max_lag + 1] if max_lag < len(corr) else corr[min_lag:]
        if len(search) < 2:
            pitches.append(0.0)
            continue

        peaks, props = find_peaks(search, height=0.3)
        if len(peaks) == 0:
            pitches.append(0.0)
            continue

        best = peaks[np.argmax(props["peak_heights"])]
        lag = best + min_lag
        pitches.append(sr / lag if lag > 0 else 0.0)

    return np.array(pitches)


def _rms_energy(signal: np.ndarray, sr: int) -> np.ndarray:
    """Compute RMS energy per frame."""
    frame_len = int(0.03 * sr)
    hop = int(0.01 * sr)
    energies = []
    for start in range(0, len(signal) - frame_len, hop):
        frame = signal[start : start + frame_len]
        energies.append(np.sqrt(np.mean(frame ** 2)))
    return np.array(energies)


def extract_voice_features(audio_bytes: bytes) -> VoiceFeatures | None:
    """Extract prosodic features from WAV audio bytes.

    Returns None on failure (caller should handle gracefully).
    """
    try:
        audio_np, sr = sf.read(io.BytesIO(audio_bytes), dtype="float32", always_2d=False)
        if audio_np.ndim > 1:
            audio_np = audio_np[:, 0]  # mono

        # Minimum 0.5 s of audio
        if len(audio_np) < sr * 0.5:
            return None

        # ── Pitch ──────────────────────────────────────────────────────────
        pitches = _autocorrelation_pitch(audio_np, sr)
        voiced = pitches[pitches > 0]

        if len(voiced) < 5:
            pitch_mean = 0.0
            pitch_std = 0.0
            pitch_range = 0.0
        else:
            pitch_mean = float(np.mean(voiced))
            pitch_std = float(np.std(voiced))
            pitch_range = float(np.max(voiced) - np.min(voiced))

        # ── Energy ─────────────────────────────────────────────────────────
        energies = _rms_energy(audio_np, sr)
        energy_mean = float(np.mean(energies)) if len(energies) > 0 else 0.0
        energy_std = float(np.std(energies)) if len(energies) > 0 else 0.0

        # ── Speaking rate (voiced-frame ratio as proxy) ────────────────────
        total_frames = len(pitches) if len(pitches) > 0 else 1
        voiced_ratio = len(voiced) / total_frames
        duration_s = len(audio_np) / sr

        # Classify features into descriptive levels
        # Pitch level (typical male ~120 Hz, female ~200 Hz, use gender-neutral thresholds)
        if pitch_mean == 0:
            pitch_level = "normal"
        elif pitch_mean < 130:
            pitch_level = "low"
        elif pitch_mean > 220:
            pitch_level = "high"
        else:
            pitch_level = "normal"

        # Pitch variability
        if pitch_std < 15:
            pitch_variability = "monotone"
        elif pitch_std > 50:
            pitch_variability = "expressive"
        else:
            pitch_variability = "normal"

        # Energy level
        if energy_mean < 0.02:
            energy_level = "low"
        elif energy_mean > 0.08:
            energy_level = "high"
        else:
            energy_level = "normal"

        # Speaking rate
        if voiced_ratio < 0.3:
            speaking_rate = "slow"
        elif voiced_ratio > 0.6:
            speaking_rate = "fast"
        else:
            speaking_rate = "normal"

        return VoiceFeatures(
            pitch_mean_hz=round(pitch_mean, 1),
            pitch_std_hz=round(pitch_std, 1),
            pitch_range_hz=round(pitch_range, 1),
            energy_mean=round(energy_mean, 4),
            energy_std=round(energy_std, 4),
            speaking_rate=speaking_rate,
            pitch_level=pitch_level,
            energy_level=energy_level,
            pitch_variability=pitch_variability,
        )

    except Exception as e:
        logger.error("[VoiceFeatures] Extraction failed: %s", e)
        return None


def format_voice_context(
    features: VoiceFeatures | None,
    audio_emotion: str = "neutral",
    audio_confidence: float = 0.5,
    text_emotion: str = "neutral",
    text_confidence: float = 0.5,
) -> str:
    """Format voice analysis into a concise context block for the LLM prompt.

    The LLM can use this to detect mismatches between what the user *says*
    and how they *sound*, enabling more empathetic responses.
    """
    lines = ["[Voice Analysis]"]

    lines.append(f"Vocal emotion: {audio_emotion} (confidence: {audio_confidence:.0%})")
    lines.append(f"Text emotion: {text_emotion} (confidence: {text_confidence:.0%})")

    if audio_emotion != text_emotion and audio_confidence > 0.4:
        lines.append(f"⚠ CONFLICT: User's words suggest '{text_emotion}' but voice sounds '{audio_emotion}'.")

    if features:
        lines.append(f"Pitch: {features['pitch_level']}, Energy: {features['energy_level']}, "
                      f"Rate: {features['speaking_rate']}, Variability: {features['pitch_variability']}")
    else:
        lines.append("Pitch/energy features: unavailable")

    lines.append("[End Voice Analysis]")
    return "\n".join(lines)
