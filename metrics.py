from prometheus_client import Counter, Histogram

# --- Product Health ---
LOGIN_TOTAL = Counter("login_total", "Total logins")
CHAT_CREATED = Counter("chat_created_total", "Total chats created")
MESSAGES_SENT = Counter("messages_sent_total", "Total messages sent")
REQUEST_COUNT = Counter("request_count_total", "Total application requests")
REQUEST_LATENCY = Histogram("request_latency_seconds", "Application request latency")

# --- AI System ---
OLLAMA_CALLS = Counter("ollama_calls_total", "Total Ollama calls")
AI_LATENCY = Histogram("ai_latency_seconds", "AI model response latency")
AI_ERRORS = Counter("ai_errors_total", "Total AI model errors")

# --- Reliability ---
APP_ERRORS = Counter("app_errors_total", "Total application-level errors")

# Counters are imported and used by app.py
