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

defmodule Rlm.TestGrepScopedPathProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text:
         "```python\nfiles = list_files()\ntarget = [path for path in files if path.endswith(\"beta.txt\")][0]\nmatches = grep_files(\"beta\", limit=5, path=target)\nprint(matches)\nfor path in files:\n    print(read_file(path, limit=5))\nFINAL(f\"{len(matches)}:{matches[0].path}:{matches[0].line}\")\n```",
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestEmbeddedFenceLineProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(_history, _system_prompt, _settings) do
    {:ok,
     %{
       text:
         "value = \"alpha\"\n``````python\nvalue = value + \" beta\"\n``````python\nFINAL(value)",
       input_tokens: 0,
       output_tokens: 0
     }}
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end
