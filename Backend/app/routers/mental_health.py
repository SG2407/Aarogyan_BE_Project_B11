from fastapi import APIRouter, Depends, Query
from app.auth import get_current_user_id
from app.database import get_supabase
from collections import defaultdict
from datetime import datetime, timedelta, timezone
import json

router = APIRouter(prefix="/mental-health", tags=["mental-health-tracker"])

_ALL_EMOTIONS = ["happy", "sad", "angry", "neutral"]


@router.get("/dashboard")
async def get_dashboard(
    days: int = Query(30, description="Days to look back. 0 = all time."),
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()

    # ── Latest session (always from all-time, for the hero card) ──────────────
    latest_result = (
        db.table("emotional_sessions")
        .select("id, mood_score, emotion, emotion_probs, session_group_id, created_at, buddy_text, user_text")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    )
    latest_session = latest_result.data[0] if latest_result.data else None

    # ── Filtered sessions for charts ──────────────────────────────────────────
    query = (
        db.table("emotional_sessions")
        .select("id, mood_score, emotion, emotion_probs, session_group_id, created_at")
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

    # Group by session_group_id for per-conversation analytics
    session_groups: dict[str, list[dict]] = defaultdict(list)

    for s in sessions:
        dt = datetime.fromisoformat(s["created_at"].replace("Z", "+00:00"))
        day_key = dt.strftime("%Y-%m-%d")

        # Determine emotion from ML probs (4-label) if available, else fall back
        ep = s.get("emotion_probs")
        if ep:
            if isinstance(ep, str):
                try:
                    ep = json.loads(ep)
                except (json.JSONDecodeError, ValueError):
                    ep = None

        if ep and isinstance(ep, dict):
            emotion = max(_ALL_EMOTIONS, key=lambda k: ep.get(k, 0.0))
        else:
            raw_emotion = (s.get("emotion") or "neutral").lower().strip()
            # Map 7→4 labels
            emotion_map = {"fearful": "sad", "disgusted": "angry", "surprised": "happy"}
            emotion = emotion_map.get(raw_emotion, raw_emotion)
            if emotion not in emotion_counts:
                emotion = "neutral"

        emotion_counts[emotion] = emotion_counts.get(emotion, 0) + 1

        # Track session groups
        gid = s.get("session_group_id")
        if gid:
            session_groups[gid].append(s)

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

    # ── Per-conversation session summaries ────────────────────────────────────
    from app.services.session_analytics import analyze_session

    conversation_sessions: list[dict] = []
    for gid, msgs in sorted(session_groups.items(), key=lambda x: x[1][0]["created_at"], reverse=True):
        probs_list = []
        for m in msgs:
            ep = m.get("emotion_probs")
            if ep:
                if isinstance(ep, str):
                    try:
                        ep = json.loads(ep)
                    except (json.JSONDecodeError, ValueError):
                        continue
                probs_list.append(ep)
        if not probs_list:
            continue
        analytics = analyze_session(probs_list)
        mood_vals = [float(m["mood_score"]) for m in msgs if m.get("mood_score") is not None]
        conversation_sessions.append({
            "session_group_id": gid,
            "message_count": len(msgs),
            "dominant_emotion": analytics["dominant_emotion"],
            "stability_score": analytics["stability_score"],
            "insight_summary": analytics["insight_summary"],
            "average_mood": round(sum(mood_vals) / len(mood_vals), 1) if mood_vals else 0.0,
            "started_at": msgs[0]["created_at"],
        })

    # Determine overall dominant emotion from the ML-based distribution
    total_emotion_count = sum(emotion_counts.values())
    if total_emotion_count > 0:
        overall_dominant = max(emotion_counts, key=lambda k: emotion_counts[k])
    else:
        overall_dominant = "neutral"

    return {
        "total_sessions": len(sessions),
        "average_mood_overall": avg(all_scores) or 0.0,
        "latest_session": latest_session,
        "emotion_distribution": emotion_counts,
        "dominant_emotion": overall_dominant,
        "conversation_sessions": conversation_sessions[:20],  # last 20 conversations
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
