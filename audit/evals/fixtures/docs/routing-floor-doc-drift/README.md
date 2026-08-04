# toolbelt

Small helper scripts for the release pipeline.

## Commands

| Command | Purpose |
|---|---|
| `bash bin/release.sh --dry-run` | Print what a release would do, change nothing |
| `bash bin/release.sh --tag <version>` | Tag and publish the release |
| `bash bin/release.sh --notify` | Post the release note to the team channel |

## Notes

`--notify` requires `SLACK_WEBHOOK` to be exported. Without it the script skips the
notification silently and still exits 0, so a green run does not prove the message went out.

The script supports exactly these three flags. Anything else is rejected with a usage error.
