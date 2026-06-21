# AI 缓存迁移通用教程

> 不需要 Claude Code，手动操作即可完成。适用于 Windows 10/11 + Git Bash 环境。

## 前置知识

| 概念 | 说明 |
| --- | --- |
| **NTFS Junction** | Windows 文件系统级别的目录重定向。应用访问 `C:\...`，Windows 内核透明转到 D 盘 |
| **和快捷方式的区别** | 快捷方式是 `.lnk` 文件，很多程序不识别；Junction 是内核级重定向，所有程序都能用 |
| **要求** | 源和目标都在 NTFS 分区；普通用户即可执行 `mklink /J`，不需要管理员权限 |

## 第一步：发现候选目录

```bash
# 查看 C 盘用户目录下各文件夹大小（按大小排序）
du -sh /c/Users/$USER/AppData/Local/*/ 2>/dev/null | sort -rh | head -20
du -sh /c/Users/$USER/AppData/Roaming/*/ 2>/dev/null | sort -rh | head -20

# 只看 >100MB 的项
du -sh /c/Users/$USER/AppData/Local/*/ 2>/dev/null | grep -E "^[0-9.]+G|^[0-9]{3,}M"

# 搜索 AI 相关的
du -sh /c/Users/$USER/AppData/Local/*/ 2>/dev/null | grep -iE "claude|openai|chatgpt|copilot|codebuddy|cline|qianwen|tabby|gemini|kimi"
```

**重点关注**：`AppData/Local/`、`AppData/Roaming/`、用户根目录下的 `.xxx` 隐藏文件夹。

## 第二步：迁移前检查

```bash
# 1. 确认目标软件已关闭
tasklist | grep -i <进程名>

# 2. 确认不是已有 junction（报错=真实目录，输出 Reparse Tag=已是 junction 跳过）
fsutil reparsepoint query "C:\Users\$USER\<路径>"

# 3. 确认 D 盘是 NTFS
powershell -NoProfile -Command "(Get-Volume -DriveLetter D).FileSystemType"

# 4. 确认 D 盘有足够空间
du -sh "/c/Users/$USER/<路径>"
df -h /d
```

## 第三步：执行迁移

```bash
# 设置变量（替换为你实际的路径）
APP="YourApp"
SRC="/c/Users/$USER/AppData/Local/$APP"
DST="/d/Users/$USER/AppData/Local/$APP"

# 1. 确保 D 盘父目录存在
mkdir -p "$(dirname "$DST")"

# 2. 复制数据到 D 盘
cp -r "$SRC"/* "$DST"/ 2>/dev/null

# 3. 验证复制完整性（两边大小应接近）
du -sh "$SRC" "$DST"

# 4. 删除 C 盘源目录
rm -rf "$SRC"

# 5. 创建 NTFS Junction（注意：路径必须用 Windows 反斜杠）
cmd /c "mklink /J \"C:\\Users\\$USER\\AppData\\Local\\$APP\" \"D:\\Users\\$USER\\AppData\\Local\\$APP\""

# 6. 验证 Junction
fsutil reparsepoint query "C:\\Users\\$USER\\AppData\\Local\\$APP"
# ✅ 看到 "Reparse Tag Value : 0xa0000003" = 成功
```

## 常见问题

### 问题 1：删除源目录报 "Device or resource busy"

**原因**：文件被内核级锁定（Chromium sandbox、Electron 运行时锁）。

**解决方案（按优先级）**：
1. **重启电脑** → 锁释放，`rm -rf` 直接删
2. **改名绕过**（不能重启时）：

   ```bash
   mv "$SRC" "$SRC.bak"
   # 然后建 junction 指向 D 盘
   cmd /c "mklink /J \"...\" \"...\""
   # .bak 残留重启后自动可删
   ```

3. 确保改名后数据已完整在 D 盘（.bak 只是残留，不影响使用）

### 问题 2：cp 时报 "Permission denied"

个别文件（如 Chromium component cache）报错可忽略——这些是运行时重建的缓存，跳过不影响功能。

```bash
cp -r ... 2>/dev/null  # 忽略报错继续
```

### 问题 3：不要用 robocopy

在 Git Bash / WSL bash 环境下，`robocopy /MOVE` 参数会被 bash 错误解析为 `/MIR`（镜像模式），导致数据丢失。**统一用 `cp -r`**。

### 问题 4：Junction 创建后应用找不到数据

```bash
# 检查 D 盘目标路径
ls -la "$DST"

# 检查 junction 指向
fsutil reparsepoint query "C:\..." | grep "Substitute"

# 如果路径写错 → 删 junction（用 rmdir！）→ 重建
cmd /c "rmdir \"C:\...\""
```

## 回滚方法

```bash
# 1. 删除 junction（是 rmdir，不是 rm -rf！rm -rf 会顺着 junction 删 D 盘数据）
cmd /c "rmdir \"C:\\Users\\$USER\\<路径>\""

# 2. 将 D 盘数据复制回 C 盘
cp -r "/d/Users/$USER/<路径>" "/c/Users/$USER/<路径>"
```

## 日常维护

```bash
# 定期检查所有 junction 是否完好（把下面路径替换为你实际的）
for p in \
  ".vscode/extensions" \
  ".claude" \
  ".workbuddy" \
  "AppData/Local/Claude-3p" \
  "AppData/Local/ima.copilot" \
  "AppData/Local/Qianwen"; do
  printf "%-50s " "$p"
  fsutil reparsepoint query "C:/Users/$USER/$p" 2>&1 | grep -q "Reparse Tag" && echo "✅" || echo "❌ 需修复"
done
```

## 常见 AI 软件缓存速查

| 软件 | 路径 | 典型大小 |
|------|------|----------|
| Claude Desktop | `AppData\Local\Claude-3p` | 5-15 GB |
| Claude Code | `.claude` | 50-200 MB |
| ChatGPT Desktop | `AppData\Local\chatgpt` / `AppData\Local\OpenAI` | 1-5 GB |
| CodeBuddy CN | `AppData\Roaming\CodeBuddy CN` | 100-500 MB |
| Cline (VSCode) | 缓存随 VSCode 扩展 | — |
| 通义千问 | `AppData\Local\Qianwen` | 500 MB - 2 GB |
| iMA Copilot | `AppData\Local\ima.copilot` | 500 MB - 1 GB |
| WorkBuddy | `.workbuddy` | 1-3 GB |
| 豆包 / MarsCode | `AppData\Local\` 下搜索 | — |
| VS Code 扩展 | `.vscode\extensions` | 500 MB - 2 GB |

## 扩展阅读

- [NTFS Junction vs Symbolic Link vs Hard Link](https://learn.microsoft.com/en-us/windows/win32/fileio/hard-links-and-junctions)
- [mklink 命令文档](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/mklink)
