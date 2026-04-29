import asyncio
import concurrent.futures
import json
import queue
import sys
import threading
import uuid


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


_real_stdout = sys.stdout
_real_stdin = sys.stdin
_write_lock = threading.Lock()
_pending_results = {}
_result_store = {}
_command_queue = queue.Queue()
_subquery_executor = concurrent.futures.ThreadPoolExecutor(max_workers=8)


def write_message(payload):
    with _write_lock:
        _real_stdout.write(json.dumps(payload) + "\n")
        _real_stdout.flush()


def stdin_reader_loop():
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

    write_message(
        {
            "type": "llm_query",
            "sub_context": sub_context,
            "instruction": instruction or "",
            "id": request_id,
        }
    )

    event.wait()
    _pending_results.pop(request_id, None)
    result = _result_store.pop(
        request_id, {"status": "error", "message": "Sub-query returned no result."}
    )

    if isinstance(result, dict):
        status = result.get("status")
        if status == "ok":
            return result.get("text", "")
        if status == "error":
            raise SubqueryError(result.get("message", "Sub-query failed."))

    raise SubqueryError(f"Unexpected sub-query result: {result!r}")


def async_llm_query(sub_context, instruction=""):
    return AwaitableQuery(_subquery_executor.submit(llm_query, sub_context, instruction))


def command_queue():
    return _command_queue


def shutdown_executor():
    _subquery_executor.shutdown(wait=False, cancel_futures=True)
