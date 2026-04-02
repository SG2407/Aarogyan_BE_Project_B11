"""
Session-level emotion analytics — pure statistics over per-message emotion probs.
No ML models. Computes dominant mood, trend, volatility, stability, and insights.

Uses 4 labels only: happy, sad, angry, neutral.
"""
from __future__ import annotations

from typing import Any

LABELS = ["happy", "sad", "angry", "neutral"]

# Valence scores for transition tracking
VALENCE: dict[str, int] = {"happy": 2, "neutral": 0, "sad": -2, "angry": -2}


def _empty_probs() -> dict[str, float]:
    return {"happy": 0.0, "sad": 0.0, "angry": 0.0, "neutral": 1.0}


def _dominant(probs: dict[str, float]) -> str:
    return max(LABELS, key=lambda k: probs.get(k, 0.0))


def _avg_probs(messages: list[dict[str, float]]) -> dict[str, float]:
    """Average emotion probs across a list of probability dicts."""
    if not messages:
        return _empty_probs()
    agg = {k: 0.0 for k in LABELS}
    for probs in messages:
        for k in LABELS:
            agg[k] += probs.get(k, 0.0)
    n = len(messages)
    return {k: round(v / n, 4) for k, v in agg.items()}


def analyze_session(emotion_probs_list: list[dict[str, float]]) -> dict[str, Any]:
    """
    Compute session-level analytics from a list of per-message EmotionProbs.

    Args:
        emotion_probs_list: List of dicts like {"happy": 0.1, "sad": 0.7, ...}
                            One per user message in the conversation.

    Returns:
        SessionAnalytics dict with:
        - dominant_emotion: most frequent label or "mixed"
        - emotion_distribution: avg probability per label
        - emotional_trend: start/middle/end phase averages
        - volatility: number of emotion label changes
        - stability_score: 0–100
        - intensity_trend: dominant confidence per message
        - upward_transitions / downward_transitions
        - insight_summary: human-readable sentence
    """
    if not emotion_probs_list:
        return _empty_analytics()

    N = len(emotion_probs_list)

    # ── 1. Emotion distribution (weighted avg) ──────────────────────────────
    distribution = {k: 0.0 for k in LABELS}
    intensity_trend: list[float] = []
    emotion_sequence: list[str] = []

    for probs in emotion_probs_list:
        for k in LABELS:
            distribution[k] += probs.get(k, 0.0) / N
        dom = _dominant(probs)
        emotion_sequence.append(dom)
        intensity_trend.append(round(probs.get(dom, 0.0), 4))

    distribution = {k: round(v, 4) for k, v in distribution.items()}

    # ── 2. Dominant emotion ─────────────────────────────────────────────────
    dominant_emotion = _dominant(distribution)
    if distribution[dominant_emotion] < 0.35:
        dominant_emotion = "mixed"

    # ── 3. Emotional trend (3 phases) ───────────────────────────────────────
    chunk = max(1, N // 3)
    start_probs = emotion_probs_list[:chunk]
    end_probs = emotion_probs_list[-chunk:]
    mid_probs = emotion_probs_list[chunk : N - chunk] or start_probs

    trend = {
        "start": _avg_probs(start_probs),
        "middle": _avg_probs(mid_probs),
        "end": _avg_probs(end_probs),
    }

    # ── 4. Volatility + transition tracking ─────────────────────────────────
    volatility = 0
    upward = 0
    downward = 0

    for i in range(1, len(emotion_sequence)):
        prev_e = emotion_sequence[i - 1]
        curr_e = emotion_sequence[i]
        if prev_e != curr_e:
            volatility += 1
            diff = VALENCE.get(curr_e, 0) - VALENCE.get(prev_e, 0)
            if diff > 0:
                upward += 1
            elif diff < 0:
                downward += 1

    # ── 5. Stability score (0–100) ──────────────────────────────────────────
    stability_score = round(max(0.0, 100.0 * (1.0 - volatility / max(N, 1))), 1)

    # ── 6. Insight summary ──────────────────────────────────────────────────
    start_dom = _dominant(trend["start"])
    end_dom = _dominant(trend["end"])
    v_start = VALENCE.get(start_dom, 0)
    v_end = VALENCE.get(end_dom, 0)

    if v_end > v_start:
        insight = (
            f"You started the session feeling {start_dom} but gradually shifted toward "
            f"feeling {end_dom}. That's a positive progression — well done for opening up!"
        )
    elif v_end < v_start:
        insight = (
            f"Your mood shifted from {start_dom} toward {end_dom} as the session progressed. "
            "It's okay to feel this way. Consider returning for another session soon."
        )
    elif volatility > N // 2:
        insight = (
            "Your emotional state fluctuated significantly during this session, "
            "suggesting a mixed or complex emotional state. Take it easy."
        )
    elif dominant_emotion in ("happy", "neutral"):
        insight = "You maintained a predominantly positive and stable mood throughout. Keep it up!"
    else:
        insight = (
            f"Your dominant mood today was {dominant_emotion}. "
            "Talking about it is a healthy first step."
        )

    return {
        "dominant_emotion": dominant_emotion,
        "emotion_distribution": distribution,
        "emotional_trend": trend,
        "volatility": volatility,
        "stability_score": stability_score,
        "intensity_trend": intensity_trend,
        "upward_transitions": upward,
        "downward_transitions": downward,
        "insight_summary": insight,
    }


def _empty_analytics() -> dict[str, Any]:
    return {
        "dominant_emotion": "unknown",
        "emotion_distribution": {k: 0.0 for k in LABELS},
        "emotional_trend": {
            "start": _empty_probs(),
            "middle": _empty_probs(),
            "end": _empty_probs(),
        },
        "volatility": 0,
        "stability_score": 100.0,
        "intensity_trend": [],
        "upward_transitions": 0,
        "downward_transitions": 0,
        "insight_summary": "No data to analyze.",
    }
