{
  description = "WIP flake for Mastodon instance with customizations";

  inputs = {
    nixpkgs.url = "github:vivlim/nixpkgs/mastodon-fixes-on-unstable";
  };

  outputs = all@{ self, nixpkgs, ... }: let
    pkgs = import nixpkgs {
      system = "x86_64-linux";
    };
  in {
    packages.x86_64-linux.gems = (pkgs.mastodon.override {
      pname = "glitch-soc";
      srcOverride = ./.;
      dependenciesDir = ./nix_dependencies;
      version = "v4.0.0";
    }).mastodon-gems;

    # Shell that currently has dependencies needed for regenerating branding
    devShell.x86_64-linux = pkgs.mkShell {
      buildInputs = [ self.packages.x86_64-linux.gems.wrappedRuby pkgs.librsvg pkgs.imagemagick ];
    };
  };
}
