# Contributing

Focused bug reports and pull requests are welcome.
Changes should be small and auditable, and must not contain model weights,
credentials, prompts, logs, databases, personal paths, or files copied from an
installed Hermes Agent or llama.cpp tree.

Report suspected vulnerabilities through the private route in
[SECURITY.md](SECURITY.md), not through a public issue or pull request.

Before proposing a change:

1. Run `./tests/run.sh`.
2. Run `./scripts/pre-public-audit.sh` from a clean Git worktree if the required
   scanners are installed.
3. Confirm listeners remain loopback-only.
4. Confirm installation does not start or enable services automatically.
5. Explain any change to process ownership, restart behaviour, or file removal.

Do not paste private runtime logs into commits or issue trackers. Reduce a
problem to a synthetic fixture first.

By submitting a contribution, you agree that it may be distributed under this
repository's MIT License.

## Upstreaming to the Hermes Agent project

This package is an independent, unofficial companion. If a change here is
also useful upstream, it can be submitted to the Hermes Agent project
(`NousResearch/hermes-agent`) as a normal contribution:

1. Sign each commit with the Developer Certificate of Origin:
   `git commit -s` adds a `Signed-off-by: Your Name <your@email>` line,
   attesting that you have the right to submit the change.
2. Keep the contribution separable: the package talks to Hermes Agent only
   through the generic `local-model` provider (`base_url`, model name,
   temperature). Never vendor Hermes code, use its logo or trade name in the
   package's own identity, or depend on internals the project does not
   document.
3. Describe the interoperability honestly: "works with Hermes Agent's custom
   local provider", with the non-affiliation note from the README.
4. Expect the project's licensing terms to govern any merged code; this
   repository's license governs everything else.
