"""Native setup regression tests; no packages, services or login shells changed.

Run: python3 -m unittest discover -s mac_dev_setup/tests -v
Requires Bash, jq and Python 3.11+.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "setup_remote_linux.sh"


class NativeSetupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="insis-native-test-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.env = dict(os.environ, HOME=str(self.home),
                        INSIS_BACKUP_DIR=str(self.home / "backups"))
        self.env.pop("NVIM_CONFIG_BRANCH", None)

    def run_setup(self, commands, check=True):
        return subprocess.run(
            ["bash", "-c", 'source "$1"; ' + commands, "test", str(SCRIPT)],
            env=self.env, text=True, capture_output=True, check=check, timeout=15,
        )

    def write(self, name, contents):
        path = self.home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        return path

    def test_claude_preserves_credentials_editors_and_hooks_on_rerun(self):
        original = {
            "env": {"ANTHROPIC_AUTH_TOKEN": "test-only", "EDITOR": "custom-editor"},
            "model": "custom-model",
            "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "existing-hook"}]}]},
        }
        target = self.write(".claude/settings.json", json.dumps(original))
        commands = "setup_claude_settings; setup_cmux_claude_notifications"
        self.run_setup(commands)
        first = target.read_bytes()
        self.run_setup(commands)
        self.assertEqual(first, target.read_bytes())
        result = json.loads(first)
        self.assertEqual(result["env"]["ANTHROPIC_AUTH_TOKEN"], "test-only")
        self.assertEqual(result["env"]["EDITOR"], "custom-editor")
        self.assertEqual(result["env"]["VISUAL"], "nvim-prompt-editor")
        self.assertEqual(len(result["hooks"]["Stop"]), 2)
        self.assertEqual(result["model"], "custom-model")
        backup = self.home / "backups" / str(target).lstrip("/")
        self.assertEqual(json.loads(backup.read_text()), original)

    def test_codex_merge_preserves_provider_and_adds_missing_scrollback(self):
        original = ('# keep this comment\nmodel_provider = "gateway"\n'
                    '[model_providers.gateway]\nbase_url = "https://example.invalid"\n'
                    '  [tui] # existing UI preferences\nscreen_reader_detection_done = true\n')
        target = self.write(".codex/config.toml", original)
        self.run_setup("setup_cmux_codex_notifications")
        first = target.read_bytes()
        self.run_setup("setup_cmux_codex_notifications")
        self.assertEqual(first, target.read_bytes())
        result = tomllib.loads(first.decode())
        self.assertEqual(result["model_provider"], "gateway")
        self.assertEqual(result["model_providers"]["gateway"]["base_url"], "https://example.invalid")
        self.assertTrue(result["tui"]["screen_reader_detection_done"])
        self.assertEqual(result["tui"]["alternate_screen"], "never")
        self.assertEqual(result["notify"], [str(self.home / ".codex/cmux-notify.sh")])
        self.assertIn("# keep this comment", first.decode())

    def test_codex_explicit_preferences_are_not_overwritten(self):
        original = 'notify = ["my-notifier"]\n[tui]\nalternate_screen = "always"\n'
        target = self.write(".codex/config.toml", original)
        self.run_setup("setup_cmux_codex_notifications")
        self.assertEqual(target.read_text(), original)

    def test_invalid_toml_is_not_replaced(self):
        target = self.write(".codex/config.toml", "[broken\n")
        result = self.run_setup("setup_cmux_codex_notifications", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), "[broken\n")

    def test_yes_mode_preserves_existing_neovim_data(self):
        for name in [".config/nvim/init.lua", ".local/share/nvim/sentinel", ".cache/nvim/sentinel"]:
            self.write(name, "user data")
        self.run_setup("AUTO_YES=true; setup_neovim_config")
        for name in [".config/nvim/init.lua", ".local/share/nvim/sentinel", ".cache/nvim/sentinel"]:
            self.assertEqual((self.home / name).read_text(), "user data")

    def test_yes_mode_does_not_reinstall_existing_neovim(self):
        self.run_setup('AUTO_YES=true; nvim() { echo "NVIM v0.10.0"; }; '
                       'wget() { return 99; }; install_neovim')

    def test_failed_standalone_download_preserves_old_file(self):
        target = self.write(".tmux.conf", "existing config\n")
        result = self.run_setup('SETUP_SCRIPT_DIR=/nonexistent; curl() { return 22; }; '
                                'install_template tmux.conf "$HOME/.tmux.conf"', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), "existing config\n")

    def test_standalone_https_and_ssh_repo_urls(self):
        for repo in ["https://github.com/runjerry/InsisVim.git", "git@github.com:runjerry/InsisVim.git"]:
            self.env["NVIM_CONFIG_REPO"] = repo
            result = self.run_setup('SETUP_SCRIPT_DIR=/nonexistent; '
                                    'curl() { printf "%s\\n" "$@"; }; '
                                    'fetch_template fish_config.fish /unused')
            self.assertIn('https://raw.githubusercontent.com/runjerry/InsisVim/linux-server-setup/mac_dev_setup/fish_config.fish', result.stdout)

    def test_standalone_branch_override(self):
        self.env["NVIM_CONFIG_BRANCH"] = "custom-setup"
        self.env["NVIM_CONFIG_REPO"] = "https://github.com/runjerry/InsisVim.git"
        result = self.run_setup('SETUP_SCRIPT_DIR=/nonexistent; '
                                'curl() { printf "%s\\n" "$@"; }; '
                                'fetch_template fish_config.fish /unused')
        self.assertIn('https://raw.githubusercontent.com/runjerry/InsisVim/custom-setup/mac_dev_setup/fish_config.fish', result.stdout)

    def test_prompt_editor_installs_without_fish(self):
        self.run_setup("setup_prompt_editor")
        helper = self.home / ".local/bin/nvim-prompt-editor"
        self.assertTrue(os.access(helper, os.X_OK))
        fake_nvim = self.write(".local/bin/nvim", '#!/bin/sh\nprintf "%s\\n" "$@"\n')
        fake_nvim.chmod(0o755)
        result = self.run_setup('"$HOME/.local/bin/nvim-prompt-editor" "file with spaces"')
        self.assertIn("-c\nset paste\nfile with spaces", result.stdout)

    def test_eof_declines_instead_of_looping(self):
        self.run_setup('if ask_yes_no "Proceed?" </dev/null; then exit 1; fi')

    def run_language_bootstrap(self, complete_python=True, complete_lua=True):
        # Neovim processes init.lua before the setup script's +luafile command.
        # Model an in-flight startup install: a second request for the same
        # parser must fail, rather than silently masking the original race.
        bootstrap = SCRIPT.read_text().split("install_neovim_language_tools() {", 1)[1]
        bootstrap = bootstrap.split("cat > \"$bootstrap\" <<'LUA'\n", 1)[1].split("\nLUA", 1)[0]
        bootstrap_path = self.write("language-bootstrap.lua", bootstrap)
        fixture = r'''
local installed, requested = {}, {}
local parser_dir = vim.fn.stdpath("data") .. "/test-parsers"
vim.fn.mkdir(parser_dir, "p")
local installer = {
    ensure_installed = function(languages)
        for _, language in ipairs(languages) do
            assert(not requested[language], "duplicate parser installation: " .. language)
            requested[language] = true
        end
        vim.defer_fn(function()
            installed.lua = COMPLETE_LUA
            installed.python = COMPLETE_PYTHON
            for language, ready in pairs(installed) do
                if ready then vim.fn.writefile({}, parser_dir .. "/" .. language .. ".so") end
            end
            print("startup parser installation finished")
        end, 20)
    end,
}
package.preload["insis.env"] = function()
    return {
        getTSEnsureList = function() return { "lua", "python" } end,
        getLSPEnsureList = function() return {} end,
        getToolEnsureList = function() return {} end,
    }
end
package.preload["mason-registry"] = function() return { refresh = function() end } end
package.preload["mason-lspconfig.mappings.server"] = function()
    return { lspconfig_to_package = {} }
end
package.preload["nvim-treesitter.install"] = function() return installer end
package.preload["nvim-treesitter.configs"] = function()
    return { get_parser_install_dir = function() return parser_dir end }
end
package.preload["nvim-treesitter.parsers"] = function()
    -- Neovim bundles Lua, so it is available before the plugin finishes installing.
    return { has_parser = function(language) return language == "lua" or installed[language] == true end }
end
local wait = vim.wait
vim.wait = function(_, predicate) return wait(250, predicate, 10) end
installer.ensure_installed({ "lua", "python" })
'''.replace("COMPLETE_PYTHON", "true" if complete_python else "false").replace(
            "COMPLETE_LUA", "true" if complete_lua else "false")
        fixture_path = self.write("language-startup.lua", fixture)
        return subprocess.run(
            ["nvim", "--headless", "--noplugin", "-i", "NONE", "-u", str(fixture_path),
             "+luafile " + str(bootstrap_path), "+qa"],
            env=self.env, text=True, capture_output=True, timeout=10,
        )

    @unittest.skipUnless(shutil.which("nvim"), "requires Neovim")
    def test_language_bootstrap_waits_for_startup_without_duplicate_parser_jobs(self):
        result = self.run_language_bootstrap()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("startup parser installation finished", result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("nvim"), "requires Neovim")
    def test_language_bootstrap_reports_a_missing_parser(self):
        result = self.run_language_bootstrap(complete_python=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Language tools not installed: parser:python", result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("nvim"), "requires Neovim")
    def test_language_bootstrap_bundled_lua_does_not_mask_unfinished_install(self):
        result = self.run_language_bootstrap(complete_lua=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Language tools not installed: parser:lua", result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("node") and shutil.which("fish"), "requires Node and Fish")
    def test_native_preview_guard_binds_to_loopback(self):
        self.run_setup("npx() { return 0; }; setup_mdview_helpers")
        guard = self.home / ".local/lib/insis-mdview/loopback.cjs"
        result = subprocess.run(
            ["node", "--require", str(guard), "-e",
             'const s=require("node:http").createServer(); '
             's.listen(0,()=>{console.log(s.address().address);s.close()})'],
            text=True, capture_output=True, check=True, timeout=10,
        )
        self.assertEqual(result.stdout.strip(), "127.0.0.1")

    def test_notifications_are_noops_without_cmux(self):
        self.run_setup("setup_cmux_claude_notifications; setup_cmux_codex_notifications; "
                       'printf \'{"hook_event_name":"Stop"}\' | "$HOME/.claude/hooks/cmux-notify.sh"; '
                       '"$HOME/.codex/cmux-notify.sh" \'{"type":"agent-turn-complete"}\'')


if __name__ == "__main__":
    unittest.main()
