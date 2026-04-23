defmodule Rlm.Providers.OpenAI do
  @moduledoc "OpenAI-compatible provider for root code generation and sub-queries."

  @behaviour Rlm.Providers.Provider

  alias Rlm.RLM.Settings

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

    with {:ok, %{status: status, body: response_body}} when status in 200..299 <-
           Req.post(url,
             finch: Rlm.Finch,
             headers: headers,
             json: body,
             receive_timeout: settings.request_timeout
           ),
         {:ok, text} <- extract_content(response_body) do
      {:ok,
       %{
         text: text,
         raw: text,
         input_tokens: get_in(response_body, ["usage", "prompt_tokens"]),
         output_tokens: get_in(response_body, ["usage", "completion_tokens"])
       }}
    else
      {:ok, %{status: status}} -> {:error, "provider request failed with HTTP #{status}"}
      {:error, _} = error -> error
    end
  end

  defp extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content) do
    {:ok, content}
  end

  defp extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_list(content) do
    text =
      content
      |> Enum.map(fn
        %{"text" => text} -> text
        %{"type" => "text", "text" => text} -> text
        _ -> ""
      end)
      |> Enum.join()

    {:ok, text}
  end

  defp extract_content(_), do: {:error, "provider response did not include message content"}
end
