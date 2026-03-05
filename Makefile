.PHONY: setup help deps test credo dialyzer coverage check format clean release publish-release setup-hooks

help:
	@echo "BotArmyJob - Job Scheduling Bot"
	@echo ""
	@echo "Available commands:"
	@echo "  make setup           - Set up project (deps.get + install git hooks)"
	@echo "  make setup-hooks     - Install git hooks for pre-push validation"
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
	@echo ""
	@echo "Normal workflow:"
	@echo "  git push             - Pre-push hook validates, builds, and publishes automatically"
	@echo ""

setup: init deps setup-hooks
	@echo "Setup complete."

setup-hooks:
	@git config core.hooksPath git-hooks
	@echo "✓ Git hooks installed (core.hooksPath = git-hooks)"

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
	@echo "Location: _build/prod/rel/job_bot/"
	@echo ""

publish-release: release
	@echo "==============================================="
	@echo "Publishing release to GitHub"
	@echo "==============================================="
	@echo ""

	# Get version from release metadata
	VERSION=$$(cat _build/prod/rel/job_bot/releases/RELEASES | tail -1 | cut -d' ' -f2); \
	echo "Version: $$VERSION"; \
	\
	# Create tarball
	echo "Creating release tarball..."; \
	tar -czf job_bot-$$VERSION.tar.gz -C _build/prod/rel job_bot/; \
	echo "✓ Tarball created: job_bot-$$VERSION.tar.gz"; \
	echo ""; \
	\
	# Create GitHub release
	echo "Creating GitHub release v$$VERSION..."; \
	gh release create v$$VERSION job_bot-$$VERSION.tar.gz \
		--title "Release v$$VERSION" \
		--notes "Job Bot Elixir release v$$VERSION. Download and deploy with Jenkins." \
		--draft=false; \
	echo "✓ Release published to GitHub"; \
	echo ""; \
	echo "Next steps:"; \
	echo "1. Jenkins will automatically detect the new release"; \
	echo "2. Trigger deployment in Jenkins UI or wait for auto-deployment"; \
	echo "3. Check deployment status: make jenkins-logs"; \
	echo ""
