# Makefile for CloudWatch Logs Analysis
# Usage: make help

# AWS Configuration
AWS_PROFILE ?= sandbox
AWS_REGION ?= eu-central-1
LOG_GROUP ?= /mi-proyecto/app

# Default target
.DEFAULT_GOAL := help

# ============================================
# CloudWatch Logs (AWS CLI)
# ============================================

logs-aws:
	@echo "Tailing CloudWatch logs from $(LOG_GROUP)..."
	@aws logs tail $(LOG_GROUP) --follow --profile $(AWS_PROFILE) --region $(AWS_REGION)

logs-aws-recent:
	@echo "Showing logs from last hour..."
	@aws logs tail $(LOG_GROUP) --since 1h --profile $(AWS_PROFILE) --region $(AWS_REGION)

logs-aws-today:
	@echo "Showing logs from today..."
	@aws logs tail $(LOG_GROUP) --since 1d --profile $(AWS_PROFILE) --region $(AWS_REGION)

logs-aws-errors:
	@echo "Filtering ERROR and CRITICAL logs from CloudWatch..."
	@aws logs filter-log-events \
		--log-group-name $(LOG_GROUP) \
		--filter-pattern '{ $$.level = "ERROR" || $$.level = "CRITICAL" }' \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--output json | jq -rC '.events[] | .message | fromjson | "\(.["@timestamp"]) [\(.level)] \(.logger // .name): \(.message)"'

logs-aws-query:
	@echo "Sample CloudWatch Insights Query:"
	@echo "fields @timestamp, level, message"
	@echo "| filter level = 'ERROR'"
	@echo "| sort @timestamp desc"
	@echo "| limit 50"

# ============================================
# CloudWatch Information
# ============================================

logs-info:
	@echo "CloudWatch Log Group Info:"
	@aws logs describe-log-groups \
		--log-group-name-prefix $(LOG_GROUP) \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--output table

logs-streams:
	@echo "CloudWatch Log Streams:"
	@aws logs describe-log-streams \
		--log-group-name $(LOG_GROUP) \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--order-by LastEventTime \
		--descending \
		--max-items 5 \
		--output table

# ============================================
# Advanced CloudWatch Queries
# ============================================

logs-filter:
	@if [ -z "$(FILTER)" ]; then \
		echo "Usage: make logs-filter FILTER='pattern'"; \
		echo "Example: make logs-filter FILTER='ERROR'"; \
		exit 1; \
	fi
	@aws logs filter-log-events \
		--log-group-name $(LOG_GROUP) \
		--filter-pattern "$(FILTER)" \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--output json | jq -rC '.events[] | .message | fromjson | "\(.["@timestamp"]) [\(.level)] \(.logger // .name): \(.message)"'

logs-by-level:
	@if [ -z "$(LEVEL)" ]; then \
		echo "Usage: make logs-by-level LEVEL=ERROR"; \
		echo "Available levels: DEBUG, INFO, WARNING, ERROR, CRITICAL"; \
		exit 1; \
	fi
	@aws logs filter-log-events \
		--log-group-name $(LOG_GROUP) \
		--filter-pattern '{ $$.level = "$(LEVEL)" }' \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--output json | jq -rC '.events[] | .message | fromjson | "\(.["@timestamp"]) [\(.level)] \(.logger // .name): \(.message)"'

logs-search:
	@if [ -z "$(QUERY)" ]; then \
		echo "Usage: make logs-search QUERY=text"; \
		exit 1; \
	fi
	@aws logs filter-log-events \
		--log-group-name $(LOG_GROUP) \
		--filter-pattern "$(QUERY)" \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--output json | jq -rC '.events[] | .message | fromjson | "\(.["@timestamp"]) [\(.level)] \(.logger // .name): \(.message)"'

logs-time-range:
	@if [ -z "$(START)" ] || [ -z "$(END)" ]; then \
		echo "Usage: make logs-time-range START=<timestamp_ms> END=<timestamp_ms>"; \
		echo "Example: make logs-time-range START=1702390000000 END=1702393600000"; \
		exit 1; \
	fi
	@aws logs filter-log-events \
		--log-group-name $(LOG_GROUP) \
		--start-time $(START) \
		--end-time $(END) \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--output json | jq -rC '.events[] | .message | fromjson | "\(.["@timestamp"]) [\(.level)] \(.logger // .name): \(.message)"'

# ============================================
# Different Output Formats
# ============================================

logs-full:
	@echo "Showing full JSON logs (last 20)..."
	@aws logs filter-log-events \
		--log-group-name $(LOG_GROUP) \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--max-items 20 \
		--output json | jq -C '.events[] | .message | fromjson'

logs-compact:
	@echo "Compact view (last 50)..."
	@aws logs filter-log-events \
		--log-group-name $(LOG_GROUP) \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--max-items 50 \
		--output json | jq -rC '.events[] | .message | fromjson | "\(.level | .[0:1]) \(.["@timestamp"][11:19]) \(.message)"'

logs-table:
	@echo "Table view (last 30)..."
	@aws logs filter-log-events \
		--log-group-name $(LOG_GROUP) \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--max-items 30 \
		--output json | jq -rC '.events[] | .message | fromjson | [.["@timestamp"], .level, .app, .process, .message] | @tsv' | column -t -s $$'\t'

logs-json:
	@echo "Pretty JSON with selected fields (last 20)..."
	@aws logs filter-log-events \
		--log-group-name $(LOG_GROUP) \
		--profile $(AWS_PROFILE) \
		--region $(AWS_REGION) \
		--max-items 20 \
		--output json | jq -C '.events[] | .message | fromjson | {time: .["@timestamp"], level, app, process, logger: (.logger // .name), message}'

# ============================================
# Help
# ============================================

help:
	@echo "═══════════════════════════════════════════════════════════"
	@echo "  CloudWatch Logs - AWS CLI Commands"
	@echo "═══════════════════════════════════════════════════════════"
	@echo ""
	@echo "TAIL & RECENT LOGS:"
	@echo "  make logs-aws                - Tail CloudWatch logs (live stream)"
	@echo "  make logs-aws-recent         - Show logs from last hour"
	@echo "  make logs-aws-today          - Show logs from today"
	@echo "  make logs-aws-errors         - Filter ERROR/CRITICAL logs (formatted)"
	@echo ""
	@echo "FILTERING & SEARCH:"
	@echo "  make logs-by-level LEVEL=X   - Filter by log level (ERROR, INFO, etc.)"
	@echo "  make logs-search QUERY=text  - Search for text in logs"
	@echo "  make logs-filter FILTER=pat  - Custom CloudWatch filter pattern"
	@echo "  make logs-time-range START=x END=y - Logs in time range (ms)"
	@echo ""
	@echo "OUTPUT FORMATS (different views):"
	@echo "  make logs-full               - Full JSON output (last 20)"
	@echo "  make logs-compact            - Compact single-line format (last 50)"
	@echo "  make logs-table              - Table format with columns"
	@echo "  make logs-json               - Pretty JSON with selected fields"
	@echo ""
	@echo "CLOUDWATCH INFO:"
	@echo "  make logs-info               - Show log group information"
	@echo "  make logs-streams            - List recent log streams"
	@echo "  make logs-aws-query          - Sample CloudWatch Insights query"
	@echo ""
	@echo "CONFIGURATION:"
	@echo "  AWS_PROFILE=$(AWS_PROFILE)"
	@echo "  AWS_REGION=$(AWS_REGION)"
	@echo "  LOG_GROUP=$(LOG_GROUP)"
	@echo ""
	@echo "Examples:"
	@echo "  make logs-aws                          # Live tail"
	@echo "  make logs-compact                      # Quick compact view"
	@echo "  make logs-by-level LEVEL=ERROR         # Filter errors"
	@echo "  make logs-search QUERY='user login'    # Search text"
	@echo "  make logs-table                        # Tabular view"
	@echo "  make logs-aws AWS_PROFILE=production   # Different profile"
	@echo "═══════════════════════════════════════════════════════════"

.PHONY: logs-aws logs-aws-recent logs-aws-today logs-aws-errors logs-aws-query \
        logs-info logs-streams \
        logs-by-level logs-search logs-filter logs-time-range \
        logs-full logs-compact logs-table logs-json \
        help
