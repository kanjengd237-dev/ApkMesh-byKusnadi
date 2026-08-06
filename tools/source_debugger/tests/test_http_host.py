import json
from pathlib import Path

import pytest

from apkmesh_debug.http_host import HttpHost
from apkmesh_debug.models import PolicyError, SourceManifest
from apkmesh_debug.policy import SourcePolicy
from apkmesh_debug.replay import ReplayStore
from apkmesh_debug.trace import TraceRecorder


def test_replay_redirect_is_checked_against_source_policy(tmp_path: Path):
    (tmp_path / "replay.json").write_text(
        json.dumps(
            {
                "responses": {
                    "GET https://example.test/start": {
                        "status": 302,
                        "headers": {"location": "https://evil.test/final"},
                        "body": "",
                    }
                }
            }
        ),
        encoding="utf-8",
    )
    manifest = SourceManifest.from_raw(
        {
            "id": "test",
            "name": "Test",
            "permissions": {"network": ["example.test"]},
        }
    )
    host = HttpHost(
        SourcePolicy(manifest),
        TraceRecorder(),
        mode="replay",
        replay=ReplayStore(tmp_path),
    )

    with pytest.raises(PolicyError):
        host.fetch("https://example.test/start")
    host.close()
