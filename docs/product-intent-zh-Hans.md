# TokenScope 产品初衷草稿

## 原始动机

我同时使用 Claude Code、Codex、Oh My Pi 和 Kimi CLI，也会接入多个模型供应商与中转服务，包括 Kimi 账号、MiniMax，以及 GPT 的多个中转站。工具和供应商一多，Token 统计就变得很困难。

我想了解 Token 消耗，并不是为了做复杂的财务系统，而是为了回答几个很具体的问题：

- 安装了一个新的省 Token 工具，到底有没有效果？
- 安装了一个新的 skill，是否增加了消耗？
- 调整了目录结构，会不会增加 Token 消耗？

所以我做了 TokenScope 这个小工具，先满足自己的个人需求，也分享给有同样困扰的朋友。

## 可复用表达

TokenScope 的出发点很简单：当一个开发者同时使用多个 Coding Agent、多个模型账号和多个中转服务时，Token 消耗会散落在不同工具的本地记录里，很难形成一个清晰的整体视图。

我需要的不是复杂报表，而是一个能帮助自己判断变化是否有效的小面板：新的省 Token 工具有没有真的省下来，新的 skill 有没有带来额外消耗，目录结构或工作流调整是否让上下文变重。

TokenScope 因此被设计成一个本地优先、轻量、安静的 macOS 工具。它把常用 Coding Agent 的 Token 用量汇总起来，让个人开发者能更容易理解自己的 AI 编程成本和工作流变化。

## 后续可用于

- README 的 “Why TokenScope” 段落
- Landing Page 的问题场景与价值主张
- App Store 描述中的开头故事或使用场景
