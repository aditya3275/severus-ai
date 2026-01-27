pipeline {
    agent any

    environment {
        IMAGE_NAME = "adityahere/severus-ai"
        IMAGE_TAG  = "v1"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install Dependencies') {
            steps {
                sh 'python3 -m pip install --upgrade pip'
                sh 'python3 -m pip install -r requirements.txt'
            }
        }

        stage('Run App Check') {
            steps {
                sh 'python3 --version'
            }
        }

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
                # Stop container if running
                /usr/local/bin/docker ps -q --filter "name=severus-ai" | xargs -r /usr/local/bin/docker stop

                # Remove container if exists
                /usr/local/bin/docker ps -aq --filter "name=severus-ai" | xargs -r /usr/local/bin/docker rm

                # Run new container
                /usr/local/bin/docker run -d \
                    -p 8501:8503 \
                    -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
                    --name severus-ai \
                    adityahere/severus-ai:v1
                '''
            }
        }
    }
}
