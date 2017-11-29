pipeline {
  agent any

  stages {
    stage('pre-build') {
      steps {
        checkout scm
        sh 'rm -rf ./results ./tmp'
      }
    }

    stage('build') {
      steps {
        sh 'sudo hab studio -D run /bin/bash scripts/build.sh'
      }
    }
  }

  post {
     always {
       archive 'tmp/*.out'
       deleteDir()
     }
   }
}
