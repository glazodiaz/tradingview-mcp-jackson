#!/bin/bash
# Alpha Finance — Paperclip Setup Script
# Run this on any Linux machine to restore the firm

set -e
FIRM_DIR="$HOME/alpha-finance"
COMPANY_NAME="Alpha Finance"

echo "Setting up Alpha Finance..."
mkdir -p "$FIRM_DIR"/{agents/{ceo,research,backtest,risk-management,execution,cost-optimizer},strategies/{active,archived,watchlist},logs/{trades,performance,agent-activity},memory/{institutional,performance},config}
cp -r . "$FIRM_DIR/"

# Start Paperclip (assumes DATABASE_URL and ANTHROPIC_API_KEY are set)
paperclipai run &
sleep 15

echo "Firm directory ready at $FIRM_DIR"
echo "Run the agent setup script next to create agents in Paperclip."
