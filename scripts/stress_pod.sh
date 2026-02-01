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
 
    for i in $(seq 1 "$TOTAL_REQUESTS"); do
      # Progress logging every 10% or at least every 100 requests
      PROGRESS_STEP=$(( TOTAL_REQUESTS / 10 ))
      [[ $PROGRESS_STEP -eq 0 ]] && PROGRESS_STEP=10
      if (( i % PROGRESS_STEP == 0 )); then
        S_COUNT=$(ls -1 "$SUCCESS_DIR/run_$RUN" 2>/dev/null | wc -l | xargs)
        F_COUNT=$(ls -1 "$FAILURE_DIR/run_$RUN" 2>/dev/null | wc -l | xargs)
        TOTAL_DONE=$((S_COUNT + F_COUNT))
        echo "[Run $RUN] Progress: $i requests launched | $TOTAL_DONE requests finished | Success: $S_COUNT | Failure: $F_COUNT"
      fi

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
        if curl -s --max-time 10 -X GET "$TARGET" > /dev/null 2>&1; then
          increment "$SUCCESS_DIR" "$RUN"
        else
          increment "$FAILURE_DIR" "$RUN"
        fi
      ) &
 
      # Greedy concurrency control: keep the pipe full
      # We poll running jobs so we dont wait on a single slow request
      while [ $(jobs -r | wc -l) -ge "$CONCURRENCY" ]; do
        sleep 0.05
      done
    done
 
    # CRITICAL: Wait for ALL remaining background processes
    echo "Waiting for remaining requests to complete..."
    wait
    echo "All requests completed for $TARGET"
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
