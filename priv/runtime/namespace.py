from runtime import files
from runtime import evidence
from runtime import jsonl
from runtime import jsondoc
from runtime import protocol
from runtime import search
from runtime import state


user_ns = {}


def FINAL(value):
    state.set_final_result(str(value))


def FINAL_VAR(value):
    state.set_final_result(None if value is None else str(value))


def SET_COMPASS(value):
    state.set_compass_map(value)


def GET_COMPASS():
    return state.get_compass_map()


def refresh_user_ns():
    user_ns.update(
        {
            "__builtins__": __builtins__,
            "context": state.get_context(),
            "list_files": files.list_files,
            "sample_files": files.sample_files,
            "read_file": files.read_file,
            "read_json": jsondoc.read_json,
            "read_jsonl": jsonl.read_jsonl,
            "render_json": jsondoc.render_json,
            "render_jsonl": jsonl.render_jsonl,
            "sample_json": jsondoc.sample_json,
            "sample_jsonl": jsonl.sample_jsonl,
            "peek_file": files.peek_file,
            "grep_files": search.grep_files,
            "grep_open": search.grep_open,
            "grep_json_paths": jsondoc.grep_json_paths,
            "grep_jsonl_fields": jsonl.grep_jsonl_fields,
            "assess_evidence": evidence.assess_evidence,
            "peek_hit": search.peek_hit,
            "open_hit": search.open_hit,
            "llm_query": protocol.llm_query,
            "async_llm_query": protocol.async_llm_query,
            "FINAL": FINAL,
            "FINAL_VAR": FINAL_VAR,
            "SET_COMPASS": SET_COMPASS,
            "GET_COMPASS": GET_COMPASS,
            "SubqueryError": protocol.SubqueryError,
        }
    )
