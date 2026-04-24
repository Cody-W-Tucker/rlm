{ pkgs, src }:

pkgs.writeShellApplication {
  name = "rlm";

  runtimeInputs = [ pkgs.elixir pkgs.git pkgs.python3 pkgs.coreutils pkgs.rebar3 ];

  text = ''
    export RLM_CALLER_CWD="$PWD"

    state_root="''${XDG_STATE_HOME:-$HOME/.local/state}/rlm/package"
    project_dir="$state_root/project"
    source_marker="$project_dir/.rlm-source"
    bundled_src='${src}'

    mkdir -p "$state_root"

    if [ ! -d "$project_dir" ] || [ ! -f "$source_marker" ] || [ "$(cat "$source_marker")" != "$bundled_src" ]; then
      rm -rf "$project_dir"
      cp -R "$bundled_src" "$project_dir"
      chmod -R u+w "$project_dir"
      printf '%s\n' "$bundled_src" > "$source_marker"
    fi

    export HOME="''${HOME:-$state_root/home}"
    export MIX_HOME="$state_root/.mix"
    export HEX_HOME="$state_root/.hex"
    mkdir -p "$HOME" "$MIX_HOME" "$HEX_HOME"

    cd "$project_dir"

    mix local.hex --force >/dev/null
    mix local.rebar --force >/dev/null

    if [ ! -d "$project_dir/deps" ]; then
      mix deps.get >/dev/null
    fi

    if [ ! -d "$project_dir/_build" ]; then
      mix compile >/dev/null
    fi

    exec mix rlm "$@"
  '';
}
