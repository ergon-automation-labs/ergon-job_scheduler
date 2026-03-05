pipeline {
  agent { label 'built-in' }

  options {
    timeout(time: 30, unit: 'MINUTES')
    timestamps()
  }

  environment {
    MIX_ENV = 'prod'
    BOT_NAME = 'job_bot'
    RELEASE_DIR = "/opt/ergon/releases/${BOT_NAME}"
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          echo "Cloning dependency repositories..."
          cd ..
          [ -d bot_army_core ] || git clone https://github.com/ergon-automation-labs/ergon-core.git bot_army_core
          [ -d bot_army_runtime ] || git clone https://github.com/ergon-automation-labs/ergon-runtime.git bot_army_runtime
        '''
      }
    }

    stage('Test') {
      steps {
        sh '''
          echo "Installing dependencies..."
          mix deps.get
          echo "Running tests..."
          mix test
        '''
      }
    }

    stage('Build Release') {
      steps {
        sh '''
          echo "Building OTP release..."
          mix deps.get --only prod
          mix release --overwrite
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          TIMESTAMP=$(date +%Y%m%d%H%M%S)
          DEST="${RELEASE_DIR}/releases/${TIMESTAMP}"

          echo "Creating release directory..."
          mkdir -p "${DEST}"

          echo "Copying release artifacts..."
          cp -r _build/prod/rel/${BOT_NAME}/* "${DEST}/"

          echo "Updating current symlink..."
          ln -sfn "${DEST}" "${RELEASE_DIR}/current"

          echo "Restarting service..."
          launchctl kickstart -k system/com.botarmy.${BOT_NAME} || launchctl load /Library/LaunchDaemons/com.botarmy.${BOT_NAME}.plist

          echo "Waiting for service to stabilize..."
          sleep 5

          echo "Deploy complete!"
        '''
      }
    }

  }

  post {
    success {
      sh '''
        VERSION=$(cat _build/prod/rel/${BOT_NAME}/releases/RELEASES | tail -1 | cut -d' ' -f2)
        /opt/bot_army/scripts/nats_publish.sh ops.deploy.complete \
          "{\"bot\":\"${BOT_NAME}\",\"node\":\"air\",\"triggered_by\":\"jenkins\",\"status\":\"success\",\"version\":\"${VERSION}\"}"
      '''
    }
    failure {
      sh '''
        /opt/bot_army/scripts/nats_publish.sh ops.deploy.failed \
          "{\"bot\":\"${BOT_NAME}\",\"node\":\"air\",\"triggered_by\":\"jenkins\",\"status\":\"failed\"}"
      '''
    }
  }
}
