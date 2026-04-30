defmodule Rlm.TestGrepTupleCompatibilityProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text: """
       ```python
       matches = grep_files("beta", limit=5)
       first = matches[0]
       print(first[0])
       print(first[1])
       print(first[2])
       FINAL(f"{first[0]}:{first[1]}")
       ```
       """,
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end
