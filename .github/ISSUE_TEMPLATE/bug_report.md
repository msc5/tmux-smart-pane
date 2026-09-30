---
name: Bug report
about: Something isn't working
labels: bug
---

**What happened, and what did you expect?**


**Steps to reproduce**
1.

**Debug report**

1. Turn on logging: `tmux set -g @smart-pane-log-level debug`
2. Reproduce the problem.
3. Run `prefix + :smart-pane-report`. The report is copied to your clipboard (or the tmux buffer `smart-pane-report`) and saved to `~/.local/share/tmux-smart-pane/debug-report.txt`.
4. Review it for anything you'd rather not share, then paste it below.
5. If the problem involves a remote session, run the report on the remote host as well.

<details><summary>Debug report</summary>

```
(paste here)
```

</details>
