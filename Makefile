SCRIPTS_DIRECTORY ?= $(abspath $(CURDIR)/../scripts)
MIX ?= /Users/abby/.local/share/mise/shims/mix

.PHONY: test-handlers test-stores test-nats test-integration test-full setup help deps test credo dialyzer coverage check format clean release publish-release setup-hooks setup-db reset-db logs deploy push-and-publish

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
	@echo "Operations (deployed server logs):"
	@echo "  make logs            - Tail job_scheduler log with grc (brew install grc; make -C .. install-grc)"
	@echo ""
	@echo "Release commands:"
	@echo "  make release         - Build OTP release locally"
	@echo "  make publish-release - Build, package, and publish to GitHub"
	@echo "  make deploy          - Deploy built release locally via Salt (for testing)"
	@echo ""
	@echo "Normal workflow:"
	@echo "  git push             - Fast compile+test validation"
	@echo "  make push-and-publish - Push then publish release asset"
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
	@MIX_ENV=test $(MIX) ecto.create || true
	@MIX_ENV=test $(MIX) ecto.migrate
	@echo "✓ Test database created and migrations applied"

reset-db:
	@echo "⚠️  Resetting test database (dropping and recreating)..."
	@MIX_ENV=test $(MIX) ecto.drop || true
	@MIX_ENV=test $(MIX) ecto.create
	@MIX_ENV=test $(MIX) ecto.migrate
	@echo "✓ Test database reset complete"

init:
	@if [ ! -d .git ]; then git init; echo "Git initialized."; else echo "Git already initialized."; fi

deps:
	$(MIX) deps.get

test:
	$(MIX) test

test-handlers:
	MIX_ENV=test $(MIX) test --only handlers --trace

test-stores:
	MIX_ENV=test $(MIX) test --only stores --trace

test-nats:
	MIX_ENV=test $(MIX) test --only nats --trace

test-integration:
	$(MIX) test --include integration --trace

test-full:
	$(MIX) test --include integration --include nats_live --trace

credo:
	$(MIX) credo --only warning

dialyzer: deps
	$(MIX) dialyzer

coverage:
	$(MIX) coveralls

check: test credo
	@echo "All checks passed!"

format:
	$(MIX) format

clean:
	$(MIX) clean
	rm -rf _build cover

release: check
	@echo "==============================================="
	@echo "Building OTP release"
	@echo "==============================================="
	rm -rf _build/prod/rel/job_scheduler
	MIX_ENV=prod $(MIX) release
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
	# Create tarball with nested structure
	echo "Creating release tarball..."; \
	cd _build/prod/rel && tar -czf job_scheduler-$$VERSION.tar.gz job_scheduler && cd - > /dev/null; \
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
	# Extract tarball (creates job_scheduler/ subdirectory)
	tar -xzf _build/prod/rel/job_scheduler-$$VERSION.tar.gz -C /opt/ergon/releases/job_scheduler/releases/$$TIMESTAMP; \
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

push-and-publish:
	@git push && $(MAKE) publish-release

logs:
	@$(SCRIPTS_DIRECTORY)/tail_bot_log.sh
