from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from typing import Optional
from datetime import date as DateType
from app.database import get_supabase
from app.auth import get_current_user_id
from app.services.consultation_pdf_service import trigger_pdf_rebuild

router = APIRouter(prefix="/consultations", tags=["consultations"])


class ConsultationCreate(BaseModel):
    name: str
    start_date: Optional[str] = None
    notes: Optional[str] = None


class ConsultationUpdate(BaseModel):
    name: Optional[str] = None
    start_date: Optional[str] = None
    notes: Optional[str] = None


@router.get("/")
async def list_consultations(user_id: str = Depends(get_current_user_id)):
    db = get_supabase()
    result = (
        db.table("consultations")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )
    return result.data or []


@router.post("/", status_code=status.HTTP_201_CREATED)
async def create_consultation(
    body: ConsultationCreate,
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()
    payload = body.model_dump(exclude_none=True)
    payload["user_id"] = user_id
    result = db.table("consultations").insert(payload).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create consultation")
    return result.data[0]


@router.get("/{consultation_id}")
async def get_consultation(
    consultation_id: str,
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()
    result = (
        db.table("consultations")
        .select("*")
        .eq("id", consultation_id)
        .eq("user_id", user_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="Consultation not found")
    return result.data[0]


@router.patch("/{consultation_id}")
async def update_consultation(
    consultation_id: str,
    body: ConsultationUpdate,
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()
    payload = body.model_dump(exclude_none=True)
    if not payload:
        raise HTTPException(status_code=400, detail="No fields to update")
    result = (
        db.table("consultations")
        .update(payload)
        .eq("id", consultation_id)
        .eq("user_id", user_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="Consultation not found")
    trigger_pdf_rebuild(consultation_id)
    return result.data[0]


@router.delete("/{consultation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_consultation(
    consultation_id: str,
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()
    # Clean up pre-built PDF from storage before deleting the record
    try:
        db.storage.from_("pdfs").remove([f"{consultation_id}/report.pdf"])
    except Exception:
        pass
    db.table("consultations").delete().eq("id", consultation_id).eq("user_id", user_id).execute()
