from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from typing import Optional, List
from app.database import get_supabase
from app.auth import get_current_user_id
from app.services.ai import chat_with_ai
from app.services.profile_context import build_profile_context

router = APIRouter(prefix="/assistant", tags=["medical-assistant"])


class MessageIn(BaseModel):
    role: str  # "user" or "assistant"
    content: str


class ChatRequest(BaseModel):
    conversation_id: Optional[str] = None
    message: str


class ConversationCreate(BaseModel):
    title: Optional[str] = None


@router.get("/conversations")
async def list_conversations(user_id: str = Depends(get_current_user_id)):
    db = get_supabase()
    result = (
        db.table("conversations")
        .select("id, title, created_at, updated_at, preview")
        .eq("user_id", user_id)
        .order("updated_at", desc=True)
        .execute()
    )
    return result.data or []


@router.post("/conversations", status_code=status.HTTP_201_CREATED)
async def create_conversation(
    body: ConversationCreate,
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()
    result = (
        db.table("conversations")
        .insert({"user_id": user_id, "title": body.title or "New Conversation"})
        .execute()
    )
    if not result.data:
        raise HTTPException(status_code=500, detail="Failed to create conversation")
    return result.data[0]


@router.get("/conversations/{conversation_id}")
async def get_conversation(
    conversation_id: str,
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()
    conv = (
        db.table("conversations")
        .select("*")
        .eq("id", conversation_id)
        .eq("user_id", user_id)
        .execute()
    )
    if not conv.data:
        raise HTTPException(status_code=404, detail="Conversation not found")

    msgs = (
        db.table("messages")
        .select("*")
        .eq("conversation_id", conversation_id)
        .order("created_at", desc=False)
        .execute()
    )
    return {**conv.data[0], "messages": msgs.data or []}


@router.delete("/conversations/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_conversation(
    conversation_id: str,
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()
    db.table("conversations").delete().eq("id", conversation_id).eq("user_id", user_id).execute()


@router.post("/chat")
async def chat(
    body: ChatRequest,
    user_id: str = Depends(get_current_user_id),
):
    db = get_supabase()

    # Resolve or create conversation
    if body.conversation_id:
        conv = (
            db.table("conversations")
            .select("id")
            .eq("id", body.conversation_id)
            .eq("user_id", user_id)
            .execute()
        )
        if not conv.data:
            raise HTTPException(status_code=404, detail="Conversation not found")
        conversation_id = body.conversation_id
    else:
        new_conv = (
            db.table("conversations")
            .insert({"user_id": user_id, "title": "New Conversation"})
            .execute()
        )
        conversation_id = new_conv.data[0]["id"]

    # Fetch message history
    history_result = (
        db.table("messages")
        .select("role, content")
        .eq("conversation_id", conversation_id)
        .order("created_at", desc=False)
        .execute()
    )
    history = history_result.data or []

    # Build AI context
    profile_context = await build_profile_context(user_id)

    # Save user message
    db.table("messages").insert(
        {"conversation_id": conversation_id, "role": "user", "content": body.message}
    ).execute()

    # Call AI
    ai_reply = await chat_with_ai(
        user_message=body.message,
        history=history,
        profile_context=profile_context,
    )

    # Save assistant message
    db.table("messages").insert(
        {"conversation_id": conversation_id, "role": "assistant", "content": ai_reply}
    ).execute()

    # Update conversation preview and title
    preview = body.message[:80]
    title_update: dict = {"preview": preview, "updated_at": "now()"}
    # Auto-title from first message if title is still default
    conv_data = (
        db.table("conversations").select("title").eq("id", conversation_id).execute()
    )
    if conv_data.data and conv_data.data[0]["title"] == "New Conversation":
        title_update["title"] = body.message[:50]

    db.table("conversations").update(title_update).eq("id", conversation_id).execute()

    return {
        "conversation_id": conversation_id,
        "reply": ai_reply,
    }
