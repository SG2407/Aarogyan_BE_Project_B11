from fastapi import APIRouter, Depends
from app.auth import get_current_user_id
from app.database import get_supabase
from collections import defaultdict
from datetime import datetime, timedelta

router = APIRouter(prefix="/mental-health", tags=["mental-health-tracker"])


@router.get("/dashboard")
async def get_dashboard(user_id: str = Depends(get_current_user_id)):
    db = get_supabase()
    result = (
        db.table("emotional_sessions")
        .select("id, mood_score, created_at, buddy_text, user_text")
        .eq("user_id", user_id)
        .order("created_at", desc=False)
        .execute()
    )
    sessions = result.data or []

    # Build weekly and monthly aggregates
    weekly: dict[str, list[float]] = defaultdict(list)
    monthly: dict[str, list[float]] = defaultdict(list)
    daily: dict[str, list[float]] = defaultdict(list)

    for s in sessions:
        if s.get("mood_score") is None:
            continue
        dt = datetime.fromisoformat(s["created_at"].replace("Z", "+00:00"))
        day_key = dt.strftime("%Y-%m-%d")
        week_key = dt.strftime("%Y-W%W")
        month_key = dt.strftime("%Y-%m")
        score = float(s["mood_score"])
        daily[day_key].append(score)
        weekly[week_key].append(score)
        monthly[month_key].append(score)

    def avg(lst): return round(sum(lst) / len(lst), 2) if lst else None

    return {
        "daily_averages": {k: avg(v) for k, v in sorted(daily.items())},
        "weekly_averages": {k: avg(v) for k, v in sorted(weekly.items())},
        "monthly_averages": {k: avg(v) for k, v in sorted(monthly.items())},
        "total_sessions": len(sessions),
        "recent_sessions": sessions[-10:],
    }
