pipeline {
    agent any

    environment {
        IMAGE_NAME      = 'react-app'
        IMAGE_TAG       = "${BUILD_NUMBER}"
        CONTAINER_NAME  = 'react-app-container'
        PORT            = '3000'
        CI              = 'true'

        // ---- Kubernetes / Helm settings ----
        K8S_NAMESPACE   = 'react-app'
        HELM_RELEASE    = 'react-app-release'
        HELM_CHART_PATH = './helm/react-app'
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Cloning repository...'
                git branch: 'master',
                    url: 'https://github.com/panchal-nikki/jenkins-learnings.git'
            }
        }

        stage('Verify Node') {
            steps {
                sh 'node --version && npm --version'
            }
        }

        stage('Install Dependencies') {
            steps {
                sh 'npm install'         // ✅ changed from bat to sh
            }
        }

        stage('Run Tests') {
            steps {
                sh 'npm test -- --watchAll=false --passWithNoTests'   // ✅ sh
            }
        }

        stage('Build') {
            steps {
                sh 'npm run build'       // ✅ sh
            }
        }

        stage('Docker Build') {
            steps {
                sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."         // ✅ sh
                sh "docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest"
            }
        }

        stage('Deploy') {
            steps {
                sh """
                    docker stop ${CONTAINER_NAME} || true
                    docker rm   ${CONTAINER_NAME} || true
                    docker run -d \\
                        --name ${CONTAINER_NAME} \\
                        -p ${PORT}:80 \\
                        --restart unless-stopped \\
                        ${IMAGE_NAME}:latest
                """
            }
        }

        // -------------------------------------------------------
        // KUBERNETES STAGES (Learning)
        // These stages only run when a kubeconfig is available.
        // Toggle with a Jenkins parameter or condition as needed.
        // -------------------------------------------------------

        stage('K8s: Create Namespace') {
            when {
                // Only run if DEPLOY_TO_K8S param is set to 'true'
                // Add a Boolean parameter "DEPLOY_TO_K8S" in Jenkins job config
                expression { return params.DEPLOY_TO_K8S == true }
            }
            steps {
                echo "Creating Kubernetes namespace: ${K8S_NAMESPACE}"
                sh "kubectl apply -f k8s/namespace.yaml"
            }
        }

        stage('K8s: Deploy Raw Manifests') {
            when {
                expression { return params.DEPLOY_TO_K8S == true }
            }
            steps {
                echo "Applying raw Kubernetes manifests..."
                sh """
                    kubectl apply -f k8s/configmap.yaml
                    kubectl apply -f k8s/deployment.yaml
                    kubectl apply -f k8s/service.yaml
                    kubectl apply -f k8s/ingress.yaml
                    kubectl apply -f k8s/hpa.yaml
                """
                sh "kubectl rollout status deployment/react-app -n ${K8S_NAMESPACE} --timeout=120s"
            }
        }

        stage('Helm: Lint Chart') {
            when {
                expression { return params.DEPLOY_WITH_HELM == true }
            }
            steps {
                echo "Linting Helm chart..."
                // helm lint checks for syntax errors in your chart templates
                sh "helm lint ${HELM_CHART_PATH}"
            }
        }

        stage('Helm: Dry Run') {
            when {
                expression { return params.DEPLOY_WITH_HELM == true }
            }
            steps {
                echo "Running Helm dry-run (renders templates without applying)..."
                sh """
                    helm upgrade --install ${HELM_RELEASE} ${HELM_CHART_PATH} \\
                        --namespace ${K8S_NAMESPACE} \\
                        --create-namespace \\
                        --set image.tag=${IMAGE_TAG} \\
                        --dry-run --debug
                """
            }
        }

        stage('Helm: Deploy') {
            when {
                expression { return params.DEPLOY_WITH_HELM == true }
            }
            steps {
                echo "Deploying with Helm release: ${HELM_RELEASE}..."
                sh """
                    helm upgrade --install ${HELM_RELEASE} ${HELM_CHART_PATH} \\
                        --namespace ${K8S_NAMESPACE} \\
                        --create-namespace \\
                        --set image.tag=${IMAGE_TAG} \\
                        --wait --timeout 120s
                """
                sh "helm status ${HELM_RELEASE} -n ${K8S_NAMESPACE}"
            }
        }
    }

    post {
        success {
            echo "✅ App is live at http://localhost:${PORT}"
            echo "✅ Helm release: ${HELM_RELEASE} | Namespace: ${K8S_NAMESPACE}"
        }
        failure {
            echo '❌ Pipeline failed. Check Console Output.'
        }
        always {
            // Show Helm history for learning purposes
            sh "helm history ${HELM_RELEASE} -n ${K8S_NAMESPACE} || true"
        }
    }
}
