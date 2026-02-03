import requests
import os
import sys

# Add project root to path
sys.path.append(os.getcwd())

try:
    from config.settings import OLLAMA_BASE_URL
    print(f"DEBUG: Using OLLAMA_BASE_URL: {OLLAMA_BASE_URL}")
except ImportError:
    OLLAMA_BASE_URL = "http://localhost:11434"
    print(f"DEBUG: Falling back to default OLLAMA_BASE_URL: {OLLAMA_BASE_URL}")

def test_connection():
    try:
        response = requests.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=5)
        if response.status_code == 200:
            print("✅ Successfully connected to Ollama!")
            models = response.json().get("models", [])
            print(f"Available models: {[m['name'] for m in models]}")
            return True
        else:
            print(f"❌ Failed to connect to Ollama. Status: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Connection error: {e}")
        return False

if __name__ == "__main__":
    if test_connection():
        sys.exit(0)
    else:
        sys.exit(1)
