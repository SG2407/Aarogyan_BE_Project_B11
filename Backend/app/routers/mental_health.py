from fastapi import APIRouter, Depends, Query
from app.auth import get_current_user_id
from app.database import get_supabase
from collections import defaultdict
from datetime import datetime, timedelta, timezone

router = APIRouter(prefix="/mental-health", tags=["mental-health-tracker"])

_ALL_EMOTIONS = ["happy", "sad", "angry", "fearful", "disgusted", "surprised", "neutral"]


@router.get("/dashboard")
async def get_dashboard(
    days: int = Query(30, description="Days to look back. 0 = all time."),
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()

    # ── Latest session (always from all-time, for the hero card) ──────────────
    latest_result = (
        db.table("emotional_sessions")
        .select("id, mood_score, emotion, created_at, buddy_text, user_text")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    )
    latest_session = latest_result.data[0] if latest_result.data else None

    # ── Filtered sessions for charts ──────────────────────────────────────────
    query = (
        db.table("emotional_sessions")
        .select("id, mood_score, emotion, created_at")
        .eq("user_id", user_id)
        .order("created_at", desc=False)
    )
    if days > 0:
        cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
        query = query.gte("created_at", cutoff)

    result = query.execute()
    sessions = result.data or []

    # ── Aggregation ───────────────────────────────────────────────────────────
    daily_scores: dict[str, list[float]] = defaultdict(list)
    daily_counts: dict[str, int] = defaultdict(int)
    weekly: dict[str, list[float]] = defaultdict(list)
    monthly: dict[str, list[float]] = defaultdict(list)
    emotion_counts: dict[str, int] = {e: 0 for e in _ALL_EMOTIONS}

    for s in sessions:
        dt = datetime.fromisoformat(s["created_at"].replace("Z", "+00:00"))
        day_key = dt.strftime("%Y-%m-%d")

        # Count emotion for every session regardless of mood_score
        emotion = (s.get("emotion") or "neutral").lower().strip()
        if emotion in emotion_counts:
            emotion_counts[emotion] += 1
        else:
            emotion_counts["neutral"] += 1

        # Mood aggregation only for sessions with a valid score
        if s.get("mood_score") is None:
            continue
        score = float(s["mood_score"])
        daily_scores[day_key].append(score)
        daily_counts[day_key] += 1
        weekly[dt.strftime("%Y-W%W")].append(score)
        monthly[dt.strftime("%Y-%m")].append(score)

    def avg(lst): return round(sum(lst) / len(lst), 2) if lst else None

    all_scores = [float(s["mood_score"]) for s in sessions if s.get("mood_score") is not None]

    return {
        "total_sessions": len(sessions),
        "average_mood_overall": avg(all_scores) or 0.0,
        "latest_session": latest_session,
        "emotion_distribution": emotion_counts,
        "daily": [
            {"date": k, "average_mood": avg(v), "session_count": daily_counts[k]}
            for k, v in sorted(daily_scores.items())
        ],
        "weekly": [{"week": k, "average_mood": avg(v)} for k, v in sorted(weekly.items())],
        "monthly": [{"month": k, "average_mood": avg(v)} for k, v in sorted(monthly.items())],
        "heatmap": [
            {"date": k, "mood": avg(v), "count": daily_counts[k]}
            for k, v in sorted(daily_scores.items())
        ],
    }
