# 下载站发布指南

一句话：**构建 → 校验 → `./release.sh` → 完事**。

## 1. 构建新版本安装包

在项目根目录（`BOSS-Recruitment`）：

```bash
# macOS（arm64）
mv .env .env.hidden-build && npx electron-builder --mac && mv .env.hidden-build .env

# Windows x64（需 Rosetta + wine，首次已装好）
mv .env .env.hidden-build && npx electron-builder --win && mv .env.hidden-build .env
```

产物在 `release/` 下，命名形如：

- `BOSS智能筛选-<版本>-arm64.dmg` / `BOSS智能筛选-<版本>-arm64-mac.zip` / `BOSS智能筛选 Setup <版本>.exe`

**安全红线：公开产物不得包含 `.env`**（构建时 mv 走、构建后 mv 回来；zip 可用 `unzip -l | grep .env` 复核，release.sh 也会自动扫描 zip）。

构建 Electron 相关注意：

- 本机 shell 若被注入 `ELECTRON_RUN_AS_NODE=1`，跑 electron 前必须 unset。
- mac 包重建后 ad-hoc 签名会失效（报 "code has no resources but signature indicates they must be present"），修复：`codesign --force --deep -s - <app路径>`。
- Windows 构建需要 wine（rcedit），本机已装 Rosetta 2 + wine。

## 2. 一键发布

```bash
cd download-site/gh-pages
./release.sh 1.0.1 \
  --dmg "../../release/BOSS智能筛选-1.0.1-arm64.dmg" \
  --zip "../../release/BOSS智能筛选-1.0.1-arm64-mac.zip" \
  --exe "../../release/BOSS智能筛选 Setup 1.0.1.exe"
```

脚本自动完成：zip 安全校验 → 建/复用 Release → 上传资产（自动改名）→ 可下载性抽验 → 页面 5 处版本号替换 → commit/push → 线上部署验证。

只改页面版本号不发资产：`./release.sh 1.0.1`。

凭据：PAT 存 `~/.dsh/github.json`（chmod 600），脚本自动读取。

## 3. GitHub 资产命名规则（坑）

GitHub 剥离资产名中的中文字符：`BOSS智能筛选-1.0.0-arm64.dmg` 会变成 `BOSS.-1.0.0-arm64.dmg`。release.sh 已统一用 `BOSS.<版本>...` 作为上传名，页面链接与之一致，无需手工处理。

## 4. 验证清单

发布后逐项确认：

- [ ] `https://qscf6-live.github.io/` 显示新版本号（脚本末步自动查）
- [ ] 每个平台按钮真实可点、无「待上传」灰卡
- [ ] 大文件断点续传可用：`curl -s -o /dev/null -w "%{http_code}" -L -r 0-1023 <下载链接>` 应返回 206 或 302
- [ ] **Safari 里开一遍页面**（见下节，历史 bug 只在 Safari 复现）

## 5. Safari 渲染教训（v1.3.1）

v1.2 曾因两个装饰性光晕 div（`.orb`，radial-gradient 背景 + transform 动画）触发 **WebKit 合成层缺陷**：元素存在即导致整页正文渲染空白（Chrome 完全正常，自动化审计全部失灵，只有用户 Safari 可见）。

给后续改版面的规矩：

1. 每次改版必须在 Safari 实机开一遍（用户日常浏览器就是 Safari 18.x）。
2. 纯装饰层（背景光晕/浮层 div）谨慎引入；必要时用 `@supports` 或直接避免「全屏大渐变 + transform 动画」组合。
3. 自动化审计（headless Chrome CDP）验证不了 WebKit 特有 bug，只作回归参考。
