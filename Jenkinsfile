pipeline {
    agent any
    stages {
        stage('拉取代码') {
            steps {
                git branch: 'master',
                    credentialsId: 'github-ssh',
                    url: 'git@github.com:moyu-777/ruoyi-cloud.git'
            }
        }
        stage('测试') {
            steps {
                sh 'ls -la'
            }
        }
    }
}
