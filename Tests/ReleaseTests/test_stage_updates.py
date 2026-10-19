import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/stage-updates.py"
SPEC = importlib.util.spec_from_file_location("stage_updates", SCRIPT)
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class StageUpdatesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "updates"
        self.source.mkdir()
        self.destination = self.root / "site"
        self.feed_url = "https://sinnfaden-updates.example/appcast.xml"
        self.calls = []
        (self.source / "Sinnfaden.zip").write_bytes(b"signed archive")
        (self.source / "private-key.txt").write_text("must never be staged")
        self.write_feed()

    def write_feed(self, name="Sinnfaden.zip", signature="signature", length="14"):
        (self.source / "appcast.xml").write_text(
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            '<channel><item><enclosure url="https://sinnfaden-updates.example/' + name
            + '" sparkle:edSignature="' + signature + '" length="' + length
            + '"/></item></channel></rss>')

    def verify(self, path, signature):
        self.calls.append((path.name, signature))

    def stage(self):
        return module.stage(self.source, self.destination, self.feed_url, self.verify)

    def test_stages_only_feed_references_and_checks_signatures(self):
        self.assertEqual(self.stage(), ["Sinnfaden.zip", "appcast.xml"])
        self.assertEqual(self.calls, [("appcast.xml", None), ("Sinnfaden.zip", "signature")])
        self.assertEqual({p.name for p in self.destination.iterdir()},
                         {"Sinnfaden.zip", "appcast.xml", "_headers"})

    def test_signature_failure_leaves_previous_site_untouched(self):
        self.destination.mkdir()
        (self.destination / "previous").write_text("kept")
        def reject(path, signature):
            raise ValueError("invalid signature")
        with self.assertRaises(ValueError):
            module.stage(self.source, self.destination, self.feed_url, reject)
        self.assertEqual((self.destination / "previous").read_text(), "kept")

    def test_rejects_path_traversal_and_external_downloads(self):
        for name in ("../Sinnfaden.zip", "%2e%2e%2fSinnfaden.zip", "Sinnfaden.zip?secret=1"):
            with self.subTest(name=name):
                self.write_feed(name=name)
                with self.assertRaises(ValueError):
                    self.stage()
        self.write_feed()
        feed = self.source / "appcast.xml"
        feed.write_text(feed.read_text().replace("sinnfaden-updates.example/", "another.example/"))
        with self.assertRaises(ValueError):
            self.stage()

    def test_rejects_unsigned_wrong_length_missing_or_symlinked_archives(self):
        self.write_feed(signature="")
        with self.assertRaises(ValueError):
            self.stage()
        self.write_feed(length="15")
        with self.assertRaises(ValueError):
            self.stage()
        self.write_feed()
        archive = self.source / "Sinnfaden.zip"
        archive.unlink()
        with self.assertRaises(ValueError):
            self.stage()
        archive.symlink_to(self.source / "private-key.txt")
        with self.assertRaises(ValueError):
            self.stage()

    def test_rejects_files_over_free_limit(self):
        with (self.source / "Sinnfaden.zip").open("wb") as handle:
            handle.truncate(module.MAX_ASSET_BYTES + 1)
        with self.assertRaisesRegex(ValueError, "25 MiB"):
            self.stage()


if __name__ == "__main__":
    unittest.main()
