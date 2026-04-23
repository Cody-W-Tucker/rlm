defmodule Rlm.Context.LoaderTest do
  use ExUnit.Case, async: false

  alias Rlm.Context.Loader
  alias Rlm.TestHelpers

  setup do
    tmp = TestHelpers.temp_dir("rlm-loader")
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp, settings: TestHelpers.settings(%{storage_dir: tmp})}
  end

  test "loads directories recursively and skips excluded folders", %{tmp: tmp, settings: settings} do
    File.mkdir_p!(Path.join(tmp, "nested"))
    File.mkdir_p!(Path.join(tmp, "node_modules"))
    File.write!(Path.join(tmp, "alpha.txt"), "alpha")
    File.write!(Path.join(tmp, "nested/beta.txt"), "beta")
    File.write!(Path.join(tmp, "node_modules/skip.txt"), "skip")

    assert {:ok, bundle} = Loader.load({:path, tmp}, settings)
    assert Enum.map(bundle.entries, &Path.basename(&1.label)) == ["alpha.txt", "beta.txt"]
    assert bundle.text =~ "alpha"
    assert bundle.text =~ "beta"
    refute bundle.text =~ "skip"
  end

  test "loads glob patterns", %{tmp: tmp, settings: settings} do
    File.write!(Path.join(tmp, "one.ex"), "one")
    File.write!(Path.join(tmp, "two.ex"), "two")
    File.write!(Path.join(tmp, "ignore.txt"), "ignore")

    assert {:ok, bundle} = Loader.load({:path, Path.join(tmp, "*.ex")}, settings)
    assert length(bundle.entries) == 2
  end

  test "loads relative paths from caller cwd when provided", %{tmp: tmp, settings: settings} do
    previous_cwd = System.get_env("RLM_CALLER_CWD")
    on_exit(fn ->
      if previous_cwd do
        System.put_env("RLM_CALLER_CWD", previous_cwd)
      else
        System.delete_env("RLM_CALLER_CWD")
      end
    end)

    File.write!(Path.join(tmp, "relative.txt"), "relative")
    System.put_env("RLM_CALLER_CWD", tmp)

    assert {:ok, bundle} = Loader.load({:path, "relative.txt"}, settings)
    assert Enum.map(bundle.entries, &Path.basename(&1.label)) == ["relative.txt"]
  end

  test "loads url context", %{settings: settings} do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "GET", "/context", fn conn ->
      Plug.Conn.resp(conn, 200, "remote context")
    end)

    assert {:ok, bundle} =
             Loader.load({:url, "http://localhost:#{bypass.port}/context"}, settings)

    assert bundle.text == "remote context"
    assert hd(bundle.entries).type == :url
  end

  test "enforces aggregate safety limits", %{tmp: tmp} do
    File.write!(Path.join(tmp, "one.txt"), String.duplicate("a", 700))
    File.write!(Path.join(tmp, "two.txt"), String.duplicate("b", 700))

    settings = TestHelpers.settings(%{storage_dir: tmp, max_context_bytes: 1_024})

    assert {:error, message} = Loader.load({:path, tmp}, settings)
    assert message =~ "safety limit"
  end
end
