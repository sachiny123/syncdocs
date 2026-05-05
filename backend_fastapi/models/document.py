from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional, List

class DocumentModel(BaseModel):
    document_id: str
    title: str = "Untitled Document"
    content: str = ""
    owner: str = ""
    collaborators: List[str] = []
    last_updated: datetime = Field(default_factory=datetime.utcnow)

class UpdateDocumentModel(BaseModel):
    content: str

class RenameDocumentModel(BaseModel):
    title: str

class UserModel(BaseModel):
    username: str
    password: str

class UserResponseModel(BaseModel):
    username: str
    token: str

class AddCollaboratorModel(BaseModel):
    username: str
