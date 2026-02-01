#!/bin/bash
# entrypoint.sh - Starts metrics and Streamlit

# Start Streamlit (Metrics will be started inside app.py)

# Start Streamlit
streamlit run app.py --server.address=0.0.0.0 --server.port=8501
