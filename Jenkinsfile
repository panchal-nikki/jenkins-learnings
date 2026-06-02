pipeline {
    agent any

    tools {
        nodejs 'Node18'
    }

    environment {
        IMAGE_NAME     = 'react-app'
        IMAGE_TAG      = "${BUILD_NUMBER}"
        CONTAINER_NAME = 'react-app-container'
        PORT           = '3000'
        CI             = 'true'
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Cloning repository...'
                git branch: 'master',
                    url: 'https://github.com/panchal-nikki/jenkins-learnings.git'
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
                """                      // ✅ sh with Linux syntax
            }
        }
    }

    post {
        success {
            echo "✅ App is live at http://localhost:${PORT}"
        }
        failure {
            echo '❌ Pipeline failed. Check Console Output.'
        }
    }
}
