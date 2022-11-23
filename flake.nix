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

      # create a procfile that also launches postgresql.
      infraProcFile = pkgs.writeText "Procfile.infra"
        ''
        redis: ${redisProcfileRunner}/bin/redis_procfile
        postgresql: ${postgresProcfileRunner}/bin/pg_procfile
        '';
        # ${builtins.readFile ./Procfile.dev}
      envFile = pkgs.writeText ".env.nixDevelop"
      ''
        LOCAL_DOMAIN=localhost
        BIND=0.0.0.0
        DB_HOST
      '';
    in pkgs.mkShell {
      buildInputs = [ self.packages.x86_64-linux.gems.wrappedRuby pkgs.librsvg pkgs.imagemagick pkgs.overmind pkgs.redis pkgs.postgresql postgresProcfileRunner ];
      shellHook = ''
      export RAILS_ENV=development
      export MASTODON_REPO_ROOT=`git rev-parse --show-toplevel`
      export OVERMIND_PROCFILE="$MASTODON_REPO_ROOT/Procfile.dev"
      export OVERMIND_SOCKET="$MASTODON_REPO_ROOT/.overmind.app.sock"
      export OVERMIND_SKIP_ENV=yeah
      export BUNDLE_PATH="$MASTODON_REPO_ROOT/vendor/bundle"

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

      echo "to launch everything: \`overmind start\`. see https://github.com/DarthSim/overmind/blob/master/README.md"
      echo "if dependencies are missing, run script in ./nix_dependencies"
      echo "bundle exec rails db:setup"
      echo "pg_ctl start|stop to control the db"
      '';
    };
  };
}
