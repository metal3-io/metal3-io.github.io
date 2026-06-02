---
title: "Copilot Review Prow Plugin"
date: 2026-06-02
draft: false
categories: ["metal3", "deployment", "community", "announcement", "prow"]
author: Peppi-Lotta Kurjenhovi
---

Metal3 admins have had the option to trigger Copilot reviews on the Metal3
projects PRs for the past 6 months now and during this time Copilot's PR review
capabilities have significantly improved the Metal3 team's workflow. Github
copilot review uses a model that is tuned for review work and admins can trigger
Copilot reviews to clean up style issues and identify obvious logical errors
before human review. This allows reviewers to focus on what matters most:
architecture, logic, and code compatibility.

Only admins (those with write access) can trigger reviews, which limits their
reach. Metal3 has just a few admins who are busy maintainers. Having copilot
review being restricted to only a couple of people, who have many other
responsibilities than just triggering copilot review on contributor's PRs,
leaves much to be desired. By allowing more people to utilize the tool we could
make the code review/fix iterations faster. The issue is, how to grant access to
trigger copilot review without granting write access to everyone. This led to
the plugin idea: since the Metal3.io bot already has write access, we could use
the bot to request Copilot reviews on behalf of any organization member.

[Prow's hook](https://docs.prow.k8s.io/docs/components/core/hook/) is the
component that listens for GitHub webhooks and dispatches them to the
appropriate [plugins](https://docs.prow.k8s.io/docs/components/plugins/).
Plugins consume the GitHub webhooks related to their function. External plugins
offer an alternative to compiling a plugin into the hook binary. Any web
endpoint that can properly handle GitHub webhooks can be configured as an
external plugin that hook will forward webhooks to. External plugin endpoints
are specified per org or org/repo in `plugins.yaml` under the `external_plugins`
field.

Since Metal3 already uses Prow to manage GitHub issues and PRs, building a
custom external plugin for Copilot review requests was a natural choice. The
plugin's goal is clear: when an organization member comments `/copilot-review`
on a PR, the Metal3.io bot should request a Copilot review on their behalf.
Initially the idea was to make a headless chrome solutions to trigger the
request from the browser. In March of 2026 there was an announcement that
copilot reviews can now be
[requested with CLI](https://github.blog/changelog/2026-03-11-request-copilot-code-review-from-github-cli/).
This news made the whole solution become much more trivial in nature.

The plugin is a Go application that runs as an HTTP webhook server in Metal3's
Prow cluster, listening for incoming GitHub events. When someone comments
`/copilot-review` on a PR. We reused other external plugin's (cherrypicker and
needs-rebase) scaffolding for webhook handling and GitHub interaction. The only
"new" logic is the permission check and CLI call.

When the webhook arrives, the plugin validates that the webhook is genuine using
HMAC signatures. Then it extracts the PR details from the comment (repository,
PR number) and checks that the commenter is an organization member. This
permission check is crucial: it prevents random users from consuming the Copilot
token budget.

If all checks pass, the plugin executes GitHub CLI command:
`gh pr edit <PR> --repo <ORG/REPO> --add-reviewer @copilot`. The CLI handles all
the heavy lifting.

The bot uses its standard GitHub token for webhook authentication and posting
status comments. For the actual Copilot review request, it uses a separate
`COPILOT_REVIEW_TOKEN` tied to an organization account with Copilot access. This
separation means we can have two token with different privileges or tokens from
different users all together. This gives more flexibility and control.

The code for the actual copilot review prow plugin can be found in
[metal3-io/utility-images](https://github.com/metal3-io/utility-images/tree/main/copilot-review-prow-plugin)
and the deployment manifest and other configs are in
[metal3-io/project-infra](https://github.com/metal3-io/project-infra/tree/main/prow/manifests/overlays/metal3/external-plugins).

## Usage

To request a Copilot review on a PR, simply comment `/copilot-review` on a pull
request. The plugin will detect the command and request a Copilot review on your
behalf. Once the request succeeds, the bot posts a confirmation comment:

> Copilot code review has been requested by @username. Please allow a few
> moments for the review to be added.

### Important: Use PR Comments, Not Review Comments

The plugin listens for **pull request comments** (using GitHub's `issue_comment`
webhook event), not review comments. Comments on the code diff/review tab
([pull_request_review_comment events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request_review_comment))
are not registered.

Always use the main PR comment section. The plugin is forgiving about whitespace
and formatting: trailing spaces are fine, command can appear anywhere in a
multi-line comment as long as it is on its own line, command is case-insensitive
and it can be combined with other bot commands.

Leading spaces break detection and quoted text (from replies) is also ignored.

### Allowed Users

Only **organization members** can trigger the command. If you're not a member of
`metal3-io`, the plugin will reject the request with:

> You must be an organization member of metal3-io to request a Copilot review.

To learn more about how to become an org member, check out the Metal3
[contributor ladder](https://github.com/metal3-io/community/blob/main/CONTRIBUTOR-LADDER.md#organization-member).

### Troubleshooting

**No response after commenting** — Make sure you're posting in the PR
conversation, not in a code review.

**"You must be an organization member" error** — You need to be added to the
`metal3-io` GitHub organization. Check out steps to become member in the
[contributor ladder](https://github.com/metal3-io/community/blob/main/CONTRIBUTOR-LADDER.md#organization-member)

**"Failed to request Copilot review" error** — The Copilot token may have
expired or the GitHub CLI command may have failed. Contact a maintainer for
further debugging.

## Conclusion

Since deployment, the plugin has operated without issues. This tool smooths the
review process by allowing all organization members to request Copilot reviews.
Most contributors can now do a whole automated review cycle before any
maintainers look at their code. This will make the overall review process more
efficient for everyone!
