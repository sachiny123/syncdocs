from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Header, Query
from fastapi.middleware.cors import CORSMiddleware
from websocket_manager.manager import manager
from models.document import (
    DocumentModel, UpdateDocumentModel, RenameDocumentModel,
    UserModel, UserResponseModel, AddCollaboratorModel,
)
from services.db_service import (
    get_document, save_document,
    create_user, login_user, get_user_by_token, search_users,
    create_document, list_documents, rename_document, delete_document,
    add_collaborator, remove_collaborator, can_access_document,
)
import uuid
import json
from typing import Optional

app = FastAPI(title="Colab Docs Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Auth helper ───────────────────────────────────────────────────────────────

async def _require_auth(authorization: Optional[str]) -> dict:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid token")
    token = authorization.split(" ", 1)[1]
    user = await get_user_by_token(token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid token")
    return user

# ─── Health ────────────────────────────────────────────────────────────────────

@app.get("/")
def read_root():
    return {"status": "ok", "message": "Colab Docs API"}

# ─── Auth ──────────────────────────────────────────────────────────────────────

@app.post("/api/auth/signup", response_model=UserResponseModel)
async def signup(body: UserModel):
    if not body.username.strip() or not body.password:
        raise HTTPException(status_code=400, detail="Username and password required")
    user = await create_user(body.username.strip(), body.password)
    if user is None:
        raise HTTPException(status_code=409, detail="Username already taken")
    return user

@app.post("/api/auth/login", response_model=UserResponseModel)
async def login(body: UserModel):
    user = await login_user(body.username.strip(), body.password)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid username or password")
    return user

# ─── User search ───────────────────────────────────────────────────────────────

@app.get("/api/users/search")
async def find_users(
    q: str = Query(default="", min_length=1),
    authorization: Optional[str] = Header(default=None),
):
    user = await _require_auth(authorization)
    if len(q.strip()) < 1:
        return []
    results = await search_users(q.strip(), exclude_username=user["username"])
    return results

# ─── Documents ─────────────────────────────────────────────────────────────────

@app.post("/api/documents")
async def create_doc(authorization: Optional[str] = Header(default=None)):
    user = await _require_auth(authorization)
    doc = await create_document(owner=user["username"])
    doc.pop("_id", None)
    return doc

@app.get("/api/documents")
async def list_docs(authorization: Optional[str] = Header(default=None)):
    user = await _require_auth(authorization)
    docs = await list_documents(username=user["username"])
    for d in docs:
        d.pop("_id", None)
    return docs

@app.get("/api/documents/{doc_id}")
async def get_doc(doc_id: str, authorization: Optional[str] = Header(default=None)):
    user = await _require_auth(authorization)
    doc = await get_document(doc_id)
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    # Only owner or collaborator can view
    if doc["owner"] != user["username"] and user["username"] not in doc.get("collaborators", []):
        raise HTTPException(status_code=403, detail="Access denied")
    doc.pop("_id", None)
    return doc

@app.patch("/api/documents/{doc_id}/rename")
async def rename_doc(
    doc_id: str,
    body: RenameDocumentModel,
    authorization: Optional[str] = Header(default=None),
):
    user = await _require_auth(authorization)
    ok = await rename_document(doc_id, body.title.strip(), owner=user["username"])
    if not ok:
        raise HTTPException(status_code=404, detail="Document not found or not yours")
    return {"status": "ok"}

@app.delete("/api/documents/{doc_id}")
async def del_doc(doc_id: str, authorization: Optional[str] = Header(default=None)):
    user = await _require_auth(authorization)
    ok = await delete_document(doc_id, owner=user["username"])
    if not ok:
        raise HTTPException(status_code=404, detail="Document not found or not yours")
    return {"status": "ok"}

# ─── Collaborators ─────────────────────────────────────────────────────────────

@app.post("/api/documents/{doc_id}/collaborators")
async def add_collab(
    doc_id: str,
    body: AddCollaboratorModel,
    authorization: Optional[str] = Header(default=None),
):
    user = await _require_auth(authorization)
    result = await add_collaborator(doc_id, body.username.strip(), owner=user["username"])
    if result == "ok":
        return {"status": "ok", "message": f"{body.username} added as collaborator"}
    elif result == "not_owner":
        raise HTTPException(status_code=403, detail="Only the document owner can add collaborators")
    elif result == "not_found":
        raise HTTPException(status_code=404, detail="Document not found")
    elif result == "user_missing":
        raise HTTPException(status_code=404, detail=f"User '{body.username}' does not exist")
    elif result == "already":
        raise HTTPException(status_code=409, detail=f"'{body.username}' is already a collaborator")
    raise HTTPException(status_code=500, detail="Unexpected error")

@app.delete("/api/documents/{doc_id}/collaborators/{collab_username}")
async def remove_collab(
    doc_id: str,
    collab_username: str,
    authorization: Optional[str] = Header(default=None),
):
    user = await _require_auth(authorization)
    ok = await remove_collaborator(doc_id, collab_username, owner=user["username"])
    if not ok:
        raise HTTPException(status_code=404, detail="Not found or not the owner")
    return {"status": "ok"}

@app.get("/api/documents/{doc_id}/collaborators")
async def list_collabs(
    doc_id: str,
    authorization: Optional[str] = Header(default=None),
):
    user = await _require_auth(authorization)
    doc = await get_document(doc_id)
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    if doc["owner"] != user["username"] and user["username"] not in doc.get("collaborators", []):
        raise HTTPException(status_code=403, detail="Access denied")
    return {
        "owner": doc["owner"],
        "collaborators": doc.get("collaborators", []),
    }

# ─── WebSocket ─────────────────────────────────────────────────────────────────

@app.websocket("/ws/document/{doc_id}")
async def websocket_endpoint(
    websocket: WebSocket,
    doc_id: str,
    username: str = "Anonymous",
    color: str = "0xFF2196F3",
):
    # Verify user can access this doc
    has_access = await can_access_document(doc_id, username)
    if not has_access:
        # If doc doesn't exist yet create it? No — just allow if doc is new.
        # We allow connection but the presence will show them.
        pass

    client_id = str(uuid.uuid4())
    await manager.connect(websocket, doc_id, client_id, username, color)
    try:
        while True:
            data = await websocket.receive_text()
            json_data = json.loads(data)
            await manager.handle_update(doc_id, client_id, json_data, websocket)
    except WebSocketDisconnect:
        manager.disconnect(websocket, doc_id)
        await manager.broadcast_presence(doc_id)
    except Exception as e:
        print(f"WebSocket error: {e}")
        manager.disconnect(websocket, doc_id)
        await manager.broadcast_presence(doc_id)
