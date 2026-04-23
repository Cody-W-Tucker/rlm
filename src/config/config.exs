import Config

config :rlm, Rlm.RLM.Settings,
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
  max_context_bytes: 10 * 1024 * 1024,
  max_context_files: 100,
  max_slice_chars: 4_000,
  storage_dir: Path.expand("~/.local/state/rlm/runs")
