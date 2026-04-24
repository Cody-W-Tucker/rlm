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
    body = %{
      model: model,
      temperature: 0.2,
      messages: messages
    }

    headers = [
      {"authorization", "Bearer #{settings.api_key}"},
      {"content-type", "application/json"}
    ]

    url = String.trim_trailing(settings.openai_base_url, "/") <> "/chat/completions"

    RequestManager.request_openai_chat(url, headers, body, settings)
  end
end
