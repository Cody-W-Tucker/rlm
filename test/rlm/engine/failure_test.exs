defmodule Rlm.Engine.FailureTest do
  use ExUnit.Case, async: true

  alias Rlm.Engine.Failure

  test "classifies async wrapper syntax errors separately" do
    exec_result = %{
      status: :error,
      error_kind: :async_wrapper_syntax_error,
      stderr: "Traceback... invalid syntax",
      details: %{
        "failed_block_index" => 1,
        "block_count" => 1,
        "failed_block_code" => "```python\nprint('x')"
      }
    }

    failure = Failure.from_exec_result(exec_result)
    assert failure.class == :async_wrapper_syntax_error
    assert failure.advice =~ "malformed fenced code"
  end

  test "adds a targeted hint for read_file string misuse" do
    exec_result = %{
      status: :error,
      error_kind: :runtime_exception,
      stderr: "Traceback\nTypeError: string indices must be integers, not 'str'",
      details: %{
        "failed_block_index" => 1,
        "block_count" => 1,
        "failed_block_code" =>
          "read_1508 = read_file(files[0], offset=1, limit=10)\nfor line in read_1508:\n    print(line['line'])"
      }
    }

    failure = Failure.from_exec_result(exec_result)
    assert failure.class == :python_exec_error
    assert failure.message =~ "`read_file()` returns one string"
  end
end
