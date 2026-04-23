import Config

[
  "/etc/rlm/config.exs",
  Path.expand("~/.config/rlm/config.exs")
]
|> Enum.filter(&File.exists?/1)
|> Enum.each(fn path ->
  path
  |> Config.Reader.read_imports!()
  |> elem(0)
  |> Application.put_all_env(persistent: true)
end)
