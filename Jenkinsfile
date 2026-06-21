pipeline {
    agent any

    environment {
        HARBOR_URL = '192.168.255.140:80'
        HARBOR_PROJECT = 'ruoyi-cloud'
        DOCKER_CREDENTIALS_ID = 'harbor-auth'
        TAG = "${BUILD_NUMBER}"
    }

    stages {
        stage('Maven 构建Java项目') {
            steps {
                sh 'mvn clean package -DskipTests'
            }
        }

        stage('复制产物到 Docker 目录') {
            steps {
                dir('docker') {
                    sh '''
                        chmod +x copy.sh
                        ./copy.sh
                        echo "复制完成，校验关键文件："
                        ls -l ruoyi/gateway/jar/*.jar
                        ls -l ruoyi/auth/jar/*.jar
                        ls -l ruoyi/visual/monitor/jar/*.jar
                        ls -l ruoyi/modules/system/jar/*.jar
                    '''
                }
            }
        }

        stage('构建并推送镜像到 Harbor') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${DOCKER_CREDENTIALS_ID}",
                    usernameVariable: 'HARBOR_USER',
                    passwordVariable: 'HARBOR_PASS'
                )]) {
                    script {
                        def services = [
                            [name: 'ruoyi-gateway', dockerfile: 'ruoyi/gateway',        context: 'ruoyi/gateway'],
                            [name: 'ruoyi-auth',    dockerfile: 'ruoyi/auth',           context: 'ruoyi/auth'],
                            [name: 'ruoyi-system',  dockerfile: 'ruoyi/modules/system', context: 'ruoyi/modules/system'],
                            [name: 'ruoyi-nginx',   dockerfile: 'ruoyi-ui',                context: 'ruoyi-ui']
                        ]

                        sh "docker login ${HARBOR_URL} -u ${HARBOR_USER} -p ${HARBOR_PASS}"

                        dir('docker') {
                            for (service in services) {
                                def imageName = "${HARBOR_URL}/${HARBOR_PROJECT}/${service.name}:${TAG}"
                                def latestImageName = "${HARBOR_URL}/${HARBOR_PROJECT}/${service.name}:latest"
                                sh """
                                    docker build -t ${imageName} -f ${service.dockerfile}/Dockerfile ${service.context}
                                    docker tag ${imageName} ${latestImageName}
                                    docker push ${imageName}
                                    docker push ${latestImageName}
                                    echo "✅ 已推送镜像: ${imageName} 和 ${latestImageName}"
                                """
                            }
                        }
                    }
                }
            }
        }
            
            stage('重启k8s微服务') {
                steps {
                    script {
                        def services = [
                            'ruoyi-gateway',
                            'ruoyi-auth',
                            'ruoyi-modules-system',
                            'ruoyi-nginx'
                        ]
                        withCredentials([file(
                            credentialsId: 'k8s-master',   // 你现有的 kubeconfig 凭据
                            variable: 'KUBECONFIG'
                        )]) {
                            for (service in services) {
                                sh """
                                    kubectl rollout restart deployment/${service} -n ruoyi-cloud
                                    kubectl rollout status deployment/${service} -n ruoyi-cloud
                                """
                            }
                        }
                    }
                }
            }
    }

        post {
            always {
                node('built-in') {
                    sh "docker image prune -f"
                }
            }
        }
}