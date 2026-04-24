defmodule Rlm.Providers.Mock do
  @moduledoc "Deterministic provider useful for local development and tests."

  @behaviour Rlm.Providers.Provider

  @impl true
  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: mock_code(),
       raw: mock_code(),
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  @impl true
  def complete_subquery(sub_context, instruction, _settings) do
    answer =
      [instruction, sub_context]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n\n")

    {:ok, %{text: answer, raw: answer, input_tokens: 0, output_tokens: 0}}
  end

  defp mock_code do
    """
    preview = context[:200]
    if preview:
        print(preview)
        FINAL("Observed context:\\n" + preview)
    else:
        files = list_files(limit=1)
        if files:
            file_preview = read_file(files[0], limit=20)
            print(files[0])
            print(file_preview)
            FINAL("Observed file context from " + files[0] + ":\\n" + file_preview)
        else:
            FINAL("No context was loaded.")
    """
  end
end
