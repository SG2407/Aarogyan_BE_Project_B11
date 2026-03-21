"""
Text-to-Speech service using OpenAI TTS API.
Returns raw audio bytes (MP3).
"""
import httpx
from app.config import get_settings


async def text_to_speech_bytes(text: str, voice: str = "nova") -> bytes:
    """
    Convert text to speech using OpenAI TTS.
    voice options: alloy, echo, fable, onyx, nova, shimmer
    'nova' is warm and friendly — suitable for Orbz.
    """
    settings = get_settings()

    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            "https://api.openai.com/v1/audio/speech",
            headers={
                "Authorization": f"Bearer {settings.openrouter_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": "tts-1",
                "input": text,
                "voice": voice,
                "response_format": "mp3",
            },
        )
        response.raise_for_status()
        return response.content
