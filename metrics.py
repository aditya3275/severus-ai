from prometheus_client import Counter

LOGIN_COUNT = Counter("login_total", "Total logins")
CHAT_CREATED = Counter("chat_created_total", "Chats created")
MESSAGES_SENT = Counter("messages_sent_total", "Messages sent")
OLLAMA_CALLS = Counter("ollama_calls_total", "Ollama calls")
