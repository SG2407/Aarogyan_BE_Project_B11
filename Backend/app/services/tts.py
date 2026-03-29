"""
Text-to-Speech service using Google Translate TTS API via httpx.
Free, no API key, no conflicting package dependencies. Returns MP3 bytes.
"""
import asyncio
import httpx

_MAX_CHARS = 100  # Google Translate TTS hard limit per request


def _split_text(text: str, limit: int = _MAX_CHARS) -> list[str]:
    """Split text into chunks at sentence boundaries, each < limit chars."""
    import re
    sentences = re.split(r"(?<=[.!?])\s+", text.strip())
    chunks: list[str] = []
    current = ""
    for sentence in sentences:
        # If a single sentence is too long, hard-split it
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


async def _fetch_chunk(client: httpx.AsyncClient, chunk: str, lang: str = "en") -> bytes:
    url = "https://translate.google.com/translate_tts"
    params = {
        "ie": "UTF-8",
        "q": chunk,
        "tl": lang,
        "client": "tw-ob",
        "total": "1",
        "idx": "0",
        "textlen": str(len(chunk)),
    }
    headers = {"User-Agent": "Mozilla/5.0 (compatible; Googlebot/2.1)"}
    resp = await client.get(url, params=params, headers=headers)
    resp.raise_for_status()
    return resp.content


async def text_to_speech_bytes(text: str, lang: str = "en") -> bytes:
    """Convert text to speech using Google Translate TTS. Returns MP3 bytes.
    Splits long text into chunks and concatenates the audio.
    Raises on failure after 20 seconds total.
    """
    chunks = _split_text(text)
    async with httpx.AsyncClient(timeout=15) as client:
        parts = await asyncio.wait_for(
            asyncio.gather(*[_fetch_chunk(client, c, lang) for c in chunks]),
            timeout=20,
        )
    return b"".join(parts)
