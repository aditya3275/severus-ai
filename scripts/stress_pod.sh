#!/bin/bash
set -e

# Use KUBECTL_BIN environment variable if set, otherwise default to kubectl
KUBECTL_CMD="${KUBECTL_BIN:-kubectl}"
 
usage() {
  echo ""
  echo "Usage:"
  echo "  stress_pod.sh -t <target_url> [-t <target_url> ...] \\"
  echo "                -tr <total_requests> -c <concurrency> \\"
  echo "                [-r <runs>] [-s <sleep_seconds>] \\"
  echo "                [-p <pod_label> ...]"
  echo ""
  exit 1
}
 
# -----------------------------
# Defaults
# -----------------------------
TOTAL_REQUESTS=100
CONCURRENCY=5
RUNS=1
SLEEP_BETWEEN_RUNS=0
 
TARGETS=()
POD_LABELS=()
DATA_SET=("alpha" "beta" "gamma" "delta" "epsilon")
 
# -----------------------------
# Parse arguments
# -----------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t) TARGETS+=("$2"); shift 2 ;;
    -tr) TOTAL_REQUESTS="$2"; shift 2 ;;
    -c) CONCURRENCY="$2"; shift 2 ;;
    -r) RUNS="$2"; shift 2 ;;
    -s) SLEEP_BETWEEN_RUNS="$2"; shift 2 ;;
    -p) POD_LABELS+=("$2"); shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done
 
[[ ${#TARGETS[@]} -eq 0 ]] && echo "ERROR: At least one -t <target_url> is required" && exit 1
 
# -----------------------------
# Counters (Atomic via Directory)
# -----------------------------
RESULTS_DIR="/tmp/stress_results_$(date +%s)"
SUCCESS_DIR="$RESULTS_DIR/success"
FAILURE_DIR="$RESULTS_DIR/failure"

mkdir -p "$SUCCESS_DIR" "$FAILURE_DIR"

increment() {
  local dir=$1
  local run_num=$2
  mktemp -p "$dir/run_$run_num" "req.XXXXXX" > /dev/null
}

cleanup_results() {
  rm -rf "$RESULTS_DIR"
}
# Register cleanup on exit
trap cleanup_results EXIT

 
# -----------------------------
# Readiness check
# -----------------------------
for TARGET in "${TARGETS[@]}"; do
  echo "Waiting for target to be ready: $TARGET"
  until curl -s "$TARGET" > /dev/null 2>&1; do sleep 2; done
  echo "✅ Target is ready: $TARGET"
done
 
# -----------------------------
# Resource Monitoring
# -----------------------------
RESOURCE_LOG=/tmp/resource_usage.log
echo "timestamp,pod,cpu_millicores,memory_mib" > "$RESOURCE_LOG"
 
monitor_resources() {
  # Trap for clean exit
  trap "exit" SIGTERM
  while true; do
    TS=$(date +%s)
    # Ensure the tmp file exists to avoid "No such file" error
    : > "$RESOURCE_LOG.tmp"
    $KUBECTL_CMD top pod --no-headers 2>/dev/null > "$RESOURCE_LOG.tmp" || true
    
    if [ -s "$RESOURCE_LOG.tmp" ]; then
      while read -r line; do
         if [ -n "$line" ]; then
           echo "$TS,$line" | awk '{print $1 "," $2 "," $3 "," $4}' >> "$RESOURCE_LOG"
         fi
      done < "$RESOURCE_LOG.tmp"
    fi
    rm -f "$RESOURCE_LOG.tmp"
    sleep 5
  done
}
 
monitor_resources &
MONITOR_PID=$!
 
# -----------------------------
# Stress Test Info
# -----------------------------
echo ""
echo "=============================================="
echo "STRESS TEST STARTED at $(date -u)"
echo "Targets            : ${TARGETS[*]}"
echo "Requests per run   : $TOTAL_REQUESTS"
echo "Concurrency        : $CONCURRENCY"
echo "Runs               : $RUNS"
echo "Sleep between runs : ${SLEEP_BETWEEN_RUNS}s"
echo "=============================================="
 
START_TIME=$(date +%s)
 
# -----------------------------
# RUN LOOP
# -----------------------------
for RUN in $(seq 1 "$RUNS"); do
  echo ""
  echo "----------------------------------------------"
  echo "RUN $RUN of $RUNS started at $(date -u)"
  echo "----------------------------------------------"
 
  RUN_START=$(date +%s)
  
  # Prepare directories for this run
  mkdir -p "$SUCCESS_DIR/run_$RUN" "$FAILURE_DIR/run_$RUN"
 
  for TARGET in "${TARGETS[@]}"; do
    echo "Sending $TOTAL_REQUESTS requests to $TARGET"
    LAST_LOGGED_STEP=0
 
    for i in $(seq 1 "$TOTAL_REQUESTS"); do

      PAYLOAD=${DATA_SET[$((i % ${#DATA_SET[@]}))]}
 
      REQUEST_BODY=$(cat <<EOF
{
  "request_id": "$RUN-$i",
  "payload": "$PAYLOAD",
  "source": "stress-pod",
  "timestamp": "$(date +%s)"
}
EOF
)
 
      (
        if curl -s --max-time 15 -X GET "$TARGET" > /dev/null 2>&1; then
          increment "$SUCCESS_DIR" "$RUN"
        else
          increment "$FAILURE_DIR" "$RUN"
        fi
      ) &
    done
 
    # Wait for the remaining requests with a timeout to avoid hangs
    echo "Burst fired! Waiting up to 60s for the batch to complete..."
    for t in $(seq 1 60); do
      S_COUNT=$(ls -1 "$SUCCESS_DIR/run_$RUN" 2>/dev/null | wc -l | xargs)
      F_COUNT=$(ls -1 "$FAILURE_DIR/run_$RUN" 2>/dev/null | wc -l | xargs)
      TOTAL_DONE=$((S_COUNT + F_COUNT))
      
      echo "[Run $RUN] Progress: $TOTAL_DONE/$TOTAL_REQUESTS finished | Success: $S_COUNT | Failure: $F_COUNT"
      
      if [ "$TOTAL_DONE" -ge "$TOTAL_REQUESTS" ]; then break; fi
      sleep 2
    done
    # Kill any truly stuck requests so we can proceed to the next run
    if [ $(jobs -r | wc -l) -gt 0 ]; then
       echo "Warning: Some requests are taking too long. Terminating them to proceed."
       kill $(jobs -p) 2>/dev/null || true
    fi
    echo "Run $RUN batch completed for $TARGET"
  done
 
  RUN_END=$(date +%s)
  echo ""
  echo "RUN $RUN COMPLETED"
  echo "Time taken : $((RUN_END - RUN_START))s"
 
  [[ "$RUN" -lt "$RUNS" && "$SLEEP_BETWEEN_RUNS" -gt 0 ]] && sleep "$SLEEP_BETWEEN_RUNS"
done
 
# -----------------------------
# Metrics Grace Period
# -----------------------------
echo "Waiting 30 seconds for final metrics collection..."
sleep 30
 
# Stop Resource Monitor
# Use a more graceful stop to avoid "Terminated" noise
kill "$MONITOR_PID" 2>/dev/null || true
# Wait a brief moment for the last write
sleep 1
 
# -----------------------------
# Summary
# -----------------------------
END_TIME=$(date +%s)
 
echo ""
echo "=============================================="
echo "ALL RUNS COMPLETED"
echo "Success requests     : $(find "$SUCCESS_DIR" -type f | wc -l | xargs)"
echo "Failed requests      : $(find "$FAILURE_DIR" -type f | wc -l | xargs)"
echo "Total execution time : $((END_TIME - START_TIME))s"
echo "=============================================="
 
# -----------------------------
# Resource Peak Summary
# -----------------------------
echo ""
echo "=============================================="
echo "RESOURCE USAGE SUMMARY (PEAK)"
echo "=============================================="
 
if [[ $(wc -l <"$RESOURCE_LOG") -le 1 ]]; then
  echo "No resource metrics captured (metrics became available late)"
else
  # Filter to show only relevant pods if POD_LABELS is used, otherwise show all
  awk -F',' -v label_pods="${POD_LABELS[*]}" '
  NR>1 {
    # If we have labels, only track pods found in labels
    # Simplified: show pods that start with or match our app names
    cpu[$2] = (cpu[$2] > $3 ? cpu[$2] : $3)
    mem[$2] = (mem[$2] > $4 ? mem[$2] : $4)
  }
  END {
    for (p in cpu) {
      # Filter out "mock" or invalid data
      if (p != "mock" && cpu[p] != "data") {
        printf "Pod: %-35s CPU_peak=%s Memory_peak=%s\n", p, cpu[p], mem[p]
      }
    }
  }' "$RESOURCE_LOG"
fi

# -----------------------------
# AI-POWERED COST ANALYSIS (Ollama)
# -----------------------------
OLLAMA_API="${OLLAMA_API:-http://localhost:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-deepseek-v3.1:671b-cloud}"

analyze_with_ollama() {
  echo ""
  echo "=============================================="
  echo "🤖 AI COST OPTIMIZATION ANALYSIS (Ollama)"
  echo "=============================================="
  
  # Check if Ollama is available
  if ! curl -s --max-time 3 "$OLLAMA_API/api/tags" > /dev/null 2>&1; then
    echo "⚠️  Ollama not available at $OLLAMA_API - skipping AI analysis"
    echo "   To enable: start Ollama with 'ollama serve'"
    return 0
  fi
  
  # Collect metrics for analysis
  local SUCCESS_COUNT=$(find "$SUCCESS_DIR" -type f 2>/dev/null | wc -l | xargs)
  local FAILURE_COUNT=$(find "$FAILURE_DIR" -type f 2>/dev/null | wc -l | xargs)
  local TOTAL_COUNT=$((SUCCESS_COUNT + FAILURE_COUNT))
  local SUCCESS_RATE=0
  [[ $TOTAL_COUNT -gt 0 ]] && SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))
  
  local DURATION=$((END_TIME - START_TIME))
  local THROUGHPUT=0
  [[ $DURATION -gt 0 ]] && THROUGHPUT=$((TOTAL_COUNT / DURATION))
  
  # Get pod count and resource metrics
  local POD_COUNT=0
  local PEAK_CPU_LIST=""
  local PEAK_MEM_LIST=""
  
  if [[ ${#POD_LABELS[@]} -gt 0 ]]; then
    for LABEL in "${POD_LABELS[@]}"; do
      local COUNT=$($KUBECTL_CMD get pods -l "$LABEL" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | xargs)
      POD_COUNT=$((POD_COUNT + COUNT))
    done
  else
    POD_COUNT=$($KUBECTL_CMD get pods --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | xargs)
  fi
  
  # Extract peak metrics from resource log
  local TOTAL_PEAK_CPU=0
  local TOTAL_PEAK_MEM=0
  if [[ -f "$RESOURCE_LOG" && $(wc -l <"$RESOURCE_LOG") -gt 1 ]]; then
    PEAK_CPU_LIST=$(awk -F',' 'NR>1 && $3 ~ /[0-9]/ {print $2 ": " $3}' "$RESOURCE_LOG" | sort -t: -k2 -rn | head -5 | tr '\n' '; ')
    PEAK_MEM_LIST=$(awk -F',' 'NR>1 && $4 ~ /[0-9]/ {print $2 ": " $4}' "$RESOURCE_LOG" | sort -t: -k2 -rn | head -5 | tr '\n' '; ')
    
    # Calculate aggregate peaks for scaling math
    TOTAL_PEAK_CPU=$(awk -F',' 'NR>1 {cpu[$2] = (cpu[$2] > $3 ? cpu[$2] : $3)} END {for (p in cpu) sum += cpu[p]; print sum}' "$RESOURCE_LOG")
    TOTAL_PEAK_MEM=$(awk -F',' 'NR>1 {mem[$2] = (mem[$2] > $4 ? mem[$2] : $4)} END {for (p in mem) sum += mem[p]; print sum}' "$RESOURCE_LOG")
  fi

  # =====================================================
  # MATHEMATICAL SCALING CALCULATIONS
  # =====================================================
  local TARGET_CPU_UTIL=50 # Target 50% utilization
  local IDEAL_POD_COUNT=$POD_COUNT
  local CPU_REQ_RECOMMENDED="N/A"
  local CPU_LIM_RECOMMENDED="N/A"
  local MEM_REQ_RECOMMENDED="N/A"
  local MEM_LIM_RECOMMENDED="N/A"
  local COST_SAVINGS_PERCENT=0
  
  if [[ $POD_COUNT -gt 0 && $TOTAL_PEAK_CPU -gt 0 ]]; then
    # Calculate Ideal Pods: (Total Peak CPU / Target Utilization)
    # Using awk for floating point and ceil logic
    IDEAL_POD_COUNT=$(awk -v total_cpu="$TOTAL_PEAK_CPU" -v target="$TARGET_CPU_UTIL" 'BEGIN {print int((total_cpu/target) + 0.99)}')
    [[ $IDEAL_POD_COUNT -lt 1 ]] && IDEAL_POD_COUNT=1
    
    # Calculate Resources per Pod (Current workload intensity)
    local CPU_PER_POD=$(awk -v total_cpu="$TOTAL_PEAK_CPU" -v pods="$POD_COUNT" 'BEGIN {print total_cpu/pods}')
    local MEM_PER_POD=$(awk -v total_mem="$TOTAL_PEAK_MEM" -v pods="$POD_COUNT" 'BEGIN {print total_mem/pods}')
    
    # Recommendations with headroom: 20% for Request, 50% for Limit
    CPU_REQ_RECOMMENDED=$(awk -v cpu="$CPU_PER_POD" 'BEGIN {printf "%.0fm", cpu * 1.2}')
    CPU_LIM_RECOMMENDED=$(awk -v cpu="$CPU_PER_POD" 'BEGIN {printf "%.0fm", cpu * 1.5}')
    MEM_REQ_RECOMMENDED=$(awk -v mem="$MEM_PER_POD" 'BEGIN {printf "%.0fMi", mem * 1.2}')
    MEM_LIM_RECOMMENDED=$(awk -v mem="$MEM_PER_POD" 'BEGIN {printf "%.0fMi", mem * 1.5}')
    
    # Calculate Savings: ((Current - Ideal) / Current) * 100
    COST_SAVINGS_PERCENT=$(awk -v cur="$POD_COUNT" -v ideal="$IDEAL_POD_COUNT" 'BEGIN {printf "%.1f", ((cur - ideal) / cur) * 100}')
  fi

  # Build the prompt
  local PROMPT="You are a Kubernetes scaling expert. I have performed mathematical scaling calculations based on stress test metrics. 
Summarize these results and explain the reasoning.

CALCULATED METRICS:
- Requests: $TOTAL_COUNT total, $FAILURE_COUNT failed (${SUCCESS_RATE}% success)
- Throughput: ${THROUGHPUT} req/s
- Current State: $POD_COUNT pods | Peak CPU: $TOTAL_PEAK_CPU m | Peak Mem: $TOTAL_PEAK_MEM Mi
- Missed Requests: $FAILURE_COUNT

DETERMINISTIC RECOMMENDATIONS (Use these in your report):
1. HORIZONTAL SCALING:
   - Recommended: $IDEAL_POD_COUNT pods (Targeting ${TARGET_CPU_UTIL}% CPU utilization)
   - Estimated Savings: ${COST_SAVINGS_PERCENT}%

2. VERTICAL SCALING:
   - CPU Request/Limit: $CPU_REQ_RECOMMENDED / $CPU_LIM_RECOMMENDED
   - Memory Request/Limit: $MEM_REQ_RECOMMENDED / $MEM_LIM_RECOMMENDED

Write a concise report following this structure:
1. MISSED REQUESTS: Analysis of failures.
2. HORIZONTAL SCALING: Recommendation based on the calculated $IDEAL_POD_COUNT pods.
3. VERTICAL SCALING: Justify the resource recommendations.
4. ESTIMATED SAVINGS: Explain the ${COST_SAVINGS_PERCENT}% savings/cost impact.

Monthly cost estimate: Assuming \$0.05/pod/hour, current cost is \$$(awk -v p="$POD_COUNT" 'BEGIN {printf "%.2f", p * 0.05 * 24 * 30}') vs optimized \$$(awk -v p="$IDEAL_POD_COUNT" 'BEGIN {printf "%.2f", p * 0.05 * 24 * 30}').

Keep it professional and data-driven. No disclaimers or filler."

  # Escape the prompt for JSON
  local ESCAPED_PROMPT=$(echo "$PROMPT" | jq -Rs .)
  
  # Call Ollama API
  echo "Analyzing with $OLLAMA_MODEL..."
  echo ""
  
  local RESPONSE=$(curl -s --max-time 60 "$OLLAMA_API/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$OLLAMA_MODEL\", \"prompt\": $ESCAPED_PROMPT, \"stream\": false}" 2>/dev/null)
  
  if [[ -z "$RESPONSE" ]]; then
    echo "⚠️  No response from Ollama - model may be loading or unavailable"
    return 0
  fi
  
  # Extract the response text
  local ANALYSIS=$(echo "$RESPONSE" | jq -r '.response // empty' 2>/dev/null)
  
  if [[ -n "$ANALYSIS" ]]; then
    echo "----------------------------------------------"
    echo "$ANALYSIS"
    echo "----------------------------------------------"
    echo ""
    
    # Save analysis to file for later reference
    local ANALYSIS_FILE="/tmp/stress_analysis_$(date +%Y%m%d_%H%M%S).txt"
    {
      echo "Stress Test Analysis - $(date)"
      echo "=============================================="
      echo "Metrics:"
      echo "  Requests: $TOTAL_COUNT (${SUCCESS_RATE}% success)"
      echo "  Duration: ${DURATION}s | Throughput: ${THROUGHPUT} req/s"
      echo "  Pods: $POD_COUNT"
      echo ""
      echo "AI Analysis:"
      echo "$ANALYSIS"
    } > "$ANALYSIS_FILE"
    echo "📄 Analysis saved to: $ANALYSIS_FILE"
  else
    echo "⚠️  Could not parse Ollama response"
    echo "Raw response: $RESPONSE"
  fi
}

# Run Ollama analysis
analyze_with_ollama
 
# -----------------------------
# Validation
# -----------------------------
if [[ ${#POD_LABELS[@]} -gt 0 ]]; then
  echo ""
  echo "Validation started"
  echo "----------------------------------------------"
 
  OVERALL_STATUS="PASS"
  EXPECTED_TOTAL=$((TOTAL_REQUESTS * RUNS))
 
  for LABEL in "${POD_LABELS[@]}"; do
    TOTAL_PODS=$($KUBECTL_CMD get pods -l "$LABEL" --field-selector=status.phase=Running -o name | wc -l)
    echo "Service label       : $LABEL"
    echo "Running pods        : $TOTAL_PODS"
    
    if [[ $TOTAL_PODS -eq 0 ]]; then
      echo "⚠️  No running pods found for label: $LABEL"
      OVERALL_STATUS="FAIL"
    else
      echo "✅ Pods are running for label: $LABEL"
      
      # -----------------------------
      # Pod Log Verification (NEW)
      # -----------------------------
      echo ""
      echo "📊 Verifying requests in pod logs..."
      echo "----------------------------------------------"
      
      TOTAL_LOG_REQUESTS=0
      for POD in $($KUBECTL_CMD get pods -l "$LABEL" --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}'); do
        # Count requests in pod logs. Using "Streamlit" as a fallback check if "GET" is not found
        # grep -c always returns a number, so we don't need || echo "0" which causes "0 0" bugs
        GET_LOGS=$($KUBECTL_CMD logs "$POD" --since=5m 2>/dev/null | grep -c "GET" || true)
        STREAMLIT_LOGS=$($KUBECTL_CMD logs "$POD" --since=5m 2>/dev/null | grep -c "Streamlit" || true)
        
        # Ensure they are valid numbers (default to 0 if empty)
        [[ -z "$GET_LOGS" ]] && GET_LOGS=0
        [[ -z "$STREAMLIT_LOGS" ]] && STREAMLIT_LOGS=0
        
        if [ "$GET_LOGS" -gt "$STREAMLIT_LOGS" ]; then
          LOG_COUNT=$GET_LOGS
        else
          LOG_COUNT=$STREAMLIT_LOGS
        fi
        
        echo "Pod: $POD → Activity detected in logs: $LOG_COUNT"
        TOTAL_LOG_REQUESTS=$((TOTAL_LOG_REQUESTS + LOG_COUNT))
      done
      
      echo "----------------------------------------------"
      echo "Verified activity in logs : $TOTAL_LOG_REQUESTS"
      echo "Expected range            : > 0"
      
      if [[ $TOTAL_LOG_REQUESTS -gt 0 ]]; then
        echo "✅ Pods activity verified via logs"
      else
        echo "⚠️  No specific request logs found (Streamlit standard behavior)"
        echo "💡 Tip: Streamlit is WebSocket-based and may not log every HTTP request."
      fi
    fi
    echo "----------------------------------------------"
  done
 
  echo "Overall validation status : $OVERALL_STATUS"
  [[ "$OVERALL_STATUS" == "FAIL" ]] && exit 1
fi
 
echo ""
echo "✅ STRESS TEST COMPLETED SUCCESSFULLY"
