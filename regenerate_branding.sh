#!/bin/sh

# update nix dependencies just in case it's needed.
./nix_dependencies/update_nix_deps.sh

nix develop --command bash -c "RAILS_ENV=development rake branding:generate"
