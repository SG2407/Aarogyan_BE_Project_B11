from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from typing import Optional, List
import json
import base64
from app.auth import get_current_user_id
from app.database import get_supabase
from app.services.ai import emotional_buddy_respond
from app.services.tts import text_to_speech_bytes
from app.services.stt import speech_to_text

router = APIRouter(prefix="/buddy", tags=["emotional-buddy"])


class BuddyTextRequest(BaseModel):
    text: str
    history: Optional[List[dict]] = None
    preferred_language: str = "English"


_LANG_CODE: dict[str, str] = {"English": "en", "Hindi": "hi", "Marathi": "mr"}


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

    # TTS — non-critical: failure returns empty audio, client can still show text
    audio_response = b""
    try:
        audio_response = await text_to_speech_bytes(ai_text, lang_code)
    except Exception as tts_err:
        import logging
        logging.getLogger(__name__).warning("TTS failed: %s", tts_err)

    # Persist session — non-critical
    session_id = None
    try:
        db = get_supabase()
        result = db.table("emotional_sessions").insert(
            {
                "user_id": user_id,
                "user_text": body.text,
                "buddy_text": ai_text,
                "mood_score": mood_score,
                "emotion": emotion,
            }
        ).execute()
        session_id = result.data[0]["id"] if result.data else None
    except Exception as db_err:
        import logging
        logging.getLogger(__name__).error("Session DB insert failed: %s", db_err, exc_info=True)

    return {
        "buddy_text": ai_text,
        "mood_score": mood_score,
        "emotion": emotion,
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

    # TTS — non-critical: if edge-tts fails, return text with no audio
    audio_response = b""
    try:
        audio_response = await text_to_speech_bytes(ai_text)
    except Exception as tts_err:
        import logging
        logging.getLogger(__name__).warning("TTS failed: %s", tts_err)

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
            }
        ).execute()
        session_id = session_result.data[0]["id"] if session_result.data else None
    except Exception as db_err:
        import logging
        logging.getLogger(__name__).error("Session DB insert failed: %s", db_err, exc_info=True)

    return {
        "user_text": user_text,
        "buddy_text": ai_text,
        "mood_score": mood_score,
        "emotion": emotion,
        "session_id": session_id,
        "audio_base64": base64.b64encode(audio_response).decode("utf-8") if audio_response else "",
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
