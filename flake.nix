{
  description = "WIP flake for Mastodon instance with customizations";

  inputs = {
    nixpkgs.url = "github:vivlim/nixpkgs/mastodon-fixes-on-unstable";
  };

  outputs = all@{ self, nixpkgs, ... }: let
    pkgs = import nixpkgs {
      system = "x86_64-linux";
    };

    version = pkgs.lib.fileContents ./nix_dependencies/version;
    yarnSha256 = pkgs.lib.fileContents ./nix_dependencies/yarn-sha256;

    nixpkgsFlakeChannel = pkgs.stdenv.mkDerivation { # create a directory that contains a link to the flake nixpkgs input, named 'nixpkgs' so that nix-shell <nixpkgs> imports use it instead.
      name = "nixpkgs-flake-channel";
      version = "1.0.0";
      phases = "installPhase";
      installPhase = ''
        mkdir -p $out
        ln -s ${pkgs.path} $out/nixpkgs
      '';
    };

    nixpkgsOverriddenMastodon = pkgs.mastodon.override {
      pname = "glitch-soc-nixpkgsovr";
      inherit version;
      srcOverride = ./.;
      dependenciesDir = ./nix_dependencies;
      #yarnOfflineCacheSha256Override = "${yarnSha256}";
    };
  in {
    packages.x86_64-linux.gems = nixpkgsOverriddenMastodon.mastodon-gems;

    packages.x86_64-linux.yarnModules = pkgs.stdenv.mkDerivation { # based on nixpkgs mastodon-modules, but only deals with yarn modules & sets env to development.
      pname = "glitch-soc-modules";
      inherit version;
      src = ./.;

      yarnOfflineCache = pkgs.fetchYarnDeps {
        yarnLock = ./yarn.lock;
        sha256 = yarnSha256;
      };

      nativeBuildInputs = with pkgs; [ fixup_yarn_lock nodejs-slim yarn ];

      RAILS_ENV = "development";
      NODE_ENV = "development";

      buildPhase = ''
        export HOME=$PWD
        # This option is needed for openssl-3 compatibility
        # Otherwise we encounter this upstream issue: https://github.com/mastodon/mastodon/issues/17924
        export NODE_OPTIONS=--openssl-legacy-provider
        fixup_yarn_lock ~/yarn.lock
        yarn config --offline set yarn-offline-mirror $yarnOfflineCache
        yarn install --offline --frozen-lockfile --ignore-engines --ignore-scripts --no-progress
        patchShebangs ~/bin
        patchShebangs ~/node_modules
        # skip running yarn install
        rm -rf ~/bin/yarn
        yarn cache clean --offline
        rm -rf ~/node_modules/.cache
      '';

      installPhase = ''
        mkdir -p $out
        cp -r node_modules $out
      '';
  };

    # Shell that currently has dependencies needed for regenerating branding
    devShell.x86_64-linux = let
      postgresProcfileRunner = pkgs.writeShellScriptBin "pg_procfile"
        ''
          # if we are told to exit, stop postgres.
          trap '${pkgs.postgresql.out}/bin/pg_ctl stop' EXIT > /dev/null
          # start postgres.
          ${pkgs.postgresql.out}/bin/pg_ctl start -o --unix_socket_directories=/tmp
          # wait for postgres to finish.
          tail --pid=$(head -n1 $PGDATA/postmaster.pid) -f /dev/null
        '';
      redisProcfileRunner = pkgs.writeShellScriptBin "redis_procfile"
        ''
          ${pkgs.redis}/bin/redis-server --dir $REDIS_DATA
        '';

      # create a procfile for launching the infrastructure
      infraProcFile = pkgs.writeText "Procfile.infra"
        ''
        redis: ${redisProcfileRunner}/bin/redis_procfile
        postgresql: ${postgresProcfileRunner}/bin/pg_procfile
        '';
    in pkgs.mkShell {
      buildInputs = [ self.packages.x86_64-linux.gems.wrappedRuby pkgs.librsvg pkgs.imagemagick pkgs.overmind pkgs.redis pkgs.nodejs-16_x pkgs.postgresql postgresProcfileRunner ];
      shellHook = ''
      export RAILS_ENV=development
      export MASTODON_REPO_ROOT=`git rev-parse --show-toplevel`
      export OVERMIND_PROCFILE="$MASTODON_REPO_ROOT/Procfile.dev"
      export OVERMIND_SOCKET="$MASTODON_REPO_ROOT/.overmind.app.sock"
      export OVERMIND_SKIP_ENV=1
      #export OVERMIND_DAEMONIZE=1
      export BUNDLE_PATH="$MASTODON_REPO_ROOT/vendor/bundle"
      export NIX_PATH=${nixpkgsFlakeChannel} # so that update_nix_deps.sh can use the flake's nixpkgs (important atm because we have a patch that fixes prefetch-yarn-deps)

      export REDIS_DATA="$MASTODON_REPO_ROOT/redis"
      mkdir -p $REDIS_DATA;

      export PGDATA="$MASTODON_REPO_ROOT/postgres/data"
      export DB_USER=$(whoami)
      export PGHOST=/tmp
      export DB_HOST=$PGHOST # for rails
      mkdir -p $PGDATA
      if [ "$(ls -A $PGDATA)" ]; then
        echo "db exists in $PGDATA"
      else
        echo "creating db in $PGDATA"
        ${pkgs.postgresql}/bin/initdb
        #bundle exec rails db:setup
      fi

      alias infra="OVERMIND_PROCFILE=\"${infraProcFile}\" OVERMIND_SOCKET=\"$MASTODON_REPO_ROOT/.overmind.infra.sock\" overmind"
      alias app="OVERMIND_ANY_CAN_DIE=1 overmind"

      infra s -D

      mkdir -p $MASTODON_REPO_ROOT/node_modules
      ${pkgs.rsync}/bin/rsync --recursive -l --chmod 755 --delete ${self.packages.x86_64-linux.yarnModules}/node_modules $MASTODON_REPO_ROOT

      export PATH=${self.packages.x86_64-linux.yarnModules}/node_modules/.bin:$MASTODON_REPO_ROOT/bin:$PATH

      # This option is needed for openssl-3 compatibility
      # Otherwise we encounter this upstream issue: https://github.com/mastodon/mastodon/issues/17924
      export NODE_OPTIONS=--openssl-legacy-provider

      echo "to launch everything: \`overmind start\`. see https://github.com/DarthSim/overmind/blob/master/README.md"
      echo "if dependencies are missing, run script in ./nix_dependencies"
      echo "bundle exec rails db:setup"
      echo "bundle exec rails assets:precompile"
      echo "pg_ctl start|stop to control the db"
      '';
    };
  };
}
