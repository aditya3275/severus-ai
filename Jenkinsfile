pipeline {
    agent any

    environment {
        IMAGE_NAME = "adityahere/severus-ai"
        IMAGE_TAG  = "v1"

        APP_PORT = "8505"

        DOCKER_BIN     = "/usr/local/bin/docker"
        DOCKER_CONTEXT = "desktop-linux"

        PYTHON_BIN  = "/usr/bin/python3"
        HELM_BIN    = "/opt/homebrew/bin/helm"
        KUBECTL_BIN = "/opt/homebrew/bin/kubectl"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        /* ================= BUILD ================= */

        stage('Application Build') {
            steps {
                sh '''
                    echo "🔧 Installing dependencies..."
                    $PYTHON_BIN -m pip install --upgrade pip
                    $PYTHON_BIN -m pip install -r requirements.txt
                '''
            }
        }

        /* ================= RUN (SMOKE START) ================= */

        stage('Run (Smoke Start)') {
            steps {
                sh '''
                    echo "🚀 Starting application for smoke test..."

                    nohup $PYTHON_BIN -m streamlit run app.py \
                      --server.port=${APP_PORT} \
                      --server.headless=true \
                      > app.log 2>&1 &

                    sleep 20
                '''
            }
        }

        /* ================= TEST ================= */

        stage('Test (Smoke Test)') {
            steps {
                sh '''
                    echo "🧪 Running smoke test..."

                    echo "---- App logs ----"
                    tail -n 30 app.log || true
                    echo "------------------"

                    curl --fail http://127.0.0.1:${APP_PORT}

                    echo "✅ Smoke test passed"
                '''
            }
        }

        /* ================= DOCKER ================= */

        stage('Docker Build Image') {
            steps {
                sh '''
                    echo "🐳 Building Docker image..."
                    $DOCKER_BIN --context ${DOCKER_CONTEXT} build \
                      -t ${IMAGE_NAME}:${IMAGE_TAG} .
                '''
            }
        }

        /* ================= SECURITY ================= */

        stage('Trivy Security Scan') {
            steps {
                sh '''
                    echo "🔐 Running Trivy scan..."

                    $DOCKER_BIN --context ${DOCKER_CONTEXT} run --rm \
                      -v /Users/aditya/.docker/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest image \
                      --severity CRITICAL,HIGH \
                      --exit-code 0 \
                      ${IMAGE_NAME}:${IMAGE_TAG} | tee trivy-report.txt
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-report.txt', fingerprint: true
                }
            }
        }

        /* ================= PUSH ================= */

        stage('Docker Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "$DOCKER_PASS" | \
                        $DOCKER_BIN --context ${DOCKER_CONTEXT} login \
                          -u "$DOCKER_USER" --password-stdin

                        $DOCKER_BIN --context ${DOCKER_CONTEXT} push \
                          ${IMAGE_NAME}:${IMAGE_TAG}
                    '''
                }
            }
        }

        /* ================= DEPLOY ================= */

        stage('Deploy to Kubernetes (Ingress via Helm)') {
            steps {
                sh '''
                    echo "☸️ Deploying Severus AI with Ingress..."

                    # Clean up existing deployment to avoid immutable selector conflicts
                    echo "🧹 Cleaning up existing deployment (if any)..."
                    $KUBECTL_BIN delete deployment severus-ai --ignore-not-found=true
                    
                    # Wait a moment for cleanup to complete
                    sleep 2

                    # Deploy with Helm
                    echo "📦 Running Helm upgrade..."
                    $HELM_BIN upgrade --install severus-ai helm/severus-ai \
                      --set image.repository=${IMAGE_NAME} \
                      --set image.tag=${IMAGE_TAG}
                '''
            }
        }

        /* ================= POST-DEPLOY PARALLEL TESTS ================= */

        stage('Post-Deployment Tests') {
            parallel {

                stage('Ingress Reachability Test') {
                    steps {
                        sh '''
                            echo "🌐 Testing Ingress reachability..."
                            curl --fail http://severus-ai.local
                            echo "✅ Ingress reachable"
                        '''
                    }
                }

                stage('Ollama Connectivity Test') {
                    steps {
                        sh '''
                            echo "🧠 Testing Ollama connectivity from pod..."

                            POD=$($KUBECTL_BIN get pod -l app.kubernetes.io/name=severus-ai -o jsonpath="{.items[0].metadata.name}")
                            echo "Using pod: $POD"

                            OLLAMA_URL=$($KUBECTL_BIN exec $POD -- sh -c 'echo $OLLAMA_BASE_URL')

                            if [ -z "$OLLAMA_URL" ]; then
                              echo "❌ OLLAMA_BASE_URL is NOT set"
                              exit 1
                            fi

                            echo "OLLAMA_BASE_URL=$OLLAMA_URL"
                            $KUBECTL_BIN exec $POD -- curl --fail ${OLLAMA_URL}/api/tags

                            echo "✅ Ollama reachable"
                        '''
                    }
                }

                stage('Kubernetes Health Test') {
                    steps {
                        sh '''
                            echo "🩺 Checking Kubernetes health..."
                            $KUBECTL_BIN rollout status deployment/severus-ai --timeout=120s
                            $KUBECTL_BIN get pods -l app.kubernetes.io/name=severus-ai
                            echo "✅ Kubernetes healthy"
                        '''
                    }
                }

                stage('Log Sanity Test') {
                    steps {
                        sh '''
                            echo "📜 Checking application logs..."
                            $KUBECTL_BIN logs deployment/severus-ai | tail -n 50
                            echo "✅ Logs look sane"
                        '''
                    }
                }

                /* 🆕 NEW STAGE */
                stage('K3s Version Validation') {
                    steps {
                        sh '''
                            echo "🧪 Validating Helm chart against multiple K3s versions..."

                            mkdir -p k3s-validation-logs

                            for VERSION in v1.26 v1.27 v1.28 v1.29 v1.30 v1.31 v1.32 v1.33 v1.34 v1.35; do
                              echo "▶ Testing against K3s $VERSION"

                              {
                                echo "====================================="
                                echo "K3s Version Target: $VERSION"
                                echo "Timestamp: $(date)"
                                echo "-------------------------------------"
                                $HELM_BIN upgrade --install severus-ai helm/severus-ai \
                                  --dry-run --debug \
                                  --set image.repository=${IMAGE_NAME} \
                                  --set image.tag=${IMAGE_TAG} \
                                  --set global.k3sVersion=$VERSION
                                echo "-------------------------------------"
                                $KUBECTL_BIN version
                                echo "====================================="
                              } > k3s-validation-logs/k3s-$VERSION.log

                            done

                            echo "✅ K3s version validation completed"
                        '''
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'k3s-validation-logs/*.log', fingerprint: true
                        }
                    }
                }
            }
        }

        /* ================= PERFORMANCE EVALUATION ================= */

        stage('Performance Evaluation') {
            when {
                expression {
                    // Only run if enabled in values.yaml
                    def enabled = sh(
                        script: '$HELM_BIN get values severus-ai -o json 2>/dev/null | grep -q \'"enabled":true\' && echo "true" || echo "false"',
                        returnStdout: true
                    ).trim()
                    return enabled == 'true'
                }
            }
            steps {
                sh '''
                    echo "🚀 Starting Performance Evaluation..."
                    echo "=============================================="
                    
                    # Check if jq is available (optional, fallback to grep)
                    if command -v jq &> /dev/null; then
                        echo "Using jq for JSON parsing"
                        USE_JQ=true
                    else
                        echo "jq not found, using grep/awk fallback"
                        USE_JQ=false
                    fi
                    
                    # Extract values from Helm (with fallback)
                    if [ "$USE_JQ" = "true" ]; then
                        TARGETS=$($HELM_BIN get values severus-ai -o json | jq -r '.performanceTest.targets[]?' 2>/dev/null || echo "http://severus-ai.local")
                        TOTAL_REQUESTS=$($HELM_BIN get values severus-ai -o json | jq -r '.performanceTest.totalRequests // 100' 2>/dev/null)
                        CONCURRENCY=$($HELM_BIN get values severus-ai -o json | jq -r '.performanceTest.concurrency // 5' 2>/dev/null)
                        RUNS=$($HELM_BIN get values severus-ai -o json | jq -r '.performanceTest.runs // 1' 2>/dev/null)
                        SLEEP=$($HELM_BIN get values severus-ai -o json | jq -r '.performanceTest.sleepBetweenRuns // 0' 2>/dev/null)
                        POD_LABELS=$($HELM_BIN get values severus-ai -o json | jq -r '.performanceTest.podLabels[]?' 2>/dev/null || echo "app.kubernetes.io/name=severus-ai")
                    else
                        # Fallback: use defaults
                        TARGETS="http://severus-ai.local"
                        TOTAL_REQUESTS=100
                        CONCURRENCY=5
                        RUNS=1
                        SLEEP=0
                        POD_LABELS="app.kubernetes.io/name=severus-ai"
                    fi
                    
                    echo "Configuration:"
                    echo "  Targets        : $TARGETS"
                    echo "  Total Requests : $TOTAL_REQUESTS"
                    echo "  Concurrency    : $CONCURRENCY"
                    echo "  Runs           : $RUNS"
                    echo "  Sleep          : ${SLEEP}s"
                    echo "  Pod Labels     : $POD_LABELS"
                    echo "=============================================="
                    
                    # Build command
                    CMD="bash scripts/stress_pod.sh"
                    
                    # Add targets
                    for TARGET in $TARGETS; do
                        CMD="$CMD -t $TARGET"
                    done
                    
                    # Add parameters
                    CMD="$CMD -tr $TOTAL_REQUESTS -c $CONCURRENCY -r $RUNS -s $SLEEP"
                    
                    # Add pod labels
                    for LABEL in $POD_LABELS; do
                        CMD="$CMD -p $LABEL"
                    done
                    
                    # Execute and capture output
                    echo ""
                    echo "Executing: $CMD"
                    echo "=============================================="
                    $CMD | tee performance-report.txt
                    
                    echo ""
                    echo "✅ Performance Evaluation completed"
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'performance-report.txt', fingerprint: true, allowEmptyArchive: true
                }
                success {
                    echo '✅ Performance test passed'
                }
                failure {
                    echo '❌ Performance test failed'
                }
            }
        }
    }
}
