"""
Persistent Python runtime for the Elixir RLM CLI.

This process keeps a REPL namespace alive across iterations and bridges
sub-queries back to the Elixir host over line-delimited JSON.
"""

import asyncio
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
context = ""
__final_result__ = None
_user_ns = {}


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
    return _result_store.pop(request_id, "")


async def async_llm_query(sub_context, instruction=""):
    return await asyncio.get_event_loop().run_in_executor(None, llm_query, sub_context, instruction)


def _refresh_user_ns():
    _user_ns.update(
        {
            "__builtins__": __builtins__,
            "context": context,
            "llm_query": llm_query,
            "async_llm_query": async_llm_query,
            "FINAL": FINAL,
            "FINAL_VAR": FINAL_VAR,
        }
    )


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

        try:
            compiled = compile(code, "<repl>", "exec")
            exec(compiled, _user_ns)
        except SyntaxError:
            protected = {"context", "llm_query", "async_llm_query", "FINAL", "FINAL_VAR", "__builtins__"}
            async_code = "async def __async_exec__():\n"
            for line in code.split("\n"):
                async_code += f"    {line}\n"
            async_code += "    return {k: v for k, v in locals().items()}\n"
            async_code += "\nimport asyncio as _asyncio\n"
            async_code += "_async_locals = _asyncio.run(__async_exec__())\n"
            async_code += f"globals().update({{k: v for k, v in _async_locals.items() if k not in {protected!r}}})\n"
            exec(compile(async_code, "<repl>", "exec"), _user_ns)
    except Exception:
        traceback.print_exc(file=captured_stderr)
    finally:
        sys.stdout = old_stdout
        sys.stderr = old_stderr

    _write_message(
        {
            "type": "exec_done",
            "stdout": captured_stdout.getvalue(),
            "stderr": captured_stderr.getvalue(),
            "has_final": __final_result__ is not None,
            "final_value": None if __final_result__ is None else str(__final_result__),
        }
    )


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
    _main_loop()
