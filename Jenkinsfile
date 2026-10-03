// ═════════════════════════════════════════════════════════════════════════════
//  RuoYi-Cloud CI/CD 流水线（优化版）
//  链路：拉代码 → Maven 构建 → 复制产物 → 构建推送镜像 → K8s 滚动更新
// ═════════════════════════════════════════════════════════════════════════════

// ── 服务清单：构建与部署【共用一份】，避免两个列表漂移 ──────────────────────
//    container 必须与 Deployment 里 containers[0].name 完全一致，
//    可用这条命令核对：
//      kubectl -n ruoyi-cloud get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" -> "}{.spec.template.spec.containers[0].name}{"\n"}{end}'
def SERVICES = [
    [name: 'ruoyi-gateway', ctx: 'ruoyi/gateway',        deploy: 'ruoyi-gateway',         container: 'ruoyi-gateway'],
    [name: 'ruoyi-auth',    ctx: 'ruoyi/auth',           deploy: 'ruoyi-auth',            container: 'ruoyi-auth'],
    [name: 'ruoyi-system',  ctx: 'ruoyi/modules/system', deploy: 'ruoyi-modules-system',  container: 'ruoyi-modules-system'],
    [name: 'ruoyi-nginx',   ctx: 'ruoyi-ui',             deploy: 'ruoyi-nginx',           container: 'ruoyi-nginx'],
]

pipeline {
    agent any

    options {
        timestamps()                 // 日志带时间戳，排查耗时方便
        skipDefaultCheckout(true)    // 用下面的显式 checkout 控制克隆参数
        disableConcurrentBuilds()    // ★ 防并发：避免两个构建互踩
        timeout(time: 60, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    parameters {
        // ★ 换成你的真实仓库地址（必须 SSH，HTTPS 在这套网络不通）
        string(name: 'GIT_URL',        defaultValue: 'git@github.com/moyu-777/ruoyi-cloud.git')
        string(name: 'GIT_BRANCH',     defaultValue: '*/master')
        string(name: 'GIT_CRED',       defaultValue: 'github-pvt')

        string(name: 'HARBOR_URL',     defaultValue: '192.168.203.120:80')
        string(name: 'HARBOR_PROJECT', defaultValue: 'ruoyi-cloud')
        string(name: 'HARBOR_CRED',    defaultValue: 'harbor-passport')

        string(name: 'KUBE_NAMESPACE', defaultValue: 'ruoyi-cloud')
        booleanParam(name: 'DO_DEPLOY', defaultValue: true)
    }

    environment {
        MVN        = '/usr/share/maven/bin/mvn'
        MAVEN_OPTS = '-Xmx512m -XX:+UseSerialGC'
    }

    stages {

        stage('拉取代码') {
            steps {
                checkout([$class: 'GitSCM',
                    branches: [[name: "${params.GIT_BRANCH}"]],
                    userRemoteConfigs: [[
                        url: "${params.GIT_URL}",
                        credentialsId: "${params.GIT_CRED}"
                    ]],
                    extensions: [
                        // ★ 浅克隆 + 放宽超时。这套网络拉 GitHub 只有 40~80KB/s，
                        //   不设会撞上 git-client 默认的 600 秒克隆超时
                        [$class: 'CloneOption', shallow: true, depth: 1, noTags: true, timeout: 30],
                        [$class: 'CleanCheckout']
                    ]
                ])
            }
        }

        stage('计算镜像 tag') {
            steps {
                script {
                    def sha   = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                    def dirty = sh(script: 'git status --porcelain | head -1 || true', returnStdout: true).trim()
                    // ★ tag = <commit短SHA>[-dirty]-<构建号>
                    //   每次唯一，才能让 kubectl set image 真正触发滚动更新
                    env.IMAGE_TAG = sha + (dirty ? '-dirty' : '') + '-' + env.BUILD_NUMBER
                    echo "本次镜像 tag: ${env.IMAGE_TAG}"
                }
            }
        }

        stage('Maven 构建') {
            steps {
                // -B                  批处理模式，日志更干净
                // -Ddocker.skip=true  若 POM 里有 fabric8 docker-maven-plugin
                //                     且指向不存在的远程 daemon，必须加这个
                sh "${MVN} -B -DskipTests -Ddocker.skip=true clean package"
            }
        }

        stage('复制产物到 Docker 目录') {
            steps {
                dir('docker') {
                    sh '''
                        set -e
                        bash copy.sh
                        echo "=== 校验关键产物 ==="
                        for f in ruoyi/gateway/jar/*.jar \
                                 ruoyi/auth/jar/*.jar \
                                 ruoyi/modules/system/jar/*.jar; do
                            if [ ! -f "$f" ]; then
                                echo "❌ 缺少产物: $f"
                                exit 1
                            fi
                            ls -l "$f"
                        done
                    '''
                }
            }
        }

        stage('构建并推送镜像') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${params.HARBOR_CRED}",
                    usernameVariable: 'HARBOR_USER',
                    passwordVariable: 'HARBOR_PASS')]) {
                    dir('docker') {
                        sh '''
                            set -e
                            # ★ --password-stdin：密码不进命令行，也就不会出现在 ps / 日志
                            echo "$HARBOR_PASS" | docker login "$HARBOR_URL" -u "$HARBOR_USER" --password-stdin
                        '''
                        script {
                            for (svc in SERVICES) {
                                def image  = "${params.HARBOR_URL}/${params.HARBOR_PROJECT}/${svc.name}:${env.IMAGE_TAG}"
                                def latest = "${params.HARBOR_URL}/${params.HARBOR_PROJECT}/${svc.name}:latest"
                                echo "── 构建 ${svc.name} ──"
                                sh """
                                    set -e
                                    docker build -t ${image} -f ${svc.ctx}/Dockerfile ${svc.ctx}
                                    docker tag  ${image} ${latest}
                                    docker push ${image}
                                    docker push ${latest}
                                    echo "✅ ${svc.name} → ${image}"
                                """
                            }
                        }
                        sh 'docker logout "$HARBOR_URL" || true'
                    }
                }
            }
        }

        stage('K8s 滚动更新') {
            when { expression { return params.DO_DEPLOY } }
            steps {
                script {
                    def updated = []
                    try {
                        for (svc in SERVICES) {
                            def image = "${params.HARBOR_URL}/${params.HARBOR_PROJECT}/${svc.name}:${env.IMAGE_TAG}"
                            echo "── 更新 ${svc.deploy} ──"

                            sh """
                                set -e
                                echo -n "更新前镜像: "
                                kubectl -n ${params.KUBE_NAMESPACE} get deployment ${svc.deploy} \\
                                  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
                            """

                            // ★ 用 set image（tag 唯一 → 一定触发滚动），不用 rollout restart
                            sh """
                                set -e
                                kubectl -n ${params.KUBE_NAMESPACE} set image \\
                                  deployment/${svc.deploy} \\
                                  ${svc.container}=${image}
                            """
                            updated << svc.deploy      // 记下来：万一后面失败要回滚它

                            sh """
                                set -e
                                kubectl -n ${params.KUBE_NAMESPACE} rollout status \\
                                  deployment/${svc.deploy} --timeout=300s
                            """
                        }
                    } finally {
                        env.UPDATED_DEPLOYS = updated.join(',')
                    }
                    echo "✅ 已更新的 Deployment: ${env.UPDATED_DEPLOYS}"
                }
            }
        }
    }

    post {
        failure {
            script {
                // 只回滚【确实被 set image 改过】的，不误伤其它服务
                if (params.DO_DEPLOY && env.UPDATED_DEPLOYS) {
                    echo "⚠️ 发布失败，回滚: ${env.UPDATED_DEPLOYS}"
                    for (d in env.UPDATED_DEPLOYS.split(',')) {
                        if (d?.trim()) {
                            sh "kubectl -n ${params.KUBE_NAMESPACE} rollout undo deployment/${d.trim()} || true"
                        }
                    }
                }
            }
        }
        always {
            // ★ 不要写 node('built-in'){...}：agent any 已占用一个 executor，
            //   在 post 里再申请节点可能造成 executor 死锁
            sh 'docker logout "$HARBOR_URL" 2>/dev/null || true'
            sh 'docker image prune -f || true'
        }
    }
}
