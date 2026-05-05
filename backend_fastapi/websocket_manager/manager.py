from fastapi import WebSocket
from typing import Dict, List
import diff_match_patch as dmp_module
import asyncio
from services.db_service import save_document, get_document
import json

dmp = dmp_module.diff_match_patch()

class ConnectionManager:
    def __init__(self):
        # Maps doc_id to a list of connected WebSockets
        self.active_connections: Dict[str, List[WebSocket]] = {}
        # Stores the current content for each document in-memory
        self.document_states: Dict[str, str] = {}
        # Track presence: map doc_id to dict of {websocket: user_info}
        self.presence: Dict[str, Dict[WebSocket, dict]] = {}
        # Debounce tasks map
        self.save_tasks: Dict[str, asyncio.Task] = {}

    async def connect(self, websocket: WebSocket, doc_id: str, client_id: str, username: str, color: str):
        await websocket.accept()
        if doc_id not in self.active_connections:
            self.active_connections[doc_id] = []
            self.presence[doc_id] = {}
            # Load initial state from DB
            doc = await get_document(doc_id)
            self.document_states[doc_id] = doc["content"] if doc else ""

        self.active_connections[doc_id].append(websocket)
        self.presence[doc_id][id(websocket)] = {
            "client_id": client_id,
            "username": username,
            "color": color,
            "cursor": 0,
            "ws": websocket,
        }

        # Send initial state to the newly connected client
        await websocket.send_json({
            "type": "init",
            "content": self.document_states[doc_id],
            "active_users": [
                {k: v for k, v in u.items() if k != "ws"}
                for u in self.presence[doc_id].values()
            ],
        })

        # Broadcast presence update to all in this doc
        await self.broadcast_presence(doc_id)

    def disconnect(self, websocket: WebSocket, doc_id: str):
        ws_id = id(websocket)
        if doc_id in self.active_connections:
            if websocket in self.active_connections[doc_id]:
                self.active_connections[doc_id].remove(websocket)
            if ws_id in self.presence.get(doc_id, {}):
                del self.presence[doc_id][ws_id]
            if not self.active_connections[doc_id]:
                del self.active_connections[doc_id]
                del self.document_states[doc_id]
                del self.presence[doc_id]
                if doc_id in self.save_tasks:
                    self.save_tasks[doc_id].cancel()
                    del self.save_tasks[doc_id]

    async def broadcast_presence(self, doc_id: str):
        if doc_id not in self.active_connections:
            return
        users = [
            {k: v for k, v in u.items() if k != "ws"}
            for u in self.presence[doc_id].values()
        ]
        message = {"type": "presence", "active_users": users}
        dead = []
        for connection in list(self.active_connections[doc_id]):
            try:
                await connection.send_json(message)
            except Exception:
                dead.append(connection)
        for ws in dead:
            self.disconnect(ws, doc_id)

    async def handle_update(self, doc_id: str, client_id: str, data: dict, sender: WebSocket):
        if doc_id not in self.document_states:
            return

        msg_type = data.get("type")

        if msg_type == "patch":
            try:
                patches = dmp.patch_fromText(data["patch"])
                current_text = self.document_states[doc_id]
                new_text, _ = dmp.patch_apply(patches, current_text)
                self.document_states[doc_id] = new_text

                # Find sender's color
                sender_info = self.presence.get(doc_id, {}).get(id(sender), {})
                color = sender_info.get("color", "0xFF000000")

                broadcast_msg = {
                    "type": "patch",
                    "patch": data["patch"],
                    "client_id": client_id,
                    "color": color,
                }
                for connection in list(self.active_connections.get(doc_id, [])):
                    if connection != sender:
                        try:
                            await connection.send_json(broadcast_msg)
                        except Exception:
                            pass

                # Debounce save
                self.schedule_save(doc_id)
            except Exception as e:
                print(f"Error applying patch: {e}")

        elif msg_type == "cursor":
            ws_id = id(sender)
            if ws_id in self.presence.get(doc_id, {}):
                self.presence[doc_id][ws_id]["cursor"] = data.get("cursor", 0)
                info = self.presence[doc_id][ws_id]
                broadcast_msg = {
                    "type": "cursor",
                    "client_id": client_id,
                    "cursor": data.get("cursor", 0),
                    "username": info["username"],
                    "color": info["color"],
                }
                for connection in list(self.active_connections.get(doc_id, [])):
                    if connection != sender:
                        try:
                            await connection.send_json(broadcast_msg)
                        except Exception:
                            pass

    def schedule_save(self, doc_id: str):
        if doc_id in self.save_tasks:
            self.save_tasks[doc_id].cancel()

        async def delayed_save():
            try:
                await asyncio.sleep(2)
                content = self.document_states.get(doc_id)
                if content is not None:
                    await save_document(doc_id, content)
            except asyncio.CancelledError:
                pass

        self.save_tasks[doc_id] = asyncio.create_task(delayed_save())

manager = ConnectionManager()
