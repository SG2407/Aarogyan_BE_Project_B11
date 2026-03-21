from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
from app.auth import get_current_user_id
from app.database import get_supabase
from app.services.ai import emotional_buddy_respond
from app.services.tts import text_to_speech_bytes
from app.services.stt import speech_to_text
from fastapi import UploadFile, File
import base64

router = APIRouter(prefix="/buddy", tags=["emotional-buddy"])


class BuddyTextRequest(BaseModel):
    text: str
    session_id: Optional[str] = None


@router.post("/voice")
async def voice_interact(
    audio: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
):
    """Receive voice audio, return AI empathetic response as voice audio."""
    audio_bytes = await audio.read()

    # STT
    user_text = await speech_to_text(audio_bytes, audio.content_type)
    if not user_text.strip():
        raise HTTPException(status_code=422, detail="Could not transcribe audio")

    # AI response
    ai_text, mood_score = await emotional_buddy_respond(user_text)

    # TTS
    audio_response = await text_to_speech_bytes(ai_text)

    # Store session mood
    db = get_supabase()
    session_result = db.table("emotional_sessions").insert(
        {
            "user_id": user_id,
            "user_text": user_text,
            "buddy_text": ai_text,
            "mood_score": mood_score,
        }
    ).execute()

    session_id = session_result.data[0]["id"] if session_result.data else None

    return {
        "user_text": user_text,
        "buddy_text": ai_text,
        "mood_score": mood_score,
        "session_id": session_id,
        "audio_base64": base64.b64encode(audio_response).decode("utf-8"),
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
