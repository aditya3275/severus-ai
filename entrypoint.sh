#!/bin/bash
# entrypoint.sh - Starts metrics and Streamlit

# Start Prometheus metrics server in the background
python3 metrics.py &

# Start Streamlit
streamlit run app.py --server.address=0.0.0.0 --server.port=8501
