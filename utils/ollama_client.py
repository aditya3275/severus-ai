import requests
from pathlib import Path
import logging
import os
import time

# =========================
# OLLAMA CONFIG (AUTO)
# =========================
try:
    from config.settings import OLLAMA_BASE_URL
except ImportError:
    OLLAMA_BASE_URL = os.getenv(
        "OLLAMA_BASE_URL", "http://localhost:11434"
    )

logger = logging.getLogger("ollama-client")


def chat_with_model(model: str, messages: list, chat_id: int):
    """
    Send chat + extracted document context to Ollama
    """

    # ---------- DEFAULT SYSTEM PROMPT ----------
    system_prompt = """
You are Severus AI, a powerful and helpful local AI assistant.
Your identity is Severus AI. You are powered by the DeepSeek model.

- If asked who you are, always identify as Severus AI.
- If asked if you are Gemma or OpenAI, clarify that you are Severus AI powered by DeepSeek.
- You can chat naturally and remember previous context.
- If the user asks about a document and no document is uploaded, clearly state that.
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
You are Severus AI, an advanced AI assistant. Your identity is Severus AI, powered by DeepSeek.

Core Behavior:
- If asked who you are, always identify as Severus AI.
- If asked about Gemma or OpenAI, clarify you are Severus AI.
- Use the provided document context to answer questions accurately.
- Mention source file names ({file_sources}) when using document info.
- Pronouns like "it" or "this file" refer to the uploaded document.
- If the answer isn't in the document or context, say you don't know.

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
    ai_start = time.time()
    try:
        from metrics import OLLAMA_CALLS, AI_LATENCY, AI_ERRORS
        logger.info(f"Sending request to Ollama @ {OLLAMA_BASE_URL}")

        response = requests.post(
            f"{OLLAMA_BASE_URL}/api/chat",
            json=payload,
            timeout=120,
        )
        OLLAMA_CALLS.inc()
        AI_LATENCY.observe(time.time() - ai_start)

        response.raise_for_status()
        return response.json()["message"]["content"]

    except Exception as e:
        from metrics import AI_ERRORS
        AI_ERRORS.inc()
        logger.error(f"Ollama error: {e}")
        return "⚠️ Error communicating with Ollama. Is Ollama running?"
