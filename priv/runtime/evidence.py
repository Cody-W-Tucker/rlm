from runtime import state
from runtime.search import Hit
from runtime.search import JsonlFieldHit
from runtime.search import OpenedHit


LINE_DELIMITED_EXTENSIONS = (".jsonl", ".ndjson", ".log", ".csv", ".tsv")


def assess_evidence(question, hits=None, reads=None, hypothesis=None):
    snapshot = state.evidence_snapshot()
    normalized_hits = normalize_hits(hits)
    normalized_reads = normalize_reads(reads)
    support = supporting_evidence(snapshot, normalized_hits)
    gaps = evidence_gaps(snapshot)
    suggested_reads = suggest_reads(snapshot, normalized_hits)
    next_action = recommend_next_action(snapshot, suggested_reads)

    return {
        "question": str(question or ""),
        "working_hypothesis": None if hypothesis is None else str(hypothesis),
        "support_summary": support_summary(snapshot),
        "supporting_evidence": support,
        "nearby_hits": normalized_hits[:5],
        "provided_reads": normalized_reads[:5],
        "gaps": gaps,
        "next_action": next_action,
        "finalize_ready": next_action == "finalize",
        "suggested_reads": suggested_reads,
    }


def normalize_hits(hits):
    if not isinstance(hits, list):
        return []

    normalized = []

    for hit in hits:
        item = normalize_hit(hit)
        if item is not None:
            normalized.append(item)

    return normalized


def normalize_hit(hit):
    if isinstance(hit, (Hit, OpenedHit)):
        return {
            "path": hit.path,
            "line": int(hit.line),
            "text": str(hit.text),
            "kind": hit.query_kind,
        }

    if isinstance(hit, JsonlFieldHit):
        return {
            "path": hit.path,
            "line": int(hit.line),
            "field": str(hit.field),
            "text": str(hit.value),
            "kind": hit.query_kind,
        }

    if isinstance(hit, dict):
        path = hit.get("path")
        line = hit.get("line")
        if path is None or line is None:
            return None

        normalized = {"path": str(path), "line": int(line)}
        if "text" in hit:
            normalized["text"] = str(hit["text"])
        if "value" in hit:
            normalized["text"] = str(hit["value"])
        if "field" in hit:
            normalized["field"] = str(hit["field"])
        if "kind" in hit:
            normalized["kind"] = hit["kind"]
        if "query_kind" in hit:
            normalized["kind"] = hit["query_kind"]
        return normalized

    return None


def normalize_reads(reads):
    if not isinstance(reads, list):
        return []

    normalized = []

    for read in reads:
        if isinstance(read, dict):
            item = {}
            if "line" in read:
                item["line"] = int(read["line"])
            if "record" in read:
                item["record_keys"] = sorted(read["record"].keys()) if isinstance(read["record"], dict) else []
            if "raw" in read:
                item["raw"] = str(read["raw"])
            if item:
                normalized.append(item)
        else:
            normalized.append({"text": str(read)})

    return normalized


def supporting_evidence(snapshot, normalized_hits):
    followups = snapshot.get("read_followups", [])
    if followups:
        return [
            {
                "path": item["path"],
                "line": item["line"],
                "kind": item.get("query_kind"),
                "why": "read followed a matched passage",
                "text": item["text"],
            }
            for item in followups[:5]
        ]

    return [
        {
            "path": item["path"],
            "line": item["line"],
            "kind": item.get("kind"),
            "why": "search hit not yet promoted to a read",
            "text": item.get("text", ""),
        }
        for item in normalized_hits[:5]
    ]


def support_summary(snapshot):
    metrics = {
        "search_count": snapshot.get("search_count", 0),
        "hit_paths": len(snapshot.get("hit_paths", [])),
        "read_files": len(snapshot.get("read_files", [])),
        "read_windows": len(snapshot.get("read_windows", [])),
        "read_followups": len(snapshot.get("read_followups", [])),
        "expected_support_searches": count_query_kind(snapshot, "expected_support"),
        "counterexample_searches": count_query_kind(snapshot, "counterexample"),
        "behavioral_searches": count_query_kind(snapshot, "behavioral"),
    }

    metrics["line_delimited_corpus"] = line_delimited_corpus()
    metrics["read_units"] = (
        max(metrics["read_files"], metrics["read_windows"])
        if metrics["line_delimited_corpus"]
        else metrics["read_files"]
    )
    return metrics


def evidence_gaps(snapshot):
    summary = support_summary(snapshot)
    gaps = []

    if summary["search_count"] == 0:
        gaps.append("No retrieval hits yet; search for behavioral markers before synthesizing.")

    if summary["read_units"] < 3:
        gaps.append("Not enough promoted evidence windows yet; inspect 3 strong hit-backed windows before finalizing.")

    if summary["read_followups"] == 0:
        gaps.append("Current reads are not tied back to matched hits yet.")

    if (
        summary["behavioral_searches"] >= 1 or summary["expected_support_searches"] >= 1
    ) and summary["counterexample_searches"] == 0:
        gaps.append("No counterexample or surprise-check pass recorded yet.")

    if len(snapshot.get("hit_paths", [])) >= 2 and len(snapshot.get("read_files", [])) < 2:
        gaps.append("Search hit multiple sources, but direct reads have not compared them yet.")

    return gaps


def suggest_reads(snapshot, normalized_hits):
    followed = {
        (item["path"], int(item["line"]))
        for item in snapshot.get("read_followups", [])
    }
    seen = set()
    suggestions = []

    for item in normalized_hits + flattened_hits():
        path = item.get("path")
        line = int(item.get("line", 0))
        if not path or line <= 0:
            continue

        key = (path, line)
        if key in followed or key in seen:
            continue

        seen.add(key)
        suggestions.append(
            {
                "path": path,
                "offset": max(1, line),
                "limit": 1 if is_line_delimited_path(path) else 3,
                "line": line,
                "reason": item.get("kind") or "matched hit",
            }
        )

        if len(suggestions) >= 5:
            break

    return suggestions


def flattened_hits():
    registry = state.hit_registry_snapshot()
    items = []

    for path_hits in registry.values():
        items.extend(path_hits)

    return sorted(items, key=lambda item: (item["path"], item["line"]))


def recommend_next_action(snapshot, suggested_reads):
    summary = support_summary(snapshot)

    if summary["read_followups"] >= 2 and summary["counterexample_searches"] >= 1 and (
        summary["read_units"] >= 3 or summary["read_files"] >= 2
    ):
        return "finalize"

    if summary["read_followups"] >= 1 and summary["counterexample_searches"] == 0:
        return "run_counterexample_search"

    if summary["search_count"] >= 2 and suggested_reads:
        return "read_more"

    if summary["search_count"] == 0:
        return "continue_search"

    return "read_more"


def count_query_kind(snapshot, kind):
    return len([
        query for query in snapshot.get("search_queries", []) if query.get("kind") == kind
    ])


def is_line_delimited_path(path):
    lowered = str(path or "").lower()
    return lowered.endswith(LINE_DELIMITED_EXTENSIONS)


def line_delimited_corpus():
    paths = state.get_file_sources()
    return bool(paths) and all(is_line_delimited_path(path) for path in paths)
