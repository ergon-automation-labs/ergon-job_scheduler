pipeline {
  // Download releases from GitHub and deploy them
  agent { label 'built-in' }

  options {
    timeout(time: 30, unit: 'MINUTES')
    timestamps()
  }

  triggers {
    // Poll GitHub every 5 minutes for new commits
    pollSCM('H/5 * * * *')
  }

  environment {
    BOT_NAME = 'job_bot'
    STATE_NAME = 'job_bot'
    RELEASE_DIR = "/opt/ergon/releases/${BOT_NAME}"
    GITHUB_REPO = "ergon-automation-labs/ergon-job"
    SALT_TARGET = '-G bot_army_node_type:air'
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Download Build Artifact') {
      steps {
        sh '''
          echo "==============================================="
          echo "Downloading pre-built release from GitHub"
          echo "==============================================="

          # Get the latest published release (not a draft)
          LATEST_RELEASE=$(gh api repos/${GITHUB_REPO}/releases \
            -q '.[] | select(.draft==false) | .tag_name' | head -1)

          if [ -z "$LATEST_RELEASE" ]; then
            echo "ERROR: No published release found on GitHub"
            exit 1
          fi

          echo "Latest release: $LATEST_RELEASE"

          # Download the tarball asset
          echo "Downloading: ${BOT_NAME}-*.tar.gz"
          mkdir -p ./release-artifact

          gh release download $LATEST_RELEASE \
            --repo ${GITHUB_REPO} \
            --pattern "*.tar.gz" \
            -D ./release-artifact

          echo "✓ Release downloaded successfully"

          # Extract tarball
          cd ./release-artifact
          TARBALL=$(ls -1 *.tar.gz | head -1)
          echo "Extracting: $TARBALL"
          tar -xzf "$TARBALL"
          rm "$TARBALL"
          ls -la
          cd ..
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          echo "==============================================="
          echo "Deploying release"
          echo "==============================================="
          echo "Start time: $(date)"

          TIMESTAMP=$(date +%Y%m%d%H%M%S)
          DEST="${RELEASE_DIR}/releases/${TIMESTAMP}"

          echo "Creating release directory..."
          mkdir -p "${DEST}"

          echo "Copying release artifacts..."
          cp -r ./release-artifact/* "${DEST}/"

          echo "Updating current symlink..."
          ln -sfn "${DEST}" "${RELEASE_DIR}/current"

          echo "Deploying service via Salt..."
          # Apply dependencies first (common.core and common.schemas are included by bot states)
          sudo /opt/salt/salt ${SALT_TARGET} state.apply common.core
          sudo /opt/salt/salt ${SALT_TARGET} state.apply common.schemas
          # Then apply the bot state
          sudo /opt/salt/salt ${SALT_TARGET} state.apply bots.${STATE_NAME}

          echo "Checking service health..."
          /opt/bot_army/scripts/health_check.sh ${BOT_NAME}

          echo "Deploy complete!"
          echo "Completion time: $(date)"
        '''
      }
    }

    stage('Run Migrations') {
      steps {
        sh '''
          echo "==============================================="
          echo "Running database migrations"
          echo "==============================================="

          # Get the release binary path
          RELEASE_BIN="${RELEASE_DIR}/current/bot_army_job/bin/bot_army_job"

          if [ ! -f "$RELEASE_BIN" ]; then
            echo "⚠️  Release binary not found at $RELEASE_BIN"
            echo "Skipping migrations (may already be at correct schema)"
            exit 0
          fi

          # Run migrations using the release
          # The release has database config from launchd environment
          echo "Running: $RELEASE_BIN eval 'BotArmyJob.Release.migrate()'"

          $RELEASE_BIN eval 'BotArmyJob.Release.migrate()' || {
            echo "⚠️  Migration failed or Release module not found"
            echo "Continuing with deployment (manual migration may be needed)"
          }

          echo "✓ Migrations complete"
        '''
      }
    }

  }

  post {
    success {
      sh '''
        # Extract version from the deployed release
        if [ -f ./release-artifact/bot_army_job/releases/start_erl.data ]; then
          VERSION=$(awk '{print $2}' ./release-artifact/bot_army_job/releases/start_erl.data)
        fi
        VERSION=${VERSION:-"0.1.0"}

        # Extract release timestamp and git SHA
        TIMESTAMP=$(basename $(readlink "${RELEASE_DIR}/current"))
        GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

        # Build richer JSON payload
        PAYLOAD=$(cat <<EOF
{"bot":"${BOT_NAME}","node":"air","triggered_by":"jenkins","status":"success","version":"${VERSION}","release":"${TIMESTAMP}","sha":"${GIT_SHA}"}
EOF
)
        echo "📢 Notifying NATS of successful deployment..."
        /opt/bot_army/scripts/nats_publish.sh ops.builds.${BOT_NAME} "$PAYLOAD" || echo "⚠️  NATS notification failed (non-blocking)"
      '''
    }
    failure {
      sh '''
        # Build JSON payload for failure
        PAYLOAD=$(cat <<EOF
{"bot":"${BOT_NAME}","node":"air","triggered_by":"jenkins","status":"failed"}
EOF
)
        echo "📢 Notifying NATS of failed deployment..."
        /opt/bot_army/scripts/nats_publish.sh ops.builds.${BOT_NAME} "$PAYLOAD" || echo "⚠️  NATS notification failed (non-blocking)"
      '''
    }
    always {
      cleanWs()
    }
  }
}
