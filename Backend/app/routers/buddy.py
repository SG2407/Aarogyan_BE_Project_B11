from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from typing import Optional, List
import json
import logging
import base64
from app.auth import get_current_user_id
from app.database import get_supabase
from app.services.ai import emotional_buddy_respond
from app.services.tts import text_to_speech_bytes
from app.services.stt import speech_to_text

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/buddy", tags=["emotional-buddy"])


class BuddyTextRequest(BaseModel):
    text: str
    history: Optional[List[dict]] = None
    preferred_language: str = "English"
    session_group_id: Optional[str] = None  # groups all messages in one conversation


_LANG_CODE: dict[str, str] = {"English": "en", "Hindi": "hi", "Marathi": "mr"}

# Map LLM 7-label emotion → 4-label system used by ML model & analytics
_EMOTION_4_MAP: dict[str, str] = {
    "happy": "happy", "sad": "sad", "angry": "angry", "neutral": "neutral",
    "fearful": "sad", "disgusted": "angry", "surprised": "happy",
}


def _detect_emotion_ml(text: str) -> dict[str, float]:
    """Run ML text emotion model. Returns 4-label probs. Non-blocking fallback on error."""
    try:
        from app.services.emotion_detection import EmotionExtractor
        extractor = EmotionExtractor.get_instance()
        return extractor.extract_text_emotion(text)
    except Exception as e:
        logger.warning("ML emotion detection failed: %s", e)
        return {"happy": 0.0, "sad": 0.0, "angry": 0.0, "neutral": 1.0}


def _detect_audio_emotion_ml(audio_bytes: bytes) -> dict[str, float]:
    """Run ML audio emotion model (Wav2Vec2). Returns 4-label probs."""
    try:
        from app.services.emotion_detection import EmotionExtractor
        extractor = EmotionExtractor.get_instance()
        if not extractor.has_audio:
            return {"happy": 0.0, "sad": 0.0, "angry": 0.0, "neutral": 1.0}
        return extractor.extract_audio_emotion(audio_bytes)
    except Exception as e:
        logger.warning("ML audio emotion detection failed: %s", e)
        return {"happy": 0.0, "sad": 0.0, "angry": 0.0, "neutral": 1.0}


def _fuse_emotions(
    text: str,
    text_probs: dict[str, float],
    audio_probs: dict[str, float] | None,
) -> dict[str, float]:
    """Fuse text + audio emotion probs. Falls back to text-only if no audio."""
    if audio_probs is None:
        return text_probs
    try:
        from app.services.fusion_engine import fuse_once
        return fuse_once(text, text_probs, audio_probs)
    except Exception as e:
        logger.warning("Emotion fusion failed, using text-only: %s", e)
        return text_probs


@router.post("/chat")
async def text_chat(
    body: BuddyTextRequest,
    user_id: str = Depends(get_current_user_id),
):
    """On-device STT path: receive transcribed text, return AI reply + audio.
    This is the primary autonomous conversation endpoint.
    Latency is ~1.5–3 s lower than /voice because audio upload and server STT are eliminated.
    """
    if not body.text.strip():
        raise HTTPException(status_code=422, detail="Text must not be empty")

    history = body.history or []
    lang_code = _LANG_CODE.get(body.preferred_language, "en")

    # AI response
    ai_text, mood_score, emotion = await emotional_buddy_respond(body.text, history, body.preferred_language)

    # ML-based text emotion detection (4 labels, more reliable than LLM self-report)
    emotion_probs = _detect_emotion_ml(body.text)
    ml_dominant = max(emotion_probs, key=lambda k: emotion_probs[k])

    # TTS — non-critical: failure returns empty audio, client can still show text
    audio_response = b""
    try:
        audio_response = await text_to_speech_bytes(ai_text, lang_code)
    except Exception as tts_err:
        logger.warning("TTS failed: %s", tts_err)

    # Persist session — non-critical
    session_id = None
    try:
        db = get_supabase()
        row: dict = {
            "user_id": user_id,
            "user_text": body.text,
            "buddy_text": ai_text,
            "mood_score": mood_score,
            "emotion": emotion,
            "emotion_probs": json.dumps(emotion_probs),
        }
        if body.session_group_id:
            row["session_group_id"] = body.session_group_id
        result = db.table("emotional_sessions").insert(row).execute()
        session_id = result.data[0]["id"] if result.data else None
    except Exception as db_err:
        logger.error("Session DB insert failed: %s", db_err, exc_info=True)

    return {
        "buddy_text": ai_text,
        "mood_score": mood_score,
        "emotion": ml_dominant,
        "emotion_probs": emotion_probs,
        "session_id": session_id,
        "audio_base64": base64.b64encode(audio_response).decode("utf-8") if audio_response else "",
    }


@router.post("/voice")
async def voice_chat(
    audio: UploadFile = File(...),
    history_json: Optional[str] = Form(default=None),
    user_id: str = Depends(get_current_user_id),
):
    """Receive voice audio, return AI empathetic response as voice audio."""
    audio_bytes = await audio.read()

    # STT
    user_text = await speech_to_text(audio_bytes, audio.content_type)
    if not user_text.strip():
        raise HTTPException(status_code=422, detail="Could not transcribe audio")

    # Parse conversation history
    history = []
    if history_json:
        try:
            history = json.loads(history_json)
        except (json.JSONDecodeError, ValueError):
            history = []

    # AI response
    ai_text, mood_score, emotion = await emotional_buddy_respond(user_text, history)

    # ML-based text emotion detection
    emotion_probs = _detect_emotion_ml(user_text)
    ml_dominant = max(emotion_probs, key=lambda k: emotion_probs[k])

    # TTS — non-critical: if edge-tts fails, return text with no audio
    audio_response = b""
    try:
        audio_response = await text_to_speech_bytes(ai_text)
    except Exception as tts_err:
        logger.warning("TTS failed: %s", tts_err)

    # Store session mood — non-critical: DB failure must not block the response
    session_id = None
    try:
        db = get_supabase()
        session_result = db.table("emotional_sessions").insert(
            {
                "user_id": user_id,
                "user_text": user_text,
                "buddy_text": ai_text,
                "mood_score": mood_score,
                "emotion": emotion,
                "emotion_probs": json.dumps(emotion_probs),
            }
        ).execute()
        session_id = session_result.data[0]["id"] if session_result.data else None
    except Exception as db_err:
        logger.error("Session DB insert failed: %s", db_err, exc_info=True)

    return {
        "user_text": user_text,
        "buddy_text": ai_text,
        "mood_score": mood_score,
        "emotion": ml_dominant,
        "emotion_probs": emotion_probs,
        "session_id": session_id,
        "audio_base64": base64.b64encode(audio_response).decode("utf-8") if audio_response else "",
    }


@router.post("/analyze-voice")
async def analyze_voice_emotion(
    audio: UploadFile = File(...),
    text: Optional[str] = Form(default=None),
    session_id: Optional[str] = Form(default=None),
    user_id: str = Depends(get_current_user_id),
):
    """Analyze voice audio for emotion. Optionally fuse with text emotion.

    This endpoint does NOT participate in the conversation flow — it only
    performs emotion analysis on the audio recording that the Flutter app
    captured alongside on-device STT.

    If `text` is provided, runs both text + audio models and fuses them.
    If `session_id` is provided, updates that session row with fused probs.
    """
    audio_bytes = await audio.read()
    if not audio_bytes:
        raise HTTPException(status_code=422, detail="Audio file is empty")

    # Run audio emotion model
    audio_probs = _detect_audio_emotion_ml(audio_bytes)

    # Optionally fuse with text
    text_probs = None
    fused_probs = audio_probs
    if text and text.strip():
        text_probs = _detect_emotion_ml(text)
        fused_probs = _fuse_emotions(text, text_probs, audio_probs)

    fused_dominant = max(fused_probs, key=lambda k: fused_probs[k])

    # Optionally update the existing session row with fused probs
    if session_id:
        try:
            db = get_supabase()
            db.table("emotional_sessions").update({
                "emotion_probs": json.dumps(fused_probs),
                "emotion": fused_dominant,
            }).eq("id", session_id).eq("user_id", user_id).execute()
        except Exception as db_err:
            logger.warning("Failed to update session with voice emotion: %s", db_err)

    return {
        "audio_emotion_probs": audio_probs,
        "text_emotion_probs": text_probs,
        "fused_emotion_probs": fused_probs,
        "dominant_emotion": fused_dominant,
    }


@router.get("/sessions")
async def list_sessions(user_id: str = Depends(get_current_user_id)):
    db = get_supabase()
    result = (
        db.table("emotional_sessions")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )
    return result.data or []


@router.get("/sessions/{session_id}")
async def get_session(session_id: str, user_id: str = Depends(get_current_user_id)):
    db = get_supabase()
    result = (
        db.table("emotional_sessions")
        .select("*")
        .eq("id", session_id)
        .eq("user_id", user_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="Session not found")
    return result.data[0]


@router.get("/session-analytics/{session_group_id}")
async def get_session_analytics(
    session_group_id: str,
    user_id: str = Depends(get_current_user_id),
):
    """Compute emotion analytics for an entire conversation session.
    Returns dominant mood, emotion distribution, trend, volatility, stability, and insight.
    """
    from app.services.session_analytics import analyze_session

    db = get_supabase()
    result = (
        db.table("emotional_sessions")
        .select("emotion_probs, mood_score, emotion, created_at")
        .eq("user_id", user_id)
        .eq("session_group_id", session_group_id)
        .order("created_at", desc=False)
        .execute()
    )
    rows = result.data or []
    if not rows:
        raise HTTPException(status_code=404, detail="No messages found for this session")

    # Parse emotion_probs from each row
    probs_list: list[dict[str, float]] = []
    for row in rows:
        ep = row.get("emotion_probs")
        if ep:
            if isinstance(ep, str):
                ep = json.loads(ep)
            probs_list.append(ep)

    analytics = analyze_session(probs_list)

    # Include per-message mood scores for the trend chart
    mood_scores = [r["mood_score"] for r in rows if r.get("mood_score") is not None]
    analytics["mood_scores"] = mood_scores
    analytics["total_messages"] = len(rows)
    analytics["average_mood"] = round(sum(mood_scores) / len(mood_scores), 1) if mood_scores else 0.0

    return analytics
