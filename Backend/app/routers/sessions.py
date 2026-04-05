import io
import uuid
import base64
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from pydantic import BaseModel
from typing import Optional, List
from app.database import get_supabase
from app.auth import get_current_user_id
from app.services.ocr import extract_text_from_file
from app.services.consultation_pdf_service import trigger_pdf_rebuild

router = APIRouter(prefix="/consultations/{consultation_id}/sessions", tags=["sessions"])

ALLOWED_TYPES = {"application/pdf", "image/jpeg", "image/png"}
MAX_FILE_SIZE = 2 * 1024 * 1024  # 2 MB


class SessionCreate(BaseModel):
    visit_date: str
    symptoms: Optional[str] = None
    diagnosis: Optional[str] = None
    medications: Optional[str] = None
    doctor_notes: Optional[str] = None


class SessionUpdate(BaseModel):
    visit_date: Optional[str] = None
    symptoms: Optional[str] = None
    diagnosis: Optional[str] = None
    medications: Optional[str] = None
    doctor_notes: Optional[str] = None


def _verify_consultation_owner(consultation_id: str, user_id: str):
    db = get_supabase()
    result = (
        db.table("consultations")
        .select("id")
        .eq("id", consultation_id)
        .eq("user_id", user_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="Consultation not found")


@router.get("/")
async def list_sessions(
    consultation_id: str,
    user_id: str = Depends(get_current_user_id),
):
    _verify_consultation_owner(consultation_id, user_id)
    db = get_supabase()
    result = (
        db.table("sessions")
        .select("*, session_documents(*)")
        .eq("consultation_id", consultation_id)
        .order("visit_date", desc=False)
        .execute()
    )
    return result.data or []


@router.post("/", status_code=status.HTTP_201_CREATED)
async def create_session(
    consultation_id: str,
    body: SessionCreate,
    user_id: str = Depends(get_current_user_id),
):
    _verify_consultation_owner(consultation_id, user_id)
    db = get_supabase()
    payload = body.model_dump(exclude_none=True)
    payload["consultation_id"] = consultation_id
    result = db.table("sessions").insert(payload).execute()
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create session")
    trigger_pdf_rebuild(consultation_id)
    return result.data[0]


@router.get("/{session_id}")
async def get_session(
    consultation_id: str,
    session_id: str,
    user_id: str = Depends(get_current_user_id),
):
    _verify_consultation_owner(consultation_id, user_id)
    db = get_supabase()
    result = (
        db.table("sessions")
        .select("*, session_documents(*)")
        .eq("id", session_id)
        .eq("consultation_id", consultation_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="Session not found")
    return result.data[0]


@router.patch("/{session_id}")
async def update_session(
    consultation_id: str,
    session_id: str,
    body: SessionUpdate,
    user_id: str = Depends(get_current_user_id),
):
    _verify_consultation_owner(consultation_id, user_id)
    db = get_supabase()
    payload = body.model_dump(exclude_none=True)
    if not payload:
        raise HTTPException(status_code=400, detail="No fields to update")
    result = (
        db.table("sessions")
        .update(payload)
        .eq("id", session_id)
        .eq("consultation_id", consultation_id)
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=404, detail="Session not found")
    trigger_pdf_rebuild(consultation_id)
    return result.data[0]


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_session(
    consultation_id: str,
    session_id: str,
    user_id: str = Depends(get_current_user_id),
):
    _verify_consultation_owner(consultation_id, user_id)
    db = get_supabase()
    db.table("sessions").delete().eq("id", session_id).eq("consultation_id", consultation_id).execute()
    trigger_pdf_rebuild(consultation_id)


@router.post("/{session_id}/documents", status_code=status.HTTP_201_CREATED)
async def upload_document(
    consultation_id: str,
    session_id: str,
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
):
    _verify_consultation_owner(consultation_id, user_id)

    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(status_code=400, detail="Only PDF, JPG, PNG allowed")

    contents = await file.read()
    if len(contents) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail="File exceeds 2 MB limit")

    db = get_supabase()
    ext = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else "bin"
    storage_path = f"{user_id}/{consultation_id}/{session_id}/{uuid.uuid4()}.{ext}"

    db.storage.from_("documents").upload(
        storage_path,
        contents,
        file_options={"content-type": file.content_type},
    )

    # Get public URL
    url_resp = db.storage.from_("documents").get_public_url(storage_path)
    public_url = url_resp if isinstance(url_resp, str) else url_resp.get("publicUrl", "")

    # OCR extraction (non-blocking best-effort)
    ocr_text = ""
    try:
        ocr_text = await extract_text_from_file(contents, file.content_type)
    except Exception:
        pass

    result = (
        db.table("session_documents")
        .insert(
            {
                "session_id": session_id,
                "file_name": file.filename,
                "storage_path": storage_path,
                "public_url": public_url,
                "content_type": file.content_type,
                "ocr_text": ocr_text,
            }
        )
        .execute()
    )

    trigger_pdf_rebuild(consultation_id)
    return result.data[0] if result.data else {"storage_path": storage_path}


@router.delete("/{session_id}/documents/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_document(
    consultation_id: str,
    session_id: str,
    document_id: str,
    user_id: str = Depends(get_current_user_id),
):
    _verify_consultation_owner(consultation_id, user_id)
    db = get_supabase()
    doc = db.table("session_documents").select("storage_path").eq("id", document_id).execute()
    if doc.data:
        db.storage.from_("documents").remove([doc.data[0]["storage_path"]])
    db.table("session_documents").delete().eq("id", document_id).execute()
    trigger_pdf_rebuild(consultation_id)
