#!/bin/bash
set -e

source dev-container-features-test-lib
source ./checks.sh

persistence_checks vscode /home/vscode

reportResults
