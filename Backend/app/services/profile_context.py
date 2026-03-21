from app.database import get_supabase


async def build_profile_context(user_id: str) -> str:
    """Serialise user profile into a plain-text context string for the AI."""
    db = get_supabase()
    result = db.table("profiles").select("*").eq("user_id", user_id).execute()
    if not result.data:
        return ""

    p = result.data[0]
    lines = []

    # Personal info
    if p.get("full_name"):
        lines.append(f"Name: {p['full_name']}")
    if p.get("date_of_birth"):
        lines.append(f"Date of Birth: {p['date_of_birth']}")
    if p.get("biological_sex"):
        lines.append(f"Sex: {p['biological_sex']}")
    if p.get("height_cm") and p.get("weight_kg"):
        h = p["height_cm"] / 100
        bmi = round(p["weight_kg"] / (h * h), 1)
        lines.append(f"Height: {p['height_cm']} cm | Weight: {p['weight_kg']} kg | BMI: {bmi}")
    if p.get("blood_group"):
        lines.append(f"Blood Group: {p['blood_group']}")

    # Medical conditions
    if p.get("existing_conditions"):
        conds = [
            f"{c['condition_name']}" + (f" ({c.get('severity', '')})" if c.get("severity") else "")
            for c in p["existing_conditions"]
        ]
        lines.append(f"Existing Conditions: {', '.join(conds)}")

    # Allergies
    if p.get("allergies"):
        allergens = [
            f"{a['allergy_name']} ({a['allergy_type']})" + (f" — {a.get('severity', '')}" if a.get("severity") else "")
            for a in p["allergies"]
        ]
        lines.append(f"Allergies: {', '.join(allergens)}")

    # Medications
    if p.get("current_medications"):
        meds = [
            f"{m['medication_name']} {m.get('dosage', '')} {m.get('frequency', '')}"
            for m in p["current_medications"]
        ]
        lines.append(f"Current Medications: {'; '.join(meds)}")

    # Lifestyle
    if p.get("lifestyle"):
        ls = p["lifestyle"]
        ls_parts = []
        if ls.get("activity_level"):
            ls_parts.append(f"Activity: {ls['activity_level']}")
        if ls.get("dietary_preference"):
            ls_parts.append(f"Diet: {ls['dietary_preference']}")
        if ls.get("smoking_status"):
            ls_parts.append(f"Smoking: {ls['smoking_status']}")
        if ls.get("alcohol_consumption"):
            ls_parts.append(f"Alcohol: {ls['alcohol_consumption']}")
        if ls_parts:
            lines.append(f"Lifestyle: {' | '.join(ls_parts)}")

    # Mental health
    if p.get("mental_health"):
        mh = p["mental_health"]
        if mh.get("diagnosed_conditions"):
            lines.append(f"Mental Health Conditions: {mh['diagnosed_conditions']}")

    return "\n".join(lines)
