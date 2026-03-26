"""
Speech-to-Text service using Groq Whisper API.
Audio input is expected as bytes (WAV, MP3, M4A, OGG, WebM).
"""
import httpx
from app.config import get_settings


async def speech_to_text(audio_bytes: bytes, content_type: str) -> str:
    settings = get_settings()

    ext_map = {
        "audio/wav": ("audio.wav", "audio/wav"),
        "audio/wave": ("audio.wav", "audio/wav"),
        "audio/mpeg": ("audio.mp3", "audio/mpeg"),
        "audio/mp4": ("audio.m4a", "audio/mp4"),
        "audio/m4a": ("audio.m4a", "audio/mp4"),
        "audio/x-m4a": ("audio.m4a", "audio/mp4"),
        "audio/ogg": ("audio.ogg", "audio/ogg"),
        "audio/webm": ("audio.webm", "audio/webm"),
        "audio/x-wav": ("audio.wav", "audio/wav"),
    }
    filename, groq_content_type = ext_map.get(content_type, ("audio.m4a", "audio/mp4"))

    from fastapi import HTTPException
    import logging
    _log = logging.getLogger(__name__)
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                "https://api.groq.com/openai/v1/audio/transcriptions",
                headers={"Authorization": f"Bearer {settings.groq_api_key}"},
                files={
                    "file": (filename, audio_bytes, groq_content_type),
                    "model": (None, "whisper-large-v3-turbo"),
                    "response_format": (None, "json"),
                },
            )
            try:
                response.raise_for_status()
            except httpx.HTTPStatusError as e:
                _log.error("Groq STT error %s: %s", e.response.status_code, e.response.text)
                raise HTTPException(
                    status_code=502,
                    detail=f"Speech recognition failed (Groq {e.response.status_code})",
                )
            data = response.json()
            return data.get("text", "")
    except HTTPException:
        raise
    except httpx.TimeoutException:
        _log.error("Groq STT request timed out")
        raise HTTPException(status_code=504, detail="Speech recognition timed out. Please try again.")
    except httpx.RequestError as e:
        _log.error("Groq STT connection error: %s", e)
        raise HTTPException(status_code=502, detail="Could not connect to speech recognition service.")
