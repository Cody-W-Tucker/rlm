"""
Persistent Python runtime for the Elixir RLM CLI.

This process keeps a REPL namespace alive across iterations and bridges
sub-queries back to the Elixir host over line-delimited JSON.
"""

import importlib.util
import sys
from pathlib import Path


def _load_runtime_package():
    package_dir = Path(__file__).with_name("runtime")
    spec = importlib.util.spec_from_file_location(
        "runtime",
        package_dir / "__init__.py",
        submodule_search_locations=[str(package_dir)],
    )

    module = importlib.util.module_from_spec(spec)
    sys.modules["runtime"] = module
    spec.loader.exec_module(module)


_load_runtime_package()

from runtime.main import run


if __name__ == "__main__":
    run()
