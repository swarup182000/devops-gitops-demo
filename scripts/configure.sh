#!/usr/bin/env bash
# Usage: ./scripts/configure.sh <github-username>
set -euo pipefail
USER_LC=$(echo "$1" | tr '[:upper:]' '[:lower:]')
sed -i.bak "s|GITHUB_USER|${USER_LC}|g" helm/demo-app/values.yaml argocd/application.yaml
rm -f helm/demo-app/values.yaml.bak argocd/application.yaml.bak
echo "Done. Ab commit + push karo."
