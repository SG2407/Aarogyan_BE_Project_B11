"""
fusion_engine.py - Deterministic multimodal emotion conflict resolution.

Merges text emotion probs and audio emotion probs using confidence-aware
weighted fusion with temporal smoothing. No ML models — pure math.

Hierarchy (applied in order):
  1. Explicit Text Override  (strong emotional keywords → boost text weight to 85%)
  2. Neutral Conflict Fix    (text=neutral, audio=emotional → trust audio 80%)
  3. Confidence-Aware Weighted Fusion (default: w_text=0.6, w_audio=0.4)
  4. Low Confidence Fallback (both below threshold → inherit previous)
  5. Temporal EMA Smoothing  (prevent sudden flips)
"""
from __future__ import annotations

from app.services.emotion_detection import EmotionProbs, empty_emotion_probs

# ── Constants ─────────────────────────────────────────────────────────────────
DEFAULT_W_TEXT = 0.6
DEFAULT_W_AUDIO = 0.4
CONF_HIGH = 0.70
CONF_LOW = 0.40
EMA_ALPHA = 0.65   # weight of current vs previous (higher = more reactive)
EMA_RESIST = 0.35  # used when flip is weak (resist sudden changes)

LABELS = list(empty_emotion_probs().keys())

# Strong keyword overrides — if found in text, boost text weight to 85%
STRONG_KEYWORDS: dict[str, list[str]] = {
    "happy": ["thrilled", "ecstatic", "overjoyed", "wonderful", "amazing", "great"],
    "sad": [
        "depressed", "devastated", "heartbroken", "hopeless", "miserable",
        "terrified", "panicking", "dread", "scared", "worried", "nervous",
    ],
    "angry": [
        "furious", "outraged", "livid", "hate", "rage", "infuriated",
        "fed up", "exhausted", "annoyed", "done with", "sick of",
    ],
    "neutral": [],
}


def _dominant(probs: EmotionProbs) -> tuple[str, float]:
    label = max(probs, key=lambda k: probs[k])
    return label, probs[label]


def _weighted_fuse(
    t: EmotionProbs, a: EmotionProbs, w_text: float, w_audio: float
) -> EmotionProbs:
    fused = {k: w_text * t[k] + w_audio * a[k] for k in LABELS}
    total = sum(fused.values())
    if total > 0:
        fused = {k: v / total for k, v in fused.items()}
    return fused


def _ema_smooth(
    current: EmotionProbs, previous: EmotionProbs, alpha: float
) -> EmotionProbs:
    smoothed = {k: alpha * current[k] + (1 - alpha) * previous[k] for k in LABELS}
    total = sum(smoothed.values())
    if total > 0:
        smoothed = {k: v / total for k, v in smoothed.items()}
    return smoothed


class FusionEngine:
    """
    Stateful fusion engine that tracks previous segment's emotion for smoothing.

    Usage:
        fusion = FusionEngine()
        fused_probs = fusion.fuse("I feel down", text_probs, audio_probs)
        # call fusion.reset() to start a new session
    """

    def __init__(self) -> None:
        self._prev: EmotionProbs | None = None

    def reset(self) -> None:
        self._prev = None

    def fuse(
        self,
        text: str,
        text_probs: EmotionProbs,
        audio_probs: EmotionProbs,
    ) -> EmotionProbs:
        """
        Run conflict resolution pipeline. Returns fused EmotionProbs (4 labels).

        Rules applied in order:
          1. Strong keyword in text → boost text weight to 85%
          2. Text=neutral but audio=emotional → trust audio 80%
          3. Confidence-aware weighted fusion (0.6 text / 0.4 audio)
          4. Both low confidence → fall back to previous
          5. Temporal EMA smoothing
        """
        t_label, t_conf = _dominant(text_probs)
        a_label, a_conf = _dominant(audio_probs)
        w_text, w_audio = DEFAULT_W_TEXT, DEFAULT_W_AUDIO

        text_lower = text.lower()

        # ── Rule 1: Explicit Text Override ────────────────────────────────
        for _emotion, keywords in STRONG_KEYWORDS.items():
            if any(kw in text_lower for kw in keywords):
                w_text, w_audio = 0.85, 0.15
                break

        # ── Rule 2: Neutral Conflict Fix ──────────────────────────────────
        if (
            w_text == DEFAULT_W_TEXT
            and t_label == "neutral"
            and a_label != "neutral"
            and a_conf > CONF_LOW
        ):
            w_text, w_audio = 0.20, 0.80

        # ── Rule 3: Audio much more confident ─────────────────────────────
        if w_text == DEFAULT_W_TEXT and a_conf - t_conf > 0.30:
            w_text, w_audio = 0.30, 0.70

        # ── Confidence-Aware Weighted Fusion ──────────────────────────────
        fused = _weighted_fuse(text_probs, audio_probs, w_text, w_audio)

        # ── Rule 4: Low Confidence Fallback ───────────────────────────────
        if t_conf < CONF_LOW and a_conf < CONF_LOW:
            if self._prev is not None:
                fused = self._prev
            else:
                fused["neutral"] = fused.get("neutral", 0.0) + 0.3
                total = sum(fused.values())
                fused = {k: v / total for k, v in fused.items()}

        # ── Rule 5: Temporal Smoothing ────────────────────────────────────
        if self._prev is not None:
            p_label, _ = _dominant(self._prev)
            f_label, f_conf = _dominant(fused)
            alpha = EMA_ALPHA if (f_label == p_label or f_conf >= CONF_HIGH) else EMA_RESIST
            fused = _ema_smooth(fused, self._prev, alpha)

        self._prev = fused
        return fused


def fuse_once(
    text: str,
    text_probs: EmotionProbs,
    audio_probs: EmotionProbs,
) -> EmotionProbs:
    """Stateless single-shot fusion (no temporal smoothing / no history)."""
    t_label, t_conf = _dominant(text_probs)
    a_label, a_conf = _dominant(audio_probs)
    w_text, w_audio = DEFAULT_W_TEXT, DEFAULT_W_AUDIO

    text_lower = text.lower()

    for _emotion, keywords in STRONG_KEYWORDS.items():
        if any(kw in text_lower for kw in keywords):
            w_text, w_audio = 0.85, 0.15
            break

    if w_text == DEFAULT_W_TEXT and t_label == "neutral" and a_label != "neutral" and a_conf > CONF_LOW:
        w_text, w_audio = 0.20, 0.80

    if w_text == DEFAULT_W_TEXT and a_conf - t_conf > 0.30:
        w_text, w_audio = 0.30, 0.70

    return _weighted_fuse(text_probs, audio_probs, w_text, w_audio)
