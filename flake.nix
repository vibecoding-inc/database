{
  description = "OracleDb - An in-memory Oracle SQL-compatible database in Elixir";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Elixir/Erlang versions
        erlang = pkgs.erlang;
        elixir = pkgs.elixir;
        
        # Build the oracle_db escript
        oracle_db = pkgs.stdenv.mkDerivation {
          pname = "oracle_db";
          version = "0.1.0";
          
          src = ./oracle_db;
          
          nativeBuildInputs = [ elixir erlang pkgs.git ];
          
          # Set environment variables for Elixir/Mix
          MIX_ENV = "prod";
          MIX_HOME = "$TMPDIR/mix";
          HEX_HOME = "$TMPDIR/hex";
          
          configurePhase = ''
            export MIX_HOME=$TMPDIR/mix
            export HEX_HOME=$TMPDIR/hex
            mkdir -p $MIX_HOME $HEX_HOME
            
            # Install hex and rebar locally
            mix local.hex --force
            mix local.rebar --force
          '';
          
          buildPhase = ''
            mix deps.get --only prod
            mix compile
            mix escript.build
          '';
          
          installPhase = ''
            mkdir -p $out/bin
            cp oracle_db $out/bin/oracle_db
          '';
          
          meta = with pkgs.lib; {
            description = "An in-memory Oracle SQL-compatible database REPL";
            homepage = "https://github.com/vibecoding-inc/database";
            license = licenses.mit;
            mainProgram = "oracle_db";
          };
        };
      in
      {
        packages = {
          default = oracle_db;
          oracle_db = oracle_db;
        };
        
        apps = {
          default = {
            type = "app";
            program = "${oracle_db}/bin/oracle_db";
          };
          oracle_db = {
            type = "app";
            program = "${oracle_db}/bin/oracle_db";
          };
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = [
            erlang
            elixir
            pkgs.git
          ];
          
          shellHook = ''
            export MIX_HOME=$PWD/.nix-mix
            export HEX_HOME=$PWD/.nix-hex
            export PATH=$MIX_HOME/bin:$PATH
            export PATH=$HEX_HOME/bin:$PATH
            
            mkdir -p $MIX_HOME $HEX_HOME
            
            echo "OracleDb development shell"
            echo "Run 'cd oracle_db && mix deps.get && mix compile' to build"
            echo "Run 'mix escript.build && ./oracle_db' to start the REPL"
          '';
        };
      }
    );
}
