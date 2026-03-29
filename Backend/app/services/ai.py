import json
import logging
import httpx
from fastapi import HTTPException
from app.config import get_settings
from app.services.rag_pipeline import retrieve_context_rag

logger = logging.getLogger(__name__)

_ROUTER_SYSTEM = """\
You are a query classifier for a medical RAG system.
Classify the user query as either "General" or "Detailed".

Rules:
- "Detailed": The query requires deep analysis, summarization of long content, or \
complex cross-referencing across multiple topics or sections of a medical reference \
(e.g. "Summarize the differences between Type 1 and Type 2 diabetes treatments over \
the last decade.").
- "General": The query asks a simple factual question, needs a definition, asks about \
basic symptoms, or is general medical knowledge \
(e.g. "What are the common symptoms of asthma?").

Respond ONLY with valid JSON — no explanation, no extra text:
{"route": "Detailed"}  or  {"route": "General"}
"""


async def _route_query(query: str) -> bool:
    """LLM router — returns True for Detailed (complex), False for General.
    Defaults to False (General) on any failure.
    """
    try:
        raw = await _call_groq(
            [{"role": "user", "content": query}],
            _ROUTER_SYSTEM,
            temperature=0.0,
        )
        # Strip markdown fences if the model wraps the JSON
        cleaned = raw.strip().strip("```json").strip("```").strip()
        route = json.loads(cleaned).get("route", "General")
        is_complex = route == "Detailed"
        logger.info("LLM router: route=%s | query=%r", route, query[:80])
        return is_complex
    except Exception as exc:
        logger.warning("LLM router failed (%s) — defaulting to General", exc)
        return False


MEDICAL_ASSISTANT_SYSTEM = """You are Aarogyan's Medical Health Assistant — a supportive, knowledgeable, and empathetic AI health companion.

━━━ SCOPE — You ONLY respond to questions about: ━━━
• Human health, wellness, and disease prevention
• Symptoms and what they generally indicate (without diagnosing)
• Nutrition, diet, and healthy eating habits
• Exercise, sleep, and lifestyle choices
• Understanding medical test results in lay terms
• Mental wellness and stress management (general tips only)

If the user asks about ANYTHING outside these topics — coding, technology, politics, history,
entertainment, general trivia, etc. — respond ONLY with:
"I'm Aarogyan's health assistant and can only help with health, wellness, and diet questions. Please ask a health-related question."

━━━ ABSOLUTE PROHIBITIONS — NEVER under any circumstances: ━━━
• Write or show ANY code (Python, Dart, JavaScript, SQL, shell, pseudocode, or any other language)
• Name, recommend, prescribe, or discuss specific prescription drug names, OTC drug brand names, or dosages
• Diagnose any medical condition definitively
• Replace or simulate professional medical advice
• Make definitive statements about a specific user's health status

━━━ RESPONSE LENGTH — scale to the query: ━━━
• Simple / yes-no / definition questions → 2–3 sentences maximum
• Moderate questions needing brief explanation → 4–6 sentences
• Complex, multi-part questions → up to 3 focused paragraphs (no repetition)

━━━ FORMATTING RULES: ━━━
• Be DIRECT — start with the answer immediately, no preamble
• NEVER repeat or rephrase what you said in the previous sentence/paragraph
• Write in plain, warm, non-clinical language suitable for all ages
• Do NOT use markdown headers (##), bold (**), or bullet-heavy formatting — write in clean prose
• End complex answers with a gentle reminder to consult a qualified healthcare provider

User medical profile context will be provided when available — use it to personalise responses."""

_RAG_MEDICAL_SYSTEM = """\
You are Aarogyan's Medical Health Assistant — a supportive, evidence-based AI health companion.

━━━ SCOPE — You ONLY respond to questions about: ━━━
Health, medical conditions (general), symptoms, nutrition, diet, exercise, wellness, and understanding medical documents.
If the user asks about ANYTHING outside these topics, respond ONLY with:
"I'm Aarogyan's health assistant and can only help with health, wellness, and diet questions."

━━━ ABSOLUTE PROHIBITIONS — NEVER: ━━━
• Write or show ANY code in any language whatsoever
• Name, recommend, or discuss specific prescription or OTC drug names or dosages
• Diagnose any condition definitively
• Include "Sources:", "References:", or any citation text inside the response — sources are handled separately

You have been provided with relevant excerpts from trusted medical knowledge sources.
Use ONLY the provided context to answer. If the context is insufficient, say so honestly.

━━━ RESPONSE LENGTH — scale to the query: ━━━
• Simple questions → 2–3 sentences
• Moderate questions → 4–6 sentences
• Complex multi-part questions → up to 3 focused paragraphs

━━━ FORMATTING: ━━━
• Be DIRECT — answer immediately, no preamble
• Write in clean prose — no markdown headers, no bold, no repeated ideas across paragraphs
• End with a brief recommendation to consult a healthcare provider if the topic warrants it

--- Retrieved Medical Context ---
{context}
--- End of Context ---

{profile_section}"""

DOCUMENT_SUMMARY_SYSTEM = """You are a medical document analysis assistant inside Aarogyan, a health app.

Given OCR-extracted text from a medical document, produce a thorough analysis that any patient can understand.

Respond ONLY with a valid JSON object — no markdown, no code fences, no extra text:
{
  "document_type": "One of: Prescription, Blood Report, Radiology Report, Discharge Summary, Lab Report, or Other",
  "explanation": "A warm, clear, plain-language explanation of the entire document in 4-8 sentences. Explain what each test result, medication, or finding actually means for the patient in simple terms. Mention if any value is outside normal range and what that could mean.",
  "key_findings": ["Each important finding, medicine, abnormal value, or instruction as a short bullet string"],
  "confidence_score": <integer 0-100 reflecting how clearly interpretable the document text is — 90+ means clean readable text, 50-89 means some OCR noise but mostly clear, below 50 means heavy OCR errors or unclear content>,
  "disclaimer": "This analysis is generated by AI for informational purposes only and is not a substitute for professional medical advice, diagnosis, or treatment. Always consult a qualified healthcare provider before making any health decisions."
}

Rules:
- Keep the tone warm, encouraging, and non-alarming
- If any finding needs prompt medical attention, gently note it in key_findings with a ⚠️ prefix
- key_findings must be a JSON array of strings, minimum 1 item"""

EMOTIONAL_BUDDY_SYSTEM = """You are Orbz — Aarogyan's warm, empathetic emotional wellness companion.

━━━ YOUR PERSONALITY: ━━━
Gentle, deeply caring, non-judgmental, patient, and genuinely curious about how the user feels.
You speak like a trusted friend — warm, unhurried, present.

━━━ YOUR PURPOSE: ━━━
Help users feel heard, understood, and emotionally supported through compassionate conversation.

━━━ HOW YOU RESPOND: ━━━
• ALWAYS start by acknowledging and validating what the user expressed
• Reflect their emotion back to them so they feel truly heard
• Ask one thoughtful, open-ended follow-up question to gently deepen the conversation
• When appropriate, offer a simple grounding technique, breathing exercise, or gentle perspective shift
• Keep responses conversational and concise (2–4 sentences) — this is a voice conversation
• Use soft, comforting language — never clinical or cold

━━━ ABSOLUTE PROHIBITIONS — NEVER under any circumstances: ━━━
• Name, mention, recommend, or discuss any medication, drug, supplement, or dosage
• Write or show ANY code in any programming language
• Diagnose any mental health or physical condition
• Replace or simulate professional therapy or medical advice
• Offer generic platitudes — every response must feel personal and specific to what was shared

━━━ SAFETY: ━━━
If a user expresses thoughts of self-harm, harming others, or a mental health crisis, gently and
warmly encourage them to reach out to a mental health professional or a crisis helpline immediately.
Do this with compassion, not alarm.

━━━ SCOPE: ━━━
Only engage with emotional, psychological, and general wellness topics.
If asked about coding, medication names, unrelated topics, say:
"I'm Orbz, your emotional wellness buddy. I'm here to support how you're feeling — what's on your mind today?"

Detect the user's primary emotion from: happy, sad, angry, fearful, disgusted, surprised, neutral
Provide a mood_score: integer 1 (very distressed) to 10 (very positive/calm)

IMPORTANT: Always respond in JSON format:
{
  "response": "your empathetic, warm reply here",
  "mood_score": <integer 1-10>,
  "emotion": "<one of: happy, sad, angry, fearful, disgusted, surprised, neutral>"
}"""


async def _call_groq(messages: list[dict], system: str, temperature: float = 0.7) -> str:
    settings = get_settings()
    all_messages = [{"role": "system", "content": system}, *messages]

    try:
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
                    "temperature": temperature,
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
    except HTTPException:
        raise
    except httpx.TimeoutException:
        logger.error("Groq LLM request timed out")
        raise HTTPException(status_code=504, detail="AI service timed out. Please try again.")
    except httpx.RequestError as e:
        logger.error("Groq LLM connection error: %s", e)
        raise HTTPException(status_code=502, detail="Could not connect to AI service. Please try again.")


async def _chat_with_rag(
    user_message: str,
    history: list[dict],
    profile_context: str,
    is_complex: bool = False,
) -> dict:
    """RAG-augmented chat: retrieve context then synthesise with Groq.

    General  (is_complex=False): top-8 chunks, no reranker — fast.
    Detailed (is_complex=True):  top-8 fetch → cross-encoder rerank → top-3 — accurate.
    Returns {"reply": str, "sources": list[str]}
    """
    top_k_return = 3 if is_complex else 8
    context_str, sources = await retrieve_context_rag(
        user_message, is_complex=is_complex, top_k_return=top_k_return
    )
    logger.info(
        "RAG retrieved %d source(s); context length=%d (reranker=%s)",
        len(sources), len(context_str), is_complex,
    )

    if not context_str:
        logger.warning("RAG returned no context — falling back to plain LLM")
        return await _chat_plain(user_message, history, profile_context)

    profile_section = ""
    if profile_context:
        profile_section = f"--- User Health Profile ---\n{profile_context}"

    system = _RAG_MEDICAL_SYSTEM.format(
        context=context_str,
        profile_section=profile_section,
    )

    messages = [*history, {"role": "user", "content": user_message}]
    reply = await _call_groq(messages, system, temperature=0.2)

    return {"reply": reply.strip(), "sources": sources}


async def _chat_plain(
    user_message: str,
    history: list[dict],
    profile_context: str,
) -> dict:
    """Plain LLM chat without RAG (fallback when Qdrant returns nothing).
    Returns {"reply": str, "sources": []}
    """
    system = MEDICAL_ASSISTANT_SYSTEM
    if profile_context:
        system += f"\n\n--- User Health Profile ---\n{profile_context}"
    messages = [*history, {"role": "user", "content": user_message}]
    reply = await _call_groq(messages, system)
    return {"reply": reply.strip(), "sources": []}


async def chat_with_ai(
    user_message: str,
    history: list[dict],
    profile_context: str,
) -> dict:
    """Returns {"reply": str, "sources": list[str]}."""
    is_complex = await _route_query(user_message)
    return await _chat_with_rag(user_message, history, profile_context, is_complex=is_complex)


async def summarise_document(ocr_text: str) -> dict:
    messages = [{"role": "user", "content": f"Please analyse this medical document and respond in the required JSON format:\n\n{ocr_text}"}]
    raw = await _call_groq(messages, DOCUMENT_SUMMARY_SYSTEM, temperature=0.2)
    try:
        cleaned = raw.strip().removeprefix("```json").removeprefix("```").removesuffix("```").strip()
        data = json.loads(cleaned)
        # Ensure confidence_score is a clamped integer
        data["confidence_score"] = max(0, min(100, int(data.get("confidence_score", 70))))
        # Ensure key_findings is always a list
        if not isinstance(data.get("key_findings"), list):
            data["key_findings"] = [str(data.get("key_findings", ""))]
        return data
    except (json.JSONDecodeError, ValueError, TypeError):
        return {
            "document_type": "Unknown",
            "explanation": raw,
            "key_findings": [],
            "confidence_score": 50,
            "disclaimer": "This analysis is generated by AI for informational purposes only and is not a substitute for professional medical advice.",
        }


import re as _re


async def emotional_buddy_respond(user_text: str, history: list[dict] | None = None) -> tuple[str, int, str]:
    """Returns (buddy_reply_text, mood_score, emotion)."""
    messages = list(history or [])
    messages.append({"role": "user", "content": user_text})
    raw = await _call_groq(messages, EMOTIONAL_BUDDY_SYSTEM)

    reply = raw
    mood_score = 5
    emotion = "neutral"

    # The LLM sometimes puts text before the JSON — find the JSON block with regex
    json_match = _re.search(r"\{.*\}", raw, _re.DOTALL)
    if json_match:
        try:
            data = json.loads(json_match.group())
            reply = data.get("response") or raw
            mood_score = max(1, min(10, int(data.get("mood_score", 5))))
            emotion = data.get("emotion", "neutral").lower().strip()
            valid_emotions = {"happy", "sad", "angry", "fearful", "disgusted", "surprised", "neutral"}
            if emotion not in valid_emotions:
                emotion = "neutral"
        except (json.JSONDecodeError, ValueError):
            pass

    # If reply still contains raw JSON junk, take only text before the first '{'
    brace_pos = reply.find("{")
    if brace_pos > 10:
        reply = reply[:brace_pos].strip()

    return reply, mood_score, emotion
