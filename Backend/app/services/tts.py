"""
Text-to-Speech service using Sarvam AI (bulbul:v3).
Reads SARVAM_API_KEY from .env via app.config.
Returns WAV bytes decoded from the API's base64 audio response.
"""
import asyncio
import base64
import re
import httpx

from app.config import get_settings

_SARVAM_TTS_URL = "https://api.sarvam.ai/text-to-speech"
_MAX_CHARS = 500  # Sarvam recommended max per input

# Map short codes → Sarvam BCP-47 codes
_LANG_MAP: dict[str, str] = {
    "en": "en-IN",
    "hi": "hi-IN",
    "mr": "mr-IN",
}

# Single warm speaker suitable for emotional-support use-case (bulbul:v3 female)
_SPEAKER = "priya"


def _split_text(text: str, limit: int = _MAX_CHARS) -> list[str]:
    """Split text into chunks at sentence boundaries, each ≤ limit chars."""
    sentences = re.split(r"(?<=[.!?])\s+", text.strip())
    chunks: list[str] = []
    current = ""
    for sentence in sentences:
        while len(sentence) > limit:
            chunks.append(sentence[:limit])
            sentence = sentence[limit:]
        if len(current) + len(sentence) + 1 <= limit:
            current = (current + " " + sentence).strip()
        else:
            if current:
                chunks.append(current)
            current = sentence
    if current:
        chunks.append(current)
    return chunks or [text[:limit]]


async def _fetch_chunk(
    client: httpx.AsyncClient,
    chunk: str,
    lang_code: str,
    api_key: str,
    speaker: str = _SPEAKER,
) -> bytes:
    payload = {
        "text": chunk,
        "target_language_code": lang_code,
        "speaker": speaker,
        "model": "bulbul:v3",
        "pace": 1.0,
        "speech_sample_rate": 22050,
    }
    headers = {
        "api-subscription-key": api_key,
        "Content-Type": "application/json",
    }
    resp = await client.post(_SARVAM_TTS_URL, json=payload, headers=headers)
    resp.raise_for_status()
    data = resp.json()
    audios = data.get("audios", [])
    if not audios:
        raise ValueError("Sarvam TTS returned no audio data")
    # API returns base64-encoded WAV
    return base64.b64decode(audios[0])


async def text_to_speech_bytes(text: str, lang: str = "en", speaker: str = _SPEAKER) -> bytes:
    """Convert text to WAV bytes using Sarvam AI bulbul:v3.
    Splits long text into chunks and concatenates raw WAV PCM data.
    Raises on failure.
    """
    settings = get_settings()
    api_key = settings.sarvam_api_key
    lang_code = _LANG_MAP.get(lang, "en-IN")
    chunks = _split_text(text)

    async with httpx.AsyncClient(timeout=20) as client:
        parts = await asyncio.wait_for(
            asyncio.gather(
                *[_fetch_chunk(client, c, lang_code, api_key, speaker) for c in chunks]
            ),
            timeout=30,
        )
    return b"".join(parts)

