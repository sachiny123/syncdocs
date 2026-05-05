from motor.motor_asyncio import AsyncIOMotorClient
import os
from datetime import datetime
import hashlib
import uuid

MONGO_URL = os.getenv("MONGO_URL", "mongodb://localhost:27017")
client = AsyncIOMotorClient(MONGO_URL)
db = client.colab_docs
documents_collection = db.get_collection("documents")
history_collection = db.get_collection("document_history")
users_collection = db.get_collection("users")

def _hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

# ─── User Auth ─────────────────────────────────────────────────────────────────

async def create_user(username: str, password: str) -> dict | None:
    existing = await users_collection.find_one({"username": username})
    if existing:
        return None
    token = str(uuid.uuid4())
    user = {
        "username": username,
        "password_hash": _hash_password(password),
        "token": token,
        "created_at": datetime.utcnow(),
    }
    await users_collection.insert_one(user)
    return {"username": username, "token": token}

async def login_user(username: str, password: str) -> dict | None:
    user = await users_collection.find_one({"username": username})
    if not user:
        return None
    if user["password_hash"] != _hash_password(password):
        return None
    return {"username": username, "token": user["token"]}

async def get_user_by_token(token: str) -> dict | None:
    return await users_collection.find_one({"token": token}, {"_id": 0, "password_hash": 0})

async def search_users(query: str, exclude_username: str) -> list:
    """Search users by prefix, excluding the caller."""
    cursor = users_collection.find(
        {
            "username": {"$regex": f"^{query}", "$options": "i"},
            "username": {"$ne": exclude_username},
        },
        {"_id": 0, "username": 1}
    ).limit(10)
    return await cursor.to_list(length=10)

async def user_exists(username: str) -> bool:
    return await users_collection.find_one({"username": username}, {"_id": 1}) is not None

# ─── Document CRUD ─────────────────────────────────────────────────────────────

async def create_document(owner: str, title: str = "Untitled Document") -> dict:
    doc_id = str(uuid.uuid4())
    now = datetime.utcnow()
    doc = {
        "document_id": doc_id,
        "title": title,
        "content": "",
        "owner": owner,
        "collaborators": [],          # list of usernames allowed to edit
        "last_updated": now,
        "created_at": now,
    }
    await documents_collection.insert_one(doc)
    return doc

async def list_documents(username: str) -> list:
    """Return docs the user owns OR is a collaborator on."""
    cursor = documents_collection.find(
        {"$or": [{"owner": username}, {"collaborators": username}]},
        {"_id": 0, "content": 0}
    ).sort("last_updated", -1)
    return await cursor.to_list(length=200)

async def get_document(doc_id: str) -> dict | None:
    doc = await documents_collection.find_one({"document_id": doc_id})
    if not doc:
        return None
    return doc

async def can_access_document(doc_id: str, username: str) -> bool:
    """True if user is owner or collaborator."""
    doc = await documents_collection.find_one(
        {"document_id": doc_id, "$or": [{"owner": username}, {"collaborators": username}]},
        {"_id": 1}
    )
    return doc is not None

async def rename_document(doc_id: str, title: str, owner: str) -> bool:
    result = await documents_collection.update_one(
        {"document_id": doc_id, "owner": owner},
        {"$set": {"title": title, "last_updated": datetime.utcnow()}}
    )
    return result.modified_count > 0

async def delete_document(doc_id: str, owner: str) -> bool:
    result = await documents_collection.delete_one({"document_id": doc_id, "owner": owner})
    return result.deleted_count > 0

async def add_collaborator(doc_id: str, collaborator: str, owner: str) -> str:
    """
    Returns:
      'ok'           — added successfully
      'not_owner'    — caller is not the owner
      'not_found'    — doc doesn't exist
      'user_missing' — collaborator username doesn't exist
      'already'      — already a collaborator
    """
    doc = await documents_collection.find_one({"document_id": doc_id})
    if not doc:
        return "not_found"
    if doc["owner"] != owner:
        return "not_owner"
    if not await user_exists(collaborator):
        return "user_missing"
    if collaborator in doc.get("collaborators", []):
        return "already"
    await documents_collection.update_one(
        {"document_id": doc_id},
        {"$addToSet": {"collaborators": collaborator}, "$set": {"last_updated": datetime.utcnow()}}
    )
    return "ok"

async def remove_collaborator(doc_id: str, collaborator: str, owner: str) -> bool:
    result = await documents_collection.update_one(
        {"document_id": doc_id, "owner": owner},
        {"$pull": {"collaborators": collaborator}}
    )
    return result.modified_count > 0

async def save_document(doc_id: str, content: str):
    now = datetime.utcnow()
    await documents_collection.update_one(
        {"document_id": doc_id},
        {"$set": {"content": content, "last_updated": now}},
        upsert=True
    )
    await history_collection.insert_one({
        "document_id": doc_id,
        "content": content,
        "timestamp": now
    })
