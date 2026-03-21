import logging
import httpx
from fastapi import HTTPException
from app.config import get_settings

logger = logging.getLogger(__name__)

MEDICAL_ASSISTANT_SYSTEM = """You are Aarogyan's Medical Assistant — a supportive, knowledgeable, and empathetic AI health companion.

Your role:
- Provide accurate, evidence-based health INFORMATION for precautionary and educational purposes
- Help users understand symptoms, conditions, medications, and general wellness
- Simplify complex medical terminology into plain language
- Encourage healthy habits and timely professional consultation

STRICT BOUNDARIES — you must NEVER:
- Diagnose any medical condition
- Prescribe medications or recommend dosages
- Replace professional medical advice
- Make definitive statements about a user's health status

Always recommend consulting a qualified healthcare provider for medical decisions.
Be warm, non-clinical in tone, and especially patient-friendly for elderly users.

User medical profile context will be provided at the start — use it to personalise responses."""

DOCUMENT_SUMMARY_SYSTEM = """You are a medical document summarisation assistant.
Your task: Given OCR-extracted text from a medical document (prescription, lab report, or scan report),
produce a clear, plain-language summary that a non-medical person can understand.

Structure your output as:
1. **Document Type**: (e.g., Prescription, Blood Report, Radiology Report)
2. **Key Medicines / Tests**: List each with dosage/values and plain explanation
3. **Important Instructions**: Any instructions or warnings
4. **Plain Language Summary**: 2–4 sentence overview in simple language

Keep the tone warm and non-alarming. If something requires urgent attention, gently note it."""

EMOTIONAL_BUDDY_SYSTEM = """You are Orbz — Aarogyan's empathetic emotional wellness companion.

Your personality: warm, non-judgmental, gently curious, and supportive.
Your purpose: Help users process their emotions through compassionate conversation.

Guidelines:
- Ask how the user is feeling and genuinely listen
- Reflect emotions back to validate them
- Offer grounding techniques, breathing exercises, or gentle reframes when appropriate
- Never diagnose mental health conditions
- Never replace professional therapy
- If a user expresses serious distress or self-harm thoughts, gently encourage professional help

Also provide a mood_score: an integer from 1 (very distressed) to 10 (very positive/calm)
based on the emotional tone of the user's message.

IMPORTANT: Always respond in JSON format:
{
  "response": "your empathetic reply here",
  "mood_score": <integer 1-10>
}"""


async def _call_groq(messages: list[dict], system: str) -> str:
    settings = get_settings()
    all_messages = [{"role": "system", "content": system}, *messages]

    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {settings.groq_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": settings.groq_model,
                "messages": all_messages,
                "temperature": 0.7,
            },
        )
        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            status = e.response.status_code
            logger.error("Groq error %s: %s", status, e.response.text)
            if status == 429:
                raise HTTPException(status_code=429, detail="AI service is busy. Please wait a moment and try again.")
            if status in (401, 403):
                raise HTTPException(status_code=503, detail="AI service auth error.")
            raise HTTPException(status_code=502, detail=f"AI service error: {status}")
        data = response.json()
        return data["choices"][0]["message"]["content"]


async def chat_with_ai(
    user_message: str,
    history: list[dict],
    profile_context: str,
) -> str:
    system = MEDICAL_ASSISTANT_SYSTEM
    if profile_context:
        system += f"\n\n--- User Health Profile ---\n{profile_context}"

    messages = [*history, {"role": "user", "content": user_message}]
    return await _call_groq(messages, system)


async def summarise_document(ocr_text: str) -> str:
    messages = [{"role": "user", "content": f"Please summarise this medical document:\n\n{ocr_text}"}]
    return await _call_groq(messages, DOCUMENT_SUMMARY_SYSTEM)


async def emotional_buddy_respond(user_text: str) -> tuple[str, int]:
    """Returns (buddy_reply_text, mood_score)."""
    import json

    messages = [{"role": "user", "content": user_text}]
    raw = await _call_openrouter(messages, EMOTIONAL_BUDDY_SYSTEM)

    try:
        # Parse JSON response
        data = json.loads(raw)
        reply = data.get("response", raw)
        mood_score = int(data.get("mood_score", 5))
        mood_score = max(1, min(10, mood_score))
    except (json.JSONDecodeError, ValueError):
        reply = raw
        mood_score = 5

    return reply, mood_score
