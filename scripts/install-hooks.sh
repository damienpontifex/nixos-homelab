#!/usr/bin/env bash
# Install git hooks for this repository

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_HOOKS_DIR="$(git rev-parse --git-dir)/hooks"

echo "Installing git hooks..."

# Install pre-commit hook
ln -sf "../../scripts/pre-commit" "$GIT_HOOKS_DIR/pre-commit"
echo "✓ Installed pre-commit hook"

echo ""
echo "Git hooks installed successfully!"
echo ""
echo "The pre-commit hook will:"
echo "  - Validate flake configuration"
echo "  - Check all Nix files for syntax errors"
echo "  - Ensure configurations can be evaluated"
echo ""
echo "To skip the hook temporarily, use: git commit --no-verify"
