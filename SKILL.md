---
name: ai-cache-migrate
description: 将 AI 助手/软件的用户缓存从 C 盘迁移到其他盘符，使用 NTFS Junction 实现应用无感知的数据重定向。适用于 C 盘空间不足，需要将 Claude、ChatGPT、CodeBuddy、Cline 等 AI 工具的缓存/模型/数据目录迁出 C 盘的场景。也适用于所有将用户数据存储在 %USERPROFILE% 下的 Electron/Chromium 类桌面应用。
---

# AI Cache Migrate — NTFS Junction 缓存迁移

将任意软件的用户数据从 C 盘迁移到其他盘符，通过 NTFS Junction（目录联接）实现透明重定向。应用完全无感知，重装系统后数据不丢失。

## 核心原则

- **安全优先**：先复制、验证、再删除源目录，任何步骤失败都可回滚
- **应用无感知**：Junction 是文件系统级别的重定向，应用访问 `C:\...` 时 Windows 底层自动转到 D 盘
- **可逆**：删除 Junction（`rmdir`，不是 `rm -rf`）不影响 D 盘数据，反向复制即可回退

## 执行流程

### 阶段一：发现候选目录

扫描 C 盘用户目录，找出占用空间大的 AI 相关软件：

```bash
# 扫描用户目录下 >100MB 的文件夹
du -sh /c/Users/$USER/AppData/Local/*/ 2>/dev/null | sort -rh | head -20
du -sh /c/Users/$USER/AppData/Roaming/*/ 2>/dev/null | sort -rh | head -20

# 只看 AI 相关的（常见命名）
du -sh /c/Users/$USER/AppData/Local/*/ 2>/dev/null | grep -iE "claude|openai|chatgpt|copilot|codebuddy|cline|qianwen|workbuddy|tabby|codeium|gemini|deepseek|kimi|doubao|marscode"
```

与用户确认哪些需要迁移，按空间从大到小排序处理。

### 阶段二：迁移前检查

对每个待迁移目录，逐项确认：

1. **目标软件已关闭** — `tasklist | grep -i <进程名>`
2. **C 盘路径是真实目录**（不是已有 junction）：
   ```bash
   fsutil reparsepoint query "C:\Users\...\<目录>"
   # 报错 = 真实目录，可迁移
   # 输出 Reparse Tag = 已是 junction，跳过
   ```
3. **D 盘有足够空间** — 目标目录大小的 1.5 倍
4. **D 盘是 NTFS** — `fsutil fsinfo volumeinfo D:\`

### 阶段三：执行迁移

对每个确认可迁移的目录，按以下步骤操作：

```bash
# 1. 确保 D 盘父目录存在
mkdir -p "D:/Users/$USER/<目标路径>"

# 2. 复制数据到 D 盘
cp -r "/c/Users/$USER/<源路径>/"* "/d/Users/$USER/<目标路径>/"

# 3. 删除 C 盘源目录
rm -rf "/c/Users/$USER/<源路径>"

# 4. 创建 NTFS Junction
cmd /c "mklink /J \"C:\\Users\\$USER\\<源路径>\" \"D:\\Users\\$USER\\<目标路径>\""

# 5. 验证
fsutil reparsepoint query "C:\\Users\\$USER\\<源路径>"
# ✅ 输出 "Reparse Tag Value : 0xa0000003" → 成功
```

**关键注意事项：**
- 步骤 3 删除源目录前，务必确认步骤 2 复制完整（检查 `du -sh` 两边的值接近）
- 步骤 4 的路径分隔符必须用 Windows 风格 `\`（cmd.exe 要求）
- 步骤 5 如果报错，数据仍在 D 盘安全，排查后重建 junction 即可
- **不要用 `robocopy`** — 在 bash 环境下行为异常，`/MOVE` 可能被误解析为 `/MIR`
- **不要用 `rm -rf` 删除 junction 本身** — 这会顺着 junction 删除 D 盘数据。用 `cmd /c "rmdir \"C:\...\""` 或 `rmdir`

### 阶段四：清理与报告

1. 处理残留文件（如有）：
   ```bash
   # 改名法 — 适用于 Chromium sandbox 等内核锁文件
   mv "/c/Users/$USER/<源路径>" "/c/Users/$USER/<源路径>.bak"
   # 建好 junction 后，.bak 重启后自动可删
   ```

2. 汇总迁移结果，更新用户维护的迁移清单。

## 常见问题处理

### 删除源目录报 "Device or resource busy"

**原因**：文件被内核级锁定（Chromium sandbox、Electron 运行时锁）。

**解决方案（按优先级）**：
1. 重启电脑 → 锁释放
2. 改名绕过（不能重启时）：`mv source source.bak` → 建 junction → .bak 重启后消除
3. 确保数据已完整复制到 D 盘（用 .bak 只是残留，不影响使用）

### cp 报 "Permission denied"

- 个别 Chromium component cache 文件报错可忽略，这些是运行时重建的
- 使用 `cp -r ... 2>/dev/null` 跳过报错文件继续

### 不要用 robocopy

在 Git Bash / WSL bash 环境下，`robocopy /MOVE` 的参数可能被 bash 错误解析。**统一使用 `cp -r`**。

### 如何区分 junction 和真实目录

```bash
fsutil reparsepoint query "C:\path\to\dir"
# 输出 Reparse Tag Value → Junction
# 报错 "The file or directory is not a reparse point" → 真实目录
```

## 回滚方法

如果迁移后软件异常，可以回退：

```bash
# 1. 删除 junction（使用 rmdir，不是 rm -rf！）
cmd /c "rmdir \"C:\Users\$USER\<路径>\""

# 2. 将 D 盘数据复制回 C 盘
cp -r "/d/Users/$USER/<路径>" "/c/Users/$USER/<路径>"
```

## 日常维护

定期运行以下命令检查所有 junction 是否完好：

```bash
for p in \
  ".vscode/extensions" \
  ".claude" \
  ".workbuddy" \
  "AppData/Local/Claude-3p"; do
  printf "%-50s " "$p"
  fsutil reparsepoint query "C:/Users/$USER/$p" 2>&1 | grep -q "Reparse Tag" && echo "✅" || echo "❌ 需修复"
done
```

> 将上面的路径替换为你实际迁移的路径清单。
