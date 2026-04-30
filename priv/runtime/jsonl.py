import json
import re

from runtime import files
from runtime import state
from runtime.search import JsonlFieldHit


def parse_jsonl_line(line):
    try:
        return json.loads(line), None
    except json.JSONDecodeError as error:
        return None, str(error)


def jsonl_window(path, offset, limit, track_read=True):
    normalized = state.normalize_allowed_path(path)
    safe_offset = max(1, int(offset))
    safe_limit = max(1, min(int(limit), 500))

    if track_read:
        state.record_read_window(normalized, safe_offset, safe_limit)

    records = []

    for number, text in files.read_lines(normalized, safe_offset, safe_limit):
        record, error = parse_jsonl_line(text)
        if error is None:
            records.append({"line": number, "record": record})
        else:
            records.append({"line": number, "raw": text, "error": error})

    return records


def read_jsonl(path, offset=1, limit=20):
    return jsonl_window(path, offset, limit)


def sample_jsonl(path, limit=20):
    normalized = state.normalize_allowed_path(path)
    safe_limit = max(1, min(int(limit), 100))
    total_lines = files.count_file_lines(normalized)

    if total_lines == 0:
        return []

    if safe_limit >= total_lines:
        return jsonl_window(normalized, 1, total_lines, track_read=False)

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
        for item in jsonl_window(normalized, offset, 1, track_read=False):
            if item["line"] not in seen_lines:
                seen_lines.add(item["line"])
                records.append(item)

    return records


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


def grep_jsonl_fields(path, field_pattern, text_pattern=".*", limit=20):
    normalized = state.normalize_allowed_path(path)
    compiled_field = re.compile(field_pattern)
    compiled_text = re.compile(text_pattern)
    safe_limit = max(1, min(int(limit), 200))
    matches = []
    state.evidence["search_patterns"].append(f"jsonl:{field_pattern}::{text_pattern}")

    with open(normalized, "r", encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            text = line.rstrip("\r\n")
            record, error = parse_jsonl_line(text)
            if error is not None:
                continue

            for field, value in iter_json_scalar_fields(record):
                if compiled_field.search(field) and compiled_text.search(value):
                    state.evidence["hit_paths"].add(normalized)
                    matches.append(JsonlFieldHit(normalized, number, field, value))
                    break

            if len(matches) >= safe_limit:
                return matches

    return matches
