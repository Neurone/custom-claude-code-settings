#!/usr/bin/env bash
# Test fixture: a hook that always fails, to prove one failing hook doesn't
# abort the rest of install-or-update.sh.
exit 1
