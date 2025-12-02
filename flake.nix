{
  description = "VibeDb - An in-memory VibeDb SQL-compatible database in Elixir";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Use beam packages for proper Erlang/Elixir version management
        beamPackages = pkgs.beam.packagesWith pkgs.beam.interpreters.erlang_27;
        elixir = beamPackages.elixir_1_17;
        erlang = pkgs.beam.interpreters.erlang_27;
        
        # Build the vibe_db escript
        vibe_db = pkgs.stdenv.mkDerivation {
          pname = "vibe_db";
          version = "0.1.0";
          
          src = ./vibe_db;
          
          nativeBuildInputs = [ elixir erlang pkgs.git ];
          
          # Set environment variables for Elixir/Mix
          MIX_ENV = "prod";
          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";
          
          configurePhase = ''
            export MIX_HOME=$TMPDIR/mix
            export HEX_HOME=$TMPDIR/hex
            mkdir -p $MIX_HOME $HEX_HOME
          '';
          
          buildPhase = ''
            export MIX_HOME=$TMPDIR/mix
            export HEX_HOME=$TMPDIR/hex
            
            # Project has no external dependencies, compile directly
            mix compile
            mix escript.build
          '';
          
          installPhase = ''
            mkdir -p $out/bin
            cp vibe_db $out/bin/vibe_db
            
            # Create a wrapper script that sets up the Erlang environment
            mv $out/bin/vibe_db $out/bin/.vibe_db-wrapped
            cat > $out/bin/vibe_db << 'EOF'
#!/bin/sh
exec "${erlang}/bin/escript" "$(dirname "$0")/.vibe_db-wrapped" "$@"
EOF
            chmod +x $out/bin/vibe_db
            substituteInPlace $out/bin/vibe_db --replace '"${erlang}' '"${erlang}'
          '';
          
          meta = with pkgs.lib; {
            description = "An in-memory VibeDb SQL-compatible database REPL";
            homepage = "https://github.com/vibecoding-inc/database";
            license = licenses.mit;
            mainProgram = "vibe_db";
          };
        };
      in
      {
        packages = {
          default = vibe_db;
          vibe_db = vibe_db;
        };
        
        apps = {
          default = {
            type = "app";
            program = "${vibe_db}/bin/vibe_db";
          };
          vibe_db = {
            type = "app";
            program = "${vibe_db}/bin/vibe_db";
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
            
            echo "VibeDb development shell"
            echo "Run 'cd vibe_db && mix deps.get && mix compile' to build"
            echo "Run 'mix escript.build && ./vibe_db' to start the REPL"
          '';
        };
      }
    );
}
