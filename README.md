# Severus AI
### Locally Hosted AI Assistant with Production-Grade DevOps Infrastructure

---

## Overview
Severus AI is a full-stack, locally hosted AI assistant web application 
built with Python and Streamlit, powered by open-source LLMs via Ollama. 
Beyond the application itself, the project features a complete 
production-grade DevOps pipeline — Kubernetes orchestration, Jenkins CI/CD, 
security scanning, observability, and automated AI-powered debugging.

---

## Key Features
- Conversational AI with context-aware multi-turn chat using Ollama (gemma3:1b / deepseek-v3.1)
- Multi-format document processing — PDF, CSV, Excel, images, and text files
- Secure user authentication with persistent chat history via SQLite
- Custom Prometheus metrics instrumentation (messages, latency, errors, logins)
- Horizontal Pod Autoscaler scaling 1–5 replicas based on CPU utilization
- Auto AI-debugging — on pipeline failure, LLM analyzes Jenkins logs and suggests fixes

---

## Tech Stack
| Layer | Tools |
|-------|-------|
| Application & UI | Python, Streamlit |
| AI Backend | Ollama (gemma3:1b, deepseek-v3.1) |
| Database | SQLite |
| Containerization | Docker |
| Orchestration | Kubernetes (K3s/k3d), Helm |
| CI/CD | Jenkins |
| Security Scanning | Aqua Trivy |
| Observability | Prometheus, Grafana, OpenSearch, Fluent-Bit |
| Ingress | Traefik |

---

## Architecture
```
User (Browser)
    ↓
Traefik Ingress → Streamlit App (Kubernetes Pod)
    ↓                    ↓
Ollama LLM Backend    SQLite (Persistent Storage)
    ↓
Prometheus /metrics endpoint
    ↓
Grafana Command Center Dashboard
    ↓
OpenSearch + Fluent-Bit (Log Aggregation)
```

---

## CI/CD Pipeline (Jenkinsfile)

▪ Build & smoke test — headless app startup validation
▪ Dockerize — builds adityahere/severus-ai:v1
▪ Security scan — Trivy scans for CRITICAL/HIGH vulnerabilities
▪ Deploy — Helm deployment to K3s, exposed via Traefik at http://severus-ai.local
▪ Parallel validation — ingress reachability, Ollama connectivity, log sanity, K8s health
▪ Helm matrix validation — tested across 10 K3s versions (v1.26–v1.35)
▪ Stress testing — concurrent request load validation
▪ Auto AI-debugging — LLM analyzes console logs and suggests fixes on failure

---

## Observability — Grafana Command Center

| Pillar | Metrics |
|--------|---------|
| Product Health | Logins, messages exchanged, requests/sec |
| AI System | Ollama call volume, LLM response latency, generation errors |
| Kubernetes Scaling | Active pods vs HPA desired state, CPU/Memory |
| Reliability | P50/P95/P99 latency, error rates, pod restart counts |

---

## Getting Started

### Prerequisites
```bash
pip install streamlit ollama pandas numpy pypdf openpyxl prometheus-client
```

### Run Locally
```bash
# Start Ollama
ollama run gemma3:1b

# Launch the app
streamlit run app.py
```

### Deploy to Kubernetes
```bash
helm upgrade --install severus-ai helm/severus-ai/
```

---

## Project Structure
```
severus-ai/
├── app.py                      # Main Streamlit entry point
├── auth.py                     # User authentication
├── chat.py                     # Chat management
├── storage.py                  # SQLite persistence
├── metrics.py                  # Prometheus instrumentation
├── file_utils.py               # Document upload handling
├── file_text_extractor.py      # Multi-format text extraction
├── utils/
│   └── ollama_client.py        # Ollama API client
├── helm/severus-ai/            # Kubernetes Helm chart
├── Jenkinsfile                 # CI/CD pipeline
├── Dockerfile                  
├── docker-compose.yml          
├── scripts/
│   └── jenkins_ai_debugger.py  # AI-powered pipeline debugger
└── README.md
```

---

## Author
Aditya
[LinkedIn] | [GitHub]
