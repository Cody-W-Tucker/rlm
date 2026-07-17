import json
import re

from runtime import state
from runtime.search import JsonPathHit


def _load_json(path):
    normalized = state.normalize_allowed_path(path)
    with open(normalized, "r", encoding="utf-8", errors="replace") as handle:
        return normalized, json.load(handle)


def _json_type_name(value):
    if isinstance(value, dict):
        return "object"
    if isinstance(value, list):
        return "array"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, (int, float)):
        return "number"
    return "string"


def iter_json_scalar_fields(value, prefix=""):
    if isinstance(value, dict):
        for key, child in value.items():
            child_prefix = f"{prefix}.{key}" if prefix else str(key)
            yield from iter_json_scalar_fields(child, child_prefix)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            child_prefix = f"{prefix}[{index}]" if prefix else f"[{index}]"
            yield from iter_json_scalar_fields(child, child_prefix)
    elif value is not None:
        yield prefix or "$", str(value)


def _tokenize_json_path(json_path):
    if json_path in (None, "", "$", "$."):
        return []

    text = str(json_path)
    if text.startswith("$"):
        text = text[1:]
    if text.startswith("."):
        text = text[1:]

    tokens = []
    index = 0

    while index < len(text):
        if text[index] == ".":
            index += 1
            continue

        if text[index] == "[":
            end = text.find("]", index)
            if end == -1:
                raise ValueError(f"invalid json_path: {json_path}")

            raw_index = text[index + 1 : end]
            if not raw_index.isdigit():
                raise ValueError(
                    "json_path array selectors must use explicit numeric indexes"
                )

            tokens.append(int(raw_index))
            index = end + 1
            continue

        end = index
        while end < len(text) and text[end] not in ".[":
            end += 1

        token = text[index:end]
        if not token:
            raise ValueError(f"invalid json_path: {json_path}")

        tokens.append(token)
        index = end

    return tokens


def _resolve_json_path(value, json_path):
    current = value

    for token in _tokenize_json_path(json_path):
        if isinstance(token, int):
            if not isinstance(current, list):
                raise ValueError(f"json_path index {token} expects an array")
            if token >= len(current):
                raise ValueError(f"json_path index out of range: {token}")
            current = current[token]
            continue

        if not isinstance(current, dict):
            raise ValueError(f"json_path key '{token}' expects an object")
        if token not in current:
            raise ValueError(f"json_path key not found: {token}")
        current = current[token]

    return current


def _truncate_value(value, limit):
    safe_limit = max(1, min(int(limit), 200))

    if isinstance(value, list):
        return {
            "type": "array",
            "length": len(value),
            "items": value[:safe_limit],
            "truncated": len(value) > safe_limit,
        }

    if isinstance(value, dict):
        keys = list(value.keys())
        subset = {key: value[key] for key in keys[:safe_limit]}
        return {
            "type": "object",
            "key_count": len(value),
            "keys": keys[:safe_limit],
            "value": subset,
            "truncated": len(value) > safe_limit,
        }

    return {"type": _json_type_name(value), "value": value, "truncated": False}


def _render_json_text(value):
    return json.dumps(value, indent=2, ensure_ascii=True)


def sample_json(path, limit=20):
    normalized, document = _load_json(path)
    state.evidence["previewed_files"].add(normalized)
    safe_limit = max(1, min(int(limit), 100))
    sample_paths = []

    for json_path, value in iter_json_scalar_fields(document):
        sample_paths.append({"json_path": json_path, "value": value})
        if len(sample_paths) >= safe_limit:
            break

    top_level_keys = list(document.keys())[:safe_limit] if isinstance(document, dict) else []

    return {
        "path": normalized,
        "root_type": _json_type_name(document),
        "top_level_keys": top_level_keys,
        "sample_paths": sample_paths,
    }


def read_json(path, json_path="$", limit=40):
    normalized, document = _load_json(path)
    value = _resolve_json_path(document, json_path)
    state.evidence["read_files"].add(normalized)
    return {
        "path": normalized,
        "json_path": json_path or "$",
        **_truncate_value(value, limit),
    }


def render_json(path, json_path="$", limit=40):
    payload = read_json(path, json_path=json_path, limit=limit)
    lines = [
        f"Path: {payload['path']}",
        f"JSON path: {payload['json_path']}",
        f"Type: {payload['type']}",
        f"Truncated: {'yes' if payload['truncated'] else 'no'}",
    ]

    if payload["type"] == "object":
        lines.append(f"Key count: {payload['key_count']}")
        if payload["keys"]:
            lines.append("Keys: " + ", ".join(str(key) for key in payload["keys"]))
        lines.append("Value:")
        lines.append(_render_json_text(payload["value"]))
    elif payload["type"] == "array":
        lines.append(f"Length: {payload['length']}")
        lines.append("Items:")
        lines.append(_render_json_text(payload["items"]))
    else:
        lines.append("Value:")
        lines.append(_render_json_text(payload["value"]))

    return "\n".join(lines)


def grep_json_paths(path, path_pattern=".*", value_pattern=".*", limit=20):
    normalized, document = _load_json(path)
    compiled_path = re.compile(path_pattern)
    compiled_value = re.compile(value_pattern)
    safe_limit = max(1, min(int(limit), 200))
    matches = []
    query = state.record_search(f"json:{path_pattern}::{value_pattern}", "grep_json_paths")

    for json_path, value in iter_json_scalar_fields(document):
        if compiled_path.search(json_path) and compiled_value.search(value):
            state.evidence["hit_paths"].add(normalized)
            state.register_hit(query, normalized, 1, f"{json_path}={value}")
            matches.append(
                JsonPathHit(
                    normalized,
                    json_path,
                    value,
                    query_id=query["id"],
                    query_kind=query["kind"],
                    query_pattern=query["pattern"],
                )
            )
            if len(matches) >= safe_limit:
                return matches

    return matches
