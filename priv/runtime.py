"""
Persistent Python runtime for the Elixir RLM CLI.

This process keeps a REPL namespace alive across iterations and bridges
sub-queries back to the Elixir host over line-delimited JSON.
"""

import asyncio
import concurrent.futures
import io
import json
import os
import queue
import re
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
_file_sources = []
_file_source_set = set()
__final_result__ = None
_user_ns = {}
_evidence = {
    "search_patterns": [],
    "hit_paths": set(),
    "previewed_files": set(),
    "read_files": set(),
}


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


class Hit:
    def __init__(self, path, line, text):
        self.path = path
        self.line = line
        self.text = text

    def __str__(self):
        return f"{self.path}:{self.line}: {self.text}"

    def __repr__(self):
        return str(self)


class OpenedHit(Hit):
    def __init__(self, path, line, text, preview):
        super().__init__(path, line, text)
        self.preview = preview

    def __str__(self):
        return f"{self.path}:{self.line}: {self.text}\n{self.preview}"

    def __repr__(self):
        return str(self)


class JsonlFieldHit:
    def __init__(self, path, line, field, value):
        self.path = path
        self.line = line
        self.field = field
        self.value = value

    def __str__(self):
        return f"{self.path}:{self.line}: {self.field}={self.value}"

    def __repr__(self):
        return str(self)


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


def list_files(limit=200, offset=0):
    safe_limit = max(0, min(int(limit), 1000))
    safe_offset = max(0, int(offset))
    return _file_sources[safe_offset : safe_offset + safe_limit]


def sample_files(limit=20):
    safe_limit = max(0, min(int(limit), 200))

    if safe_limit == 0 or not _file_sources:
        return []

    if safe_limit >= len(_file_sources):
        return list(_file_sources)

    if safe_limit == 1:
        return [_file_sources[0]]

    last_index = len(_file_sources) - 1
    step = last_index / (safe_limit - 1)
    indices = []

    for idx in range(safe_limit):
        candidate = round(idx * step)
        if not indices or candidate != indices[-1]:
            indices.append(candidate)

    while len(indices) < safe_limit:
        candidate = min(last_index, indices[-1] + 1)
        if candidate == indices[-1]:
            break
        indices.append(candidate)

    return [_file_sources[idx] for idx in indices[:safe_limit]]


def _normalize_allowed_path(path):
    if not isinstance(path, str):
        raise ValueError("path must be a string")

    normalized = os.path.realpath(path)
    if normalized not in _file_source_set:
        raise ValueError(f"path is not in the allowed file set: {path}")
    return normalized


def read_file(path, offset=1, limit=200):
    normalized = _normalize_allowed_path(path)
    safe_offset = max(1, int(offset))
    safe_limit = max(1, min(int(limit), 1000))

    _evidence["read_files"].add(normalized)

    return _read_file_lines(normalized, safe_offset, safe_limit)


def _read_file_lines(normalized, safe_offset, safe_limit):
    selected = []
    end_line = safe_offset + safe_limit - 1

    # Stream until the requested window instead of materializing the whole file.
    with open(normalized, "r", encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            if number < safe_offset:
                continue

            selected.append((number, line.rstrip("\r\n")))

            if number >= end_line:
                break

    return "\n".join(f"{number}: {line}" for number, line in selected)


def _read_lines(normalized, safe_offset, safe_limit):
    selected = []
    end_line = safe_offset + safe_limit - 1

    with open(normalized, "r", encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            if number < safe_offset:
                continue

            selected.append((number, line.rstrip("\r\n")))

            if number >= end_line:
                break

    return selected


def _parse_jsonl_line(line):
    try:
        return json.loads(line), None
    except json.JSONDecodeError as error:
        return None, str(error)


def _jsonl_window(path, offset, limit):
    normalized = _normalize_allowed_path(path)
    safe_offset = max(1, int(offset))
    safe_limit = max(1, min(int(limit), 500))
    _evidence["read_files"].add(normalized)

    records = []

    for number, text in _read_lines(normalized, safe_offset, safe_limit):
        record, error = _parse_jsonl_line(text)
        if error is None:
            records.append({"line": number, "record": record})
        else:
            records.append({"line": number, "raw": text, "error": error})

    return records


def read_jsonl(path, offset=1, limit=20):
    return _jsonl_window(path, offset, limit)


def _count_file_lines(normalized):
    with open(normalized, "r", encoding="utf-8") as handle:
        return sum(1 for _ in handle)


def sample_jsonl(path, limit=20):
    normalized = _normalize_allowed_path(path)
    safe_limit = max(1, min(int(limit), 100))
    total_lines = _count_file_lines(normalized)

    if total_lines == 0:
        return []

    if safe_limit >= total_lines:
        return _jsonl_window(normalized, 1, total_lines)

    if safe_limit == 1:
        offsets = [1]
    else:
        last_index = total_lines - 1
        step = last_index / (safe_limit - 1)
        offsets = []

        for idx in range(safe_limit):
            candidate = 1 + round(idx * step)
            if not offsets or candidate != offsets[-1]:
                offsets.append(candidate)

    records = []
    seen_lines = set()

    for offset in offsets:
        for item in _jsonl_window(normalized, offset, 1):
            if item["line"] not in seen_lines:
                seen_lines.add(item["line"])
                records.append(item)

    return records


def _iter_json_scalar_fields(value, prefix=""):
    if isinstance(value, dict):
        for key, child in value.items():
            child_prefix = f"{prefix}.{key}" if prefix else str(key)
            yield from _iter_json_scalar_fields(child, child_prefix)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            child_prefix = f"{prefix}[{index}]" if prefix else f"[{index}]"
            yield from _iter_json_scalar_fields(child, child_prefix)
    elif value is not None:
        yield prefix or "$", str(value)


def grep_jsonl_fields(path, field_pattern, text_pattern=".*", limit=20):
    normalized = _normalize_allowed_path(path)
    compiled_field = re.compile(field_pattern)
    compiled_text = re.compile(text_pattern)
    safe_limit = max(1, min(int(limit), 200))
    matches = []
    _evidence["search_patterns"].append(f"jsonl:{field_pattern}::{text_pattern}")

    with open(normalized, "r", encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            text = line.rstrip("\r\n")
            record, error = _parse_jsonl_line(text)
            if error is not None:
                continue

            for field, value in _iter_json_scalar_fields(record):
                if compiled_field.search(field) and compiled_text.search(value):
                    _evidence["hit_paths"].add(normalized)
                    matches.append(JsonlFieldHit(normalized, number, field, value))
                    break

            if len(matches) >= safe_limit:
                return matches

    return matches


def peek_file(path, limit=40, offset=1):
    normalized = _normalize_allowed_path(path)
    safe_offset = max(1, int(offset))
    safe_limit = max(1, min(int(limit), 80))
    _evidence["previewed_files"].add(normalized)
    return _read_file_lines(normalized, safe_offset, safe_limit)


def _match_preview(path, line, window):
    safe_window = max(0, int(window))
    start = max(1, line - safe_window)
    limit = max(1, safe_window * 2 + 1)
    return peek_file(path, offset=start, limit=limit)


def peek_hit(hit, before=5, after=10):
    if not isinstance(hit, Hit):
        raise ValueError("hit must be a grep_files() or grep_open() result")

    safe_before = max(0, min(int(before), 80))
    safe_after = max(0, min(int(after), 80))
    start = max(1, hit.line - safe_before)
    limit = max(1, safe_before + safe_after + 1)
    return peek_file(hit.path, offset=start, limit=limit)


def open_hit(hit, window=12):
    if not isinstance(hit, Hit):
        raise ValueError("hit must be a grep_files() or grep_open() result")

    safe_window = max(0, min(int(window), 80))
    return OpenedHit(hit.path, hit.line, hit.text, _match_preview(hit.path, hit.line, safe_window))


def grep_files(pattern, limit=50):
    compiled = re.compile(pattern)
    safe_limit = max(1, min(int(limit), 500))
    matches = []
    _evidence["search_patterns"].append(pattern)

    for path in _file_sources:
        with open(path, "r", encoding="utf-8") as handle:
            for number, line in enumerate(handle, start=1):
                if compiled.search(line):
                    _evidence["hit_paths"].add(path)
                    matches.append(Hit(path, number, line.rstrip(chr(10))))
                    if len(matches) >= safe_limit:
                        return matches

    return matches


def grep_open(pattern, limit=10, window=12):
    compiled = re.compile(pattern)
    safe_limit = max(1, min(int(limit), 200))
    safe_window = max(0, min(int(window), 80))
    matches = []
    _evidence["search_patterns"].append(pattern)

    for path in _file_sources:
        with open(path, "r", encoding="utf-8") as handle:
            for number, line in enumerate(handle, start=1):
                text = line.rstrip(chr(10))
                if compiled.search(line):
                    _evidence["hit_paths"].add(path)
                    matches.append(OpenedHit(path, number, text, _match_preview(path, number, safe_window)))
                    if len(matches) >= safe_limit:
                        return matches

    return matches


def _refresh_user_ns():
    _user_ns.update(
        {
            "__builtins__": __builtins__,
            "context": context,
            "list_files": list_files,
            "sample_files": sample_files,
            "read_file": read_file,
            "read_jsonl": read_jsonl,
            "sample_jsonl": sample_jsonl,
            "peek_file": peek_file,
            "grep_files": grep_files,
            "grep_open": grep_open,
            "grep_jsonl_fields": grep_jsonl_fields,
            "peek_hit": peek_hit,
            "open_hit": open_hit,
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
    protected = {
        "context",
        "list_files",
        "read_file",
        "grep_files",
        "llm_query",
        "async_llm_query",
        "FINAL",
        "FINAL_VAR",
        "__builtins__",
    }
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
    details = dict(meta.get("details") or {})
    details["evidence"] = _evidence_snapshot()

    return {
        "type": "exec_done",
        "stdout": captured_stdout.getvalue(),
        "stderr": captured_stderr.getvalue(),
        "has_final": __final_result__ is not None,
        "final_value": None if __final_result__ is None else str(__final_result__),
        "status": meta.get("status", "ok"),
        "error_kind": meta.get("error_kind"),
        "recovery_kind": meta.get("recovery_kind"),
        "details": details,
    }


def _evidence_snapshot():
    return {
        "search_count": len(_evidence["search_patterns"]),
        "search_patterns": list(_evidence["search_patterns"]),
        "hit_paths": sorted(_evidence["hit_paths"]),
        "previewed_files": sorted(_evidence["previewed_files"]),
        "read_files": sorted(_evidence["read_files"]),
    }


def _reset_tracking():
    global _evidence
    _evidence = {
        "search_patterns": [],
        "hit_paths": set(),
        "previewed_files": set(),
        "read_files": set(),
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
    global _file_sources
    global _file_source_set
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
        elif msg_type == "set_file_sources":
            _file_sources = [os.path.realpath(path) for path in message.get("paths", []) if isinstance(path, str)]
            _file_source_set = set(_file_sources)
            _write_message({"type": "file_sources_set"})
        elif msg_type == "reset_final":
            __final_result__ = None
            _reset_tracking()
            _write_message({"type": "final_reset"})


if __name__ == "__main__":
    _write_message({"type": "ready"})
    reader = threading.Thread(target=_stdin_reader_loop, daemon=True)
    reader.start()

    try:
        _main_loop()
    finally:
        _subquery_executor.shutdown(wait=False, cancel_futures=True)
