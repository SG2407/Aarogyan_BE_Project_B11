from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from typing import Optional, List
from app.database import get_supabase
from app.auth import get_current_user_id

router = APIRouter(prefix="/profile", tags=["profile"])


# ─── Nested models ────────────────────────────────────────────────────────────

class ExistingCondition(BaseModel):
    condition_name: str
    severity: Optional[str] = None
    diagnosed_year: Optional[int] = None


class Allergy(BaseModel):
    allergy_type: str
    allergy_name: str
    reaction: Optional[str] = None
    severity: Optional[str] = None


class Medication(BaseModel):
    medication_name: str
    dosage: str
    frequency: str
    route: Optional[str] = None
    prescribed_for: Optional[str] = None


class Supplement(BaseModel):
    supplement_name: str
    dosage: Optional[str] = None
    frequency: Optional[str] = None
    type: Optional[str] = None


class PastHistory(BaseModel):
    history_type: str
    description: str
    approximate_year: Optional[int] = None
    notes: Optional[str] = None


class FamilyHistory(BaseModel):
    condition_name: str
    relation: str


class Lifestyle(BaseModel):
    activity_level: Optional[str] = None
    exercise_type: Optional[str] = None
    exercise_frequency: Optional[str] = None
    dietary_preference: Optional[str] = None
    dietary_restrictions: Optional[str] = None
    eating_pattern: Optional[str] = None
    avg_sleep_hours: Optional[float] = None
    sleep_issues: Optional[str] = None
    smoking_status: Optional[str] = None
    smoking_frequency: Optional[str] = None
    alcohol_consumption: Optional[str] = None
    tobacco_use: Optional[bool] = None
    stress_level: Optional[str] = None


class MentalHealth(BaseModel):
    diagnosed_conditions: Optional[str] = None
    current_medications: Optional[str] = None
    in_therapy: Optional[bool] = None


# ─── Full profile model ────────────────────────────────────────────────────────

class ProfileUpsertRequest(BaseModel):
    # Section 1 personal
    full_name: Optional[str] = None
    date_of_birth: Optional[str] = None
    biological_sex: Optional[str] = None
    height_cm: Optional[float] = None
    weight_kg: Optional[float] = None
    blood_group: Optional[str] = None
    city: Optional[str] = None
    region_state: Optional[str] = None
    preferred_language: Optional[str] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    # Sections 2–9 as JSON lists / objects
    existing_conditions: Optional[List[ExistingCondition]] = None
    allergies: Optional[List[Allergy]] = None
    current_medications: Optional[List[Medication]] = None
    supplements: Optional[List[Supplement]] = None
    past_medical_history: Optional[List[PastHistory]] = None
    family_medical_history: Optional[List[FamilyHistory]] = None
    lifestyle: Optional[Lifestyle] = None
    mental_health: Optional[MentalHealth] = None


@router.get("/me")
async def get_profile(user_id: str = Depends(get_current_user_id)):
    db = get_supabase()
    result = db.table("profiles").select("*").eq("user_id", user_id).execute()
    if not result.data:
        return {}
    return result.data[0]


@router.put("/me")
async def upsert_profile(
    body: ProfileUpsertRequest,
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()
    payload = body.model_dump(exclude_none=True)
    payload["user_id"] = user_id

    # Serialise list/object fields to dict for JSONB
    for key in [
        "existing_conditions", "allergies", "current_medications",
        "supplements", "past_medical_history", "family_medical_history",
        "lifestyle", "mental_health",
    ]:
        if key in payload and payload[key] is not None:
            if isinstance(payload[key], list):
                payload[key] = [
                    item.model_dump() if hasattr(item, "model_dump") else item
                    for item in payload[key]
                ]
            elif hasattr(payload[key], "model_dump"):
                payload[key] = payload[key].model_dump()

    # Upsert
    result = (
        db.table("profiles")
        .upsert(payload, on_conflict="user_id")
        .execute()
    )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to save profile",
        )
    return result.data[0]
