import re

from runtime import files
from runtime import state


class Hit:
    def __init__(self, path, line, text):
        self.path = path
        self.line = line
        self.text = text

    def __str__(self):
        return f"{self.path}:{self.line}: {self.text}"

    def __repr__(self):
        return str(self)

    def __getitem__(self, key):
        if key in {"path", "line", "text"}:
            return getattr(self, key)
        raise KeyError(key)


class OpenedHit(Hit):
    def __init__(self, path, line, text, preview):
        super().__init__(path, line, text)
        self.preview = preview

    def __str__(self):
        return f"{self.path}:{self.line}: {self.text}\n{self.preview}"

    def __repr__(self):
        return str(self)

    def __getitem__(self, key):
        if key == "preview":
            return self.preview
        return super().__getitem__(key)


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

    def __getitem__(self, key):
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


def grep_files(pattern, limit=50):
    compiled = re.compile(pattern)
    safe_limit = max(1, min(int(limit), 500))
    matches = []
    state.evidence["search_patterns"].append(pattern)

    for path in state.get_file_sources():
        with open(path, "r", encoding="utf-8") as handle:
            for number, line in enumerate(handle, start=1):
                if compiled.search(line):
                    state.evidence["hit_paths"].add(path)
                    matches.append(Hit(path, number, line.rstrip(chr(10))))
                    if len(matches) >= safe_limit:
                        return matches

    return matches


def grep_open(pattern, limit=10, window=12):
    compiled = re.compile(pattern)
    safe_limit = max(1, min(int(limit), 200))
    safe_window = max(0, min(int(window), 80))
    matches = []
    state.evidence["search_patterns"].append(pattern)

    for path in state.get_file_sources():
        with open(path, "r", encoding="utf-8") as handle:
            for number, line in enumerate(handle, start=1):
                text = line.rstrip(chr(10))
                if compiled.search(line):
                    state.evidence["hit_paths"].add(path)
                    matches.append(
                        OpenedHit(path, number, text, match_preview(path, number, safe_window))
                    )
                    if len(matches) >= safe_limit:
                        return matches

    return matches
