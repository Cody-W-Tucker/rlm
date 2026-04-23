{
  description = "A Home Manager-friendly Elixir environment for the RLM CLI";

  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # unstable Nixpkgs

  outputs =
    { self, ... }@inputs:

    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [ inputs.self.overlays.default ];
            };
          }
        );

      module = import ./nix/modules/rlm.nix self;
    in
    {
      homeManagerModules = {
        default = module;
        rlm = module;
      };

      packages = forEachSupportedSystem (
        { pkgs }:
        let
          package = import ./nix/packages/rlm.nix { inherit pkgs; };
        in
        {
          default = package;
          rlm = package;
        }
      );

      apps = forEachSupportedSystem (
        { pkgs }:
        let
          package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        in
        {
          default = {
            type = "app";
            program = "${package}/bin/rlm";
            meta.description = "Run the RLM CLI";
          };

          rlm = {
            type = "app";
            program = "${package}/bin/rlm";
            meta.description = "Run the RLM CLI";
          };
        }
      );

      overlays.default = final: prev: rec {
        # documentation
        # https://nixos.org/manual/nixpkgs/stable/#sec-beam

        # ==== ERLANG ====

        # use whatever version is currently defined in nixpkgs
        # erlang = pkgs.beam.interpreters.erlang;

        # use latest version of Erlang 27
        erlang = final.beam.interpreters.erlang_27;

        # specify exact version of Erlang OTP
        # erlang = pkgs.beam.interpreters.erlang.override {
        #   version = "26.2.2";
        #   sha256 = "sha256-7S+mC4pDcbXyhW2r5y8+VcX9JQXq5iEUJZiFmgVMPZ0=";
        # }

        # ==== BEAM packages ====

        # all BEAM packages will be compile with your preferred erlang version
        pkgs-beam = final.beam.packagesWith erlang;

        # ==== Elixir ====

        # use whatever version is currently defined in nixpkgs
        # elixir = pkgs-beam.elixir;

        # use latest version of Elixir 1.17
        elixir = pkgs-beam.elixir_1_17;

        # specify exact version of Elixir
        # elixir = pkgs-beam.elixir.override {
        #   version = "1.17.1";
        #   sha256 = "sha256-a7A+426uuo3bUjggkglY1lqHmSbZNpjPaFpQUXYtW9k=";
        # };
      };

      devShells = forEachSupportedSystem (
        { pkgs }:
        {
          default = pkgs.mkShellNoCC {
            packages =
              with pkgs;
              [
                # use the Elixr/OTP versions defined above; will also install OTP, mix, hex, rebar3
                elixir

                # mix needs it for downloading dependencies
                git

                # useful for fetching remote context and inspecting JSON responses
                curl
                jq
                python3

                # convenient for local docs/examples and future assets
                nodejs_20
              ]
              ++
                # Linux only
                pkgs.lib.optionals pkgs.stdenv.isLinux (
                  with pkgs;
                  [
                    gigalixir
                    inotify-tools
                    libnotify
                  ]
                )
              ++
                # macOS only
                pkgs.lib.optionals pkgs.stdenv.isDarwin (
                  with pkgs;
                  [
                    terminal-notifier
                  ]
                );
            }
            // {
              shellHook = ''
                echo "RLM CLI shell ready"
                echo "  mix deps.get && mix compile"
                echo "  mix test"
                echo '  mix rlm --provider mock --text "sample context" "What is this about?"'
              '';
            };
        }
      );
    };
}
