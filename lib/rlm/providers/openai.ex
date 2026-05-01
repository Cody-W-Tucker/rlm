defmodule Rlm.Providers.OpenAI do
  @moduledoc "OpenAI-compatible provider for root code generation and sub-queries."

  @behaviour Rlm.Providers.Provider

  alias Rlm.Providers.RequestManager
  alias Rlm.Settings

  @impl true
  def generate_code(history, system_prompt, %Settings{} = settings) do
    messages = [%{role: "system", content: system_prompt} | history]
    request_chat(messages, settings, settings.model)
  end

  @impl true
  def complete_subquery(sub_context, instruction, %Settings{} = settings) do
    model = settings.sub_model || settings.model

    messages = [
      %{
        role: "system",
        content:
          "You are a helpful assistant. Answer the user's question using only the provided context. Respond in natural language, not code."
      },
      %{
        role: "user",
        content: "Context:\n#{sub_context}\n\nInstruction: #{instruction}"
      }
    ]

    request_chat(messages, settings, model)
  end

  defp request_chat(messages, %Settings{} = settings, model) do
    headers = [
      {"authorization", "Bearer #{settings.api_key}"},
      {"content-type", "application/json"}
    ]

    {url, body} = build_request(messages, settings, model)

    RequestManager.request_openai_chat(url, headers, body, settings)
  end

  def build_request(messages, %Settings{} = settings, model) do
    base_url = String.trim_trailing(settings.openai_base_url, "/")

    if responses_endpoint?(base_url) do
      {responses_url(base_url), responses_body(messages, model)}
    else
      {chat_completions_url(base_url), chat_body(messages, model)}
    end
  end

  defp chat_body(messages, model) do
    %{
      model: model,
      temperature: 0.2,
      messages: messages
    }
  end

  defp responses_body(messages, model) do
    {instructions, input} = split_instructions(messages)

    %{
      model: model,
      temperature: 0.2,
      input: input
    }
    |> maybe_put_instructions(instructions)
  end

  defp split_instructions([%{role: "system", content: content} | rest]) when is_binary(content) do
    {content, rest}
  end

  defp split_instructions(messages), do: {nil, messages}

  defp maybe_put_instructions(body, nil), do: body
  defp maybe_put_instructions(body, instructions), do: Map.put(body, :instructions, instructions)

  defp responses_endpoint?(base_url) do
    String.ends_with?(base_url, "/responses") or String.contains?(base_url, "/responses?")
  end

  defp responses_url(base_url), do: base_url

  defp chat_completions_url(base_url) do
    if String.ends_with?(base_url, "/chat/completions") do
      base_url
    else
      base_url <> "/chat/completions"
    end
  end
end
