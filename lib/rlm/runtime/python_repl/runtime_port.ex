defmodule Rlm.Runtime.PythonRepl.RuntimePort do
  @moduledoc false

  def open(settings, opts) do
    runtime_path = Keyword.get(opts, :runtime_path, default_runtime_path())
    command = settings.runtime_command ++ [runtime_path]
    {executable, args} = split_command(command)

    resolved =
      if String.contains?(executable, "/") do
        executable
      else
        System.find_executable(executable) || executable
      end

    Port.open({:spawn_executable, resolved}, [
      :binary,
      :exit_status,
      :hide,
      args: args
    ])
  end

  def send_payload(port, payload) do
    Port.command(port, Jason.encode!(payload) <> "\n")
  end

  def default_runtime_path do
    :rlm
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join("runtime.py")
  end

  def split_command([executable | args]), do: {executable, args}
end
