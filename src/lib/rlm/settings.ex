defmodule Rlm.Settings do
  @moduledoc "Validated runtime settings resolved from application config and explicit overrides."

  @enforce_keys [
    :provider,
    :model,
    :sub_model,
    :max_iterations,
    :max_depth,
    :max_sub_queries,
    :api_key,
    :request_timeout
  ]
  defstruct [
    :provider,
    :model,
    :sub_model,
    :api_key,
    :openai_base_url,
    :request_timeout,
    :runtime_command,
    :max_iterations,
    :max_depth,
    :max_sub_queries,
    :truncate_length,
    :metadata_preview_lines,
    :max_context_bytes,
    :max_context_files,
    :max_slice_chars,
    :storage_dir
  ]

  @type t :: %__MODULE__{}

  @schema [
    provider: [type: {:in, [:openai, :mock]}, required: true],
    model: [type: :string, required: true],
    sub_model: [type: {:or, [:string, nil]}, required: true],
    api_key: [type: :string, required: true],
    openai_base_url: [type: :string, required: true],
    request_timeout: [type: :integer, required: true],
    runtime_command: [type: {:list, :string}, required: true],
    max_iterations: [type: :integer, required: true],
    max_depth: [type: :integer, required: true],
    max_sub_queries: [type: :integer, required: true],
    truncate_length: [type: :integer, required: true],
    metadata_preview_lines: [type: :integer, required: true],
    max_context_bytes: [type: :integer, required: true],
    max_context_files: [type: :integer, required: true],
    max_slice_chars: [type: :integer, required: true],
    storage_dir: [type: :string, required: true]
  ]

  def load(overrides \\ %{}) do
    config =
      :rlm
      |> Application.get_env(__MODULE__, [])
      |> Enum.into(%{})

    env = %{
      provider: nil,
      model: nil,
      sub_model: nil,
      api_key: nil,
      openai_base_url: nil,
      request_timeout: nil,
      runtime_command: nil,
      max_iterations: nil,
      max_depth: nil,
      max_sub_queries: nil,
      truncate_length: nil,
      metadata_preview_lines: nil,
      max_context_bytes: nil,
      max_context_files: nil,
      max_slice_chars: nil,
      storage_dir: nil
    }

    merged =
      config
      |> Map.merge(reject_nil(env))
      |> Map.merge(normalize_overrides(overrides))
      |> normalize_sub_model()
      |> normalize_runtime_command()
      |> default_api_key()

    with {:ok, validated} <- NimbleOptions.validate(Enum.into(merged, []), @schema),
         :ok <- validate_ranges(validated) do
      {:ok, struct(__MODULE__, validated)}
    else
      {:error, %NimbleOptions.ValidationError{} = error} -> {:error, Exception.message(error)}
      {:error, _} = error -> error
    end
  end

  defp normalize_overrides(overrides) when is_list(overrides),
    do: overrides |> Enum.into(%{}) |> normalize_overrides()

  defp normalize_overrides(overrides) do
    overrides
    |> reject_nil()
    |> normalize_provider()
  end

  defp default_api_key(%{provider: :mock} = merged), do: Map.put_new(merged, :api_key, "mock-key")
  defp default_api_key(merged), do: merged

  defp normalize_sub_model(merged) do
    case Map.get(merged, :sub_model) do
      "" -> Map.put(merged, :sub_model, nil)
      value -> Map.put(merged, :sub_model, value)
    end
  end

  defp normalize_runtime_command(merged) do
    case Map.get(merged, :runtime_command) do
      command when is_binary(command) -> Map.put(merged, :runtime_command, [command])
      _ -> merged
    end
  end

  defp normalize_provider(cleaned) do
    if Map.has_key?(cleaned, :provider) do
      Map.update!(cleaned, :provider, &env_provider/1)
    else
      cleaned
    end
  end

  defp reject_nil(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end

  defp env_provider(nil), do: nil
  defp env_provider(provider) when provider in [:openai, :mock], do: provider

  defp env_provider(provider) when is_binary(provider) do
    provider
    |> String.downcase()
    |> case do
      "openai" -> :openai
      "mock" -> :mock
      other -> raise ArgumentError, "unsupported provider #{inspect(other)}"
    end
  end

  defp validate_ranges(settings) do
    validations = [
      {:max_iterations, 1, 100},
      {:max_depth, 1, 1},
      {:max_sub_queries, 0, 500},
      {:truncate_length, 100, 50_000},
      {:metadata_preview_lines, 1, 100},
      {:max_context_bytes, 1_024, 100_000_000},
      {:max_context_files, 1, 10_000},
      {:max_slice_chars, 64, 20_000}
    ]

    Enum.reduce_while(validations, :ok, fn {key, min, max}, :ok ->
      value = Keyword.fetch!(settings, key)

      if value in min..max do
        {:cont, :ok}
      else
        {:halt, {:error, "#{key} must be between #{min} and #{max}."}}
      end
    end)
    |> case do
      :ok -> validate_runtime_command(settings)
      error -> error
    end
  end

  defp validate_runtime_command(settings) do
    command = Keyword.fetch!(settings, :runtime_command)

    if command == [] do
      {:error, "runtime_command must contain at least one executable."}
    else
      validate_provider_requirements(settings)
    end
  end

  defp validate_provider_requirements(settings) do
    provider = Keyword.fetch!(settings, :provider)
    api_key = Keyword.fetch!(settings, :api_key)

    cond do
      provider == :openai and String.trim(api_key) == "" ->
        {:error, "api_key is required for the openai provider."}

      true ->
        :ok
    end
  end
end
