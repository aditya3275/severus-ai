pipeline {
    agent any

    environment {
        IMAGE_NAME = "adityahere/severus-ai"
        IMAGE_TAG  = "v1"
        APP_PORT   = "8501"
        SCAN_IMAGE = "adityahere/severus-ai:v1"

        // Absolute paths (macOS Jenkins safe)
        DOCKER_BIN  = "/usr/local/bin/docker"
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

        /* ================= APPLICATION QUALITY GATES ================= */

        stage('Application Build') {
            steps {
                sh '''
                    echo "🔧 Building application..."
                    $PYTHON_BIN --version
                    $PYTHON_BIN -m pip install --upgrade pip
                    $PYTHON_BIN -m pip install -r requirements.txt
                '''
            }
        }

        stage('Application Run') {
            steps {
                sh '''
                    echo "🚀 Running Streamlit application (smoke run)..."

                    nohup $PYTHON_BIN -m streamlit run app.py \
                        --server.port=${APP_PORT} \
                        --server.address=0.0.0.0 \
                        --server.headless=true \
                        > app.log 2>&1 &

                    sleep 30
                '''
            }
        }

        stage('Application Test') {
            steps {
                sh '''
                    echo "🧪 Testing Streamlit application..."

                    tail -n 50 app.log || true

                    curl --fail --retry 10 --retry-delay 3 http://127.0.0.1:${APP_PORT}

                    echo "✅ Streamlit app is reachable"

                    pkill -f "python3 -m streamlit run app.py" || true
                '''
            }
        }

        /* ================= DOCKER & SECURITY ================= */

        stage('Docker Build Image') {
            steps {
                sh '''
                    echo "🐳 Building Docker image..."
                    $DOCKER_BIN build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                '''
            }
        }

        stage('Trivy Security Scan') {
            steps {
                script {
                    echo "🔐 Running Trivy scan on ${SCAN_IMAGE}"

                    sh """
                        $DOCKER_BIN run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        aquasec/trivy:latest image \
                        --exit-code 1 \
                        --severity CRITICAL,HIGH \
                        --format table \
                        ${SCAN_IMAGE} 2>&1 | tee trivy-report.txt
                    """
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-report.txt', fingerprint: true
                }
            }
        }

        stage('Docker Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "$DOCKER_PASS" | $DOCKER_BIN login -u "$DOCKER_USER" --password-stdin
                        $DOCKER_BIN push ${IMAGE_NAME}:${IMAGE_TAG}
                    '''
                }
            }
        }

        /* ================= K3s DEPLOY ================= */

        stage('Deploy to Kubernetes (K3s via Helm)') {
            steps {
                sh '''
                    echo "☸️ Deploying Severus AI to K3s using Helm..."

                    $HELM_BIN upgrade --install severus-ai helm/severus-ai \
                      --set image.repository=${IMAGE_NAME} \
                      --set image.tag=${IMAGE_TAG}
                '''
            }
        }

        stage('Verify Kubernetes Deployment') {
            steps {
                sh '''
                    echo "🔍 Verifying Kubernetes deployment on K3s..."

                    $KUBECTL_BIN get pods -l app=severus-ai
                    $KUBECTL_BIN get svc severus-ai

                    $KUBECTL_BIN rollout status deployment/severus-ai --timeout=120s
                '''
            }
        }
    }
}
