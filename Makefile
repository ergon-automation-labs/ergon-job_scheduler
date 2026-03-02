.PHONY: setup help deps test credo dialyzer coverage check format clean

help:
	@echo "BotArmyJob - Job Scheduling Bot"
	@echo ""
	@echo "Available commands:"
	@echo "  make setup        - Set up project (deps.get)"
	@echo "  make test         - Run all tests"
	@echo "  make credo        - Run linter"
	@echo "  make dialyzer     - Run static analysis"
	@echo "  make coverage     - Run tests with coverage"
	@echo "  make check        - Run all checks (test, credo, dialyzer)"
	@echo "  make format       - Format Elixir code"
	@echo "  make clean        - Clean build artifacts"
	@echo ""

setup: init deps
	@echo "Setup complete."

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
