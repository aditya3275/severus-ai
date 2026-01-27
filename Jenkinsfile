pipeline {
    agent any

    environment {
        IMAGE_NAME = "adityahere/severus-ai"
        IMAGE_TAG  = "v1"
        APP_PORT   = "8501"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        /* ------------------- NEW STAGES START ------------------- */

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
                    echo "🚀 Running application (smoke run)..."
                    nohup python3 app.py > app.log 2>&1 &
                    echo $! > app.pid
                    sleep 10
                '''
            }
        }

        stage('Application Test') {
            steps {
                sh '''
                    echo "🧪 Testing application..."

                    # Check process still running
                    ps -p $(cat app.pid)

                    # Basic sanity test (imports)
                    python3 - <<EOF
import app
print("✅ App imports successfully")
EOF

                    # Cleanup
                    kill $(cat app.pid)
                '''
            }
        }

        /* ------------------- NEW STAGES END ------------------- */

        stage('Docker Build Image') {
            steps {
                sh '''
                    /usr/local/bin/docker build -t $IMAGE_NAME:$IMAGE_TAG .
                '''
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
                        /usr/local/bin/docker push $IMAGE_NAME:$IMAGE_TAG
                    '''
                }
            }
        }

        stage('Docker Run') {
            steps {
                sh '''
                    # Stop old container
                    /usr/local/bin/docker ps -q --filter "name=severus-ai" | xargs -r /usr/local/bin/docker stop
                    /usr/local/bin/docker ps -aq --filter "name=severus-ai" | xargs -r /usr/local/bin/docker rm

                    # Run new container
                    /usr/local/bin/docker run -d \
                        -p 8503:8501 \
                        -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
                        --name severus-ai \
                        adityahere/severus-ai:v1
                '''
            }
        }
    }
}
