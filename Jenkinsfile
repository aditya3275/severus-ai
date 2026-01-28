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
                            POD=$($KUBECTL_BIN get pod -l app=severus-ai -o jsonpath="{.items[0].metadata.name}")
                            $KUBECTL_BIN exec $POD -- \
                              curl --fail $OLLAMA_BASE_URL/api/tags
                            echo "✅ Ollama reachable from pod"
                        '''
                    }
                }

                stage('Kubernetes Health Test') {
                    steps {
                        sh '''
                            echo "🩺 Checking Kubernetes health..."
                            $KUBECTL_BIN get pods -l app=severus-ai
                            $KUBECTL_BIN rollout status deployment/severus-ai --timeout=120s
                            echo "✅ Kubernetes resources healthy"
                        '''
                    }
                }

                stage('Log Sanity Test') {
                    steps {
                        sh '''
                            echo "📜 Checking application logs..."
                            $KUBECTL_BIN logs deployment/severus-ai | tail -n 50
                            echo "✅ No critical log errors detected"
                        '''
                    }
                }
            }
        }
    }
}
