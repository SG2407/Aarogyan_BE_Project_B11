"""
Text-based and audio-based emotion detection.

Text:  j-hartmann/emotion-english-distilroberta-base
Audio: superb/wav2vec2-base-superb-er (Speech Emotion Recognition)

Lazy-loaded singleton — models are only instantiated on first use.
Maps all raw labels to 4 target labels: happy, sad, angry, neutral.
"""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)

STANDARD_LABELS = ["happy", "sad", "angry", "neutral"]

# Maps raw HuggingFace model output labels → 4 standard labels
LABEL_MAP: dict[str, str] = {
    # positive
    "joy": "happy", "happy": "happy", "happiness": "happy", "hap": "happy",
    "surprise": "happy",
    # sadness  (fear/anxiety → sad: both low-energy negative emotions)
    "sadness": "sad", "sad": "sad", "grief": "sad",
    "fear": "sad", "anxiety": "sad", "anxious": "sad",
    # anger  (disgust/frustration → angry: both high-energy negative emotions)
    "anger": "angry", "angry": "angry", "ang": "angry",
    "disgust": "angry", "frustrated": "angry",
    # neutral
    "neutral": "neutral", "neu": "neutral",
}

EmotionProbs = dict[str, float]


def empty_emotion_probs() -> EmotionProbs:
    """Default emotion state: fully neutral."""
    return {"happy": 0.0, "sad": 0.0, "angry": 0.0, "neutral": 1.0}


def _normalize(raw_scores: list[dict]) -> EmotionProbs:
    """Map [{label, score}] → normalised EmotionProbs (sums to 1.0)."""
    mapped: dict[str, float] = {k: 0.0 for k in STANDARD_LABELS}
    for item in raw_scores:
        label = LABEL_MAP.get(item["label"].lower())
        if label:
            mapped[label] += float(item["score"])
    total = sum(mapped.values())
    if total > 0:
        mapped = {k: v / total for k, v in mapped.items()}
    else:
        mapped["neutral"] = 1.0
    return mapped


def dominant(probs: EmotionProbs) -> tuple[str, float]:
    """Returns (dominant_label, confidence) for the highest-probability emotion."""
    label = max(probs, key=lambda k: probs[k])
    return label, probs[label]


class EmotionExtractor:
    """
    Lazy-loaded singleton emotion classifier for both text and audio.

    Usage:
        extractor = EmotionExtractor.get_instance()
        text_probs = extractor.extract_text_emotion("I feel really sad today")
        audio_probs = extractor.extract_audio_emotion(audio_bytes)
    """

    _instance: EmotionExtractor | None = None

    def __init__(self) -> None:
        from transformers import pipeline as hf_pipeline

        logger.info("[Emotion] Loading text classifier (j-hartmann/emotion-english-distilroberta-base)…")
        self._text_clf = hf_pipeline(
            "text-classification",
            model="j-hartmann/emotion-english-distilroberta-base",
            top_k=None,
            device=-1,  # CPU
        )
        logger.info("[Emotion] Text classifier loaded.")

        self._audio_clf = None
        try:
            logger.info("[Emotion] Loading audio classifier (superb/wav2vec2-base-superb-er)…")
            self._audio_clf = hf_pipeline(
                "audio-classification",
                model="superb/wav2vec2-base-superb-er",
                device=-1,
            )
            logger.info("[Emotion] Audio classifier loaded.")
        except Exception as e:
            logger.warning("[Emotion] Audio classifier unavailable: %s", e)

    @classmethod
    def get_instance(cls) -> EmotionExtractor:
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def extract_text_emotion(self, text: str) -> EmotionProbs:
        """
        Classify emotion from text using DistilRoBERTa.
        Returns EmotionProbs with 4 labels summing to 1.0.
        Truncates to 512 tokens automatically.
        """
        if not text.strip():
            return empty_emotion_probs()
        try:
            results = self._text_clf(text[:512])
            scores = results[0] if isinstance(results[0], list) else results
            return _normalize(scores)
        except Exception as e:
            logger.error("[Emotion] Text extraction error: %s", e)
            return empty_emotion_probs()

    def extract_audio_emotion(self, audio_bytes: bytes) -> EmotionProbs:
        """
        Classify emotion from speech audio using Wav2Vec2 (SUPERB-ER).
        Accepts raw audio bytes (WAV format). Loads via soundfile,
        feeds numpy array directly to the HuggingFace pipeline.
        Returns EmotionProbs with 4 labels summing to 1.0.
        """
        if not self._audio_clf or not audio_bytes:
            return empty_emotion_probs()
        try:
            import soundfile as sf
            import io

            audio_np, sample_rate = sf.read(
                io.BytesIO(audio_bytes), dtype="float32", always_2d=False
            )
            if audio_np.ndim > 1:
                audio_np = audio_np[:, 0]  # mono

            results = self._audio_clf(
                {"array": audio_np, "sampling_rate": sample_rate},
                top_k=None,
            )
            return _normalize(results)
        except Exception as e:
            logger.error("[Emotion] Audio extraction error: %s", e)
            return empty_emotion_probs()

    @property
    def has_audio(self) -> bool:
        """Whether the audio classifier is available."""
        return self._audio_clf is not None
