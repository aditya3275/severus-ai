import os

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
DEFAULT_MODEL = "gemma3:1b"


APP_NAME = "Ollama Streamlit Chat"
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
