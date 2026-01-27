pipeline {
    agent any

    environment {
        IMAGE_NAME = "adityahere/severus-ai"
        IMAGE_TAG  = "v1"
        APP_PORT   = "8501"
        SCAN_IMAGE = "adityahere/severus-ai:v1"
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
                    python3 --version
                    python3 -m pip install --upgrade pip
                    python3 -m pip install -r requirements.txt
                '''
            }
        }

        stage('Application Run') {
            steps {
                sh '''
                    echo "🚀 Running Streamlit application (smoke run)..."

                    nohup python3 -m streamlit run app.py \
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

                    tail -n 30 app.log || true

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
                    /usr/local/bin/docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                '''
            }
        }

        stage('Trivy Security Scan') {
            steps {
                script {
                    echo "🔐 Running Trivy scan on ${SCAN_IMAGE}"

                    sh """
                        docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        aquasec/trivy:latest image \
                        --exit-code 1 \
                        --severity CRITICAL,HIGH \
                        --format table \
                        ${SCAN_IMAGE} | tee trivy-report.txt
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
                        echo "$DOCKER_PASS" | /usr/local/bin/docker login -u "$DOCKER_USER" --password-stdin
                        /usr/local/bin/docker push ${IMAGE_NAME}:${IMAGE_TAG}
                    '''
                }
            }
        }

        stage('Docker Run') {
            steps {
                sh '''
                    echo "🧹 Cleaning old container..."
                    /usr/local/bin/docker ps -q --filter "name=severus-ai" | xargs -r /usr/local/bin/docker stop
                    /usr/local/bin/docker ps -aq --filter "name=severus-ai" | xargs -r /usr/local/bin/docker rm

                    echo "🚀 Running new container..."
                    /usr/local/bin/docker run -d \
                        -p 8503:8501 \
                        -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
                        --name severus-ai \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
        }
    }
}
