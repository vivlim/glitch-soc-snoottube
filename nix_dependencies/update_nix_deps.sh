#! /usr/bin/env nix-shell
#! nix-shell -i /bin/sh -p bundix

# lightweight version of the script in nixpkgs for building the nix files that declare dependencies

# cd to where the script is located
cd $(dirname "$0")

bundix --lockfile="../Gemfile.lock" --gemfile="../Gemfile"
