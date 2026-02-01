from prometheus_client import Counter

LOGIN_COUNT = Counter("login_total", "Total logins")
CHAT_CREATED = Counter("chat_created_total", "Chats created")
MESSAGES_SENT = Counter("messages_sent_total", "Messages sent")
OLLAMA_CALLS = Counter("ollama_calls_total", "Ollama calls")

if __name__ == "__main__":
    from prometheus_client import start_http_server
    import time
    start_http_server(8000)
    print("🚀 Prometheus metrics server started on port 8000")
    while True:
        time.sleep(3600)
