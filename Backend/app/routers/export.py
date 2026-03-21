from fastapi import APIRouter, Depends, HTTPException
from app.auth import get_current_user_id
from app.database import get_supabase
from app.services.pdf_export import generate_consultation_pdf
from fastapi.responses import StreamingResponse
import io

router = APIRouter(prefix="/export", tags=["export"])


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

    # Fetch sessions + documents
    sessions = (
        db.table("sessions")
        .select("*, session_documents(*)")
        .eq("consultation_id", consultation_id)
        .order("visit_date", desc=False)
        .execute()
    )

    pdf_bytes = await generate_consultation_pdf(cons.data[0], sessions.data or [])

    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="consultation_{consultation_id}.pdf"'
        },
    )
