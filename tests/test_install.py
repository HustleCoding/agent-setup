import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agent-setup-test-")
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.repo = root / "agent's setup"
        shutil.copytree(SOURCE, self.repo, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        self.home = root / "home"
        for harness in (".claude", ".codex", ".dsh"):
            (self.home / harness).mkdir(parents=True)
        self.env = {**os.environ, "HOME": str(self.home)}

    def write(self, relative, contents):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
        return path

    def install(self):
        return subprocess.run(
            ["bash", str(self.repo / "install.sh")],
            env=self.env,
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_keeps_other_hooks_in_the_same_group(self):
        other_hook = {"type": "command", "command": "echo keep-me"}
        similarly_named = {"type": "command", "command": "echo style-reminder guidance"}
        old_hook = {"type": "command", "command": "bash '/old location/hooks/style-reminder.sh'"}
        existing = {
            "permissions": {"allow": ["Read"]},
            "hooks": {
                "UserPromptSubmit": [
                    {"matcher": "*", "hooks": [other_hook, old_hook]},
                    {"hooks": [similarly_named]},
                ],
                "Stop": [{"hooks": [{"type": "command", "command": "echo stop"}]}],
            },
        }
        for harness, file in ((".claude", "settings.json"), (".codex", "hooks.json")):
            self.write(f"{harness}/{file}", json.dumps(existing))

        self.install()

        for harness, file in ((".claude", "settings.json"), (".codex", "hooks.json")):
            with self.subTest(harness=harness):
                data = json.loads((self.home / harness / file).read_text())
                self.assertEqual(data["permissions"], existing["permissions"])
                self.assertEqual(data["hooks"]["Stop"], existing["hooks"]["Stop"])
                groups = data["hooks"]["UserPromptSubmit"]
                self.assertIn({"matcher": "*", "hooks": [other_hook]}, groups)
                self.assertIn({"hooks": [similarly_named]}, groups)
                commands = [hook["command"] for group in groups for hook in group["hooks"]]
                self.assertNotIn(old_hook["command"], commands)
                self.assertEqual(sum("/hooks/style-reminder.sh" in c for c in commands), 1)

    def test_installed_hook_runs_when_repo_path_contains_an_apostrophe(self):
        self.install()
        data = json.loads((self.home / ".codex/hooks.json").read_text())
        command = data["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"]
        result = subprocess.run(
            ["bash", "-c", command], env=self.env, check=True, capture_output=True, text=True
        )
        payload = json.loads(result.stdout)
        self.assertEqual(payload["hookSpecificOutput"]["hookEventName"], "UserPromptSubmit")

    def test_rerun_preserves_user_settings_blocks_and_skills(self):
        marker = "<!-- agent-setup:begin (from old location) -->\nold rules\n<!-- agent-setup:end -->"
        for path in (".claude/CLAUDE.md", ".codex/AGENTS.md", ".dsh/AGENTS.md"):
            self.write(path, f"before\n\n{marker}\n\nafter\n")
        self.write(
            ".codex/config.toml",
            'model = "test-model"\n\n[features]\nmulti_agent = true\nhooks = false\n'
            '\n[profiles.work]\nmodel_verbosity = "high"\npersonality = "warm"\n',
        )
        self.write(".codex/skills/grill-me/SKILL.md", "my original skill\n")

        self.install()
        files = (
            ".claude/CLAUDE.md", ".claude/settings.json", ".codex/AGENTS.md",
            ".codex/config.toml", ".codex/hooks.json", ".dsh/AGENTS.md",
            ".dsh/hooks.json", ".dsh/cordis.patch.yml",
        )
        first = {name: (self.home / name).read_bytes() for name in files}
        self.install()
        self.assertEqual(first, {name: (self.home / name).read_bytes() for name in files})

        for name in (".claude/CLAUDE.md", ".codex/AGENTS.md", ".dsh/AGENTS.md"):
            contents = (self.home / name).read_text()
            self.assertIn("before", contents)
            self.assertIn("after", contents)
            self.assertEqual(contents.count("<!-- agent-setup:begin"), 1)
            self.assertNotIn("old rules", contents)

        config = (self.home / ".codex/config.toml").read_text()
        root, rest = config.split("[features]", 1)
        features, profile = rest.split("[profiles.work]", 1)
        self.assertIn('model = "test-model"', root)
        self.assertIn('model_verbosity = "low"', root)
        self.assertIn('personality = "none"', root)
        self.assertIn("multi_agent = true", features)
        self.assertIn("hooks = true", features)
        self.assertIn('model_verbosity = "high"', profile)
        self.assertIn('personality = "warm"', profile)

        skill = self.home / ".codex/skills/grill-me"
        self.assertTrue(skill.is_symlink())
        self.assertEqual(skill.resolve(), (self.repo / "skills/grill-me").resolve())
        backups = list((self.home / ".agent-setup-backup").glob("*/.codex/grill-me/SKILL.md"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "my original skill\n")
        for harness in (".claude", ".codex", ".dsh"):
            with self.subTest(harness=harness):
                installed = self.home / harness / "skills/agent-guardrails"
                self.assertTrue(installed.is_symlink())
                self.assertEqual(installed.resolve(), (self.repo / "skills/agent-guardrails").resolve())

    def test_codex_config_ignores_table_like_lines_inside_multiline_strings(self):
        original = (
            'developer_instructions = """\n[features]\nhooks = false\n'
            'model_verbosity = "high"\n"""\n\n'
            '[profiles.work]\npersonality = "warm"\n'
        )
        self.write(".codex/config.toml", original)
        self.install()
        config = (self.home / ".codex/config.toml").read_text()
        self.assertIn(original, config)
        self.assertTrue(config.endswith("\n[features]\nhooks = true\n"))
        self.assertIn('model_verbosity = "low"\n', config[:config.index("developer_instructions")])

    def test_replaces_a_hook_with_a_broken_old_apostrophe_path(self):
        old = "bash '/old user's setup/hooks/style-reminder.sh'"
        self.write(
            ".codex/hooks.json",
            json.dumps({"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": old}]}]}}),
        )
        self.install()
        data = json.loads((self.home / ".codex/hooks.json").read_text())
        groups = data["hooks"]["UserPromptSubmit"]
        self.assertEqual(len(groups), 1)
        self.assertEqual(len(groups[0]["hooks"]), 1)
        self.assertNotEqual(groups[0]["hooks"][0]["command"], old)

    def test_codex_config_updates_quoted_keys_without_creating_duplicates(self):
        self.write(
            ".codex/config.toml",
            '"model_verbosity" = "high"\n'
            '[ "features" ] # existing settings\n"hooks" = false\nother = true\n'
            '[profiles.work]\n"model_verbosity" = "high"\n',
        )
        self.install()
        config = (self.home / ".codex/config.toml").read_text()
        self.assertIn('"model_verbosity" = "low"', config)
        self.assertIn('"hooks" = true', config)
        self.assertIn('[profiles.work]\n"model_verbosity" = "high"', config)
        try:
            import tomllib
        except ImportError:
            self.skipTest("tomllib is available in Python 3.11 and newer")
        parsed = tomllib.loads(config)
        self.assertTrue(parsed["features"]["hooks"])
        self.assertTrue(parsed["features"]["other"])
        self.assertEqual(parsed["profiles"]["work"]["model_verbosity"], "high")

    def test_codex_config_leaves_inline_features_untouched(self):
        original = 'features = { hooks = false, other = true }\n'
        path = self.write(".codex/config.toml", original)
        result = subprocess.run(
            ["bash", str(self.repo / "install.sh")],
            env=self.env, capture_output=True, text=True, timeout=30,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cannot safely update inline or dotted features", result.stderr)
        self.assertEqual(path.read_text(), original)


if __name__ == "__main__":
    unittest.main()
