import os


context = ""
file_sources = []
file_source_set = set()
final_result = None

evidence = {
    "search_patterns": [],
    "hit_paths": set(),
    "previewed_files": set(),
    "read_files": set(),
}


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
        "hit_paths": sorted(evidence["hit_paths"]),
        "previewed_files": sorted(evidence["previewed_files"]),
        "read_files": sorted(evidence["read_files"]),
    }


def reset_tracking():
    global evidence
    evidence = {
        "search_patterns": [],
        "hit_paths": set(),
        "previewed_files": set(),
        "read_files": set(),
    }
