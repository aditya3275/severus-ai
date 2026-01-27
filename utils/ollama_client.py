import requests
from pathlib import Path
import logging
import os

# =========================
# OLLAMA CONFIG (AUTO)
# =========================
OLLAMA_BASE_URL = os.getenv(
    "OLLAMA_BASE_URL", "http://localhost:11434"  # default for local runs
)

logger = logging.getLogger("ollama-client")


def chat_with_model(model: str, messages: list, chat_id: int):
    """
    Send chat + extracted document context to Ollama
    """

    # ---------- DEFAULT SYSTEM PROMPT ----------
    system_prompt = """
You are a helpful, conversational AI assistant.

You can chat naturally with the user and remember things mentioned earlier
in the conversation.

If the user asks about a document and no document is available,
clearly say that no document has been uploaded yet.
"""

    document_text = ""

    # ---------- READ EXTRACTED DOCUMENT ----------
    extracted_file = Path(f"data/uploads/{chat_id}/extracted_text.txt")

    if extracted_file.exists():
        document_text = extracted_file.read_text(
            encoding="utf-8",
            errors="ignore",
        )

    # ---------- READ FILE NAMES ----------
    uploaded_files = []
    chat_upload_dir = Path(f"data/uploads/{chat_id}")

    if chat_upload_dir.exists():
        for f in chat_upload_dir.iterdir():
            if f.is_file() and f.name != "extracted_text.txt":
                uploaded_files.append(f.name)

    file_sources = ", ".join(uploaded_files) if uploaded_files else "Unknown file"

    # ---------- DOCUMENT-AWARE PROMPT ----------
    if document_text.strip():
        system_prompt = f"""
You are a helpful, conversational AI assistant.

You can:
- Chat naturally with the user
- Remember things mentioned earlier in the conversation
- Read, summarize, explain, and answer questions about the user's uploaded documents

Behavior rules:
- If the user asks general questions, respond naturally.
- If the user asks about the document, use document content.
- Pronouns like "it", "this", "the file" refer to the uploaded document.
- Treat misspellings of "summarize" as summarize intent.
- ALWAYS mention source file names when answering from documents.
- If answer is not found, say you don't know.

Uploaded document sources:
{file_sources}

<Document Context>
{document_text}
</Document Context>
"""

    # ---------- BUILD MESSAGE PAYLOAD ----------
    ollama_messages = [{"role": "system", "content": system_prompt}]

    for role, content in messages:
        ollama_messages.append({"role": role, "content": content})

    payload = {
        "model": model,
        "messages": ollama_messages,
        "stream": False,
    }

    # ---------- SEND TO OLLAMA ----------
    try:
        logger.info(f"Sending request to Ollama @ {OLLAMA_BASE_URL}")

        response = requests.post(
            f"{OLLAMA_BASE_URL}/api/chat",
            json=payload,
            timeout=120,
        )

        response.raise_for_status()
        return response.json()["message"]["content"]

    except Exception as e:
        logger.error(f"Ollama error: {e}")
        return "⚠️ Error communicating with Ollama. Is Ollama running?"
