# 🗂️ AI Cache Migrate

> 🚀 Move your AI assistant cache off C: drive with zero app awareness. NTFS junction, one script, done.

> NTFS Junction 缓存迁移 — 把 AI 助手的数据从 C 盘搬到其他盘，应用无感知

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue)]()

---

## 解决的问题

AI 桌面应用（Claude Desktop、ChatGPT、CodeBuddy、Cline 等）往往在 `C:\Users\...` 下堆积 GB 级别的缓存和模型文件，导致 C 盘爆满。

这个工具利用 **NTFS Junction（目录联接）** 将数据透明重定向到其他盘符——应用仍以为数据在 C 盘，实际读写都在 D 盘完成。

## 实测效果

> 2026-08-13 更新：新增 Kimi / 千问 Roaming / CodeBuddy 迁移；WorkBuddy Updater、MetisBot Updater 已随软件卸载移除。

| 项目 | 大小 | 迁移结果 |
|------|------|----------|
| Claude Desktop (Claude-3p) | 14.0 GB | ✅ |
| Qianwen (Local) | 3.4 GB | ✅ |
| WorkBuddy (.workbuddy) | 2.7 GB | ✅ |
| iMA Copilot | 765 MB | ✅ |
| CodeBuddy CN (Roaming) | 179 MB | ✅ |
| Kimi (.kimi-work) | 141 MB | ✅ |
| Qianwen (Roaming) | 69 MB | ✅ |
| Claude Code (.claude) | 59 MB | ✅ |
| CodeBuddyExtension | 49 MB | ✅ |
| CodeBuddy (.codebuddy) | 48 MB | ✅ |
| Kimi webbridge | 10 MB | ✅ |
| **合计释放 C 盘** | **~21.4 GB** | |

> 注：Kimi Desktop（约 2.7 GB）与 Doubao 桌面模式（约 1.5 GB）在其他机器/环境实测过可迁移，数据量视使用情况而定。

## 原理

```
应用写入 → C:\Users\xxx\AppData\Local\Claude-3p\cache\...
              ↓  (NTFS Junction — 文件系统级重定向)
            D:\Users\xxx\AppData\Local\Claude-3p\cache\...
```

- **不是快捷方式**：Junction 是 NTFS 内核特性，所有程序都遵循
- **不需要管理员权限**：`mklink /J` 普通用户即可执行
- **C 盘不占空间**：Junction 本身是 0 字节的元数据
- **重装系统数据不丢**：D 盘数据完好，重建 junction 即恢复

## 两种使用方式

### 方式一：Claude Code Skill（推荐）

安装为 Claude Code 技能，直接在对话中使用：

```bash
# 安装
git clone https://github.com/<your-username>/ai-cache-migrate.git
mkdir -p ~/.claude/skills/
cp -r ai-cache-migrate ~/.claude/skills/ai-cache-migrate
```

然后在 Claude Code 中输入 `/ai-cache-migrate` 即可启动迁移流程。Claude 会引导你完成：
1. 扫描 C 盘发现候选目录
2. 逐项确认迁移
3. 执行迁移并验证

### 方式二：手动脚本

参见 [references/tutorial.md](references/tutorial.md) — 完整的 step-by-step 教程，不依赖 Claude Code。

## 前置条件

- Windows 10 / 11
- D 盘（或其他盘符）为 NTFS 格式
- Git Bash 或 WSL（用于 `du`、`cp`、`rm` 命令）

## 安全设计

| 保护措施 | 说明 |
| --- | --- |
| 先复制后删除 | 数据先完整复制到 D 盘，确认无误后才删 C 盘源目录 |
| 自动跳过 junction | 已迁移的目录不会被重复处理 |
| 运行中检测 | 检测目标软件是否正在运行，避免数据冲突 |
| 可回滚 | 删除 junction → 反向复制即可恢复 |
| 改名降级 | 遇到内核锁定文件时，改名绕过而非强制删除 |

## 常见 AI 软件缓存路径速查

| 软件 | 典型路径 |
|------|----------|
| Claude Desktop | `AppData\Local\Claude-3p` |
| Claude Code (VSCode) | `.claude` |
| Kimi Desktop | `AppData\Local\Programs\kimi-desktop`, `AppData\Roaming\kimi-desktop`, `AppData\Local\kimi-desktop-updater`, `AppData\Local\KimiAppCache` |
| Kimi (工作数据) | `.kimi-work`, `.kimi-webbridge` |
| Doubao 桌面模式 | `AppData\Local\Doubao` |
| ChatGPT Desktop | `AppData\Local\chatgpt` |
| CodeBuddy CN | `AppData\Roaming\CodeBuddy CN` |
| Cline (VSCode) | `.vscode\extensions\` (相关部分) |
| 通义千问 | `AppData\Local\Qianwen`、`AppData\Roaming\Qianwen` |
| iMA Copilot | `AppData\Local\ima.copilot` |
| WorkBuddy | `.workbuddy` |
| 豆包 / MarsCode | `AppData\Local\` 下搜索 |

> 不确定某软件的缓存位置？用任务管理器看进程名 → `AppData\Local\<进程名>` 八成就是。

## ⚠️ 重要提醒

- **不要用 `rm -rf` 删除 junction** — 这会顺着 junction 删掉 D 盘的真实数据。用 `rmdir` 删除 junction 本身。
- **重装软件后检查** — 有些卸载程序会删除 junction 并重建真实目录，需要重新迁移。
- **备份软件注意** — 部分备份工具不跟踪 junction，确认你的备份覆盖 D 盘实际路径。

## License

MIT
