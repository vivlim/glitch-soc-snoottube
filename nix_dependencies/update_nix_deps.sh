#! /usr/bin/env nix-shell
#! nix-shell -i /bin/sh -p bundix ruby prefetch-yarn-deps

# lightweight version of the script in nixpkgs for building the nix files that declare dependencies
# currently must be run inside `nix develop` because the nixpkgs referenced in the flake has a fix for prefetch-yarn-deps.

# cd to where the script is located
cd $(dirname "$0")

# create gemset.nix
bundix --lockfile="../Gemfile.lock" --gemfile="../Gemfile"

# this is what ashkitten did for tootcat's update.sh
YARN_SHA256="$(prefetch-yarn-deps -v ../yarn.lock | tee /dev/stderr | tail -n2)"
# write it as a double-quoted nix string to a file that can be imported
echo "\"$YARN_SHA256\"" > yarn-sha256.nix

# fetch version string
VERSION="$(ruby -e "require '../lib/mastodon/version.rb'; puts Mastodon::Version.to_s")"
echo "\"$VERSION\"" > version.nix
