self:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.rlm;
  defaultStorageDir = "${config.xdg.stateHome}/rlm/runs";

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

  optionalSetting = name: value: defaultValue:
    lib.optionalString (value != defaultValue) ",\n  ${name}: ${renderValue value}";

  configText = ''
    import Config

    config :rlm, Rlm.Settings,
      api_key: ${apiKeyExpr}${optionalSetting "model" cfg.model "gpt-5.4-mini"}${optionalSetting "sub_model" cfg.subModel null}${optionalSetting "openai_base_url" cfg.openaiBaseUrl "https://api.openai.com/v1"}${optionalSetting "connect_timeout" cfg.connectTimeout 5000}${optionalSetting "first_byte_timeout" cfg.firstByteTimeout 30000}${optionalSetting "idle_timeout" cfg.idleTimeout 15000}${optionalSetting "total_timeout" cfg.totalTimeout 120000}${optionalSetting "runtime_command" cfg.runtimeCommand [ "python3" ]}${optionalSetting "max_iterations" cfg.maxIterations 12}${optionalSetting "max_sub_queries" cfg.maxSubQueries 24}${optionalSetting "truncate_length" cfg.truncateLength 5000}${optionalSetting "max_context_bytes" cfg.maxContextBytes (10 * 1024 * 1024)}${optionalSetting "max_context_files" cfg.maxContextFiles 100}${optionalSetting "max_slice_chars" cfg.maxSliceChars 4000}${optionalSetting "storage_dir" cfg.storageDir defaultStorageDir}

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
      default = "gpt-5.4-mini";
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

    connectTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5000;
      description = "Connection timeout in milliseconds for provider requests.";
    };

    firstByteTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30000;
      description = "How long to wait for the provider to start returning bytes.";
    };

    idleTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15000;
      description = "How long a streaming provider response may stay silent before the request is considered dead.";
    };

    totalTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120000;
      description = "Hard total deadline in milliseconds for a provider request, even if progress continues.";
    };

    runtimeCommand = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "python3" ];
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
      default = defaultStorageDir;
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
