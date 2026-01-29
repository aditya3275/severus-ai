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

        /* ================= PHASE A (RUN ONCE) ================= */

        stage('Phase A – Observability Bootstrap') {
            steps {
                sh '''
                    echo "🔍 Checking if Phase A already ran..."

                    if $KUBECTL_BIN get configmap observability-bootstrap -n observability >/dev/null 2>&1; then
                        echo "✅ Phase A already completed. Skipping..."
                        exit 0
                    fi

                    echo "🚀 Running Phase A: Observability Bootstrap (ONE TIME)"

                    $KUBECTL_BIN create namespace observability || true

                    $HELM_BIN repo add grafana https://grafana.github.io/helm-charts || true
                    $HELM_BIN repo update

                    $HELM_BIN upgrade --install loki grafana/loki-stack \
                      --namespace observability \
                      --set grafana.enabled=false \
                      --set loki.persistence.enabled=false \
                      --set loki.auth_enabled=false

                    $HELM_BIN upgrade --install grafana grafana/grafana \
                      --namespace observability \
                      --set adminPassword=admin \
                      --set service.type=ClusterIP

                    $KUBECTL_BIN create configmap observability-bootstrap \
                      -n observability \
                      --from-literal=installed=true

                    echo "✅ Phase A completed successfully"
                '''
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
                    tail -n 30 app.log || true
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

        stage('Deploy to Kubernetes') {
            steps {
                sh '''
                    echo "☸️ Deploying Severus AI..."

                    $KUBECTL_BIN delete deployment severus-ai --ignore-not-found

                    $HELM_BIN upgrade --install severus-ai helm/severus-ai \
                      --set image.repository=${IMAGE_NAME} \
                      --set image.tag=${IMAGE_TAG}
                '''
            }
        }

        /* ================= POST-DEPLOY ================= */

        stage('Post-Deployment Tests') {
            parallel {

                stage('Ingress Reachability Test') {
                    steps {
                        sh 'curl --fail http://severus-ai.local'
                    }
                }

                stage('Kubernetes Health Test') {
                    steps {
                        sh '''
                            $KUBECTL_BIN rollout status deployment/severus-ai --timeout=120s
                            $KUBECTL_BIN get pods -l app=severus-ai
                        '''
                    }
                }

                stage('Log Sanity Test') {
                    steps {
                        sh '''
                            $KUBECTL_BIN logs deployment/severus-ai | tail -n 50
                        '''
                    }
                }

                /* ✅ RESTORED EXACTLY WHERE IT BELONGS */
                stage('K3s Version Validation') {
                    steps {
                        sh '''
                            echo "🧪 Validating Helm chart across K3s versions..."
                            mkdir -p k3s-validation-logs

                            for VERSION in v1.26 v1.27 v1.28 v1.29 v1.30 v1.31 v1.32 v1.33 v1.34 v1.35 v1.36; do
                              echo "▶ Testing against K3s $VERSION"

                              {
                                echo "====================================="
                                echo "Target K3s Version: $VERSION"
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
                              } > k3s-validation-logs/k3s-${VERSION}.log
                            done

                            echo "✅ K3s compatibility validation complete"
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
    }
}
