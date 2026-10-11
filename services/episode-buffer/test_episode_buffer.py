#!/usr/bin/env python3
import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).with_name("episode_buffer.py")
SPEC = importlib.util.spec_from_file_location("episode_buffer", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class HelpersTest(unittest.TestCase):
    def test_normalize(self):
        self.assertEqual(MODULE.normalize("Merlin (2008)"), "merlin2008")
        self.assertEqual(MODULE.normalize("Пригоди Мерліна"), "пригодимерліна")

    def test_parse_date(self):
        parsed = MODULE.parse_date("2026-10-11T10:00:00Z")
        self.assertEqual(parsed.isoformat(), "2026-10-11T10:00:00+00:00")

    def test_episode_key(self):
        self.assertEqual(MODULE.EpisodeBuffer.episode_key({"seasonNumber": 2, "episodeNumber": 3}), (2, 3))


class FakeApi:
    def __init__(self, episodes):
        self.episodes = episodes
        self.puts = []
        self.posts = []
        self.deletes = []

    def get(self, path, query=None):
        if path == "/api/v3/episode":
            return self.episodes
        raise AssertionError(path)

    def put(self, path, body):
        self.puts.append((path, body))

    def post(self, path, body):
        self.posts.append((path, body))

    def delete(self, path):
        self.deletes.append(path)


class BufferPolicyTest(unittest.TestCase):
    def make_app(self, episodes, *, tags=None, dry_run=False):
        app = MODULE.EpisodeBuffer.__new__(MODULE.EpisodeBuffer)
        app.tags = {1: "rolling-3", 2: "keep"}
        app.managed_tag = "rolling-3"
        app.keep_tag = "keep"
        app.buffer_size = 3
        app.dry_run = dry_run
        app.sonarr = FakeApi(episodes)
        app.state = type("FakeState", (), {"data": {"processed": {}, "dry_run_candidates": {}}})()
        return app, {"id": 10, "title": "Example", "tags": tags or [1]}

    @staticmethod
    def episodes():
        return [
            {"id": 1, "seasonNumber": 1, "episodeNumber": 1, "monitored": True, "hasFile": True, "episodeFileId": 11, "airDateUtc": "2020-01-01T00:00:00Z"},
            {"id": 2, "seasonNumber": 1, "episodeNumber": 2, "monitored": False, "hasFile": False, "episodeFileId": 0, "airDateUtc": "2020-01-02T00:00:00Z"},
            {"id": 3, "seasonNumber": 1, "episodeNumber": 3, "monitored": False, "hasFile": False, "episodeFileId": 0, "airDateUtc": "2020-01-03T00:00:00Z"},
            {"id": 4, "seasonNumber": 1, "episodeNumber": 4, "monitored": False, "hasFile": False, "episodeFileId": 0, "airDateUtc": "2020-01-04T00:00:00Z"},
            {"id": 5, "seasonNumber": 1, "episodeNumber": 5, "monitored": False, "hasFile": False, "episodeFileId": 0, "airDateUtc": "2020-01-05T00:00:00Z"},
        ]

    def test_active_run_recycles_and_searches_three(self):
        app, series = self.make_app(self.episodes())
        watched = [{"Id": "jf-1", "ParentIndexNumber": 1, "IndexNumber": 1}]
        app.process_series(series, watched)
        self.assertEqual(app.sonarr.deletes, ["/api/v3/episodefile/11"])
        self.assertEqual(app.sonarr.posts[0][1]["episodeIds"], [2, 3, 4])
        monitored = {body["id"]: body["monitored"] for _, body in app.sonarr.puts}
        self.assertEqual(monitored, {1: False, 2: True, 3: True, 4: True})
        self.assertIn("jf-1", app.state.data["processed"])

    def test_keep_tag_blocks_all_mutations(self):
        app, series = self.make_app(self.episodes(), tags=[1, 2])
        app.process_series(series, [{"Id": "jf-1", "ParentIndexNumber": 1, "IndexNumber": 1}])
        self.assertFalse(app.sonarr.puts or app.sonarr.posts or app.sonarr.deletes)

    def test_multi_episode_file_is_not_deleted(self):
        episodes = self.episodes()
        episodes[1]["episodeFileId"] = 11
        episodes[1]["hasFile"] = True
        app, series = self.make_app(episodes)
        app.process_series(series, [{"Id": "jf-1", "ParentIndexNumber": 1, "IndexNumber": 1}])
        self.assertEqual(app.sonarr.deletes, [])
        self.assertNotIn("jf-1", app.state.data["processed"])


if __name__ == "__main__":
    unittest.main()
