import os
import re

from runtime import files
from runtime import state


class Hit:
    def __init__(self, path, line, text, query_id=None, query_kind=None, query_pattern=None):
        self.path = path
        self.line = line
        self.text = text
        self.query_id = query_id
        self.query_kind = query_kind
        self.query_pattern = query_pattern

    def __str__(self):
        return f"{self.path}:{self.line}: {self.text}"

    def __repr__(self):
        return str(self)

    def __getitem__(self, key):
        if key == 0:
            return self.path
        if key == 1:
            return self.line
        if key == 2:
            return self.text
        if key in {"path", "line", "text"}:
            return getattr(self, key)
        raise KeyError(key)


class OpenedHit(Hit):
    def __init__(self, path, line, text, preview, query_id=None, query_kind=None, query_pattern=None):
        super().__init__(path, line, text, query_id, query_kind, query_pattern)
        self.preview = preview

    def __str__(self):
        return f"{self.path}:{self.line}: {self.text}\n{self.preview}"

    def __repr__(self):
        return str(self)

    def __getitem__(self, key):
        if key == 3:
            return self.preview
        if key == "preview":
            return self.preview
        return super().__getitem__(key)


class JsonlFieldHit:
    def __init__(self, path, line, field, value, query_id=None, query_kind=None, query_pattern=None):
        self.path = path
        self.line = line
        self.field = field
        self.value = value
        self.query_id = query_id
        self.query_kind = query_kind
        self.query_pattern = query_pattern

    def __str__(self):
        return f"{self.path}:{self.line}: {self.field}={self.value}"

    def __repr__(self):
        return str(self)

    def __getitem__(self, key):
        if key == 0:
            return self.path
        if key == 1:
            return self.line
        if key == 2:
            return self.field
        if key == 3:
            return self.value
        if key in {"path", "line", "field", "value"}:
            return getattr(self, key)
        raise KeyError(key)


def match_preview(path, line, window):
    safe_window = max(0, int(window))
    start = max(1, line - safe_window)
    limit = max(1, safe_window * 2 + 1)
    return files.peek_file(path, offset=start, limit=limit)


def peek_hit(hit, before=5, after=10):
    if not isinstance(hit, Hit):
        raise ValueError("hit must be a grep_files() or grep_open() result")

    safe_before = max(0, min(int(before), 80))
    safe_after = max(0, min(int(after), 80))
    start = max(1, hit.line - safe_before)
    limit = max(1, safe_before + safe_after + 1)
    return files.peek_file(hit.path, offset=start, limit=limit)


def open_hit(hit, window=12):
    if not isinstance(hit, Hit):
        raise ValueError("hit must be a grep_files() or grep_open() result")

    safe_window = max(0, min(int(window), 80))
    return OpenedHit(hit.path, hit.line, hit.text, match_preview(hit.path, hit.line, safe_window))


def _scoped_paths(path):
    if path is None:
        return state.get_file_sources()

    if not isinstance(path, str):
        raise ValueError("path must be a string when provided")

    normalized = os.path.realpath(path)
    allowed = state.get_file_sources()

    if normalized in allowed:
        return [normalized]

    prefix = normalized + os.sep
    scoped = [candidate for candidate in allowed if candidate.startswith(prefix)]

    if scoped:
        return scoped

    raise ValueError(f"path is not in the allowed file set: {path}")


def grep_files(pattern, limit=50, path=None):
    compiled = re.compile(pattern)
    safe_limit = max(1, min(int(limit), 500))
    matches = []
    query = state.record_search(pattern, "grep_files")

    for candidate in _scoped_paths(path):
        with open(candidate, "r", encoding="utf-8") as handle:
            for number, line in enumerate(handle, start=1):
                if compiled.search(line):
                    state.evidence["hit_paths"].add(candidate)
                    text = line.rstrip(chr(10))
                    state.register_hit(query, candidate, number, text)
                    matches.append(
                        Hit(
                            candidate,
                            number,
                            text,
                            query_id=query["id"],
                            query_kind=query["kind"],
                            query_pattern=query["pattern"],
                        )
                    )
                    if len(matches) >= safe_limit:
                        return matches

    return matches


def grep_open(pattern, limit=10, window=12, path=None):
    compiled = re.compile(pattern)
    safe_limit = max(1, min(int(limit), 200))
    safe_window = max(0, min(int(window), 80))
    matches = []
    query = state.record_search(pattern, "grep_open")

    for candidate in _scoped_paths(path):
        with open(candidate, "r", encoding="utf-8") as handle:
            for number, line in enumerate(handle, start=1):
                text = line.rstrip(chr(10))
                if compiled.search(line):
                    state.evidence["hit_paths"].add(candidate)
                    state.register_hit(query, candidate, number, text)
                    matches.append(
                        OpenedHit(
                            candidate,
                            number,
                            text,
                            match_preview(candidate, number, safe_window),
                            query_id=query["id"],
                            query_kind=query["kind"],
                            query_pattern=query["pattern"],
                        )
                    )
                    if len(matches) >= safe_limit:
                        return matches

    return matches
