import os
import re


context = ""
file_sources = []
file_source_set = set()
final_result = None

evidence = {
    "search_patterns": [],
    "search_queries": [],
    "hit_paths": set(),
    "previewed_files": set(),
    "read_files": set(),
    "read_windows": set(),
    "read_followups": [],
}

search_counter = 0
hit_registry = {}
read_followup_keys = set()

THEORY_LOADED_PATTERNS = [
    r"\biterative\b",
    r"\bincremental\b",
    r"\bmvp\b",
    r"minimum\s+viable",
    r"thin\s+slice",
    r"vertical\s+slice",
    r"progressive\s+elaboration",
    r"learning[-\s]+by[-\s]+doing",
    r"decomposition\s+strategy",
]

CONTRADICTION_PATTERNS = [
    r"counterexample",
    r"contradict",
    r"disconfirm",
    r"exception",
    r"however",
    r"instead",
    r"alternative",
    r"contrast",
    r"but\b",
    r"not\s+always",
]


def set_context(value):
    global context
    context = value


def set_file_sources(paths):
    global file_sources
    global file_source_set
    file_sources = [os.path.realpath(path) for path in paths if isinstance(path, str)]
    file_source_set = set(file_sources)


def get_context():
    return context


def get_file_sources():
    return file_sources


def normalize_allowed_path(path):
    if not isinstance(path, str):
        raise ValueError("path must be a string")

    normalized = os.path.realpath(path)
    if normalized not in file_source_set:
        raise ValueError(f"path is not in the allowed file set: {path}")
    return normalized


def set_final_result(value):
    global final_result
    final_result = value


def get_final_result():
    return final_result


def reset_final_result():
    set_final_result(None)


def evidence_snapshot():
    return {
        "search_count": len(evidence["search_patterns"]),
        "search_patterns": list(evidence["search_patterns"]),
        "search_queries": list(evidence["search_queries"]),
        "hit_paths": sorted(evidence["hit_paths"]),
        "previewed_files": sorted(evidence["previewed_files"]),
        "read_files": sorted(evidence["read_files"]),
        "read_windows": sorted(evidence["read_windows"]),
        "read_followups": list(evidence["read_followups"]),
    }


def reset_tracking():
    global evidence
    global search_counter
    global hit_registry
    global read_followup_keys
    evidence = {
        "search_patterns": [],
        "search_queries": [],
        "hit_paths": set(),
        "previewed_files": set(),
        "read_files": set(),
        "read_windows": set(),
        "read_followups": [],
    }
    search_counter = 0
    hit_registry = {}
    read_followup_keys = set()


def classify_search_kind(pattern):
    normalized = str(pattern or "")

    if any(re.search(candidate, normalized, re.IGNORECASE) for candidate in CONTRADICTION_PATTERNS):
        return "contradiction"

    if any(re.search(candidate, normalized, re.IGNORECASE) for candidate in THEORY_LOADED_PATTERNS):
        return "theory_loaded"

    return "behavioral"


def record_search(pattern, source):
    global search_counter
    search_counter += 1

    entry = {
        "id": search_counter,
        "pattern": str(pattern),
        "source": source,
        "kind": classify_search_kind(pattern),
    }

    evidence["search_patterns"].append(str(pattern))
    evidence["search_queries"].append(entry)
    return entry


def register_hit(query, path, line, text):
    hit_registry.setdefault(path, []).append(
        {
            "path": path,
            "line": int(line),
            "text": text,
            "query_id": query["id"],
            "query_kind": query["kind"],
            "pattern": query["pattern"],
            "source": query["source"],
        }
    )


def record_read_window(path, offset, limit):
    evidence["read_files"].add(path)
    evidence["read_windows"].add(f"{path}:{offset}:{limit}")

    start = int(offset)
    stop = start + int(limit) - 1

    for hit in hit_registry.get(path, []):
        if start <= hit["line"] <= stop:
            key = (path, hit["line"], hit["query_id"], start, stop)

            if key in read_followup_keys:
                continue

            read_followup_keys.add(key)
            evidence["read_followups"].append(
                {
                    "path": path,
                    "line": hit["line"],
                    "pattern": hit["pattern"],
                    "query_kind": hit["query_kind"],
                    "query_id": hit["query_id"],
                    "source": hit["source"],
                    "text": hit["text"],
                    "window": f"{path}:{start}:{limit}",
                }
            )
