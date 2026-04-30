defmodule Rlm.TestInvalidPathRecoveryProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(history, _system_prompt, _settings) do
    if Enum.any?(history, &String.contains?(&1.content, "path is not in the allowed file set")) do
      {:ok,
       %{
         text: "```python\nhits = grep_files(\"Aimlessness|Belief|Sexual\", limit=5)\npaths = []\nfor hit in hits:\n    if hit.path not in paths:\n        paths.append(hit.path)\n    if len(paths) == 3:\n        break\nfor path in paths:\n    print(read_file(path, limit=5))\nFINAL(\"recovered after invalid path\")\n```",
         input_tokens: 0,
         output_tokens: 0
       }}
    else
      {:ok,
       %{
         text: "```python\nprint(\"Searching first\")\ndiscipline_hits = grep_open(\"Aimlessness|Belief|Sexual\", limit=5)\nprint(discipline_hits)\nread_file(\"pages/Building_Discipline.md\", limit=20)\n```",
         input_tokens: 0,
         output_tokens: 0
       }}
    end
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end

defmodule Rlm.TestProseRecoveryProvider do
  @behaviour Rlm.Providers.Provider

  def generate_code(history, _system_prompt, _settings) do
    if Enum.any?(history, &String.contains?(&1.content, "Could not extract Python code from provider response")) do
      {:ok,
       %{
         text: "```python\nanswer = \"recovered after prose-only response\"\nprint(answer)\nFINAL(answer)\n```",
         input_tokens: 0,
         output_tokens: 0
       }}
    else
      {:ok,
       %{
         text: "I already know the answer and do not need to write code for this run.",
         input_tokens: 0,
         output_tokens: 0
       }}
    end
  end

  def complete_subquery(_sub_context, _instruction, _settings) do
    {:ok, %{text: "unused", input_tokens: 0, output_tokens: 0}}
  end
end
