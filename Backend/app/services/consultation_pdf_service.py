"""
Background PDF orchestration for Consultation Tracker.

Pipeline (triggered on every consultation/session/document mutation):

  trigger_pdf_rebuild(consultation_id)
      → marks consultations.pdf_status = 'processing'
      → fires asyncio background task: rebuild_consultation_pdf(consultation_id)

  rebuild_consultation_pdf(consultation_id)
      1. Fetch full consultation + sessions + documents from Supabase
      2. For each session:
           a. Generate AI summary (or reuse cached one from sessions.ai_summary)
           b. Fetch every document and convert to PNG image pages
      3. Build PDF via pdf_export.generate_consultation_pdf (with enriched data)
      4. Upload PDF to Supabase Storage: pdfs/{consultation_id}/report.pdf
      5. Mark consultations.pdf_status = 'ready', pdf_path = <storage path>

  On any failure: marks pdf_status = 'none' so export falls back to on-demand generation.
"""
from __future__ import annotations

import asyncio
import io
import logging
import threading

from app.database import get_supabase
from app.services.pdf_export import generate_consultation_pdf
from app.services.ai import generate_session_summary

logger = logging.getLogger(__name__)

_PDF_BUCKET = "pdfs"


def _pdf_storage_path(consultation_id: str) -> str:
    return f"{consultation_id}/report.pdf"


# ── Document → image pages ────────────────────────────────────────────────────

async def _fetch_document_images(doc: dict) -> list[bytes]:
    """Download a document from Supabase Storage (service-role) and return PNG image bytes per page.

    - Images (jpg/png) → returned as-is (single-element list)
    - PDFs            → each page rendered to PNG via PyMuPDF
    - Returns []      on any failure (graceful degradation)
    """
    storage_path = doc.get("storage_path") or ""
    content_type = doc.get("content_type") or ""
    name = doc.get("file_name") or ""

    if not storage_path:
        return []

    try:
        db = get_supabase()
        file_bytes: bytes = db.storage.from_("documents").download(storage_path)
    except Exception as exc:
        logger.warning("Could not download document '%s' (path: %s): %s", name, storage_path, exc)
        return []

    # Images — return directly
    is_image = content_type in ("image/jpeg", "image/png") or \
               name.lower().endswith((".jpg", ".jpeg", ".png"))
    if is_image:
        return [file_bytes]

    # PDFs — render each page to PNG using PyMuPDF
    is_pdf = content_type == "application/pdf" or name.lower().endswith(".pdf")
    if is_pdf:
        try:
            import fitz  # PyMuPDF
            pdf_doc = fitz.open(stream=file_bytes, filetype="pdf")
            pages: list[bytes] = []
            for page in pdf_doc:
                mat = fitz.Matrix(1.5, 1.5)   # ~108 DPI — clear without being huge
                pix = page.get_pixmap(matrix=mat, alpha=False)
                pages.append(pix.tobytes("png"))
            pdf_doc.close()
            logger.info(
                "Converted PDF '%s' to %d image page(s)", name, len(pages)
            )
            return pages
        except Exception as exc:
            logger.warning("PDF→image conversion failed for '%s': %s", name, exc)
            return []

    return []


# ── AI summary (with DB caching) ──────────────────────────────────────────────

async def _get_or_generate_summary(session: dict) -> dict | None:
    """Return the cached ai_summary from the session row, or generate and persist one."""
    existing = session.get("ai_summary")
    if existing and isinstance(existing, dict):
        logger.debug("Using cached AI summary for session %s", session.get("id"))
        return existing

    try:
        summary = await generate_session_summary(session)
    except Exception as exc:
        logger.warning(
            "AI summary generation failed for session %s: %s",
            session.get("id"), exc,
        )
        return None

    # Persist back so we don't regenerate next time
    try:
        get_supabase().table("sessions") \
            .update({"ai_summary": summary}) \
            .eq("id", session["id"]) \
            .execute()
    except Exception as exc:
        logger.warning(
            "Could not persist ai_summary for session %s: %s",
            session.get("id"), exc,
        )

    return summary


# ── Full rebuild ──────────────────────────────────────────────────────────────

async def rebuild_consultation_pdf(consultation_id: str) -> None:
    """Build (or rebuild) the pre-computed PDF and upload it to Supabase Storage.
    Always runs in the background — never called from the hot path.
    """
    logger.info("PDF rebuild started for consultation %s", consultation_id)
    db = get_supabase()

    try:
        # 1. Fetch consultation
        cons_res = db.table("consultations").select("*").eq("id", consultation_id).execute()
        if not cons_res.data:
            logger.warning("PDF rebuild: consultation %s not found — aborting", consultation_id)
            return
        consultation = cons_res.data[0]

        # 2. Fetch sessions + documents
        sessions_res = (
            db.table("sessions")
            .select("*, session_documents(*)")
            .eq("consultation_id", consultation_id)
            .order("visit_date", desc=False)
            .execute()
        )
        sessions = sessions_res.data or []

        # 3. Enrich each session sequentially (AI summary + document images)
        enriched_sessions: list[dict] = []
        for session in sessions:
            # 3a. AI summary
            ai_summary = await _get_or_generate_summary(session)

            # 3b. Document images
            enriched_docs: list[dict] = []
            for doc in (session.get("session_documents") or []):
                image_pages = await _fetch_document_images(doc)
                enriched_docs.append({**doc, "image_pages": image_pages})

            enriched_sessions.append({
                **session,
                "ai_summary": ai_summary,
                "session_documents": enriched_docs,
            })

        # 4. Generate PDF bytes
        pdf_bytes = await generate_consultation_pdf(consultation, enriched_sessions)
        logger.info(
            "PDF generated for consultation %s: %d bytes, %d session(s)",
            consultation_id, len(pdf_bytes), len(enriched_sessions),
        )

        # 5. Upload to Supabase Storage (overwrite)
        path = _pdf_storage_path(consultation_id)
        try:
            db.storage.from_(_PDF_BUCKET).upload(
                path,
                pdf_bytes,
                file_options={"content-type": "application/pdf", "upsert": "true"},
            )
        except Exception:
            # Some Supabase versions don't support upsert flag — remove then re-upload
            try:
                db.storage.from_(_PDF_BUCKET).remove([path])
            except Exception:
                pass
            db.storage.from_(_PDF_BUCKET).upload(
                path,
                pdf_bytes,
                file_options={"content-type": "application/pdf"},
            )

        # 6. Get public URL
        url_resp = db.storage.from_(_PDF_BUCKET).get_public_url(path)
        pdf_url = url_resp if isinstance(url_resp, str) else url_resp.get("publicUrl", "")

        # 7. Mark consultation as ready
        db.table("consultations").update({
            "pdf_status": "ready",
            "pdf_path": path,
        }).eq("id", consultation_id).execute()

        logger.info(
            "PDF rebuild complete for consultation %s → %s", consultation_id, pdf_url
        )

    except Exception as exc:
        logger.error(
            "PDF rebuild FAILED for consultation %s: %s",
            consultation_id, exc, exc_info=True,
        )
        # Reset status so export falls back to on-demand generation
        try:
            db.table("consultations").update({"pdf_status": "none"}) \
                .eq("id", consultation_id).execute()
        except Exception:
            pass


# ── Public trigger ────────────────────────────────────────────────────────────

def trigger_pdf_rebuild(consultation_id: str) -> None:
    """Non-blocking entry point.

    Marks pdf_status='processing' synchronously, then schedules
    rebuild_consultation_pdf as an asyncio task (or thread fallback).
    Safe to call from any async FastAPI handler.
    """
    # Mark as processing so export endpoint can inform the user
    try:
        get_supabase().table("consultations") \
            .update({"pdf_status": "processing"}) \
            .eq("id", consultation_id) \
            .execute()
    except Exception as exc:
        logger.warning(
            "Could not set pdf_status=processing for %s: %s",
            consultation_id, exc,
        )

    # Schedule the rebuild
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            loop.create_task(rebuild_consultation_pdf(consultation_id))
        else:
            threading.Thread(
                target=asyncio.run,
                args=(rebuild_consultation_pdf(consultation_id),),
                daemon=True,
            ).start()
    except Exception as exc:
        logger.warning(
            "Could not schedule PDF rebuild task for %s: %s",
            consultation_id, exc,
        )
