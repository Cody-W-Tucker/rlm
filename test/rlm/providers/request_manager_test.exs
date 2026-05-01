defmodule Rlm.Providers.RequestManagerTest do
  use ExUnit.Case, async: false

  alias Rlm.Providers.OpenAI
  alias Rlm.Providers.RequestManager
  alias Rlm.Providers.RequestManager.Error
  alias Rlm.TestHelpers

  setup do
    settings =
      TestHelpers.settings(%{
        provider: :openai,
        api_key: "test-key",
        openai_base_url: "https://example.invalid/v1",
        connect_timeout: 500,
        first_byte_timeout: 150,
        idle_timeout: 120,
        total_timeout: 350
      })

    {:ok, settings: settings}
  end

  test "accumulates streamed provider output", %{settings: settings} do
    assert {:ok, response} =
             RequestManager.request_openai_chat(
               request_url(settings),
               request_headers(settings),
               request_body(),
               settings,
               fn _url, options ->
                 into = Keyword.fetch!(options, :into)

                 {:cont, _acc} =
                   into.(
                     {:data, "data: {\"choices\":[{\"delta\":{\"content\":\"Hel"},
                     {nil, nil}
                   )

                 {:cont, _acc} = into.({:data, "lo\"}}]}\n\n"}, {nil, nil})

                 {:cont, _acc} =
                   into.(
                     {:data, "data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n"},
                     {nil, nil}
                   )

                 {:cont, _acc} = into.({:data, "data: [DONE]\n\n"}, {nil, nil})
                 {:ok, %Req.Response{status: 200}}
               end
             )

    assert response.text == "Hello world"
  end

  test "treats missing first bytes as first-byte timeout", %{settings: settings} do
    assert {:error, %Error{} = error} =
             RequestManager.request_openai_chat(
               request_url(settings),
               request_headers(settings),
               request_body(),
               settings,
               fn _url, _options ->
                 Process.sleep(settings.first_byte_timeout + 50)
                 {:ok, %Req.Response{status: 200}}
               end
             )

    assert error.class == :first_byte_timeout
    assert error.partial_text == ""
  end

  test "returns recoverable partial output on idle timeout", %{settings: settings} do
    assert {:error, %Error{} = error} =
             RequestManager.request_openai_chat(
               request_url(settings),
               request_headers(settings),
               request_body(),
               settings,
               fn _url, options ->
                 into = Keyword.fetch!(options, :into)

                 {:cont, _acc} =
                   into.(
                     {:data,
                      "data: {\"choices\":[{\"delta\":{\"content\":\"Promising partial\"}}]}\n\n"},
                     {nil, nil}
                   )

                 Process.sleep(settings.idle_timeout + 50)
                 {:ok, %Req.Response{status: 200}}
               end
             )

    assert error.class == :idle_timeout
    assert error.partial_text == "Promising partial"
  end

  test "stops long-but-active streams at the total deadline with partial output", %{
    settings: settings
  } do
    tight_settings = %{settings | total_timeout: 160, first_byte_timeout: 120, idle_timeout: 120}

    assert {:error, %Error{} = error} =
             RequestManager.request_openai_chat(
               request_url(tight_settings),
               request_headers(tight_settings),
               request_body(),
               tight_settings,
               fn _url, options ->
                 into = Keyword.fetch!(options, :into)

                 {:cont, _acc} =
                   into.(
                     {:data, "data: {\"choices\":[{\"delta\":{\"content\":\"Part 1\"}}]}\n\n"},
                     {nil, nil}
                   )

                 Process.sleep(90)

                 {:cont, _acc} =
                   into.(
                     {:data, "data: {\"choices\":[{\"delta\":{\"content\":\" + Part 2\"}}]}\n\n"},
                     {nil, nil}
                   )

                 Process.sleep(90)
                 {:ok, %Req.Response{status: 200}}
               end
             )

    assert error.class == :total_timeout
    assert error.partial_text =~ "Part 1"
  end

  test "accumulates streamed responses-api output", %{settings: settings} do
    responses_url = "https://opencode.ai/zen/v1/responses"

    assert {:ok, response} =
             RequestManager.request_openai_chat(
               responses_url,
               request_headers(settings),
               %{model: "test-model", input: [%{role: "user", content: "hello"}]},
               settings,
               fn _url, options ->
                 into = Keyword.fetch!(options, :into)

                 {:cont, _acc} =
                   into.({:data, "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hel\"}\n\n"}, {nil, nil})

                 {:cont, _acc} =
                   into.({:data, "data: {\"type\":\"response.output_text.delta\",\"delta\":\"lo world\"}\n\n"}, {nil, nil})

                 {:cont, _acc} = into.({:data, "data: [DONE]\n\n"}, {nil, nil})
                 {:ok, %Req.Response{status: 200}}
               end
             )

    assert response.text == "Hello world"
  end

  test "build_request uses responses endpoint directly when configured", %{settings: settings} do
    {url, body} =
      OpenAI.build_request(
        [%{role: "system", content: "sys"}, %{role: "user", content: "hello"}],
        %{settings | openai_base_url: "https://opencode.ai/zen/v1/responses"},
        "gpt-5.4-mini"
      )

    assert url == "https://opencode.ai/zen/v1/responses"
    assert body[:model] == "gpt-5.4-mini"
    assert body[:instructions] == "sys"
    assert body[:input] == [%{role: "user", content: "hello"}]
    refute Map.has_key?(body, :messages)
  end

  defp request_url(settings) do
    String.trim_trailing(settings.openai_base_url, "/") <> "/chat/completions"
  end

  defp request_headers(settings) do
    [
      {"authorization", "Bearer #{settings.api_key}"},
      {"content-type", "application/json"}
    ]
  end

  defp request_body do
    %{
      model: "test-model",
      temperature: 0.2,
      messages: [%{role: "user", content: "hello"}]
    }
  end
end
