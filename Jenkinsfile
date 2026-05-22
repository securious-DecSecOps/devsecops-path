pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  parameters {
    string(name: 'WORKLOAD_NAME', defaultValue: 'simple-web', description: 'Workload profile name.')
    string(name: 'WORKLOAD_DIR', defaultValue: 'examples/simple-web', description: 'Build context source directory.')
    string(name: 'APP_NAME', defaultValue: 'simple-web', description: 'Kubernetes application name.')
    string(name: 'DOCKERFILE_PATH', defaultValue: 'examples/simple-web/Dockerfile', description: 'Dockerfile path.')
    string(name: 'BUILD_CONTEXT', defaultValue: 'examples/simple-web', description: 'Docker build context.')
    string(name: 'NAMESPACE', defaultValue: 'secure-path-dev', description: 'Target Kubernetes namespace.')
    string(name: 'REGISTRY_URL', defaultValue: 'localhost:9092', description: 'Container registry host.')
    string(name: 'REGISTRY_PROJECT', defaultValue: 'secure-delivery', description: 'Container registry project or repository namespace.')
    string(name: 'IMAGE_TAG', defaultValue: '', description: 'Image tag. Defaults to BUILD_NUMBER when blank.')
    string(name: 'KUBECONFIG', defaultValue: '/var/jenkins_home/kubeconfig', description: 'Kubeconfig path in the Jenkins container.')
    choice(name: 'DEPLOY_MODE', choices: ['kubectl', 'helm', 'argocd'], description: 'Deployment mode for this run.')
    booleanParam(name: 'ENFORCE_GATE', defaultValue: false, description: 'Fail the pipeline when the security gate blocks.')
    string(name: 'HELM_RELEASE', defaultValue: 'simple-web', description: 'Helm release name.')
    string(name: 'HELM_CHART_DIR', defaultValue: 'helm/simple-web', description: 'Helm chart directory.')
    string(name: 'GITOPS_APP_DIR', defaultValue: 'gitops/apps/simple-web/dev', description: 'GitOps app environment directory.')
  }

  environment {
    WORKLOAD_NAME = "${params.WORKLOAD_NAME}"
    WORKLOAD_DIR = "${params.WORKLOAD_DIR}"
    APP_NAME = "${params.APP_NAME}"
    DOCKERFILE_PATH = "${params.DOCKERFILE_PATH}"
    BUILD_CONTEXT = "${params.BUILD_CONTEXT}"
    NAMESPACE = "${params.NAMESPACE}"
    REGISTRY_URL = "${params.REGISTRY_URL}"
    REGISTRY_PROJECT = "${params.REGISTRY_PROJECT}"
    KUBECONFIG = "${params.KUBECONFIG}"
    DEPLOY_MODE = "${params.DEPLOY_MODE}"
    ENFORCE_GATE = "${params.ENFORCE_GATE}"
    HELM_RELEASE = "${params.HELM_RELEASE}"
    HELM_CHART_DIR = "${params.HELM_CHART_DIR}"
    GITOPS_APP_DIR = "${params.GITOPS_APP_DIR}"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Preflight Tools') {
      steps {
        sh '''
          set -euo pipefail

          require_cmd() {
            if ! command -v "$1" >/dev/null 2>&1; then
              echo "ERROR: required command not found: $1" >&2
              exit 1
            fi
          }

          for cmd in docker kubectl helm trivy python3 jq git; do
            require_cmd "$cmd"
          done

          docker --version
          kubectl version --client=true
          helm version
          trivy --version
          python3 --version
          jq --version
          git --version

          if [[ ! -f "${KUBECONFIG}" ]]; then
            echo "ERROR: KUBECONFIG does not exist: ${KUBECONFIG}" >&2
            exit 1
          fi

          # Node reachability is environment-dependent. Keep this as a warning
          # so tool preflight can still distinguish missing tools from a
          # temporarily unavailable cluster.
          if ! kubectl get nodes; then
            echo "WARN: kubectl get nodes failed. Deployment may fail later." >&2
          fi
        '''
      }
    }

    stage('Prepare Metadata') {
      steps {
        script {
          env.IMAGE_TAG = params.IMAGE_TAG?.trim() ? params.IMAGE_TAG.trim() : env.BUILD_NUMBER
          env.IMAGE = "${env.REGISTRY_URL}/${env.REGISTRY_PROJECT}/${env.APP_NAME}:${env.IMAGE_TAG}"
          env.REPORT_DIR = "reports/dev/${env.BUILD_NUMBER}"
        }
        sh '''
          set -euo pipefail
          mkdir -p \
            "${REPORT_DIR}/docker" \
            "${REPORT_DIR}/trivy" \
            "${REPORT_DIR}/gate" \
            "${REPORT_DIR}/registry" \
            "${REPORT_DIR}/helm" \
            "${REPORT_DIR}/gitops" \
            "${REPORT_DIR}/argocd" \
            "${REPORT_DIR}/kubernetes" \
            "${REPORT_DIR}/events"

          GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || true)"
          {
            echo "BUILD_NUMBER=${BUILD_NUMBER}"
            echo "GIT_SHA=${GIT_SHA:-unknown}"
            echo "WORKLOAD_NAME=${WORKLOAD_NAME}"
            echo "WORKLOAD_DIR=${WORKLOAD_DIR}"
            echo "APP_NAME=${APP_NAME}"
            echo "IMAGE=${IMAGE}"
            echo "NAMESPACE=${NAMESPACE}"
            echo "DEPLOY_MODE=${DEPLOY_MODE}"
            echo "ENFORCE_GATE=${ENFORCE_GATE}"
            echo "REPORT_DIR=${REPORT_DIR}"
          } | tee "${REPORT_DIR}/metadata.txt"
        '''
      }
    }

    stage('Docker Build') {
      steps {
        sh 'bash scripts/build-image.sh'
      }
    }

    stage('Trivy Scan') {
      steps {
        sh 'bash scripts/trivy-scan.sh'
      }
    }

    stage('Security Gate') {
      steps {
        sh 'bash scripts/security-gate.sh'
      }
    }

    stage('Registry Login') {
      steps {
        sh 'bash scripts/registry-login.sh'
      }
    }

    stage('Registry Push') {
      steps {
        sh 'bash scripts/push-image.sh'
      }
    }

    stage('Deploy') {
      steps {
        script {
          if (env.DEPLOY_MODE == 'kubectl') {
            sh 'bash scripts/deploy-kubectl.sh'
          } else if (env.DEPLOY_MODE == 'helm') {
            sh 'bash scripts/deploy-helm.sh'
          } else if (env.DEPLOY_MODE == 'argocd') {
            sh 'bash scripts/update-gitops-image.sh'
            sh 'bash scripts/deploy-argocd.sh'
          } else {
            error("Unsupported DEPLOY_MODE='${env.DEPLOY_MODE}'. Use kubectl, helm, or argocd.")
          }
        }
      }
    }

    stage('Collect Evidence') {
      steps {
        sh 'bash scripts/collect-evidence.sh'
      }
    }

    stage('Archive Evidence') {
      steps {
        archiveArtifacts artifacts: "${env.REPORT_DIR}/**", allowEmptyArchive: true, fingerprint: true
      }
    }
  }
}

