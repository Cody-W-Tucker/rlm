defmodule Rlm.Context.Loader do
  @moduledoc "Context loading for files, directories, globs, pasted text, and URLs."

  alias Rlm.Context.Entry
  alias Rlm.Settings

  @excluded_segments MapSet.new([".git", "_build", "deps", "node_modules"])

  def empty_bundle do
    %{entries: [], text: "", bytes: 0, lazy_bytes: 0, lazy_entries: []}
  end

  def load_many(sources, %Settings{} = settings) do
    Enum.reduce_while(sources, {:ok, empty_bundle()}, fn source, {:ok, bundle} ->
      with {:ok, loaded} <- load(source, settings),
           {:ok, merged} <- append(bundle, loaded, settings) do
        {:cont, {:ok, merged}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  def append(bundle, loaded_bundle, settings \\ nil) do
    merged = %{
      entries: bundle.entries ++ loaded_bundle.entries,
      text: join_text(bundle.text, loaded_bundle.text),
      bytes: bundle.bytes + loaded_bundle.bytes,
      lazy_bytes: Map.get(bundle, :lazy_bytes, 0) + Map.get(loaded_bundle, :lazy_bytes, 0),
      lazy_entries: bundle.lazy_entries ++ Map.get(loaded_bundle, :lazy_entries, [])
    }

    validate_bundle(merged, settings)
  end

  def from_text(text, label, %Settings{} = settings) do
    with {:ok, valid_text} <- validate_text(text, label),
         {:ok, valid_text} <- ensure_text_limit(valid_text, settings.max_context_bytes, label) do
      entry = %Entry{
        id: unique_id(),
        type: :text,
        label: label,
        text: valid_text,
        bytes: byte_size(valid_text),
        metadata: %{source: label}
      }

      {:ok,
       %{entries: [entry], text: valid_text, bytes: byte_size(valid_text), lazy_bytes: 0, lazy_entries: []}}
    end
  end

  def load({:text, text}, settings), do: from_text(text, "text", settings)
  def load({:url, url}, settings), do: load_url(url, settings)
  def load({:path, path}, settings), do: load_path(path, settings)

  def load(source, settings) when is_binary(source) do
    cond do
      url?(source) -> load({:url, source}, settings)
      true -> load({:path, source}, settings)
    end
  end

  defp load_path(path, settings) do
    expanded = expand_from_caller(path)

    cond do
      File.regular?(expanded) -> load_file(expanded, settings)
      File.dir?(expanded) -> load_directory(expanded, settings)
      wildcard?(path) -> load_glob(expanded, path, settings)
      true -> {:error, "Context source not found: #{path}"}
    end
  end

  defp load_file(path, %Settings{} = settings) do
    with {:ok, stat} <- File.stat(path),
         {:ok, size} <- ensure_file_limit(stat.size, settings.max_lazy_file_bytes, path) do
      entry = %Entry{
        id: unique_id(),
        type: :file,
        label: path,
        text: "",
        bytes: 0,
        metadata: %{path: path, lazy: true}
      }

      {:ok, %{entries: [entry], text: "", bytes: 0, lazy_bytes: size, lazy_entries: [entry]}}
    end
  end

  defp load_directory(path, settings) do
    files =
      path
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(&excluded_path?/1)
      |> Enum.sort()

    if length(files) > settings.max_context_files do
      {:error, "Directory #{path} exceeds the #{settings.max_context_files} file safety limit."}
    else
      files
      |> Enum.map(&{:path, &1})
      |> load_many(settings)
    end
  end

  defp load_glob(expanded_pattern, original_pattern, settings) do
    matches =
      expanded_pattern
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(&excluded_path?/1)
      |> Enum.sort()

    cond do
      matches == [] ->
        {:error, "No files matched glob #{original_pattern}."}

      length(matches) > settings.max_context_files ->
        {:error,
         "Glob #{original_pattern} exceeds the #{settings.max_context_files} file safety limit."}

      true ->
        load_many(Enum.map(matches, &{:path, &1}), settings)
    end
  end

  defp expand_from_caller(path) do
    case System.get_env("RLM_CALLER_CWD") do
      nil -> Path.expand(path)
      "" -> Path.expand(path)
      base_dir -> Path.expand(path, base_dir)
    end
  end

  defp load_url(url, %Settings{} = settings) do
    case Req.get(url, finch: Rlm.Finch, receive_timeout: 30_000, max_redirects: 3) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        body = to_string(response.body)

        with {:ok, text} <- ensure_text_limit(body, settings.max_context_bytes, url) do
          entry = %Entry{
            id: unique_id(),
            type: :url,
            label: url,
            text: text,
            bytes: byte_size(text),
            metadata: %{url: url, status: status}
          }

          {:ok,
           %{entries: [entry], text: text, bytes: byte_size(text), lazy_bytes: 0, lazy_entries: []}}
        end

      {:ok, %{status: status}} ->
        {:error, "Failed to fetch #{url}: HTTP #{status}"}

      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{Exception.message(reason)}"}
    end
  end

  defp join_text("", right), do: right
  defp join_text(left, ""), do: left
  defp join_text(left, right), do: left <> "\n\n" <> right

  defp validate_bundle(bundle, nil), do: {:ok, bundle}

  defp validate_bundle(bundle, %Settings{} = settings) do
    cond do
      length(bundle.entries) > settings.max_context_files ->
        {:error, "Loaded context exceeds the #{settings.max_context_files} file safety limit."}

      bundle.bytes > settings.max_context_bytes ->
         {:error,
          "Loaded preloaded context exceeds the #{div(settings.max_context_bytes, 1024 * 1024)}MB safety limit."}

      true ->
        {:ok, bundle}
    end
  end

  defp validate_text(content, label) do
    if String.valid?(content) do
      {:ok, content}
    else
      {:error, "#{label} is not valid UTF-8 text."}
    end
  end

  defp ensure_text_limit(text, max_bytes, label) do
    if byte_size(text) <= max_bytes do
      {:ok, text}
    else
      {:error, "#{label} exceeds the #{div(max_bytes, 1024 * 1024)}MB safety limit."}
    end
  end

  defp ensure_file_limit(size, max_bytes, label) do
    if size <= max_bytes do
      {:ok, size}
    else
      {:error, "#{label} exceeds the #{div(max_bytes, 1024 * 1024)}MB safety limit."}
    end
  end

  defp wildcard?(path), do: String.contains?(path, ["*", "?", "[", "{"])

  defp excluded_path?(path) do
    path
    |> Path.split()
    |> Enum.any?(&MapSet.member?(@excluded_segments, &1))
  end

  defp url?(value), do: String.starts_with?(value, ["http://", "https://"])
  defp unique_id, do: System.unique_integer([:positive])
end
