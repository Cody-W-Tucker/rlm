defmodule Rlm.SettingsTest do
  use ExUnit.Case, async: false

  alias Rlm.Settings

  setup do
    app_env = Application.get_env(:rlm, Settings)

    on_exit(fn ->
      Application.put_env(:rlm, Settings, app_env)
    end)

    :ok
  end

  test "merges application config with explicit overrides" do
    Application.put_env(:rlm, Settings,
      provider: :mock,
      model: "config-model",
      sub_model: nil,
      api_key: "config-key",
      openai_base_url: "https://example.invalid",
      request_timeout: 60_000,
      runtime_command: ["python3"],
      max_iterations: 8,
      max_depth: 1,
      max_sub_queries: 4,
      truncate_length: 500,
      metadata_preview_lines: 4,
      max_context_bytes: 2_048,
      max_context_files: 4,
      max_slice_chars: 256,
      storage_dir: "/tmp/config-storage"
    )

    assert {:ok, settings} =
             Settings.load(%{model: "override-model", storage_dir: "/tmp/override-storage"})

    assert settings.provider == :mock
    assert settings.model == "override-model"
    assert settings.storage_dir == "/tmp/override-storage"
    assert settings.max_iterations == 8
  end

  test "fails fast when openai credentials are missing" do
    Application.put_env(:rlm, Settings,
      provider: :openai,
      model: "gpt-4o-mini",
      sub_model: nil,
      api_key: "",
      openai_base_url: "https://api.openai.com/v1",
      request_timeout: 60_000,
      runtime_command: ["python3"],
      max_iterations: 12,
      max_depth: 1,
      max_sub_queries: 24,
      truncate_length: 5_000,
      metadata_preview_lines: 12,
      max_context_bytes: 10_485_760,
      max_context_files: 100,
      max_slice_chars: 4_000,
      storage_dir: "/tmp/openai-storage"
    )

    assert {:error, message} = Settings.load()
    assert message =~ "api_key"
  end

  test "validates numeric ranges" do
    assert {:error, message} = Settings.load(%{provider: :mock, max_iterations: 0})
    assert message =~ "max_iterations"
  end
end
