self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.rlm;

  renderValue = value:
    if value == null then
      "nil"
    else if builtins.isBool value then
      if value then "true" else "false"
    else if builtins.isInt value then
      toString value
    else if builtins.isList value then
      "[" + lib.concatStringsSep ", " (map renderValue value) + "]"
    else
      builtins.toJSON value;

  apiKeyExpr = ''File.read!("${cfg.apiKeyFile}") |> String.trim()'';

  configText = ''
    import Config

    config :rlm, Rlm.RLM.Settings,
      provider: :openai,
      model: ${renderValue cfg.model},
      sub_model: ${renderValue cfg.subModel},
      api_key: ${apiKeyExpr},
      openai_base_url: ${renderValue cfg.openaiBaseUrl},
      request_timeout: ${renderValue cfg.requestTimeout},
      runtime_command: ${renderValue cfg.runtimeCommand},
      max_iterations: ${renderValue cfg.maxIterations},
      max_depth: 1,
      max_sub_queries: ${renderValue cfg.maxSubQueries},
      truncate_length: ${renderValue cfg.truncateLength},
      metadata_preview_lines: ${renderValue cfg.metadataPreviewLines},
      max_context_bytes: ${renderValue cfg.maxContextBytes},
      max_context_files: ${renderValue cfg.maxContextFiles},
      max_slice_chars: ${renderValue cfg.maxSliceChars},
      storage_dir: ${renderValue cfg.storageDir}

    ${cfg.extraConfig}
  '';
in
{
  options.programs.rlm = {
    enable = lib.mkEnableOption "the rlm CLI configuration";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "inputs.rlm.packages.${pkgs.stdenv.hostPlatform.system}.default";
      description = "Package added to home.packages for the RLM CLI.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "gpt-4o-mini";
      description = "Root model identifier.";
    };

    subModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional sub-query model identifier.";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing the OpenAI API key. The file is read at runtime, so the secret is not embedded in the Nix store.";
    };

    openaiBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://api.openai.com/v1";
      description = "OpenAI-compatible provider API base URL. Defaults to the vanilla OpenAI endpoint.";
    };

    requestTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60000;
      description = "OpenAI-compatible provider request timeout in milliseconds.";
    };

    runtimeCommand = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${pkgs.python3}/bin/python3" ];
      description = "Command used to start the persistent Python REPL runtime.";
    };

    maxIterations = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
      description = "Maximum number of root-model iterations.";
    };

    maxSubQueries = lib.mkOption {
      type = lib.types.ints.between 0 500;
      default = 24;
      description = "Maximum number of sub-queries per run.";
    };

    truncateLength = lib.mkOption {
      type = lib.types.ints.between 100 50000;
      default = 5000;
      description = "Maximum amount of execution output fed back between iterations.";
    };

    metadataPreviewLines = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 12;
      description = "How many lines of context preview to include in root-model metadata.";
    };

    maxContextBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10 * 1024 * 1024;
      description = "Maximum aggregate context size in bytes.";
    };

    maxContextFiles = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Maximum number of files loaded into a single run.";
    };

    maxSliceChars = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4000;
      description = "Reserved for compatibility with the Elixir settings schema.";
    };

    storageDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/rlm/runs";
      description = "Directory where run trajectories are stored.";
    };

    createStorageDir = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to create the configured storage directory during Home Manager activation.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra Elixir config to append to ~/.config/rlm/config.exs.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.apiKeyFile != null;
        message = "programs.rlm.apiKeyFile must be set when programs.rlm.enable = true.";
      }
    ];

    xdg.configFile."rlm/config.exs".text = configText;

    home.packages = [ cfg.package ];

    home.activation.rlmAliStorageDir = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.optionalString cfg.createStorageDir ''
        mkdir -p ${lib.escapeShellArg cfg.storageDir}
      ''
    );
  };
}
