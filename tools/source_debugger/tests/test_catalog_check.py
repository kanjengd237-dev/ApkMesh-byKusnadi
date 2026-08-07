import importlib.util
from pathlib import Path


_MODULE_PATH = Path(__file__).parents[1] / "examples" / "check_catalog.py"
_SPEC = importlib.util.spec_from_file_location("check_catalog", _MODULE_PATH)
assert _SPEC is not None and _SPEC.loader is not None
_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MODULE)
check_catalog = _MODULE.check_catalog


class FakeRuntime:
    def __init__(self):
        self.calls = []

    def call(self, method, *args):
        self.calls.append((method, *args))
        if method == "home":
            return {
                "recommended": [{"id": "app-1", "name": "Demo"}],
                "categories": [{"id": "genre:action", "name": "Action"}],
            }
        if method == "category":
            assert args == ("genre:action",)
            return {
                "id": "genre:action",
                "name": "Action",
                "apps": [],
            }
        raise AssertionError(method)


def test_catalog_check_passes_source_defined_category_ids():
    runtime = FakeRuntime()

    result = check_catalog(runtime, 0)

    assert result["ok"] is True
    assert result["checked_categories"] == [
        {"id": "genre:action", "name": "Action", "apps": 0, "first_app": ""}
    ]
    assert runtime.calls == [("home",), ("category", "genre:action")]
