import io
import logging

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse

from app.auth import get_current_user_id
from app.database import get_supabase
from app.services.pdf_export import generate_consultation_pdf

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/export", tags=["export"])

_PDF_BUCKET = "pdfs"


@router.get("/consultation/{consultation_id}/pdf")
async def export_consultation_pdf(
    consultation_id: str,
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()

    # Verify ownership
    cons = (
        db.table("consultations")
        .select("*")
        .eq("id", consultation_id)
        .eq("user_id", user_id)
        .execute()
    )
    if not cons.data:
        raise HTTPException(status_code=404, detail="Consultation not found")

    consultation = cons.data[0]

    # ── Try to serve pre-built PDF from storage ──────────────────────────────
    if consultation.get("pdf_status") == "ready" and consultation.get("pdf_path"):
        try:
            pdf_bytes = db.storage.from_(_PDF_BUCKET).download(consultation["pdf_path"])
            return StreamingResponse(
                io.BytesIO(pdf_bytes),
                media_type="application/pdf",
                headers={
                    "Content-Disposition": (
                        f'attachment; filename="consultation_{consultation_id}.pdf"'
                    )
                },
            )
        except Exception as e:
            logger.warning(
                "Pre-built PDF unavailable for %s, falling back to on-demand: %s",
                consultation_id,
                e,
            )

    # ── On-demand fallback ───────────────────────────────────────────────────
    sessions = (
        db.table("sessions")
        .select("*, session_documents(*)")
        .eq("consultation_id", consultation_id)
        .order("visit_date", desc=False)
        .execute()
    )

    pdf_bytes = await generate_consultation_pdf(consultation, sessions.data or [])

    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="consultation_{consultation_id}.pdf"'
        },
    )
