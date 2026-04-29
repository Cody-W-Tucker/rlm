import io
import sys
import traceback

from runtime import namespace
from runtime import protocol
from runtime import state


def classify_syntax_error(error):
    message = str(error)

    if "unterminated triple-quoted string literal" in message:
        return "syntax_unterminated_triple_quote"

    return "syntax_error"


def capture_exception_metadata(error, stage):
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
            error_kind = classify_syntax_error(error)
    elif isinstance(error, protocol.SubqueryError):
        error_kind = "subquery_error"
    else:
        error_kind = "runtime_exception"

    return {
        "status": "error",
        "error_kind": error_kind,
        "recovery_kind": None,
        "details": details,
    }


def recover_unterminated_final(code, error):
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


def recover_from_syntax_error(code, error):
    recovered = recover_unterminated_final(code, error)

    if recovered is None:
        return None

    return {
        "final_value": recovered,
        "status": "recovered",
        "error_kind": classify_syntax_error(error),
        "recovery_kind": "salvaged_unterminated_final",
        "details": {
            "compile_stage": "direct",
            "syntax_message": str(error),
        },
    }


def should_try_async_wrapper(error_meta):
    return error_meta.get("error_kind") not in {
        "syntax_unterminated_triple_quote",
        "async_wrapper_syntax_error",
    }


def try_direct_exec(code, captured_stderr):
    try:
        compiled = compile(code, "<repl>", "exec")
        exec(compiled, namespace.user_ns)

        return {
            "status": "ok",
            "error_kind": None,
            "recovery_kind": None,
            "details": {"compile_stage": "direct"},
        }
    except Exception as error:
        if not isinstance(error, SyntaxError):
            traceback.print_exc(file=captured_stderr)

        return capture_exception_metadata(error, "direct")


def try_async_wrapper_exec(code, captured_stderr):
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
    async_code += (
        f"globals().update({{k: v for k, v in _async_locals.items() if k not in {protected!r}}})\n"
    )

    try:
        exec(compile(async_code, "<repl>", "exec"), namespace.user_ns)

        return {
            "status": "recovered",
            "error_kind": None,
            "recovery_kind": "async_wrapper",
            "details": {"compile_stage": "async_wrapper"},
        }
    except Exception as error:
        traceback.print_exc(file=captured_stderr)
        return capture_exception_metadata(error, "async_wrapper")


def build_exec_result(captured_stdout, captured_stderr, meta):
    details = dict(meta.get("details") or {})
    details["evidence"] = state.evidence_snapshot()
    final_result = state.get_final_result()

    return {
        "type": "exec_done",
        "stdout": captured_stdout.getvalue(),
        "stderr": captured_stderr.getvalue(),
        "has_final": final_result is not None,
        "final_value": None if final_result is None else str(final_result),
        "status": meta.get("status", "ok"),
        "error_kind": meta.get("error_kind"),
        "recovery_kind": meta.get("recovery_kind"),
        "details": details,
    }


def execute_code(code):
    namespace.refresh_user_ns()
    captured_stdout = io.StringIO()
    captured_stderr = io.StringIO()
    old_stdout = sys.stdout
    old_stderr = sys.stderr

    try:
        sys.stdout = captured_stdout
        sys.stderr = captured_stderr

        exec_meta = try_direct_exec(code, captured_stderr)

        if exec_meta["status"] == "error" and exec_meta["error_kind"] in {
            "syntax_unterminated_triple_quote",
            "syntax_error",
        }:
            recovery = recover_from_syntax_error(
                code, SyntaxError(exec_meta["details"].get("syntax_message", ""))
            )

            if recovery is not None:
                state.set_final_result(recovery["final_value"])
                exec_meta = {
                    "status": recovery["status"],
                    "error_kind": recovery["error_kind"],
                    "recovery_kind": recovery["recovery_kind"],
                    "details": recovery["details"],
                }
            elif should_try_async_wrapper(exec_meta):
                exec_meta = try_async_wrapper_exec(code, captured_stderr)
    finally:
        sys.stdout = old_stdout
        sys.stderr = old_stderr

    protocol.write_message(build_exec_result(captured_stdout, captured_stderr, exec_meta))
