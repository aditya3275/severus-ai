pipeline {
    agent any

    environment {
        IMAGE_NAME = "adityahere/severus-ai"
        IMAGE_TAG  = "v1"
        APP_PORT   = "8501"
        SCAN_IMAGE = "adityahere/severus-ai:v1"

        // FIX for macOS Jenkins PATH issues
        DOCKER_BIN = "/usr/local/bin/docker"
        PYTHON_BIN = "/usr/bin/python3"
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

                    echo "---- Streamlit logs ----"
                    tail -n 50 app.log || true
                    echo "-----------------------"

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

        stage('Docker Run') {
            steps {
                sh '''
                    echo "🧹 Cleaning old container..."
                    $DOCKER_BIN ps -q --filter "name=severus-ai" | xargs -r $DOCKER_BIN stop
                    $DOCKER_BIN ps -aq --filter "name=severus-ai" | xargs -r $DOCKER_BIN rm

                    echo "🚀 Running new container..."
                    $DOCKER_BIN run -d \
                        -p 8503:8501 \
                        -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
                        --name severus-ai \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
        }
    }
}
