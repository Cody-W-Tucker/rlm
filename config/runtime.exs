import Config

[
  "/etc/rlm/config.exs",
  Path.expand("~/.config/rlm/config.exs")
]
|> Enum.filter(&File.exists?/1)
|> Enum.each(fn path ->
  {imported, _imports} = Config.Reader.read_imports!(path)

  Enum.each(imported, fn {app, entries} ->
    Enum.each(entries, fn {key, value} ->
      current = Application.get_env(app, key)

      merged =
        if Keyword.keyword?(current) and Keyword.keyword?(value) do
          Keyword.merge(current, value)
        else
          value
        end

      Application.put_env(app, key, merged, persistent: true)
    end)
  end)
end)
