from runtime import state


class PathRef(str):
    def __getitem__(self, key):
        if key == "path":
            return str(self)
        return super().__getitem__(key)


def list_files(limit=200, offset=0):
    safe_limit = max(0, min(int(limit), 1000))
    safe_offset = max(0, int(offset))
    file_sources = state.get_file_sources()
    return [PathRef(path) for path in file_sources[safe_offset : safe_offset + safe_limit]]


def sample_files(limit=20):
    safe_limit = max(0, min(int(limit), 200))
    file_sources = state.get_file_sources()

    if safe_limit == 0 or not file_sources:
        return []

    if safe_limit >= len(file_sources):
        return [PathRef(path) for path in file_sources]

    if safe_limit == 1:
        return [PathRef(file_sources[0])]

    last_index = len(file_sources) - 1
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

    return [PathRef(file_sources[idx]) for idx in indices[:safe_limit]]


def read_file(path, offset=1, limit=200):
    normalized = state.normalize_allowed_path(path)
    safe_offset = max(1, int(offset))
    safe_limit = max(1, min(int(limit), 1000))

    state.record_read_window(normalized, safe_offset, safe_limit)

    return read_file_lines(normalized, safe_offset, safe_limit)


def read_file_lines(normalized, safe_offset, safe_limit):
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


def read_lines(normalized, safe_offset, safe_limit):
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


def count_file_lines(normalized):
    with open(normalized, "r", encoding="utf-8") as handle:
        return sum(1 for _ in handle)


def peek_file(path, limit=40, offset=1):
    normalized = state.normalize_allowed_path(path)
    safe_offset = max(1, int(offset))
    safe_limit = max(1, min(int(limit), 80))
    state.evidence["previewed_files"].add(normalized)
    return read_file_lines(normalized, safe_offset, safe_limit)
