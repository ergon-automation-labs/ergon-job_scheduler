.PHONY: setup help deps test credo dialyzer coverage check format clean release publish-release setup-hooks setup-db reset-db deploy

help:
	@echo "BotArmyJob - Job Scheduling Bot"
	@echo ""
	@echo "Setup commands:"
	@echo "  make setup           - Set up project (deps.get + install git hooks + setup database)"
	@echo "  make setup-hooks     - Install git hooks for pre-push validation"
	@echo "  make setup-db        - Create and migrate test database (required for testing)"
	@echo "  make reset-db        - Drop and recreate test database (useful for troubleshooting)"
	@echo ""
	@echo "Development commands:"
	@echo "  make test            - Run all tests"
	@echo "  make credo           - Run linter"
	@echo "  make dialyzer        - Run static analysis"
	@echo "  make coverage        - Run tests with coverage"
	@echo "  make check           - Run all checks (test, credo, dialyzer)"
	@echo "  make format          - Format Elixir code"
	@echo "  make clean           - Clean build artifacts"
	@echo ""
	@echo "Release commands (normally automatic via git hook):"
	@echo "  make release         - Build OTP release locally (manual, if needed)"
	@echo "  make publish-release - Build, package, and publish to GitHub (manual, if needed)"
	@echo "  make deploy          - Deploy built release locally via Salt (for testing)"
	@echo ""
	@echo "Normal workflow:"
	@echo "  git push             - Pre-push hook validates, builds, and publishes automatically"
	@echo "                         Jenkins then deploys automatically"
	@echo ""

setup: init deps setup-hooks setup-db
	@echo "✓ Setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Configure .env with your database settings (if needed)"
	@echo "  2. Run: make test"
	@echo "  3. Start developing!"
	@echo ""

setup-hooks:
	@git config core.hooksPath git-hooks
	@echo "✓ Git hooks installed (core.hooksPath = git-hooks)"

setup-db:
	@echo "Setting up test database..."
	@MIX_ENV=test mix ecto.create || true
	@MIX_ENV=test mix ecto.migrate
	@echo "✓ Test database created and migrations applied"

reset-db:
	@echo "⚠️  Resetting test database (dropping and recreating)..."
	@MIX_ENV=test mix ecto.drop || true
	@MIX_ENV=test mix ecto.create
	@MIX_ENV=test mix ecto.migrate
	@echo "✓ Test database reset complete"

init:
	@if [ ! -d .git ]; then git init; echo "Git initialized."; else echo "Git already initialized."; fi

deps:
	mix deps.get

test:
	mix test

credo:
	mix credo

dialyzer: deps
	mix dialyzer

coverage:
	mix coveralls

check: test credo dialyzer
	@echo "All checks passed!"

format:
	mix format

clean:
	mix clean
	rm -rf _build cover

release: check
	@echo "==============================================="
	@echo "Building OTP release"
	@echo "==============================================="
	MIX_ENV=prod mix release --overwrite
	@echo ""
	@echo "✓ Release built successfully"
	@echo "Location: _build/prod/rel/job_scheduler/"
	@echo ""

publish-release: release
	@echo "==============================================="
	@echo "Publishing release to GitHub"
	@echo "==============================================="
	@echo ""

	# Get version from mix.exs
	VERSION=$$(grep 'version:' mix.exs | head -1 | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "Version: $$VERSION"; \
	\
	# Create tarball with flat structure
	echo "Creating release tarball..."; \
	cd _build/prod/rel && tar -czf job_scheduler-$$VERSION.tar.gz -C job_scheduler . && cd - > /dev/null; \
	echo "✓ Tarball created: _build/prod/rel/job_scheduler-$$VERSION.tar.gz"; \
	echo ""; \
	\
	# Create GitHub release
	echo "Creating GitHub release v$$VERSION..."; \
	gh release create v$$VERSION _build/prod/rel/job_scheduler-$$VERSION.tar.gz \
		--repo "ergon-automation-labs/ergon-job" \
		--title "Release v$$VERSION" \
		--notes "Job Scheduler Elixir release v$$VERSION. Deployed by Jenkins." \
		--draft=false; \
	echo "✓ Release published to GitHub"; \
	echo ""; \
	echo "Next steps:"; \
	echo "1. Jenkins will automatically detect the new release"; \
	echo "2. Trigger deployment in Jenkins UI or wait for auto-deployment"; \
	echo "3. Monitor deployment in Jenkins"; \
	echo ""

deploy: release
	@echo "==============================================="
	@echo "Deploying release locally via Salt"
	@echo "==============================================="
	@echo ""

	# Get version from mix.exs
	VERSION=$$(grep 'version:' mix.exs | head -1 | sed 's/.*version: "\([^"]*\)".*/\1/'); \
	echo "Version: $$VERSION"; \
	echo ""; \
	\
	# Create release directory with timestamp
	TIMESTAMP=$$(date +%Y%m%d%H%M%S); \
	DEST="/opt/ergon/releases/job_scheduler/releases/$$TIMESTAMP"; \
	echo "Deploying to: $$DEST"; \
	mkdir -p "$$DEST"; \
	\
	# Extract tarball
	cd _build/prod/rel && tar -xzf job_scheduler-$$VERSION.tar.gz -C "$$DEST" && cd - > /dev/null; \
	\
	# Update symlink
	ln -sfn "$$DEST" /opt/ergon/releases/job_scheduler/current; \
	echo "✓ Release deployed successfully"; \
	echo ""; \
	\
	# Apply Salt state
	echo "Applying Salt state..."; \
	sudo /opt/salt/salt -G bot_army_node_type:air state.apply bots.job || true; \
	echo ""; \
	\
	echo "Next steps:"; \
	echo "1. Verify service is running: launchctl list com.botarmy.job_scheduler"; \
	echo "2. Check logs: tail -50 /var/log/bot_army/job_scheduler.log"; \
	echo ""
