#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p judy_statistical_analysis/results

Rscript judy_statistical_analysis/analysis.R \
  > judy_statistical_analysis/results/analysis_output.txt 2>&1

Rscript -e 'writeLines(capture.output(sessionInfo()), "judy_statistical_analysis/results/session_info.txt")'

echo "Analysis completed. Results saved in judy_statistical_analysis/results."
