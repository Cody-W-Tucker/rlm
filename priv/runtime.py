"""
Persistent Python runtime for the Elixir RLM CLI.

This process keeps a REPL namespace alive across iterations and bridges
sub-queries back to the Elixir host over line-delimited JSON.
"""

import asyncio
import concurrent.futures
import io
import json
import queue
import sys
import threading
import traceback
import uuid


_real_stdout = sys.stdout
_real_stdin = sys.stdin
_write_lock = threading.Lock()
_pending_results = {}
_result_store = {}
_command_queue = queue.Queue()
_subquery_executor = concurrent.futures.ThreadPoolExecutor(max_workers=8)
context = ""
__final_result__ = None
_user_ns = {}


class SubqueryError(RuntimeError):
    pass


class AwaitableQuery:
    def __init__(self, future):
        self._future = future

    def __await__(self):
        return asyncio.wrap_future(self._future).__await__()

    def result(self):
        return self._future.result()

    def __str__(self):
        return self.result()

    def __repr__(self):
        return repr(self.result())


def FINAL(value):
    global __final_result__
    __final_result__ = str(value)


def FINAL_VAR(value):
    global __final_result__
    __final_result__ = None if value is None else str(value)


def _write_message(payload):
    with _write_lock:
        _real_stdout.write(json.dumps(payload) + "\n")
        _real_stdout.flush()


def _stdin_reader_loop():
    while True:
        line = _real_stdin.readline()
        if not line:
            for event in list(_pending_results.values()):
                event.set()
            _command_queue.put(None)
            break

        line = line.strip()
        if not line:
            continue

        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg_type = message.get("type")
        if msg_type == "llm_result":
            request_id = message.get("id", "")
            if request_id in _pending_results:
                _result_store[request_id] = message.get("result", "")
                _pending_results[request_id].set()
        elif msg_type == "shutdown":
            _command_queue.put(None)
            break
        else:
            _command_queue.put(message)


def llm_query(sub_context, instruction=""):
    request_id = uuid.uuid4().hex[:12]
    event = threading.Event()
    _pending_results[request_id] = event

    _write_message(
        {
            "type": "llm_query",
            "sub_context": sub_context,
            "instruction": instruction or "",
            "id": request_id,
        }
    )

    event.wait()
    _pending_results.pop(request_id, None)
    result = _result_store.pop(request_id, {"status": "error", "message": "Sub-query returned no result."})

    if isinstance(result, dict):
        status = result.get("status")
        if status == "ok":
            return result.get("text", "")
        if status == "error":
            raise SubqueryError(result.get("message", "Sub-query failed."))

    raise SubqueryError(f"Unexpected sub-query result: {result!r}")


def async_llm_query(sub_context, instruction=""):
    return AwaitableQuery(_subquery_executor.submit(llm_query, sub_context, instruction))


def _refresh_user_ns():
    _user_ns.update(
        {
            "__builtins__": __builtins__,
            "context": context,
            "llm_query": llm_query,
            "async_llm_query": async_llm_query,
            "FINAL": FINAL,
            "FINAL_VAR": FINAL_VAR,
            "SubqueryError": SubqueryError,
        }
    )


def _classify_syntax_error(error):
    message = str(error)

    if "unterminated triple-quoted string literal" in message:
        return "syntax_unterminated_triple_quote"

    return "syntax_error"


def _capture_exception_metadata(error, stage):
    details = {
        "compile_stage": stage,
        "exception_type": type(error).__name__,
        "message": str(error),
    }

    if isinstance(error, SyntaxError):
        details["syntax_message"] = str(error)

        if stage == "async_wrapper":
            error_kind = "async_wrapper_syntax_error"
        else:
            error_kind = _classify_syntax_error(error)
    elif isinstance(error, SubqueryError):
        error_kind = "subquery_error"
    else:
        error_kind = "runtime_exception"

    return {
        "status": "error",
        "error_kind": error_kind,
        "recovery_kind": None,
        "details": details,
    }


def _recover_unterminated_final(code, error):
    if not isinstance(error, SyntaxError):
        return None

    if "unterminated triple-quoted string literal" not in str(error):
        return None

    final_markers = ['FINAL("""', "FINAL(''')"]

    for marker in final_markers:
        start = code.find(marker)
        if start == -1:
            continue

        recovered = code[start + len(marker) :]
        recovered = recovered.lstrip("\r\n")

        if recovered.strip() == "":
            return None

        return recovered.rstrip()

    return None


def _recover_from_syntax_error(code, error):
    recovered = _recover_unterminated_final(code, error)

    if recovered is None:
        return None

    return {
        "final_value": recovered,
        "status": "recovered",
        "error_kind": _classify_syntax_error(error),
        "recovery_kind": "salvaged_unterminated_final",
        "details": {
            "compile_stage": "direct",
            "syntax_message": str(error),
        },
    }


def _should_try_async_wrapper(error_meta):
    return error_meta.get("error_kind") not in {
        "syntax_unterminated_triple_quote",
        "async_wrapper_syntax_error",
    }


def _try_direct_exec(code, captured_stderr):
    try:
        compiled = compile(code, "<repl>", "exec")
        exec(compiled, _user_ns)

        return {
            "status": "ok",
            "error_kind": None,
            "recovery_kind": None,
            "details": {"compile_stage": "direct"},
        }
    except Exception as error:
        if not isinstance(error, SyntaxError):
            traceback.print_exc(file=captured_stderr)

        return _capture_exception_metadata(error, "direct")


def _try_async_wrapper_exec(code, captured_stderr):
    protected = {"context", "llm_query", "async_llm_query", "FINAL", "FINAL_VAR", "__builtins__"}
    async_code = "async def __async_exec__():\n"

    for line in code.split("\n"):
        async_code += f"    {line}\n"

    async_code += "    return {k: v for k, v in locals().items()}\n"
    async_code += "\nimport asyncio as _asyncio\n"
    async_code += "_async_locals = _asyncio.run(__async_exec__())\n"
    async_code += f"globals().update({{k: v for k, v in _async_locals.items() if k not in {protected!r}}})\n"

    try:
        exec(compile(async_code, "<repl>", "exec"), _user_ns)

        return {
            "status": "recovered",
            "error_kind": None,
            "recovery_kind": "async_wrapper",
            "details": {"compile_stage": "async_wrapper"},
        }
    except Exception as error:
        traceback.print_exc(file=captured_stderr)
        return _capture_exception_metadata(error, "async_wrapper")


def _build_exec_result(captured_stdout, captured_stderr, meta):
    return {
        "type": "exec_done",
        "stdout": captured_stdout.getvalue(),
        "stderr": captured_stderr.getvalue(),
        "has_final": __final_result__ is not None,
        "final_value": None if __final_result__ is None else str(__final_result__),
        "status": meta.get("status", "ok"),
        "error_kind": meta.get("error_kind"),
        "recovery_kind": meta.get("recovery_kind"),
        "details": meta.get("details") or {},
    }


def _execute_code(code):
    global __final_result__
    _refresh_user_ns()
    captured_stdout = io.StringIO()
    captured_stderr = io.StringIO()
    old_stdout = sys.stdout
    old_stderr = sys.stderr

    try:
        sys.stdout = captured_stdout
        sys.stderr = captured_stderr

        exec_meta = _try_direct_exec(code, captured_stderr)

        if exec_meta["status"] == "error" and exec_meta["error_kind"] in {
            "syntax_unterminated_triple_quote",
            "syntax_error",
        }:
            recovery = _recover_from_syntax_error(code, SyntaxError(exec_meta["details"].get("syntax_message", "")))

            if recovery is not None:
                __final_result__ = recovery["final_value"]
                exec_meta = {
                    "status": recovery["status"],
                    "error_kind": recovery["error_kind"],
                    "recovery_kind": recovery["recovery_kind"],
                    "details": recovery["details"],
                }
            elif _should_try_async_wrapper(exec_meta):
                exec_meta = _try_async_wrapper_exec(code, captured_stderr)
    finally:
        sys.stdout = old_stdout
        sys.stderr = old_stderr

    _write_message(_build_exec_result(captured_stdout, captured_stderr, exec_meta))


def _main_loop():
    global context
    global __final_result__

    while True:
        message = _command_queue.get()
        if message is None:
            break

        msg_type = message.get("type")
        if msg_type == "exec":
            _execute_code(message.get("code", ""))
        elif msg_type == "set_context":
            context = message.get("value", "")
            _write_message({"type": "context_set"})
        elif msg_type == "reset_final":
            __final_result__ = None
            _write_message({"type": "final_reset"})


if __name__ == "__main__":
    _write_message({"type": "ready"})
    reader = threading.Thread(target=_stdin_reader_loop, daemon=True)
    reader.start()

    try:
        _main_loop()
    finally:
        _subquery_executor.shutdown(wait=False, cancel_futures=True)
