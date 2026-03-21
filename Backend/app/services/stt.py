"""
Speech-to-Text service using OpenAI Whisper via OpenRouter / OpenAI API.
Audio input is expected as bytes (WAV, MP3, M4A, OGG, WebM).
"""
import httpx
import io
from app.config import get_settings


async def speech_to_text(audio_bytes: bytes, content_type: str) -> str:
    settings = get_settings()

    # Use OpenAI Whisper API (compatible endpoint)
    async with httpx.AsyncClient(timeout=60.0) as client:
        # Determine file extension from content_type
        ext_map = {
            "audio/wav": "audio.wav",
            "audio/wave": "audio.wav",
            "audio/mpeg": "audio.mp3",
            "audio/mp4": "audio.m4a",
            "audio/ogg": "audio.ogg",
            "audio/webm": "audio.webm",
            "audio/x-wav": "audio.wav",
        }
        filename = ext_map.get(content_type, "audio.wav")

        response = await client.post(
            "https://api.openai.com/v1/audio/transcriptions",
            headers={"Authorization": f"Bearer {settings.openrouter_api_key}"},
            files={
                "file": (filename, audio_bytes, content_type),
                "model": (None, "whisper-1"),
            },
        )
        response.raise_for_status()
        data = response.json()
        return data.get("text", "")
